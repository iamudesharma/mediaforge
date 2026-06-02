//! Thumbnail extraction: **CPU-only** pipeline (never HW decode / VideoToolbox / GPU).
//!
//! - **Single-pass** batch when positions span a short window (e.g. 0–9s)
//! - **Segmented seek** per position when span covers most of a long clip (filmstrip)
//! - Backward stream seek + `avcodec_flush_buffers` (A2)
//! - `skip_frame=NonKey` until near each target, then full decode (A3)
//! - `swscale` for YUV→RGB at source size; `fast_image_resize` (SIMD) for downscale
//! - Batch JPEG/WebP encode via `rayon` after decode (decode stays single-threaded)

use std::io::Cursor;
use std::path::{Path, PathBuf};

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video as DecoderVideo;
use ffmpeg_next::codec::discard::Discard;
use ffmpeg_next::format::{context::Input, Pixel};
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags};
use ffmpeg_next::util::frame::video::Video;
use ffmpeg_next::Rational;
use image::{ImageBuffer, ImageFormat, RgbImage};
use rayon::prelude::*;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::{
    apply_preview_scrub_decoder_settings, apply_thumbnail_decoder_settings,
    ensure_ffmpeg_initialized, ensure_input_accessible, flush_video_decoder, input_duration_ms,
    log::PreviewLogScope,
    input::output_stem_from_input, map_ffmpeg_error, ms_to_stream_ts, open_input,
    open_input_for_preview, seek_stream_backward, seek_stream_two_tier,
    use_segmented_thumbnail_seek, SeekOutcome,
};
use crate::ffmpeg::interrupt::attach_interrupt;
use crate::jobs::registry::CancellationToken;
use crate::types::{
    BatchThumbnailBytesOptions, BatchThumbnailBytesResult, BatchThumbnailOptions,
    BatchThumbnailResult, ThumbnailBytesOptions, ThumbnailFormat, ThumbnailOptions,
};

pub fn extract_thumbnail(options: ThumbnailOptions, token: CancellationToken) -> Result<String> {
    let bytes = extract_thumbnail_bytes(
        ThumbnailBytesOptions {
            input_path: options.input_path.clone(),
            position_ms: options.position_ms,
            width: options.width,
            height: options.height,
            format: options.format.clone(),
        },
        token,
    )?;

    let input = options.input_path.trim();
    let explicit = options
        .output_path
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty());
    let mut output = resolve_thumb_path(input, explicit, &options.format)?;
    if write_bytes(&bytes, &output).is_err() && explicit.is_some() {
        log::warn!(
            "thumbnail write to {} failed; using app temp dir",
            output.display()
        );
        output = resolve_thumb_path(input, None, &options.format)?;
        write_bytes(&bytes, &output)?;
    }

    Ok(output.to_string_lossy().into_owned())
}

pub fn extract_thumbnail_bytes(
    options: ThumbnailBytesOptions,
    token: CancellationToken,
) -> Result<Vec<u8>> {
    ensure_ffmpeg_initialized()?;

    let input = options.input_path.trim();
    ensure_input_accessible(input)?;

    let rgb = decode_scrub_rgb_frame_at_cached(
        input,
        options.position_ms,
        options.width,
        options.height,
        token,
    )?;
    encode_rgb_to_bytes(&rgb, &options.format)
}

pub fn extract_batch_thumbnails(
    options: BatchThumbnailOptions,
    token: CancellationToken,
) -> Result<BatchThumbnailResult> {
    if token.is_cancelled() {
        return Err(VideoForgeError::Cancelled);
    }

    ensure_ffmpeg_initialized()?;
    let input = options.input_path.trim();
    ensure_input_accessible(input)?;

    let n = options.positions_ms.len();
    if n == 0 {
        return Ok(BatchThumbnailResult {
            paths: vec![],
            decoded_status: vec![],
        });
    }

    let explicit_paths = options.output_paths.as_ref().map(|paths| {
        if paths.len() != n {
            Err(VideoForgeError::InvalidInput(format!(
                "output_paths length {} must match positions_ms length {n}",
                paths.len()
            )))
        } else {
            Ok(paths
                .iter()
                .map(|p| PathBuf::from(p.trim()))
                .collect::<Vec<_>>())
        }
    });
    let explicit_paths = match explicit_paths {
        Some(Ok(p)) => Some(p),
        Some(Err(e)) => return Err(e),
        None => None,
    };

    let output_dir = if explicit_paths.is_some() {
        None
    } else {
        let dir = PathBuf::from(options.output_dir.trim());
        if options.output_dir.trim().is_empty() {
            return Err(VideoForgeError::InvalidInput(
                "output_dir is required when output_paths is not set".into(),
            ));
        }
        ensure_output_parent(&dir)?;
        std::fs::create_dir_all(&dir).map_err(map_io_err)?;
        Some(dir)
    };

    let mut targets = build_targets(&options.positions_ms);
    decode_batch_frames(
        input,
        &mut targets,
        options.width,
        options.height,
        Some(&options.format),
        token,
        false,
    )?;

    let mut paths = vec![String::new(); n];
    let mut decoded_status: Vec<crate::types::ThumbnailDecodeStatus> = Vec::with_capacity(n);
    for t in targets {
        let bytes = t
            .bytes
            .as_ref()
            .ok_or_else(|| missing_bytes_err(t.index))?;
        let path = if let Some(ref explicit) = explicit_paths {
            let p = &explicit[t.index];
            if let Some(parent) = p.parent() {
                if !parent.as_os_str().is_empty() {
                    std::fs::create_dir_all(parent).map_err(map_io_err)?;
                }
            }
            p.clone()
        } else {
            batch_thumb_path(output_dir.as_ref().unwrap(), t.index, &options.format)
        };
        write_bytes(bytes, &path)?;
        paths[t.index] = path.to_string_lossy().into_owned();
        decoded_status.push(decode_status_to_dto(t.status));
    }

    Ok(BatchThumbnailResult { paths, decoded_status })
}

pub fn extract_batch_thumbnail_bytes(
    options: BatchThumbnailBytesOptions,
    token: CancellationToken,
) -> Result<BatchThumbnailBytesResult> {
    if token.is_cancelled() {
        return Err(VideoForgeError::Cancelled);
    }

    ensure_ffmpeg_initialized()?;
    let input = options.input_path.trim();
    ensure_input_accessible(input)?;

    let n = options.positions_ms.len();
    if n == 0 {
        return Ok(BatchThumbnailBytesResult {
            frames: vec![],
            decoded_status: vec![],
        });
    }

    let mut targets = build_targets(&options.positions_ms);
    decode_batch_frames(
        input,
        &mut targets,
        options.width,
        options.height,
        Some(&options.format),
        token,
        false,
    )?;

    let mut frames = vec![Vec::new(); n];
    let mut decoded_status: Vec<crate::types::ThumbnailDecodeStatus> = Vec::with_capacity(n);
    for t in targets {
        frames[t.index] = t.bytes.ok_or_else(|| missing_bytes_err(t.index))?;
        decoded_status.push(decode_status_to_dto(t.status));
    }

    Ok(BatchThumbnailBytesResult { frames, decoded_status })
}

struct BatchTarget {
    index: usize,
    position_ms: u64,
    rgb: Option<RgbFrame>,
    bytes: Option<Vec<u8>>,
    /// What we actually decoded for this position (PR #3 graceful-degrade).
    /// `Exact` is the happy path; `NearestKeyframe` means we could not
    /// land a frame at/after `position_ms` so the consumer will see a
    /// `position_ms` that does not match the decoded frame's PTS.
    status: DecodeStatus,
}

/// Status of a single batch thumbnail's decode (PR #3).
///
/// `Exact` is the default and means a frame was captured at or after
/// the requested `position_ms`. `NearestKeyframe` is the graceful
/// fallback: the demuxer exhausted its packets before reaching
/// `position_ms` (file truncated, edit cut, or sparse keyframes), so
/// the caller receives the closest keyframe we *did* decode. The
/// FRB-exported [DecodeStatusDto] surfaces this so the UI can flag
/// "approximate" thumbnails in a filmstrip.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum DecodeStatus {
    Exact,
    NearestKeyframe,
    /// Hard failure (decoder crashed, codec not supported, etc.). The
    /// batch path returns the error from this target; the preview
    /// single-frame path returns [VideoForgeError::InvalidInput].
    Failed,
}

impl Default for DecodeStatus {
    fn default() -> Self {
        DecodeStatus::Exact
    }
}

#[derive(Clone)]
pub(crate) struct RgbFrame {
    pub(crate) width: u32,
    pub(crate) height: u32,
    pub(crate) data: Vec<u8>,
}

fn build_targets(positions_ms: &[u64]) -> Vec<BatchTarget> {
    positions_ms
        .iter()
        .enumerate()
        .map(|(i, &position_ms)| BatchTarget {
            index: i,
            position_ms,
            rgb: None,
            bytes: None,
            status: DecodeStatus::default(),
        })
        .collect()
}

fn missing_bytes_err(index: usize) -> VideoForgeError {
    VideoForgeError::Internal(format!("missing thumbnail bytes for index {index}"))
}

fn missing_rgb_err(index: usize) -> VideoForgeError {
    VideoForgeError::Internal(format!("missing decoded RGB for thumbnail index {index}"))
}

/// Decode one video frame to packed RGB24 (preview / scrub; separate from JPEG thumbnail path).
pub(crate) fn decode_rgb_frame_at(
    input: &str,
    position_ms: u64,
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: CancellationToken,
) -> Result<RgbFrame> {
    decode_scrub_rgb_frame_at(input, position_ms, max_w, max_h, token)
}

/// Optimized single-frame scrub: video-only demuxer, segmented seek, tight GOP window.
pub(crate) fn decode_scrub_rgb_frame_at(
    input: &str,
    position_ms: u64,
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: CancellationToken,
) -> Result<RgbFrame> {
    let _log = PreviewLogScope::quiet();
    let mut target = BatchTarget {
        index: 0,
        position_ms,
        rgb: None,
        bytes: None,
        status: DecodeStatus::default(),
    };
    decode_batch_frames(
        input,
        std::slice::from_mut(&mut target),
        max_w,
        max_h,
        None,
        token,
        true,
    )?;
    target.rgb.ok_or_else(|| {
        VideoForgeError::InvalidInput("could not decode frame at position".into())
    })
}

/// Cache-aware variant of [decode_scrub_rgb_frame_at]: tries the demuxer
/// cache first to avoid the `avformat_open_input` round-trip on repeated
/// calls. On miss, opens a fresh decoder, decodes, then re-inserts the
/// (open) entry into the cache via [crate::cache::release].
pub(crate) fn decode_scrub_rgb_frame_at_cached(
    input: &str,
    position_ms: u64,
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: CancellationToken,
) -> Result<RgbFrame> {
    use crate::cache::{acquire, release, OpenMode};

    let mut entry = acquire(input, OpenMode::Preview)?;
    let stream_idx = match entry.ictx.streams().best(ffmpeg_next::media::Type::Video) {
        Some(s) => s.index(),
        None => {
            return Err(VideoForgeError::InvalidInput(
                "no video stream in cached input".into(),
            ));
        }
    };
    let tb = entry
        .ictx
        .stream(stream_idx)
        .map(|s| s.time_base())
        .ok_or_else(|| VideoForgeError::Internal("missing stream for time_base".into()))?;

    let mut target = BatchTarget {
        index: 0,
        position_ms,
        rgb: None,
        bytes: None,
        status: DecodeStatus::default(),
    };
    let decode_out = decode_batch_frames_with_decoder(
        &mut entry.ictx,
        &mut entry.decoder,
        stream_idx,
        tb,
        std::slice::from_mut(&mut target),
        max_w,
        max_h,
        None,
        &token,
        true,
    );
    // Always release the entry back to the cache (even on error) so the
    // next call to the same path avoids the open. Decoder state may be
    // partially mid-seek; that is fine — the next call will re-seek.
    release(input, entry);
    decode_out?;
    target.rgb.ok_or_else(|| {
        VideoForgeError::InvalidInput("could not decode frame at position".into())
    })
}

/// Decode all batch positions using single-pass or segmented seek (A1).
fn decode_batch_frames(
    input: &str,
    targets: &mut [BatchTarget],
    max_w: Option<u32>,
    max_h: Option<u32>,
    encode_format: Option<&ThumbnailFormat>,
    token: CancellationToken,
    preview_scrub: bool,
) -> Result<()> {
    if targets.is_empty() {
        return Ok(());
    }

    for t in targets.iter_mut() {
        t.rgb = None;
        t.bytes = None;
        t.status = DecodeStatus::default();
    }

    targets.sort_by_key(|t| t.position_ms);

    let mut ictx = if preview_scrub {
        open_input_for_preview(input)?
    } else {
        open_input(input)?
    };
    attach_interrupt(&mut ictx, token.clone());

    let stream = ictx
        .streams()
        .best(ffmpeg_next::media::Type::Video)
        .ok_or_else(|| VideoForgeError::InvalidInput("no video stream".into()))?;
    let stream_idx = stream.index();
    let tb = stream.time_base();
    let params = stream.parameters();
    let duration_ms = input_duration_ms(&ictx);

    let mut dec_ctx = CodecContext::from_parameters(params).map_err(map_ffmpeg_error)?;
    if preview_scrub {
        apply_preview_scrub_decoder_settings(&mut dec_ctx);
    } else {
        apply_thumbnail_decoder_settings(&mut dec_ctx);
    }
    let mut decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;

    let positions: Vec<u64> = targets.iter().map(|t| t.position_ms).collect();
    let use_segmented = use_segmented_thumbnail_seek(&positions, duration_ms)
        || (preview_scrub && targets.len() == 1);
    decode_batch_frames_with_decoder(
        &mut ictx,
        &mut decoder,
        stream_idx,
        tb,
        targets,
        max_w,
        max_h,
        encode_format,
        &token,
        preview_scrub,
    )
}

/// Inner decode loop, shared by the open-and-decode path
/// ([decode_batch_frames]) and the cache-aware path
/// ([crate::cache::acquire] -> [decode_scrub_rgb_frame_at_cached]).
///
/// Owning the [Input] / [DecoderVideo] outside the lock is the cache
/// protocol — the caller is responsible for re-inserting the entry via
/// [crate::cache::release] after this function returns (success or
/// error).
fn decode_batch_frames_with_decoder(
    ictx: &mut Input,
    decoder: &mut DecoderVideo,
    stream_idx: usize,
    tb: Rational,
    targets: &mut [BatchTarget],
    max_w: Option<u32>,
    max_h: Option<u32>,
    encode_format: Option<&ThumbnailFormat>,
    token: &CancellationToken,
    preview_scrub: bool,
) -> Result<()> {
    let duration_ms = input_duration_ms(ictx);
    let positions: Vec<u64> = targets.iter().map(|t| t.position_ms).collect();
    let use_segmented = use_segmented_thumbnail_seek(&positions, duration_ms)
        || (preview_scrub && targets.len() == 1);
    if use_segmented {
        let first = positions[0];
        let last = *positions.last().unwrap();
        log::info!(
            "thumbnail batch: segmented seek ({} frames, span {}–{} ms, duration {} ms)",
            targets.len(),
            first,
            last,
            duration_ms
        );
        decode_batch_segmented(
            ictx,
            stream_idx,
            tb,
            decoder,
            targets,
            max_w,
            max_h,
            token,
            segmented_gop_approach_ms(preview_scrub, targets.len()),
        )?;
    } else {
        log::debug!(
            "thumbnail batch: single-pass ({} frames, span {} ms)",
            targets.len(),
            positions.last().unwrap().saturating_sub(positions[0])
        );
        decode_batch_sequential(
            ictx,
            stream_idx,
            tb,
            decoder,
            targets,
            max_w,
            max_h,
            &token,
        )?;
    }

    if let Some(format) = encode_format {
        encode_batch_targets_parallel(targets, format, &token)?;
    }
    Ok(())
}

/// How long before the target timestamp we switch from NonKey discard to full decode (A3).
const GOP_APPROACH_MS: u64 = 900;

/// Tight window for interactive scrub (decode only near the target frame).
const SCRUB_GOP_APPROACH_MS: u64 = 280;

/// Single-frame scrub at arbitrary playhead (Edit Frame): wide enough for 2–4s GOP UHD HEVC.
const SINGLE_FRAME_SCRUB_GOP_MS: u64 = 1500;

/// GOP discard window for segmented thumbnail / scrub decode.
pub(crate) fn segmented_gop_approach_ms(preview_scrub: bool, target_count: usize) -> u64 {
    if preview_scrub && target_count == 1 {
        SINGLE_FRAME_SCRUB_GOP_MS
    } else if preview_scrub {
        SCRUB_GOP_APPROACH_MS
    } else {
        GOP_APPROACH_MS
    }
}

/// One forward demux + decode between the first and last position (best for short spans).
fn decode_batch_sequential(
    ictx: &mut Input,
    stream_idx: usize,
    tb: Rational,
    decoder: &mut DecoderVideo,
    targets: &mut [BatchTarget],
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: &CancellationToken,
) -> Result<()> {
    let first_ms = targets[0].position_ms;
    if first_ms > 0 {
        let seek_ts = ms_to_stream_ts(first_ms, tb);
        if seek_stream_backward(ictx, stream_idx, seek_ts).is_err() {
            log::warn!(
                "thumbnail seek to {first_ms}ms failed; decoding from start"
            );
        }
        flush_video_decoder(decoder);
    }

    let mut frame = Video::empty();
    let mut color_scaler: Option<ScalerContext> = None;
    let mut color_src_key: Option<(u32, u32, Pixel, u32, u32)> = None;
    let mut last_rgb: Option<RgbFrame> = None;
    let mut last_rgb_pts_ms: Option<u64> = None;
    let mut next = 0usize;

    for (s, packet) in ictx.packets() {
        if token.is_cancelled() {
            return Err(VideoForgeError::Cancelled);
        }
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        while decoder.receive_frame(&mut frame).is_ok() {
            let pts_ms = frame_pts_ms(&frame, tb);
            apply_frame_to_batch_targets(
                decoder,
                &frame,
                pts_ms,
                targets,
                &mut next,
                max_w,
                max_h,
                &mut color_scaler,
                &mut color_src_key,
                &mut last_rgb,
                &mut last_rgb_pts_ms,
            )?;
            if next >= targets.len() {
                decoder.skip_frame(Discard::None);
                return Ok(());
            }
        }
    }

    decoder.send_eof().map_err(map_ffmpeg_error)?;
    while decoder.receive_frame(&mut frame).is_ok() {
        let pts_ms = frame_pts_ms(&frame, tb);
        apply_frame_to_batch_targets(
            decoder,
            &frame,
            pts_ms,
            targets,
            &mut next,
            max_w,
            max_h,
            &mut color_scaler,
            &mut color_src_key,
            &mut last_rgb,
            &mut last_rgb_pts_ms,
        )?;
        if next >= targets.len() {
            decoder.skip_frame(Discard::None);
            return Ok(());
        }
    }

    decoder.skip_frame(Discard::None);
    if next < targets.len() {
        if let Some(rgb) = last_rgb {
            // PR #3: graceful-degrade instead of the old silent "use
            // last frame for everyone" fill. We only fill positions
            // *past* the last decoded PTS, and we mark them so the UI
            // can distinguish.
            fill_remaining_targets_with_nearest_keyframe(
                targets,
                next,
                &rgb,
                *last_rgb_pts_ms.get_or_insert(0),
            );
            return Ok(());
        }
        return batch_incomplete_error(next, targets.len());
    }
    Ok(())
}

/// Seek per position — best when positions span most of a long iPhone / filmstrip clip (A1).
fn decode_batch_segmented(
    ictx: &mut Input,
    stream_idx: usize,
    tb: Rational,
    decoder: &mut DecoderVideo,
    targets: &mut [BatchTarget],
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: &CancellationToken,
    gop_approach_ms: u64,
) -> Result<()> {
    let mut color_scaler: Option<ScalerContext> = None;
    let mut color_src_key: Option<(u32, u32, Pixel, u32, u32)> = None;

    for t in targets.iter_mut() {
        if token.is_cancelled() {
            return Err(VideoForgeError::Cancelled);
        }

        let target_ms = t.position_ms;
        let mut captured = decode_one_segmented_target(
            ictx,
            stream_idx,
            tb,
            decoder,
            t,
            max_w,
            max_h,
            token,
            gop_approach_ms,
            target_ms,
            target_ms,
            &mut color_scaler,
            &mut color_src_key,
        )?;

        if !captured {
            log::warn!(
                "thumbnail segmented decode at {target_ms}ms failed; retry from start"
            );
            captured = decode_one_segmented_target(
                ictx,
                stream_idx,
                tb,
                decoder,
                t,
                max_w,
                max_h,
                token,
                target_ms,
                0,
                target_ms,
                &mut color_scaler,
                &mut color_src_key,
            )?;
        }

        decoder.skip_frame(Discard::None);
        if !captured {
            return Err(VideoForgeError::InvalidInput(format!(
                "could not decode thumbnail at {target_ms}ms"
            )));
        }
    }

    Ok(())
}

/// Seek near [seek_ms] and decode until a frame at/after [target_ms] is captured.
///
/// PR #3: on `seek_ms=0` (the "retry from start" path) we still use
/// the [seek_stream_two_tier] helper so an unreachable exact PTS falls
/// back to `AVSEEK_FLAG_ANY` instead of erroring out. The two-tier
/// helper is also used for the per-target seek; on a sparse-GOP clip
/// where the backward seek lands before the target and there is no
/// keyframe between the seek point and the target, the helper retries
/// with `AVSEEK_FLAG_ANY` and we decode forward from the prior
/// keyframe.
fn decode_one_segmented_target(
    ictx: &mut Input,
    stream_idx: usize,
    tb: Rational,
    decoder: &mut DecoderVideo,
    target: &mut BatchTarget,
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: &CancellationToken,
    gop_approach_ms: u64,
    seek_ms: u64,
    target_ms: u64,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
) -> Result<bool> {
    use crate::ffmpeg::SeekOutcome;
    if token.is_cancelled() {
        return Err(VideoForgeError::Cancelled);
    }

    let seek_ts = ms_to_stream_ts(seek_ms, tb);
    // Two-tier seek: backward (to keyframe), any (exact PTS) as a
    // second attempt. If the first tier also returns `Ok(Back)`, that
    // is the normal happy path; the second tier is rare.
    let outcome = match seek_stream_two_tier(ictx, stream_idx, seek_ts) {
        Ok(o) => Some(o),
        Err(e) => {
            // Total failure: only fall back to "from start" when the
            // caller had asked for a non-zero seek (i.e. we're in the
            // first iteration of the per-target loop and the seek_ts
            // is the per-target position, not 0).
            if seek_ms > 0 {
                log::warn!(
                    "thumbnail segmented two-tier seek to {seek_ms}ms failed ({e}); trying from start"
                );
                seek_stream_two_tier(ictx, stream_idx, 0).ok()
            } else {
                return Err(e);
            }
        }
    };
    if outcome.is_none() {
        return Ok(false);
    }
    flush_video_decoder(decoder);
    decoder.skip_frame(Discard::NonKey);

    let mut frame = Video::empty();
    let mut captured = false;
    let mut last_pts_ms: u64 = 0;

    for (s, packet) in ictx.packets() {
        if token.is_cancelled() {
            decoder.skip_frame(Discard::None);
            return Err(VideoForgeError::Cancelled);
        }
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        while decoder.receive_frame(&mut frame).is_ok() {
            let pts_ms = frame_pts_ms(&frame, tb);
            apply_skip_until_target(decoder, pts_ms, target_ms, gop_approach_ms);
            last_pts_ms = pts_ms;

            if pts_ms >= target_ms {
                capture_target_frame(
                    &frame,
                    target,
                    max_w,
                    max_h,
                    color_scaler,
                    color_src_key,
                )?;
                // PR #3: mark this target as an exact match. If the
                // two-tier seek had to fall back to `AVSEEK_FLAG_ANY`
                // we still treat the decode as exact because we did
                // land on a frame at/after the target.
                target.status = DecodeStatus::Exact;
                captured = true;
                break;
            }
        }
        if captured {
            break;
        }
    }

    if !captured {
        // If the two-tier seek landed us at `SeekOutcome::Any` (exact
        // PTS) but the demuxer still did not produce a frame, the
        // container is broken. Mark as failed so the caller can
        // surface a different error message.
        if matches!(outcome, Some(SeekOutcome::Any)) {
            log::warn!(
                "[Thumbnail] two-tier seek landed at SeekOutcome::Any but no frame at/after \
                 {target_ms}ms (last decoded PTS = {last_pts_ms}ms)"
            );
        }
    }

    Ok(captured)
}

fn apply_skip_until_target(
    decoder: &mut DecoderVideo,
    pts_ms: u64,
    target_ms: u64,
    gop_approach_ms: u64,
) {
    let approach = target_ms.saturating_sub(gop_approach_ms);
    if pts_ms < approach {
        decoder.skip_frame(Discard::NonKey);
    } else {
        decoder.skip_frame(Discard::None);
    }
}

fn capture_target_frame(
    frame: &Video,
    target: &mut BatchTarget,
    max_w: Option<u32>,
    max_h: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
) -> Result<()> {
    target.rgb = Some(video_to_rgb(
        frame,
        max_w,
        max_h,
        color_scaler,
        color_src_key,
    )?);
    Ok(())
}

/// Apply one decoded frame to sorted batch targets (first frame with `pts >= position`).
fn apply_frame_to_batch_targets(
    decoder: &mut DecoderVideo,
    frame: &Video,
    pts_ms: u64,
    targets: &mut [BatchTarget],
    next: &mut usize,
    max_w: Option<u32>,
    max_h: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
    last_rgb: &mut Option<RgbFrame>,
    last_rgb_pts_ms: &mut Option<u64>,
) -> Result<()> {
    apply_skip_until_target(decoder, pts_ms, targets[*next].position_ms, GOP_APPROACH_MS);

    let rgb = video_to_rgb(frame, max_w, max_h, color_scaler, color_src_key)?;
    *last_rgb = Some(rgb.clone());
    *last_rgb_pts_ms = Some(pts_ms);

    while *next < targets.len() && pts_ms >= targets[*next].position_ms {
        targets[*next].rgb = Some(rgb.clone());
        // Frame PTS >= target position, so the match is exact.
        targets[*next].status = DecodeStatus::Exact;
        *next += 1;
        if *next < targets.len() {
            apply_skip_until_target(decoder, pts_ms, targets[*next].position_ms, GOP_APPROACH_MS);
        }
    }
    Ok(())
}

/// Map the internal `DecodeStatus` to the FRB-exported DTO. A single
/// `Failed` slot in a batch is already returned as `Err` from the
/// caller (see `batch_incomplete_error` and the
/// `decode_one_segmented_target` failure path), so the DTO only has to
/// distinguish `Exact` vs `NearestKeyframe` from the consumer's POV.
fn decode_status_to_dto(status: DecodeStatus) -> crate::types::ThumbnailDecodeStatus {
    match status {
        DecodeStatus::Exact | DecodeStatus::Failed => crate::types::ThumbnailDecodeStatus::Exact,
        DecodeStatus::NearestKeyframe => crate::types::ThumbnailDecodeStatus::NearestKeyframe,
    }
}

/// Graceful-degrade: if a target is past the demuxer's last PTS, fill
/// it with the closest keyframe we already decoded and mark its status
/// as `NearestKeyframe`. The caller surfaces this through the
/// `BatchThumbnailResult.decoded_status` field so the UI can show a
/// subtle indicator (e.g. dimmed thumbnail, "approximate" badge).
///
/// Replaces the previous `fill_remaining_targets_from_last_rgb` which
/// silently masked off-by-one position requests with the same RGB
/// frame for every remaining target. The new behavior:
/// - Only applies to targets whose `position_ms` is *after* the last
///   decoded PTS. Targets at/before the last decoded PTS still get
///   the exact match (or an earlier frame from `apply_frame_to_batch_targets`).
/// - Marks each affected target with `DecodeStatus::NearestKeyframe`.
/// - Logs a `warn!` so users can grep for the fallback in production.
fn fill_remaining_targets_with_nearest_keyframe(
    targets: &mut [BatchTarget],
    next: usize,
    last_rgb: &RgbFrame,
    last_pts_ms: u64,
) {
    let remaining = targets.len().saturating_sub(next);
    if remaining == 0 {
        return;
    }
    let mut filled = 0usize;
    for t in targets.iter_mut().skip(next) {
        if t.position_ms > last_pts_ms {
            t.rgb = Some(last_rgb.clone());
            t.status = DecodeStatus::NearestKeyframe;
            filled += 1;
        }
    }
    if filled > 0 {
        log::warn!(
            "[Thumbnail] nearest-keyframe fallback: {filled} target(s) past last decoded PTS \
             ({last_pts_ms}ms) — using closest decoded frame; UI should flag as approximate"
        );
    }
}

/// Parallel JPEG/WebP encode after batch decode (decode/demux stays single-threaded).
fn encode_batch_targets_parallel(
    targets: &mut [BatchTarget],
    format: &ThumbnailFormat,
    token: &CancellationToken,
) -> Result<()> {
    if token.is_cancelled() {
        return Err(VideoForgeError::Cancelled);
    }

    if targets.len() <= 1 {
        for t in targets.iter_mut() {
            let rgb = t.rgb.as_ref().ok_or_else(|| missing_rgb_err(t.index))?;
            t.bytes = Some(encode_rgb_to_bytes(rgb, format)?);
        }
        return Ok(());
    }

    let encoded: Vec<Result<Vec<u8>>> = targets
        .par_iter()
        .map(|t| {
            if token.is_cancelled() {
                return Err(VideoForgeError::Cancelled);
            }
            let rgb = t.rgb.as_ref().ok_or_else(|| missing_rgb_err(t.index))?;
            encode_rgb_to_bytes(rgb, format)
        })
        .collect();

    for (t, bytes) in targets.iter_mut().zip(encoded) {
        t.bytes = Some(bytes?);
    }
    Ok(())
}

fn batch_incomplete_error(decoded: usize, total: usize) -> Result<()> {
    if decoded >= total {
        return Ok(());
    }
    Err(VideoForgeError::InvalidInput(
        format!(
            "could not decode {} of {} batch thumbnail positions",
            total - decoded,
            total
        )
        .into(),
    ))
}

fn frame_pts_ms(frame: &Video, tb: Rational) -> u64 {
    let pts = frame.timestamp().unwrap_or(0);
    let ms = pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0;
    ms.max(0.0) as u64
}

pub(crate) fn thumb_dimensions(
    src_w: u32,
    src_h: u32,
    max_w: Option<u32>,
    max_h: Option<u32>,
) -> (u32, u32) {
    match (max_w, max_h) {
        (Some(w), Some(h)) => (w & !1, h & !1),
        (Some(w), None) => {
            let h = (src_h as f64 * w as f64 / src_w as f64) as u32;
            (w & !1, h & !1)
        }
        _ => (src_w & !1, src_h & !1),
    }
}

pub(crate) fn video_to_rgb(
    frame: &Video,
    max_w: Option<u32>,
    max_h: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
) -> Result<RgbFrame> {
    let src_w = frame.width();
    let src_h = frame.height();
    let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_w, max_h);

    let data = convert_frame_to_rgb24(
        frame,
        out_w,
        out_h,
        color_scaler,
        color_src_key,
    )?;

    Ok(RgbFrame {
        width: out_w,
        height: out_h,
        data,
    })
}

/// YUV (or other FFmpeg pixel format) → packed RGB24, scaled to `(out_w, out_h)` in one pass.
fn convert_frame_to_rgb24(
    frame: &Video,
    out_w: u32,
    out_h: u32,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel, u32, u32)>,
) -> Result<Vec<u8>> {
    let src_w = frame.width();
    let src_h = frame.height();
    let fmt = frame.format();
    if crate::ffmpeg::hw_decode::is_hw_pixel_format(fmt) {
        return Err(VideoForgeError::Internal(
            "cannot swscale hardware-decoded frame; transfer to system memory or use pixel-buffer preview path".into(),
        ));
    }
    let key = (src_w, src_h, fmt, out_w, out_h);
    if color_scaler.is_none() || *color_src_key != Some(key) {
        *color_scaler = Some(
            ScalerContext::get(
                fmt,
                src_w,
                src_h,
                Pixel::RGB24,
                out_w,
                out_h,
                Flags::FAST_BILINEAR,
            )
            .map_err(map_ffmpeg_error)?,
        );
        *color_src_key = Some(key);
    }

    let mut rgb = Video::empty();
    color_scaler
        .as_mut()
        .expect("color scaler")
        .run(frame, &mut rgb)
        .map_err(map_ffmpeg_error)?;
    copy_rgb24_plane(&rgb)
}

fn copy_rgb24_plane(rgb: &Video) -> Result<Vec<u8>> {
    let stride = rgb.stride(0) as usize;
    let h = rgb.height() as usize;
    let w = rgb.width() as usize;
    let mut data = Vec::with_capacity(w * h * 3);
    let slice = rgb.data(0);
    for row in 0..h {
        let start = row * stride;
        data.extend_from_slice(&slice[start..start + w * 3]);
    }
    Ok(data)
}

fn encode_rgb_to_bytes(frame: &RgbFrame, format: &ThumbnailFormat) -> Result<Vec<u8>> {
    let img: RgbImage =
        ImageBuffer::from_raw(frame.width, frame.height, frame.data.clone()).ok_or_else(|| {
            VideoForgeError::Internal("invalid RGB buffer".into())
        })?;

    let image_format = match format {
        ThumbnailFormat::Jpeg => ImageFormat::Jpeg,
        ThumbnailFormat::Webp => ImageFormat::WebP,
    };

    let mut buffer = Vec::new();
    img.write_to(&mut Cursor::new(&mut buffer), image_format)
        .map_err(map_io_err)?;
    Ok(buffer)
}

fn write_bytes(bytes: &[u8], path: &Path) -> Result<()> {
    ensure_output_parent(path)?;
    std::fs::write(path, bytes).map_err(map_io_err)
}

fn map_io_err(err: impl std::fmt::Display) -> VideoForgeError {
    VideoForgeError::IoError(err.to_string())
}

fn ensure_output_parent(path: &Path) -> Result<()> {
    let parent = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    std::fs::create_dir_all(parent).map_err(map_io_err)?;
    Ok(())
}

fn default_thumb_dir() -> PathBuf {
    std::env::temp_dir()
        .join("video_forge")
        .join("thumbnails")
}

fn batch_thumb_path(dir: &Path, index: usize, format: &ThumbnailFormat) -> PathBuf {
    let ext = match format {
        ThumbnailFormat::Jpeg => "jpg",
        ThumbnailFormat::Webp => "webp",
    };
    dir.join(format!("thumb_{index:04}.{ext}"))
}

fn resolve_thumb_path(
    input: &str,
    explicit: Option<&str>,
    format: &ThumbnailFormat,
) -> Result<PathBuf> {
    if let Some(p) = explicit.map(str::trim).filter(|s| !s.is_empty()) {
        return Ok(PathBuf::from(p));
    }
    if crate::ffmpeg::is_remote_input(input) {
        return Err(VideoForgeError::InvalidInput(
            "remote input requires an explicit thumbnail output path".into(),
        ));
    }

    let ext = match format {
        ThumbnailFormat::Jpeg => "jpg",
        ThumbnailFormat::Webp => "webp",
    };
    let stem = output_stem_from_input(input);
    let dir = default_thumb_dir();
    std::fs::create_dir_all(&dir).map_err(map_io_err)?;
    Ok(dir.join(format!("{stem}_thumb.{ext}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn segmented_gop_approach_single_scrub_is_wide() {
        assert_eq!(
            segmented_gop_approach_ms(true, 1),
            SINGLE_FRAME_SCRUB_GOP_MS
        );
        assert!(segmented_gop_approach_ms(true, 1) > SCRUB_GOP_APPROACH_MS);
    }

    #[test]
    fn segmented_gop_approach_multi_scrub_stays_tight() {
        assert_eq!(
            segmented_gop_approach_ms(true, 3),
            SCRUB_GOP_APPROACH_MS
        );
    }

    #[test]
    fn segmented_gop_approach_thumbnail_batch_uses_default() {
        assert_eq!(
            segmented_gop_approach_ms(false, 10),
            GOP_APPROACH_MS
        );
    }

    // --- PR #3: graceful-degrade + status mapping ---

    fn make_test_target(position_ms: u64, status: DecodeStatus) -> BatchTarget {
        BatchTarget {
            index: 0,
            position_ms,
            rgb: None,
            bytes: None,
            status,
        }
    }

    #[test]
    fn graceful_degrade_marks_only_past_pts_targets() {
        // Last decoded PTS = 5000 ms. Targets at 3000, 5000, 7000, 9000.
        // 3000 and 5000 are at-or-before the last PTS so they should
        // remain Exact (caller is expected to have set Exact on them
        // already via apply_frame_to_batch_targets). 7000 and 9000 are
        // *past* the last PTS and should be marked NearestKeyframe.
        let last_rgb = RgbFrame {
            width: 16,
            height: 16,
            data: vec![0u8; 16 * 16 * 3],
        };
        let mut targets = vec![
            make_test_target(3000, DecodeStatus::Exact),
            make_test_target(5000, DecodeStatus::Exact),
            make_test_target(7000, DecodeStatus::Exact),
            make_test_target(9000, DecodeStatus::Exact),
        ];
        fill_remaining_targets_with_nearest_keyframe(&mut targets, 2, &last_rgb, 5000);
        assert_eq!(targets[0].status, DecodeStatus::Exact);
        assert_eq!(targets[1].status, DecodeStatus::Exact);
        assert_eq!(targets[2].status, DecodeStatus::NearestKeyframe);
        assert_eq!(targets[3].status, DecodeStatus::NearestKeyframe);
    }

    #[test]
    fn graceful_degrade_no_fill_when_all_targets_already_matched() {
        // next == targets.len() → no fill happens.
        let last_rgb = RgbFrame {
            width: 4,
            height: 4,
            data: vec![0u8; 4 * 4 * 3],
        };
        let mut targets = vec![make_test_target(0, DecodeStatus::Exact)];
        fill_remaining_targets_with_nearest_keyframe(&mut targets, 1, &last_rgb, 9999);
        // Status unchanged.
        assert_eq!(targets[0].status, DecodeStatus::Exact);
    }

    #[test]
    fn decode_status_dto_mapping() {
        // The DTO collapses `Failed` to `Exact` (the batch path returns
        // an Err on Failed before reaching the consumer).
        assert_eq!(
            decode_status_to_dto(DecodeStatus::Exact),
            crate::types::ThumbnailDecodeStatus::Exact
        );
        assert_eq!(
            decode_status_to_dto(DecodeStatus::Failed),
            crate::types::ThumbnailDecodeStatus::Exact
        );
        assert_eq!(
            decode_status_to_dto(DecodeStatus::NearestKeyframe),
            crate::types::ThumbnailDecodeStatus::NearestKeyframe
        );
    }

    #[test]
    fn frame_pts_ms_handles_zero_timebase() {
        // Defensive: a broken or zero time_base (parser bug) should
        // not produce NaN/negative values.
        let tb = Rational(0, 1);
        // Construct an empty Video frame; we only need timestamp()
        // to return 0 for this test.
        let frame = Video::empty();
        assert_eq!(frame_pts_ms(&frame, tb), 0);
    }
}
