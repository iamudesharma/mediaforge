mod beauty_pass;
mod engine;
mod lut_assets;
mod lut_bake;
mod overlay_pass;
mod surface;

pub use engine::{capabilities, engine, is_available};
pub use surface::{
    apply_surface_beauty, apply_surface_beauty_pipeline, apply_surface_ops, apply_surface_overlay,
    create_surface, destroy_surface, readback_surface, upload_surface,
};
#[cfg(target_vendor = "apple")]
pub use surface::{
    apply_surface_beauty_pipeline_with_output, attach_output_texture, attach_output_texture_wgpu,
    detach_output_texture,
};

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

pub fn filter_rgba(
    buffer: RgbaImageBuffer,
    filter: ImageFilter,
) -> Result<RgbaImageBuffer, String> {
    let gpu = engine()?;
    gpu.apply_filter_rgba(buffer, &filter)
}
