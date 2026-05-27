//! Single-frame preview decode for texture display (Sprint V1.1).
//!
//! Reuses thumbnail seek/decode; outputs RGBA8888 for [GpuTextureRegistry] upload.

use crate::error::{Result, VideoProcessorError};
use crate::jobs::registry::CancellationToken;
use crate::pipeline::thumbnail;
use crate::types::PreviewFrameRgba;

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
