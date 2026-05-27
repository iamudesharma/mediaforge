//! Single-frame preview decode for texture display (Sprint V1.1+).
//!
//! V1.1: RGBA via thumbnail CPU path. V1.4: Apple VideoToolbox → BGRA `CVPixelBuffer`.

use crate::error::{Result, VideoProcessorError};
use crate::jobs::registry::CancellationToken;
use crate::pipeline::thumbnail;
use crate::types::{PreviewFramePixelBuffer, PreviewFrameRgba};

#[cfg(any(target_os = "ios", target_os = "macos"))]
use super::preview_hw;

#[cfg(any(target_os = "ios", target_os = "macos"))]
pub use preview_hw::hw_preview_enabled;

#[cfg(not(any(target_os = "ios", target_os = "macos")))]
pub fn hw_preview_enabled() -> bool {
    false
}

/// Decode one preview frame at [position_ms], scaled so the longest edge is at most [max_edge].
pub fn decode_preview_frame_rgba(
    input_path: &str,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFrameRgba> {
    let token = CancellationToken::new();
    let max_w = max_edge;
    let rgb = thumbnail::decode_rgb_frame_at(
        input_path.trim(),
        position_ms,
        max_w,
        None,
        token,
    )?;
    let rgba = rgb24_to_rgba8888(&rgb.data, rgb.width, rgb.height)?;
    Ok(PreviewFrameRgba {
        pts_ms: position_ms,
        width: rgb.width,
        height: rgb.height,
        rgba,
    })
}

/// Apple HW path: VideoToolbox decode → BGRA `CVPixelBuffer` (hand off via [pixel_buffer_ptr]).
pub fn decode_preview_frame_pixel_buffer(
    input_path: &str,
    position_ms: u64,
    max_edge: Option<u32>,
) -> Result<PreviewFramePixelBuffer> {
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    {
        return preview_hw::decode_preview_pixel_buffer(input_path, position_ms, max_edge);
    }
    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    {
        let _ = (input_path, position_ms, max_edge);
        Err(VideoProcessorError::Internal(
            "HW preview decode is only available on Apple platforms".into(),
        ))
    }
}

/// Release a preview buffer when not presented to the texture plugin.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub fn release_preview_pixel_buffer(ptr: u64) {
    if ptr == 0 {
        return;
    }
    unsafe {
        crate::ffmpeg::vt_pipeline::release_pixel_buffer(ptr as *mut std::ffi::c_void);
    }
}

#[cfg(not(any(target_os = "ios", target_os = "macos")))]
pub fn release_preview_pixel_buffer(_ptr: u64) {}

fn rgb24_to_rgba8888(rgb: &[u8], width: u32, height: u32) -> Result<Vec<u8>> {
    let w = width as usize;
    let h = height as usize;
    let expected = w * h * 3;
    if rgb.len() < expected {
        return Err(VideoProcessorError::Internal(format!(
            "RGB buffer too small: got {} need {expected}",
            rgb.len()
        )));
    }
    let mut rgba = Vec::with_capacity(w * h * 4);
    for i in 0..(w * h) {
        let si = i * 3;
        rgba.push(rgb[si]);
        rgba.push(rgb[si + 1]);
        rgba.push(rgb[si + 2]);
        rgba.push(255);
    }
    Ok(rgba)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rgb24_to_rgba_dimensions() {
        let rgb = vec![255u8, 0, 0, 0, 255, 0];
        let rgba = rgb24_to_rgba8888(&rgb, 2, 1).unwrap();
        assert_eq!(rgba.len(), 8);
        assert_eq!(&rgba[0..4], &[255, 0, 0, 255]);
        assert_eq!(&rgba[4..8], &[0, 255, 0, 255]);
    }
}
