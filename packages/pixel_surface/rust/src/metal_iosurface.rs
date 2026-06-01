//! Apple-only IOSurface + CVMetalTextureCache → wgpu Texture bridge.
//!
//! Creates a BGRA8888 `CVPixelBuffer` (always IOSurface-backed on modern macOS),
//! gets a `metal::Texture` view of it via `CVMetalTextureCache`, and lets
//! `image_forge` beauty compute write directly into the GPU resource.
//!
//! The returned `CVPixelBufferRef` is retained +1 and can be handed to
//! `pixel_surface::presentPixelBuffer(handle, ptr)` for zero-copy display.

#[cfg(target_vendor = "apple")]
mod imp {
    use std::ptr;
    use std::sync::OnceLock;

    use metal::Texture as MetalTexture;
    use metal::foreign_types::ForeignType;

    pub type CVPixelBufferRef = *mut std::ffi::c_void;
    pub type CVMetalTextureCacheRef = *mut std::ffi::c_void;
    pub type CVMetalTextureRef = *mut std::ffi::c_void;
    pub type MTLDeviceRef = *mut std::ffi::c_void;
    pub type MTLTextureRef = *mut metal::MTLTexture;
    pub type CFAllocatorRef = *mut std::ffi::c_void;
    pub type OSStatus = i32;

    /// `kCVPixelFormatType_32BGRA == 'BGRA'`.
    pub const K_CV_32BGRA: u32 = u32::from_be_bytes(*b"BGRA");

    /// `kIOSurfaceBytesPerRow` — required for the wgpu row pitch calculation.
    /// Set to width * 4 (BGRA8888).
    #[allow(dead_code)]
    pub const K_IO_SURFACE_BYTES_PER_ROW: &str = "IOSurfaceBytesPerRow";

    #[link(name = "CoreVideo", kind = "framework")]
    #[link(name = "CoreFoundation", kind = "framework")]
    #[link(name = "Metal", kind = "framework")]
    extern "C" {
        #[allow(dead_code)]
        fn CFRelease(cf: *mut std::ffi::c_void);

        fn CVPixelBufferCreate(
            allocator: CFAllocatorRef,
            width: usize,
            height: usize,
            pixel_format_type: u32,
            pixel_buffer_attributes: *mut std::ffi::c_void,
            pixel_buffer_out: *mut CVPixelBufferRef,
        ) -> OSStatus;
        fn CVPixelBufferRetain(pixel_buffer: CVPixelBufferRef) -> CVPixelBufferRef;
        fn CVPixelBufferRelease(pixel_buffer: CVPixelBufferRef);
        fn CVPixelBufferGetWidth(pixel_buffer: CVPixelBufferRef) -> usize;
        fn CVPixelBufferGetHeight(pixel_buffer: CVPixelBufferRef) -> usize;
        #[allow(dead_code)]
        fn CVPixelBufferGetBaseAddress(pixel_buffer: CVPixelBufferRef) -> *mut u8;
        fn CVPixelBufferGetBytesPerRow(pixel_buffer: CVPixelBufferRef) -> usize;

        fn CVMetalTextureCacheCreate(
            allocator: CFAllocatorRef,
            cache_attributes: *mut std::ffi::c_void,
            metal_device: MTLDeviceRef,
            texture_attributes: *mut std::ffi::c_void,
            cache_out: *mut CVMetalTextureCacheRef,
        ) -> OSStatus;
        fn CVMetalTextureCacheCreateTextureFromImage(
            allocator: CFAllocatorRef,
            texture_cache: CVMetalTextureCacheRef,
            source_image: CVPixelBufferRef,
            texture_attributes: *mut std::ffi::c_void,
            pixel_format: u32,
            width: usize,
            height: usize,
            plane_index: usize,
            texture_out: *mut CVMetalTextureRef,
        ) -> OSStatus;
        fn CVMetalTextureCacheFlush(cache: CVMetalTextureCacheRef, options: u64);
        fn CVMetalTextureGetTexture(texture: CVMetalTextureRef) -> MTLTextureRef;
    }

    /// Process-wide `CVMetalTextureCache` per Metal device.
    /// Lazily initialized; flushes if the device changes.
    ///
    /// Wrapped in `*mut` (non-null) for Send/Sync. The `*mut c_void` is a
    /// CFTypeRef which is documented as thread-safe.
    static METAL_TEXTURE_CACHE: OnceLock<parking_lot::Mutex<Option<MetalTextureCacheEntry>>> =
        OnceLock::new();

    struct MetalTextureCacheEntry {
        cache: CVMetalTextureCacheRef,
        /// Raw device pointer (for equality check); the `device` field is a
        /// +1 retain so the device stays alive.
        device_ptr: MTLDeviceRef,
        #[allow(dead_code)]
        device: metal::Device,
    }

    unsafe impl Send for MetalTextureCacheEntry {}
    unsafe impl Sync for MetalTextureCacheEntry {}

    fn metal_texture_cache_for_device(
        device: &metal::Device,
    ) -> Result<CVMetalTextureCacheRef, String> {
        let mutex = METAL_TEXTURE_CACHE.get_or_init(|| parking_lot::Mutex::new(None));
        let mut guard = mutex.lock();
        let device_ptr = device.as_ptr() as MTLDeviceRef;
        if let Some(entry) = guard.as_ref() {
            if entry.device_ptr == device_ptr {
                return Ok(entry.cache);
            }
            unsafe { CVMetalTextureCacheFlush(entry.cache, 0) };
        }
        let mut cache: CVMetalTextureCacheRef = ptr::null_mut();
        let status = unsafe {
            CVMetalTextureCacheCreate(
                ptr::null_mut(),
                ptr::null_mut(),
                device_ptr,
                ptr::null_mut(),
                &mut cache,
            )
        };
        if status != 0 || cache.is_null() {
            return Err(format!("CVMetalTextureCacheCreate failed: status={status}"));
        }
        *guard = Some(MetalTextureCacheEntry {
            cache,
            device_ptr,
            device: device.clone(),
        });
        Ok(cache)
    }

    /// A BGRA8888 CVPixelBuffer plus a Metal texture view of it.
    ///
    /// Drop releases the CVPixelBuffer. The Metal texture is owned by the
    /// `CVMetalTextureCache` (process-global); we hold a +1 retain.
    pub struct IosurfacePixelBuffer {
        pub pixel_buffer: CVPixelBufferRef,
        pub metal_texture: MetalTexture,
        pub width: u32,
        pub height: u32,
        pub bytes_per_row: u32,
    }

    // SAFETY: CVPixelBufferRef and metal::Texture are Core Foundation / objc
    // objects documented as thread-safe for retain/release.
    unsafe impl Send for IosurfacePixelBuffer {}
    unsafe impl Sync for IosurfacePixelBuffer {}

    impl Drop for IosurfacePixelBuffer {
        fn drop(&mut self) {
            unsafe {
                if !self.pixel_buffer.is_null() {
                    CVPixelBufferRelease(self.pixel_buffer);
                }
            }
        }
    }

    /// Create a BGRA8888 IOSurface-backed CVPixelBuffer (modern Apple platforms
    /// make all CVPixelBuffers IOSurface-backed by default) and a Metal texture
    /// view of it ready to be imported as a wgpu `Texture`.
    pub fn create_bgra_iosurface_pixel_buffer(
        device: &metal::Device,
        width: u32,
        height: u32,
    ) -> Result<IosurfacePixelBuffer, String> {
        if width == 0 || height == 0 {
            return Err("pixel buffer dimensions must be > 0".into());
        }

        unsafe {
            // 1. Create BGRA CVPixelBuffer. NULL attributes on modern macOS =
            //    IOSurface-backed + Metal-compatible (both are defaults).
            let mut pixel_buffer: CVPixelBufferRef = ptr::null_mut();
            let status = CVPixelBufferCreate(
                ptr::null_mut(),
                width as usize,
                height as usize,
                K_CV_32BGRA,
                ptr::null_mut(),
                &mut pixel_buffer,
            );
            if status != 0 || pixel_buffer.is_null() {
                return Err(format!("CVPixelBufferCreate failed: status={status}"));
            }

            let bytes_per_row = CVPixelBufferGetBytesPerRow(pixel_buffer) as u32;
            let actual_w = CVPixelBufferGetWidth(pixel_buffer) as u32;
            let actual_h = CVPixelBufferGetHeight(pixel_buffer) as u32;
            if actual_w != width || actual_h != height {
                CVPixelBufferRelease(pixel_buffer);
                return Err(format!(
                    "CVPixelBufferCreate size mismatch: requested {width}x{height} got {actual_w}x{actual_h}"
                ));
            }

            // 2. Get a Metal texture view of the CVPixelBuffer.
            let cache = metal_texture_cache_for_device(device)?;
            let mut cv_mtl_texture: CVMetalTextureRef = ptr::null_mut();
            let status = CVMetalTextureCacheCreateTextureFromImage(
                ptr::null_mut(),
                cache,
                pixel_buffer,
                ptr::null_mut(),
                K_CV_32BGRA,
                width as usize,
                height as usize,
                0,
                &mut cv_mtl_texture,
            );
            if status != 0 || cv_mtl_texture.is_null() {
                CVPixelBufferRelease(pixel_buffer);
                return Err(format!(
                    "CVMetalTextureCacheCreateTextureFromImage failed: status={status}"
                ));
            }
            let mtl_raw = CVMetalTextureGetTexture(cv_mtl_texture);
            if mtl_raw.is_null() {
                CVPixelBufferRelease(pixel_buffer);
                return Err("CVMetalTextureGetTexture returned NULL".into());
            }
            // `CVMetalTextureGetTexture` returns an unretained reference on
            // modern SDKs. The caller of `getMetalTexturePtr` (Swift) already
            // holds a +1 retain on the MTLTexture (it asked the cache for it),
            // so we transfer that +1 to this `metal::Texture` wrapper. The
            // wrapper's Drop releases it; the `IosurfacePixelBuffer`'s Drop
            // releases the matching CVPixelBuffer.
            let metal_texture = metal::Texture::from_ptr(mtl_raw);

            Ok(IosurfacePixelBuffer {
                pixel_buffer,
                metal_texture,
                width,
                height,
                bytes_per_row,
            })
        }
    }

    /// Retain a CVPixelBuffer pointer (for handoff to platform plugin via
    /// `presentPixelBuffer`). The +1 acquired here will be consumed by the
    /// plugin's `takeRetainedValue()`.
    pub fn retain_pixel_buffer(ptr: CVPixelBufferRef) -> CVPixelBufferRef {
        unsafe { CVPixelBufferRetain(ptr) }
    }

    /// Release a CVPixelBuffer pointer we no longer need.
    pub fn release_pixel_buffer(ptr: CVPixelBufferRef) {
        if !ptr.is_null() {
            unsafe { CVPixelBufferRelease(ptr) };
        }
    }

    /// Adopt a raw `MTLTexture*` (e.g. from Swift via `presentPixelBuffer`
    /// handoff) as a Rust `metal::Texture` with +1 retain.
    ///
    /// # Safety
    /// `ptr` must be a valid `MTLTexture*` retained by the caller.
    pub unsafe fn adopt_metal_texture(ptr: *mut metal::MTLTexture) -> MetalTexture {
        metal::Texture::from_ptr(ptr)
    }
}

#[cfg(target_vendor = "apple")]
pub use imp::*;
