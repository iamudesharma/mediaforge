use std::path::Path;

use crate::error::{Result, VideoProcessorError};
use crate::ffmpeg::{
    ensure_ffmpeg_initialized, ensure_input_accessible, is_remote_input, map_ffmpeg_error,
    open_input,
};
use crate::ffmpeg::large_file::probe_mp4_fast;
use crate::ffmpeg::probe_cache::{get as probe_cache_get, insert as probe_cache_insert};
use crate::types::MediaInfo;

pub fn probe_media_info(path: &str) -> Result<MediaInfo> {
    let trimmed = path.trim();
    ensure_input_accessible(trimmed)?;

    if is_remote_input(trimmed) {
        if let Some(cached) = probe_cache_get(trimmed) {
            return Ok(cached);
        }
    }

    let path = Path::new(trimmed);
    if !is_remote_input(trimmed) {
        let file_size = std::fs::metadata(path)
            .map(|m| m.len())
            .unwrap_or(0);
        if let Ok(Some(fast)) = probe_mp4_fast(path) {
            if fast.width > 0 && fast.duration_ms > 0 && !fast_probe_suspicious(&fast, file_size)
            {
                return Ok(fast);
            }
        }
    }

    let info = probe_with_ffmpeg(trimmed)?;
    if is_remote_input(trimmed) {
        probe_cache_insert(trimmed, info.clone());
    }
    Ok(info)
}

/// Reject fast-probe results that look like a wrong track or unit bug (→ FFmpeg fallback).
fn fast_probe_suspicious(info: &MediaInfo, file_size: u64) -> bool {
    if file_size < 2_000_000 {
        return false;
    }
    if info.duration_ms >= 5_000 {
        return false;
    }
    // e.g. 50 MB file probed as <5 s → implausible bitrate
    info.bitrate > 8_000_000
}

fn probe_with_ffmpeg(input: &str) -> Result<MediaInfo> {
    ensure_ffmpeg_initialized()?;

    let file_size = if is_remote_input(input) {
        0
    } else {
        std::fs::metadata(input)
            .map_err(|e| VideoProcessorError::IoError(e.to_string()))?
            .len()
    };

    let ictx = open_input(input)?;

    let duration_ms = if ictx.duration() > 0 {
        (ictx.duration() as f64 / ffmpeg_next::ffi::AV_TIME_BASE as f64 * 1000.0) as u64
    } else {
        0
    };

    let mut width = 0u32;
    let mut height = 0u32;
    let mut rotation = 0i32;
    let mut fps = 0.0f32;
    let mut video_codec = String::new();
    let mut audio_codec = None;
    let mut bitrate = 0u64;

    for stream in ictx.streams() {
        let medium = stream.parameters().medium();
        if medium == ffmpeg_next::media::Type::Video && width == 0 {
            let params = stream.parameters();
            if let Ok(ctx) = ffmpeg_next::codec::context::Context::from_parameters(params) {
                if let Ok(decoder) = ctx.decoder().video() {
                    width = decoder.width();
                    height = decoder.height();
                }
            }
            if let Some(r) = stream.metadata().get("rotate") {
                rotation = r.parse().unwrap_or(0);
            }
            let rate = stream.avg_frame_rate();
            if rate.1 != 0 {
                fps = rate.0 as f32 / rate.1 as f32;
            }
            video_codec = stream.parameters().id().name().to_string();
            bitrate = ictx.bit_rate() as u64;
        } else if medium == ffmpeg_next::media::Type::Audio && audio_codec.is_none() {
            audio_codec = Some(stream.parameters().id().name().to_string());
        }
    }

    Ok(MediaInfo {
        duration_ms,
        width,
        height,
        rotation,
        fps,
        video_codec,
        audio_codec,
        bitrate,
        file_size,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn probe_missing_file_errors() {
        let err = probe_media_info("/nonexistent/video.mp4").unwrap_err();
        assert!(matches!(err, crate::error::VideoProcessorError::FileNotFound(_)));
    }
}
