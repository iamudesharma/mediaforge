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
    /// 1. `mtl_texture` must be a non-null, valid `MTLTexture*` and the
    ///    caller must hold at least one `+1` retain on the underlying
    ///    Objective-C object. The `metal::Texture` wrapper itself owns one
    ///    retain (`Drop` releases it), so the caller does not need to
    ///    supply an *additional* retain — but it must not, after this call,
    ///    release its own retain while the wgpu import is still alive.
    /// 2. The texture must be 2D (`MTLTextureType::D2`) and its pixel format
    ///    must be `MTLPixelFormat::BGRA8Unorm` (the only format wgpu
    ///    accepts for this import path). In debug builds we assert this
    ///    format match; release builds trust the caller.
    /// 3. The texture's `MTLTextureUsage` must include
    ///    `MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead`
    ///    (mapped to `STORAGE_BINDING` in the wgpu descriptor). wgpu
    ///    asserts this at the Metal HAL layer; a mismatch returns an
    ///    invalid texture to the caller.
    /// 4. The wgpu `Device` must be the same Metal device that created the
    ///    `MTLTexture`. Cross-device imports are undefined behaviour in
    ///    Metal itself, not in this wrapper.
    /// 5. The returned `wgpu::Texture` borrows the underlying Metal
    ///    resource. The caller must keep `mtl_texture` (or another
    ///    `+1`-retained clone of it) alive for the entire lifetime of the
    ///    returned `wgpu::Texture`. Dropping the `metal::Texture` first
    ///    causes use-after-free when wgpu submits a command buffer that
    ///    references the texture.
    pub unsafe fn wrap_metal_texture_as_wgpu_bgra(
        device: &wgpu::Device,
        mtl_texture: metal::Texture,
        width: u32,
        height: u32,
    ) -> wgpu::Texture {
        // Debug-only preconditions. These run in test / debug builds; in
        // release they compile to nothing, so we keep the cost out of the
        // hot path while still catching caller mistakes under `cargo test`.
        #[cfg(debug_assertions)]
        {
            let format = mtl_texture.pixel_format();
            debug_assert_eq!(
                format,
                metal::MTLPixelFormat::BGRA8Unorm,
                "wrap_metal_texture_as_wgpu_bgra requires BGRA8Unorm, got {:?}",
                format
            );
            debug_assert_eq!(
                mtl_texture.texture_type(),
                metal::MTLTextureType::D2,
                "wrap_metal_texture_as_wgpu_bgra requires 2D textures"
            );
        }
        let hal_texture = unsafe {
            wgpu::hal::metal::Device::texture_from_raw(
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
            )
        };
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
        // SAFETY: see the function-level `# Safety` doc. The caller has
        // promised the device, the texture format, and the retain
        // ordering. We additionally wrap the call so future
        // `_in_unsafe_fn` enforcement cannot accidentally drop the
        // unsafe-ness of the inner call.
        unsafe {
            device.create_texture_from_hal::<wgpu::hal::metal::Api>(hal_texture, &desc)
        }
    }
}

#[cfg(target_vendor = "apple")]
pub use imp::*;
