//! Shared RGBA buffer type for GPU upload (no FRB / Flutter).

/// Packed RGBA8888 image bytes (row-major).
#[derive(Debug, Clone)]
pub struct RgbaBuffer {
    pub width: u32,
    pub height: u32,
    pub pixels: Vec<u8>,
}

impl RgbaBuffer {
    pub fn new(width: u32, height: u32, pixels: Vec<u8>) -> Result<Self, String> {
        let expected = (width as usize)
            .checked_mul(height as usize)
            .and_then(|n| n.checked_mul(4))
            .ok_or_else(|| "dimensions overflow".to_string())?;
        if pixels.len() < expected {
            return Err(format!(
                "pixel length {} < expected {expected} for {width}×{height}",
                pixels.len()
            ));
        }
        Ok(Self {
            width,
            height,
            pixels,
        })
    }
}
