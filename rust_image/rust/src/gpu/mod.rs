mod engine;

pub use engine::{capabilities, engine, is_available};

use crate::api::image::{ImageFilter, ResizeAlgorithm, RgbaImageBuffer};

pub fn resize_rgba(
    buffer: RgbaImageBuffer,
    width: u32,
    height: u32,
    algorithm: ResizeAlgorithm,
) -> Result<RgbaImageBuffer, String> {
    let gpu = engine()?;
    gpu.resize_rgba(buffer, width, height, algorithm)
}

pub fn filter_rgba(buffer: RgbaImageBuffer, filter: ImageFilter) -> Result<RgbaImageBuffer, String> {
    let gpu = engine()?;
    gpu.apply_filter_rgba(buffer, &filter)
}
