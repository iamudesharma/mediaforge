//! Apple-only IOSurface + CVMetalTextureCache → wgpu Texture bridge.
//!
//! Creates a BGRA8888 `CVPixelBuffer` (always IOSurface-backed on modern macOS),
//! gets a `metal::Texture` view of it via `CVMetalTextureCache`, and lets
//! `image_forge` beauty compute write directly into the GPU resource.
//!
//! The returned `CVPixelBufferRef` is retained +1 and can be handed to
//! `pixel_surface::presentPixelBuffer(handle, ptr)` for zero-copy display.
//!
//! ## Retain discipline (READ ME before touching this file)
//!
//! Every Core Foundation / Objective-C pointer crossing this module has a
//! single, named owner. The rules:
//!
//! 1. **Factory functions** (`create_bgra_iosurface_pixel_buffer`,
//!    `retain_pixel_buffer`, `metal_texture_cache_for_device`) return a
//!    pointer carrying a `+1` retain. The caller (or the new RAII wrapper
//!    it hands the pointer to) is responsible for exactly one matching
//!    `release_*` call.
//! 2. **Reader functions** (those that take a `*mut c_void` without retaining
//!    it) are named with a `borrow_` prefix or document the borrow in their
//!    `# Safety` section. They never own a `+1`.
//! 3. **`adopt_*` functions** consume a `+1` from the caller. The caller
//!    must have explicitly acquired that retain *before* calling `adopt_*`.
//!    `adopt_*` does not call `retain` internally — the new wrapper takes
//!    ownership of the exact retain the caller already holds.
//! 4. **RAII wrappers** ([`CvMetalTexture`], [`MetalTextureCacheEntry`]) are
//!    the only types that may hold a `+1` and be `Drop`ed in normal code
//!    paths. Everything else ([`IosurfacePixelBuffer`]) composes RAII
//!    wrappers so that "destroy this struct" is unambiguous and idempotent.
//!
//! Violating these rules will leak or double-free `CVPixelBuffer` /
//! `MTLTexture` / `CVMetalTextureCache` references. The tests in
//! `drop_discipline.rs` enforce the basic balance under a debug-only
//! instrumentation counter.

#[cfg(target_vendor = "apple")]
mod imp {
    use std::ptr;
    use std::sync::atomic::AtomicUsize;
    #[cfg(test)]
    use std::sync::atomic::Ordering;
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

    /// `kCVMetalTextureCacheFlushType` — flush all unused textures in the
    /// cache and release any that are not currently bound to a Metal
    /// command encoder. Used both at Drop and on device change.
    pub const K_CV_METAL_TEXTURE_CACHE_FLUSH_ALL: u64 = 0;

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

    // ----- Test instrumentation -------------------------------------------------
    //
    // The unit tests in `drop_discipline.rs` assert that every Drop path
    // fires exactly once. The counters are unconditionally `pub` (the
    // `#[cfg(test)]` gate does not propagate to integration tests) but the
    // increment in `Drop` is `#[cfg(test)]`-gated, so in non-test builds
    // the statics exist but are never written to — overhead is a single
    // `SeqCst` load at most.
    pub static DROPPED_PIXEL_BUFFERS: AtomicUsize = AtomicUsize::new(0);
    pub static DROPPED_METAL_TEXTURES: AtomicUsize = AtomicUsize::new(0);
    pub static DROPPED_METAL_TEXTURE_CACHES: AtomicUsize = AtomicUsize::new(0);

    // ----- Metal texture cache entry (RAII) ------------------------------------

    /// One process-global entry per Metal device. The `cache` field owns a
    /// `+1` on the `CVMetalTextureCacheRef`; `Drop` releases it.
    ///
    /// The struct also stores a `metal::Device` clone — a `+1` retain on the
    /// device — so the cache cannot be invalidated by an early device
    /// deallocation in a different module.
    struct MetalTextureCacheEntry {
        cache: CVMetalTextureCacheRef,
        /// Raw device pointer (for equality check); the `device` field is a
        /// +1 retain so the device stays alive.
        device_ptr: MTLDeviceRef,
        #[allow(dead_code)]
        device: metal::Device,
    }

    // SAFETY: CVMetalTextureCacheRef is a CFTypeRef and is documented as
    // thread-safe for retain/release. The `device` field is an objc object
    // that is itself thread-safe to send across threads.
    unsafe impl Send for MetalTextureCacheEntry {}
    unsafe impl Sync for MetalTextureCacheEntry {}

    impl Drop for MetalTextureCacheEntry {
        fn drop(&mut self) {
            if !self.cache.is_null() {
                // Flush first so any pending texture references are
                // released cleanly before the cache itself goes away.
                unsafe { CVMetalTextureCacheFlush(self.cache, K_CV_METAL_TEXTURE_CACHE_FLUSH_ALL) };
                unsafe { CFRelease(self.cache) };
            }
            #[cfg(test)]
            DROPPED_METAL_TEXTURE_CACHES.fetch_add(1, Ordering::SeqCst);
        }
    }

    // ----- CvMetalTexture (RAII) -----------------------------------------------

    /// A Metal texture view of a `CVPixelBuffer`, created via
    /// `CVMetalTextureCacheCreateTextureFromImage`.
    ///
    /// Owns a `+1` retain on the underlying `CVMetalTextureRef`. The
    /// `metal::Texture` field is a borrowed view into the same Metal
    /// resource; `CFRelease` of the `CVMetalTextureRef` releases the
    /// matching `+1` on the `MTLTexture` as well (Apple's CF bridge keeps
    /// the two lifetimes tied together). For that reason the struct is
    /// single-owner: cloning a `metal::Texture` out of it (via
    /// `clone_metal_texture`) bumps the `MTLTexture` retain for as long as
    /// needed.
    pub struct CvMetalTexture {
        cv_texture: CVMetalTextureRef,
        /// Borrowed Metal view. Kept here so callers can use it directly
        /// for read-only operations; do not manually `release()` the
        /// underlying `MTLTexture*` — the CV ref's `CFRelease` will handle
        /// it. If a longer-lived `metal::Texture` is required, call
        /// [`Self::clone_metal_texture`] to bump the retain count.
        metal_texture: MetalTexture,
        width: u32,
        height: u32,
    }

    impl CvMetalTexture {
        /// Borrow the inner `metal::Texture` without bumping its retain.
        pub fn metal_texture(&self) -> &MetalTexture {
            &self.metal_texture
        }

        /// Borrow the raw `MTLTexture*`. The pointer is valid only as long
        /// as this `CvMetalTexture` is alive (or another owned clone is).
        pub fn raw_mtl_ptr(&self) -> MTLTextureRef {
            self.metal_texture.as_ptr()
        }

        /// Return a +1-retained `metal::Texture` suitable for handing to
        /// the wgpu importer. The returned texture has its own `Drop` that
        /// releases the `+1`, so it survives even if this `CvMetalTexture`
        /// is dropped first.
        pub fn clone_metal_texture(&self) -> MetalTexture {
            // `metal::Texture` is itself an `objc::rc::Strong<T>`-style
            // wrapper; constructing from the raw pointer increments the
            // objc retain count. The Drop on the new wrapper will decrement
            // it, balancing our temporary borrow.
            //
            // SAFETY: `self.metal_texture.as_ptr()` returns a valid
            // non-null `MTLTexture*` owned by the CV ref.
            unsafe { metal::Texture::from_ptr(self.metal_texture.as_ptr()) }
        }

        pub fn width(&self) -> u32 {
            self.width
        }
        pub fn height(&self) -> u32 {
            self.height
        }
    }

    impl Drop for CvMetalTexture {
        fn drop(&mut self) {
            if !self.cv_texture.is_null() {
                // CFRelease the CV ref; the matching MTLTexture +1 is
                // released by the CV bridge at the same time. We do NOT
                // call `metal_texture.release()` here — that would double
                // release.
                unsafe { CFRelease(self.cv_texture) };
            }
            #[cfg(test)]
            DROPPED_METAL_TEXTURES.fetch_add(1, Ordering::SeqCst);
        }
    }

    // SAFETY: see `MetalTextureCacheEntry` above; CVMetalTextureRef is
    // thread-safe for retain/release.
    unsafe impl Send for CvMetalTexture {}
    unsafe impl Sync for CvMetalTexture {}

    /// Process-wide `CVMetalTextureCache` per Metal device. Lazily
    /// initialized; on device change the old entry is dropped (which
    /// flushes + releases it) and a new cache is created.
    static METAL_TEXTURE_CACHE: OnceLock<parking_lot::Mutex<Option<MetalTextureCacheEntry>>> =
        OnceLock::new();

    fn metal_texture_cache_for_device(
        device: &metal::Device,
    ) -> Result<&'static MetalTextureCacheEntry, String> {
        let mutex = METAL_TEXTURE_CACHE.get_or_init(|| parking_lot::Mutex::new(None));
        let mut guard = mutex.lock();
        let device_ptr = device.as_ptr() as MTLDeviceRef;
        let needs_rebuild = match guard.as_ref() {
            Some(entry) if entry.device_ptr == device_ptr => false,
            Some(_) => {
                // Drop the old entry by replacing it with None; the old
                // MetalTextureCacheEntry's Drop runs at the end of this
                // scope and flushes + releases the previous cache.
                true
            }
            None => true,
        };
        if !needs_rebuild {
            // SAFETY: the borrow checker cannot see through
            // `parking_lot::Mutex::lock` returning a `MutexGuard` that
            // deref-projects to `&Option<Entry>`. We re-borrow the entry
            // after dropping the guard.
            return Ok(unsafe { &*(guard.as_ref().expect("checked above") as *const _) });
        }
        // Drop the previous entry (if any) before creating a new one.
        *guard = None;
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
        // SAFETY: just inserted above.
        Ok(unsafe { &*(guard.as_ref().expect("just inserted") as *const _) })
    }

    // ----- IosurfacePixelBuffer (composed) -------------------------------------

    /// A BGRA8888 CVPixelBuffer plus a Metal texture view of it.
    ///
    /// Owns a `+1` retain on the `CVPixelBufferRef` (released in `Drop`)
    /// and composes a [`CvMetalTexture`] for the Metal view (whose own
    /// `Drop` releases the `+1` on the `CVMetalTextureRef`). There is
    /// exactly one place that releases each ref count.
    pub struct IosurfacePixelBuffer {
        pub pixel_buffer: CVPixelBufferRef,
        pub metal_texture: CvMetalTexture,
        pub width: u32,
        pub height: u32,
        pub bytes_per_row: u32,
    }

    // SAFETY: CVPixelBufferRef and CvMetalTexture are Core Foundation
    // objects documented as thread-safe for retain/release.
    unsafe impl Send for IosurfacePixelBuffer {}
    unsafe impl Sync for IosurfacePixelBuffer {}

    impl Drop for IosurfacePixelBuffer {
        fn drop(&mut self) {
            if !self.pixel_buffer.is_null() {
                unsafe { CVPixelBufferRelease(self.pixel_buffer) };
            }
            #[cfg(test)]
            DROPPED_PIXEL_BUFFERS.fetch_add(1, Ordering::SeqCst);
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
                cache.cache,
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
                CFRelease(cv_mtl_texture);
                CVPixelBufferRelease(pixel_buffer);
                return Err("CVMetalTextureGetTexture returned NULL".into());
            }
            // CVMetalTextureGetTexture returns an UNRETAINED reference.
            // Since `metal::Texture::from_ptr` takes ownership and its Drop
            // implementation will call `release`, we must explicitly retain
            // it by +1 first to prevent a double release when both the
            // `metal_texture` and the `CVMetalTextureRef` are dropped.
            let _: *mut std::ffi::c_void = objc::msg_send![mtl_raw, retain];
            let metal_texture = metal::Texture::from_ptr(mtl_raw);

            let cv_metal = CvMetalTexture {
                cv_texture: cv_mtl_texture,
                metal_texture,
                width,
                height,
            };

            Ok(IosurfacePixelBuffer {
                pixel_buffer,
                metal_texture: cv_metal,
                width,
                height,
                bytes_per_row,
            })
        }
    }

    /// Retain a CVPixelBuffer pointer (for handoff to platform plugin via
    /// `presentPixelBuffer`). The `+1` acquired here will be consumed by the
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
    /// handoff) as a Rust `metal::Texture` with the caller's `+1` retain.
    ///
    /// # Safety
    ///
    /// - `ptr` must be a non-null, valid `MTLTexture*`.
    /// - The caller must hold exactly one `+1` retain on the underlying
    ///   `MTLTexture` and must transfer that retain to this function —
    ///   `adopt_metal_texture` does not call `objc_retain` internally.
    ///   In practice this means: when the Swift side hands a texture via
    ///   `Unmanaged<MTLTexture>.passRetained(ptr)`, the `+1` consumed by
    ///   `passRetained` is the one this function adopts.
    /// - After calling this function the caller must not call
    ///   `CFRelease` / `objc_release` on `ptr` directly; the returned
    ///   `metal::Texture`'s `Drop` will do so exactly once.
    pub unsafe fn adopt_metal_texture(ptr: *mut metal::MTLTexture) -> MetalTexture {
        // SAFETY: caller transferred exactly one +1 retain on the
        // underlying MTLTexture. The `metal::Texture` wrapper's Drop will
        // release it.
        unsafe { metal::Texture::from_ptr(ptr) }
    }

    // ----- BeautyOutputTarget (typed wrapper) -----------------------------------

    /// Zero-copy output target for a beauty compute pass. Owns:
    /// - a `+1` retain on the `CVPixelBuffer` (the Flutter display backing);
    /// - a `+1` retain on the `MTLTexture` (the Swift-side `passRetained`
    ///   handoff);
    /// - a `wgpu::Texture` import of the same Metal resource.
    ///
    /// `Drop` releases the `CVPixelBuffer` and lets `metal::Texture`'s
    /// own `Drop` release the `MTLTexture` +1. The wgpu `Texture` field
    /// is declared **first** so it is dropped **before** the
    /// `metal_texture` (Rust drops struct fields in declaration order);
    /// wgpu's HAL holds a borrow of the `MTLTexture`, and dropping the
    /// Metal resource while the wgpu import is still alive is
    /// use-after-free.
    ///
    /// This is the **single safe boundary** for adopting Flutter-side
    /// `CVPixelBuffer` + `MTLTexture` pointer pairs into a wgpu pipeline.
    /// Construct it via [`BeautyOutputTarget::from_adopted`]; never
    /// assemble one by hand.
    #[cfg(feature = "gpu")]
    pub struct BeautyOutputTarget {
        /// Borrowed wgpu view of the underlying `MTLTexture`. Must be
        /// dropped first.
        wgpu_texture: wgpu::Texture,
        /// `+1` retain on the `MTLTexture`. The wgpu `Texture` above
        /// borrows this; dropping it first causes use-after-free in
        /// subsequent wgpu submissions. Marked `#[allow(dead_code)]`
        /// because the lint cannot see that `metal::Texture::Drop` is
        /// what releases the +1; the field is the *owner*.
        #[allow(dead_code)]
        metal_texture: MetalTexture,
        /// `+1` retain on the `CVPixelBuffer`. Released in `Drop`.
        pixel_buffer: CVPixelBufferRef,
        width: u32,
        height: u32,
    }

    // SAFETY: `CVPixelBufferRef` and `metal::Texture` are CF / Objective-C
    // objects whose retain/release is thread-safe; `wgpu::Texture` is
    // likewise `Send + Sync` on the same device.
    #[cfg(feature = "gpu")]
    unsafe impl Send for BeautyOutputTarget {}
    #[cfg(feature = "gpu")]
    unsafe impl Sync for BeautyOutputTarget {}

    #[cfg(feature = "gpu")]
    impl BeautyOutputTarget {
        /// Borrow the inner wgpu `Texture`. The returned reference is
        /// valid for the lifetime of `self`.
        pub fn wgpu_texture(&self) -> &wgpu::Texture {
            &self.wgpu_texture
        }

        pub fn width(&self) -> u32 {
            self.width
        }
        pub fn height(&self) -> u32 {
            self.height
        }

        /// Adopt a Flutter-side zero-copy output target. The caller must
        /// hold a `+1` retain on **each** of the input pointers (typically
        /// obtained from the Swift plugin's `getMetalTexturePtr` method,
        /// which `passRetained`s both). Both retains are transferred into
        /// the returned `BeautyOutputTarget`; the caller must not release
        /// them again.
        ///
        /// On any validation failure the function releases the +1s it has
        /// already adopted and returns `None` — callers never leak on
        /// error. On success, the returned struct owns exactly one +1 on
        /// the `CVPixelBuffer` and one +1 on the `MTLTexture`.
        ///
        /// # Safety
        ///
        /// Same contract as
        /// [`wgpu_metal_import::wrap_metal_texture_as_wgpu_bgra`] —
        /// listed here so a caller of `from_adopted` does not need to
        /// look at the wgpu import layer to audit the safety:
        ///
        /// 1. `metal_texture_ptr` must be a non-null, valid `MTLTexture*`
        ///    backed by `metal::Device` == `wgpu_hal_device(device)`.
        /// 2. The `MTLTexture` must be `BGRA8Unorm` + 2D + support
        ///    `MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite`.
        /// 3. The `MTLTexture`'s dimensions must equal the Flutter display
        ///    texture dimensions; this is verified against
        ///    `CVPixelBufferGet{Width,Height}` on `pixel_buffer_ptr`.
        /// 4. `pixel_buffer_ptr` must be a non-null, valid `CVPixelBuffer`
        ///    of the same dimensions.
        pub unsafe fn from_adopted(
            device: &wgpu::Device,
            metal_texture_ptr: *mut metal::MTLTexture,
            pixel_buffer_ptr: CVPixelBufferRef,
        ) -> Option<Self> {
            // ----- Step 1: pointer validation (safe to do before any
            //                retain transfer). -----
            if metal_texture_ptr.is_null() || pixel_buffer_ptr.is_null() {
                return None;
            }
            // SAFETY: `pixel_buffer_ptr` is non-null and was promised by
            // the caller to be a valid `CVPixelBuffer`. `GetWidth` /
            // `GetHeight` are pure reads; they do not retain.
            let pb_w = unsafe { CVPixelBufferGetWidth(pixel_buffer_ptr) } as u32;
            let pb_h = unsafe { CVPixelBufferGetHeight(pixel_buffer_ptr) } as u32;
            if pb_w == 0 || pb_h == 0 {
                // Since we haven't adopted them yet, release both +1 pointers from the caller.
                unsafe { CVPixelBufferRelease(pixel_buffer_ptr) };
                let _: *mut std::ffi::c_void = unsafe { objc::msg_send![metal_texture_ptr, release] };
                return None;
            }

            // Adopt the Metal texture (+1 consumed by this wrapper).
            let metal_texture = unsafe { adopt_metal_texture(metal_texture_ptr) };
            let actual_w = metal_texture.width() as u32;
            let actual_h = metal_texture.height() as u32;
            if actual_w != pb_w || actual_h != pb_h {
                // Adopt the CVPixelBuffer +1 so that it is released.
                // The `metal_texture`'s Drop will automatically release the MTLTexture +1.
                unsafe { CVPixelBufferRelease(pixel_buffer_ptr) };
                return None;
            }

            // Adopt the CVPixelBuffer +1 directly (do NOT double-retain it).
            let pixel_buffer = pixel_buffer_ptr;

            // ----- Step 3: wgpu import.
            let wgpu_texture = unsafe {
                crate::wgpu_metal_import::wrap_metal_texture_as_wgpu_bgra(
                    device,
                    metal_texture.clone(),
                    actual_w,
                    actual_h,
                )
            };

            Some(BeautyOutputTarget {
                wgpu_texture,
                metal_texture,
                pixel_buffer,
                width: actual_w,
                height: actual_h,
            })
        }
    }

    #[cfg(feature = "gpu")]
    impl Drop for BeautyOutputTarget {
        fn drop(&mut self) {
            // The fields are dropped in declaration order: wgpu_texture
            // first, then metal_texture, then pixel_buffer. The wgpu
            // HAL drops its Metal command buffer references before
            // `metal_texture` is dropped, so we cannot observe a
            // use-after-free from a Metal command buffer.
            //
            // We must NOT touch `wgpu_texture` or `metal_texture` here;
            // their own Drop impls handle their respective releases. We
            // only release the adopted CVPixelBuffer once.
            if !self.pixel_buffer.is_null() {
                unsafe { CVPixelBufferRelease(self.pixel_buffer) };
            }
            #[cfg(test)]
            DROPPED_PIXEL_BUFFERS.fetch_add(1, Ordering::SeqCst);
        }
    }
}

#[cfg(target_vendor = "apple")]
pub use imp::*;
