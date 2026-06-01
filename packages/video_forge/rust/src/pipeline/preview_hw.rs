//! Apple VideoToolbox preview decode → BGRA `CVPixelBuffer` (Sprint V1.4).

use ffmpeg_next::codec::decoder::Video as DecoderVideo;
use ffmpeg_next::codec::discard::Discard;
use ffmpeg_next::util::frame::video::Video;
use ffmpeg_next::Rational;

use crate::error::{Result, VideoProcessorError};
use crate::ffmpeg::{
    ensure_ffmpeg_initialized, ensure_input_accessible, flush_video_decoder, hw_decode,
    map_ffmpeg_error, ms_to_stream_ts, open_input, open_video_decoder, seek_stream_backward,
};
use crate::pipeline::thumbnail::thumb_dimensions;
use crate::types::PreviewFramePixelBuffer;

const GOP_APPROACH_MS: u64 = 900;

/// `VFP_DISABLE_HW_PREVIEW=1` forces RGBA software preview on Apple.
pub fn hw_preview_enabled() -> bool {
    hw_decode::enabled()
        && !matches!(
            std::env::var("VFP_DISABLE_HW_PREVIEW").as_deref(),
            Ok("1") | Ok("true") | Ok("yes")
        )
}

/// Decode one HW frame and transfer to a BGRA `CVPixelBuffer` for texture presentation.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub fn decode_preview_pixel_buffer(
    input_path: &str,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFramePixelBuffer> {
    ensure_ffmpeg_initialized()?;
    let input = input_path.trim();
    ensure_input_accessible(input)?;

    let mut ictx = open_input(input)?;
    let stream = ictx
        .streams()
        .best(ffmpeg_next::media::Type::Video)
        .ok_or_else(|| VideoProcessorError::InvalidInput("no video stream".into()))?;
    let stream_idx = stream.index();
    let tb = stream.time_base();
    let params = stream.parameters();

    let (mut decoder, hw) =
        open_video_decoder(params, true).map_err(|e| VideoProcessorError::Internal(e.to_string()))?;
    let mut hw = hw.ok_or_else(|| {
        VideoProcessorError::Internal("VideoToolbox preview decode unavailable".into())
    })?;

    let target_ms = position_ms;
    let seek_ts = ms_to_stream_ts(target_ms, tb);
    if seek_stream_backward(&mut ictx, stream_idx, seek_ts).is_err() && target_ms > 0 {
        let _ = seek_stream_backward(&mut ictx, stream_idx, 0);
    }
    flush_video_decoder(&mut decoder);
    decoder.skip_frame(Discard::NonKey);

    let mut frame = Video::empty();
    let mut captured = false;
    let mut pts_ms = target_ms;

    for (s, packet) in ictx.packets() {
        if s.index() != stream_idx {
            continue;
        }
        decoder.send_packet(&packet).map_err(map_ffmpeg_error)?;

        while decoder.receive_frame(&mut frame).is_ok() {
            let frame_pts = frame_pts_ms(&frame, tb);
            apply_skip_until_target(&mut decoder, frame_pts, target_ms);

            if frame_pts >= target_ms {
                pts_ms = frame_pts;
                captured = true;
                break;
            }
        }
        if captured {
            break;
        }
    }

    decoder.skip_frame(Discard::None);

    if !captured || !hw_decode::is_hw_pixel_format(frame.format()) {
        return Err(VideoProcessorError::Internal(
            "HW preview decode did not produce a VideoToolbox frame".into(),
        ));
    }

    let src_w = frame.width();
    let src_h = frame.height();
    let (out_w, out_h) = thumb_dimensions(src_w, src_h, max_edge, None);

    hw.ensure_transfer_session()?;
    let session = hw
        .transfer_session()
        .ok_or_else(|| VideoProcessorError::Internal("VT transfer session missing".into()))?;

    unsafe {
        let pb = crate::ffmpeg::vt_pipeline::transfer_vt_frame_to_bgra_pixel_buffer(
            session,
            &frame,
            out_w as usize,
            out_h as usize,
        )?;
        let ptr = crate::ffmpeg::vt_pipeline::retain_pixel_buffer_for_handoff(pb);
        Ok(PreviewFramePixelBuffer {
            pts_ms,
            width: out_w,
            height: out_h,
            pixel_buffer_ptr: ptr,
        })
    }
}

#[cfg(not(any(target_os = "ios", target_os = "macos")))]
pub fn decode_preview_pixel_buffer(
    _input_path: &str,
    _position_ms: u64,
    _max_edge: Option<u32>,
) -> Result<PreviewFramePixelBuffer> {
    Err(VideoProcessorError::Internal(
        "HW preview decode is only available on Apple platforms".into(),
    ))
}

fn frame_pts_ms(frame: &Video, tb: Rational) -> u64 {
    let pts = frame.timestamp().unwrap_or(0);
    let ms = pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0;
    ms.max(0.0) as u64
}

fn apply_skip_until_target(decoder: &mut DecoderVideo, pts_ms: u64, target_ms: u64) {
    let approach = target_ms.saturating_sub(GOP_APPROACH_MS);
    if pts_ms < approach {
        decoder.skip_frame(Discard::NonKey);
    } else {
        decoder.skip_frame(Discard::None);
    }
}
