use std::fs::File;
use std::io::Cursor;
use std::path::Path;

use memmap2::Mmap;
use mp4parse::{MediaTimeScale, Track, TrackType};

use crate::error::{Result, VideoForgeError};
use crate::types::MediaInfo;

/// Fast metadata extraction using memory-mapped MP4 parsing.
/// Returns None for non-MP4 containers or parse failures (caller falls back to FFmpeg).
pub fn probe_mp4_fast(path: &Path) -> Result<Option<MediaInfo>> {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("")
        .to_lowercase();
    if ext != "mp4" && ext != "m4v" && ext != "mov" {
        return Ok(None);
    }

    let file = File::open(path).map_err(|e| VideoForgeError::IoError(e.to_string()))?;
    let file_size = file
        .metadata()
        .map_err(|e| VideoForgeError::IoError(e.to_string()))?
        .len();

    let mmap = unsafe { Mmap::map(&file).map_err(|e| VideoForgeError::IoError(e.to_string()))? };

    let mut cursor = Cursor::new(&mmap[..]);
    let context = match mp4parse::read_mp4(&mut cursor) {
        Ok(ctx) => ctx,
        Err(_) => return Ok(None),
    };

    let movie_timescale = context.timescale;
    let track = pick_video_track(&context.tracks, movie_timescale);
    let Some(track) = track else {
        return Ok(None);
    };

    let duration_ms = track_duration_ms(track, movie_timescale);
    if duration_ms == 0 {
        return Ok(None);
    }

    // tkhd width/height are 16.16 fixed-point (pixels in upper 16 bits).
    let width = track
        .tkhd
        .as_ref()
        .map(|t| (t.width >> 16) as u32)
        .unwrap_or(0);
    let height = track
        .tkhd
        .as_ref()
        .map(|t| (t.height >> 16) as u32)
        .unwrap_or(0);
    let rotation = 0i32;

    Ok(Some(MediaInfo {
        duration_ms,
        width,
        height,
        rotation,
        fps: 30.0,
        video_codec: "h264".into(),
        audio_codec: None,
        bitrate: if duration_ms > 0 {
            (file_size * 8000) / duration_ms
        } else {
            0
        },
        file_size,
        has_dolby_vision: false,
        prefer_software_preview: false,
    }))
}

fn is_video_track(track: &Track) -> bool {
    matches!(
        track.track_type,
        TrackType::Video | TrackType::AuxiliaryVideo
    )
}

fn ticks_to_ms(ticks: u64, timescale: u64) -> u64 {
    if timescale == 0 {
        return 0;
    }
    ((ticks as u128) * 1000 / (timescale as u128)) as u64
}

/// Duration from mdhd (track timescale) or tkhd (movie timescale).
fn track_duration_ms(track: &Track, movie_timescale: Option<MediaTimeScale>) -> u64 {
    if let (Some(duration), Some(scale)) = (&track.duration, &track.timescale) {
        let ms = ticks_to_ms(duration.0, scale.0);
        if ms > 0 {
            return ms;
        }
    }
    if let (Some(tkhd), Some(movie_scale)) = (track.tkhd.as_ref(), movie_timescale) {
        if tkhd.duration > 0 {
            return ticks_to_ms(tkhd.duration, movie_scale.0);
        }
    }
    if let (Some(edited), Some(movie_scale)) = (track.edited_duration, movie_timescale) {
        return ticks_to_ms(edited.0, movie_scale.0);
    }
    0
}

/// Prefer the longest video track (iPhone MOV often lists metadata/aux tracks first).
fn pick_video_track<'a>(
    tracks: &'a [Track],
    movie_timescale: Option<MediaTimeScale>,
) -> Option<&'a Track> {
    tracks
        .iter()
        .filter(|t| is_video_track(t))
        .max_by_key(|t| track_duration_ms(t, movie_timescale))
        .or_else(|| {
            tracks
                .iter()
                .max_by_key(|t| track_duration_ms(t, movie_timescale))
        })
}

/// Opens large files via mmap for zero-copy sample access (reserved for future demux/IO paths).
pub fn open_mmap(path: &Path) -> Result<Mmap> {
    let file = File::open(path).map_err(|e| VideoForgeError::IoError(e.to_string()))?;
    unsafe { Mmap::map(&file).map_err(|e| VideoForgeError::IoError(e.to_string())) }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ticks_to_ms_uses_timescale_not_magic_divisor() {
        // 60 s @ timescale 600 → 36_000 ticks (not 60_000 ms).
        assert_eq!(ticks_to_ms(36_000, 600), 60_000);
        // Old bug: tkhd.duration / 1000 would yield 36 ms for this case.
        assert_ne!(36_000 / 1000, 60_000);
    }
}
