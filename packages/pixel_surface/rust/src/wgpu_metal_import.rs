//! Import an Apple Metal `MTLTexture` as a wgpu `Texture`.
//!
//! Used to share the same GPU resource between the Flutter `CVPixelBuffer`
//! (displayed via `FlutterTexture`) and the wgpu compute engine (used to write
//! beauty output). Writes to the wgpu texture become visible to the Flutter
//! `Texture` widget on the next `textureFrameAvailable` call.

#[cfg(target_vendor = "apple")]
pub mod imp {
    /// Import an existing `metal::Texture` (e.g. an `MTLTexture` obtained from
    /// a `CVPixelBuffer`'s `CVMetalTextureCache` view) as a wgpu `Texture`.
    ///
    /// The wgpu `Texture` borrows the underlying MTLTexture; do NOT drop the
    /// `metal::Texture` before this wgpu `Texture`.
    ///
    /// # Safety
    ///
    /// - `mtl_texture` must be a valid `MTLTexture*` retained by the caller.
    /// - The texture must be 2D, BGRA8Unorm, and have `STORAGE | COPY_DST`
    ///   usage (so wgpu can write to it from a compute shader).
    /// - The wgpu `Device` must be the same Metal device that created the
    ///   `MTLTexture`.
    pub unsafe fn wrap_metal_texture_as_wgpu_bgra(
        device: &wgpu::Device,
        mtl_texture: metal::Texture,
        width: u32,
        height: u32,
    ) -> wgpu::Texture {
        let hal_texture = wgpu::hal::metal::Device::texture_from_raw(
            mtl_texture,
            wgpu::TextureFormat::Bgra8Unorm,
            metal::MTLTextureType::D2,
            1, // array_layers
            1, // mip_levels
            wgpu::hal::CopyExtent {
                width: width as u32,
                height: height as u32,
                depth: 1,
            },
        );
        let desc = wgpu::TextureDescriptor {
            label: Some("imported_iosurface_bgra"),
            size: wgpu::Extent3d {
                width,
                height,
                depth_or_array_layers: 1,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Bgra8Unorm,
            usage: wgpu::TextureUsages::STORAGE_BINDING
                | wgpu::TextureUsages::TEXTURE_BINDING
                | wgpu::TextureUsages::COPY_DST,
            view_formats: &[],
        };
        unsafe {
            device.create_texture_from_hal::<wgpu::hal::metal::Api>(hal_texture, &desc)
        }
    }
}

#[cfg(target_vendor = "apple")]
pub use imp::*;
