use std::fs::File;
use std::io::Cursor;
use std::path::Path;

use memmap2::Mmap;

use crate::error::{Result, VideoProcessorError};
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

    let file = File::open(path).map_err(|e| VideoProcessorError::IoError(e.to_string()))?;
    let file_size = file
        .metadata()
        .map_err(|e| VideoProcessorError::IoError(e.to_string()))?
        .len();

    let mmap = unsafe { Mmap::map(&file).map_err(|e| VideoProcessorError::IoError(e.to_string()))? };

    let mut cursor = Cursor::new(&mmap[..]);
    let context = match mp4parse::read_mp4(&mut cursor) {
        Ok(ctx) => ctx,
        Err(_) => return Ok(None),
    };

    let track = context.tracks.first();
    let Some(track) = track else {
        return Ok(None);
    };

    let duration_ms = track
        .tkhd
        .as_ref()
        .map(|t| t.duration / 1000)
        .or_else(|| track.duration.map(|d| d.0 / 1000))
        .unwrap_or(0);
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
    }))
}

/// Opens large files via mmap for zero-copy sample access (reserved for future demux/IO paths).
pub fn open_mmap(path: &Path) -> Result<Mmap> {
    let file = File::open(path).map_err(|e| VideoProcessorError::IoError(e.to_string()))?;
    unsafe { Mmap::map(&file).map_err(|e| VideoProcessorError::IoError(e.to_string())) }
}
