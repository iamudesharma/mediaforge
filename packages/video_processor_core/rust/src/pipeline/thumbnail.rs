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

use fast_image_resize::images::Image as FirImage;
use fast_image_resize::{FilterType, PixelType, ResizeAlg, ResizeOptions, Resizer};
use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video as DecoderVideo;
use ffmpeg_next::codec::discard::Discard;
use ffmpeg_next::format::{context::Input, Pixel};
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags};
use ffmpeg_next::util::frame::video::Video;
use ffmpeg_next::Rational;
use image::{ImageBuffer, ImageFormat, RgbImage};
use rayon::prelude::*;

use crate::error::{Result, VideoProcessorError};
use crate::ffmpeg::{
    apply_thumbnail_decoder_settings, ensure_ffmpeg_initialized, ensure_input_accessible,
    flush_video_decoder, input_duration_ms, input::output_stem_from_input, map_ffmpeg_error,
    ms_to_stream_ts, open_input, seek_stream_backward, use_segmented_thumbnail_seek,
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

    let rgb = decode_rgb_frame_at(
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
        return Err(VideoProcessorError::Cancelled);
    }

    ensure_ffmpeg_initialized()?;
    let input = options.input_path.trim();
    ensure_input_accessible(input)?;

    let n = options.positions_ms.len();
    if n == 0 {
        return Ok(BatchThumbnailResult { paths: vec![] });
    }

    let explicit_paths = options.output_paths.as_ref().map(|paths| {
        if paths.len() != n {
            Err(VideoProcessorError::InvalidInput(format!(
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
            return Err(VideoProcessorError::InvalidInput(
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
    )?;

    let mut paths = vec![String::new(); n];
    for t in targets {
        let bytes = t
            .bytes
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
        write_bytes(&bytes, &path)?;
        paths[t.index] = path.to_string_lossy().into_owned();
    }

    Ok(BatchThumbnailResult { paths })
}

pub fn extract_batch_thumbnail_bytes(
    options: BatchThumbnailBytesOptions,
    token: CancellationToken,
) -> Result<BatchThumbnailBytesResult> {
    if token.is_cancelled() {
        return Err(VideoProcessorError::Cancelled);
    }

    ensure_ffmpeg_initialized()?;
    let input = options.input_path.trim();
    ensure_input_accessible(input)?;

    let n = options.positions_ms.len();
    if n == 0 {
        return Ok(BatchThumbnailBytesResult { frames: vec![] });
    }

    let mut targets = build_targets(&options.positions_ms);
    decode_batch_frames(
        input,
        &mut targets,
        options.width,
        options.height,
        Some(&options.format),
        token,
    )?;

    let mut frames = vec![Vec::new(); n];
    for t in targets {
        frames[t.index] = t.bytes.ok_or_else(|| missing_bytes_err(t.index))?;
    }

    Ok(BatchThumbnailBytesResult { frames })
}

struct BatchTarget {
    index: usize,
    position_ms: u64,
    rgb: Option<RgbFrame>,
    bytes: Option<Vec<u8>>,
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
        })
        .collect()
}

fn missing_bytes_err(index: usize) -> VideoProcessorError {
    VideoProcessorError::Internal(format!("missing thumbnail bytes for index {index}"))
}

fn missing_rgb_err(index: usize) -> VideoProcessorError {
    VideoProcessorError::Internal(format!("missing decoded RGB for thumbnail index {index}"))
}

/// Decode one video frame to packed RGB24 (preview / scrub; separate from JPEG thumbnail path).
pub(crate) fn decode_rgb_frame_at(
    input: &str,
    position_ms: u64,
    max_w: Option<u32>,
    max_h: Option<u32>,
    token: CancellationToken,
) -> Result<RgbFrame> {
    let mut target = BatchTarget {
        index: 0,
        position_ms,
        rgb: None,
        bytes: None,
    };
    decode_batch_frames(
        input,
        std::slice::from_mut(&mut target),
        max_w,
        max_h,
        None,
        token,
    )?;
    target.rgb.ok_or_else(|| {
        VideoProcessorError::InvalidInput("could not decode frame at position".into())
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
) -> Result<()> {
    if targets.is_empty() {
        return Ok(());
    }

    for t in targets.iter_mut() {
        t.rgb = None;
        t.bytes = None;
    }

    targets.sort_by_key(|t| t.position_ms);

    let mut ictx = open_input(input)?;
    attach_interrupt(&mut ictx, token.clone());

    let stream = ictx
        .streams()
        .best(ffmpeg_next::media::Type::Video)
        .ok_or_else(|| VideoProcessorError::InvalidInput("no video stream".into()))?;
    let stream_idx = stream.index();
    let tb = stream.time_base();
    let params = stream.parameters();
    let duration_ms = input_duration_ms(&ictx);

    let mut dec_ctx = CodecContext::from_parameters(params).map_err(map_ffmpeg_error)?;
    apply_thumbnail_decoder_settings(&mut dec_ctx);
    let mut decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;

    let positions: Vec<u64> = targets.iter().map(|t| t.position_ms).collect();
    if use_segmented_thumbnail_seek(&positions, duration_ms) {
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
            &mut ictx,
            stream_idx,
            tb,
            &mut decoder,
            targets,
            max_w,
            max_h,
            &token,
        )?;
    } else {
        log::debug!(
            "thumbnail batch: single-pass ({} frames, span {} ms)",
            targets.len(),
            positions.last().unwrap().saturating_sub(positions[0])
        );
        decode_batch_sequential(
            &mut ictx,
            stream_idx,
            tb,
            &mut decoder,
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
    let mut color_src_key: Option<(u32, u32, Pixel)> = None;
    let mut last_rgb: Option<RgbFrame> = None;
    let mut next = 0usize;

    for (s, packet) in ictx.packets() {
        if token.is_cancelled() {
            return Err(VideoProcessorError::Cancelled);
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
        )?;
        if next >= targets.len() {
            decoder.skip_frame(Discard::None);
            return Ok(());
        }
    }

    decoder.skip_frame(Discard::None);
    if next < targets.len() {
        if let Some(rgb) = last_rgb {
            fill_remaining_targets_from_last_rgb(targets, next, &rgb);
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
) -> Result<()> {
    let mut color_scaler: Option<ScalerContext> = None;
    let mut color_src_key: Option<(u32, u32, Pixel)> = None;

    for t in targets.iter_mut() {
        if token.is_cancelled() {
            return Err(VideoProcessorError::Cancelled);
        }

        let target_ms = t.position_ms;
        let seek_ts = ms_to_stream_ts(target_ms, tb);
        if seek_stream_backward(ictx, stream_idx, seek_ts).is_err() && target_ms > 0 {
            log::warn!("thumbnail segmented seek to {target_ms}ms failed; trying from start");
            let _ = seek_stream_backward(ictx, stream_idx, 0);
        }
        flush_video_decoder(decoder);
        decoder.skip_frame(Discard::NonKey);

        let mut frame = Video::empty();
        let mut captured = false;

        for (s, packet) in ictx.packets() {
            if token.is_cancelled() {
                decoder.skip_frame(Discard::None);
                return Err(VideoProcessorError::Cancelled);
            }
            if s.index() != stream_idx {
                continue;
            }
            decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

            while decoder.receive_frame(&mut frame).is_ok() {
                let pts_ms = frame_pts_ms(&frame, tb);
                apply_skip_until_target(decoder, pts_ms, target_ms);

                if pts_ms >= target_ms {
                    capture_target_frame(
                        &frame,
                        t,
                        max_w,
                        max_h,
                        &mut color_scaler,
                        &mut color_src_key,
                    )?;
                    captured = true;
                    break;
                }
            }
            if captured {
                break;
            }
        }

        decoder.skip_frame(Discard::None);
        if !captured {
            return Err(VideoProcessorError::InvalidInput(format!(
                "could not decode thumbnail at {target_ms}ms"
            )));
        }
    }

    Ok(())
}

fn apply_skip_until_target(decoder: &mut DecoderVideo, pts_ms: u64, target_ms: u64) {
    let approach = target_ms.saturating_sub(GOP_APPROACH_MS);
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
    color_src_key: &mut Option<(u32, u32, Pixel)>,
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
    color_src_key: &mut Option<(u32, u32, Pixel)>,
    last_rgb: &mut Option<RgbFrame>,
) -> Result<()> {
    apply_skip_until_target(decoder, pts_ms, targets[*next].position_ms);

    let rgb = video_to_rgb(frame, max_w, max_h, color_scaler, color_src_key)?;
    *last_rgb = Some(rgb.clone());

    while *next < targets.len() && pts_ms >= targets[*next].position_ms {
        targets[*next].rgb = Some(rgb.clone());
        *next += 1;
        if *next < targets.len() {
            apply_skip_until_target(decoder, pts_ms, targets[*next].position_ms);
        }
    }
    Ok(())
}

fn fill_remaining_targets_from_last_rgb(
    targets: &mut [BatchTarget],
    next: usize,
    last_rgb: &RgbFrame,
) {
    let remaining = targets.len().saturating_sub(next);
    if remaining > 0 {
        log::debug!(
            "thumbnail batch: using last decoded frame for {remaining} position(s) past last PTS"
        );
    }
    for t in targets.iter_mut().skip(next) {
        t.rgb = Some(last_rgb.clone());
    }
}

/// Parallel JPEG/WebP encode after batch decode (decode/demux stays single-threaded).
fn encode_batch_targets_parallel(
    targets: &mut [BatchTarget],
    format: &ThumbnailFormat,
    token: &CancellationToken,
) -> Result<()> {
    if token.is_cancelled() {
        return Err(VideoProcessorError::Cancelled);
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
                return Err(VideoProcessorError::Cancelled);
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
    Err(VideoProcessorError::InvalidInput(
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

fn video_to_rgb(
    frame: &Video,
    max_w: Option<u32>,
    max_h: Option<u32>,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel)>,
) -> Result<RgbFrame> {
    let src_w = frame.width();
    let src_h = frame.height();
    let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_w, max_h);

    let src_rgb = convert_frame_to_rgb24(frame, color_scaler, color_src_key)?;
    let data = if src_w == out_w && src_h == out_h {
        src_rgb
    } else {
        downscale_rgb24(src_rgb, src_w, src_h, out_w, out_h)?
    };

    Ok(RgbFrame {
        width: out_w,
        height: out_h,
        data,
    })
}

/// YUV (or other FFmpeg pixel format) → packed RGB24 at **source** resolution.
fn convert_frame_to_rgb24(
    frame: &Video,
    color_scaler: &mut Option<ScalerContext>,
    color_src_key: &mut Option<(u32, u32, Pixel)>,
) -> Result<Vec<u8>> {
    let src_w = frame.width();
    let src_h = frame.height();
    let fmt = frame.format();
    let key = (src_w, src_h, fmt);
    if color_scaler.is_none() || *color_src_key != Some(key) {
        *color_scaler = Some(
            ScalerContext::get(
                fmt,
                src_w,
                src_h,
                Pixel::RGB24,
                src_w,
                src_h,
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

fn downscale_rgb24(
    data: Vec<u8>,
    src_w: u32,
    src_h: u32,
    out_w: u32,
    out_h: u32,
) -> Result<Vec<u8>> {
    let src_image =
        FirImage::from_vec_u8(src_w, src_h, data, PixelType::U8x3).map_err(map_fir_buffer_err)?;
    let mut dst_image = FirImage::new(out_w, out_h, PixelType::U8x3);
    let mut resizer = Resizer::new();
    let options =
        ResizeOptions::new().resize_alg(ResizeAlg::Convolution(FilterType::Bilinear));
    resizer
        .resize(&src_image, &mut dst_image, Some(&options))
        .map_err(map_resize_err)?;
    Ok(dst_image.into_vec())
}

fn map_fir_buffer_err(err: fast_image_resize::ImageBufferError) -> VideoProcessorError {
    VideoProcessorError::Internal(format!("thumbnail image buffer: {err:?}"))
}

fn map_resize_err(err: fast_image_resize::ResizeError) -> VideoProcessorError {
    VideoProcessorError::Internal(format!("thumbnail resize: {err}"))
}

fn encode_rgb_to_bytes(frame: &RgbFrame, format: &ThumbnailFormat) -> Result<Vec<u8>> {
    let img: RgbImage =
        ImageBuffer::from_raw(frame.width, frame.height, frame.data.clone()).ok_or_else(|| {
            VideoProcessorError::Internal("invalid RGB buffer".into())
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

fn map_io_err(err: impl std::fmt::Display) -> VideoProcessorError {
    VideoProcessorError::IoError(err.to_string())
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
        .join("flutter_video_processor")
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
        return Err(VideoProcessorError::InvalidInput(
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
