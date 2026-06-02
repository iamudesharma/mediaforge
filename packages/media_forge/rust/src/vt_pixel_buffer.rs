//! Apple VideoToolbox decode → BGRA `CVPixelBuffer` for Flutter texture (no RGBA on hot path).
//!
//! # Zero-copy path
//! When the VT decoder outputs `kCVPixelFormatType_32BGRA` at the target preview
//! size, [`VtPreviewTransfer::transfer_to_bgra`] retains and returns the decoder's
//! own `CVPixelBuffer` directly. VideoToolbox hardware-decode frames are always
//! IOSurface-backed, so `canAdoptPixelBufferDirectly` in the Swift plugin returns
//! `true` and the frame is presented with no CPU copy.
//!
//! # Copy fallback
//! When the decoder outputs YUV (the common case for HEVC), a `VTPixelTransferSession`
//! converts to BGRA. The destination buffer is allocated from a `CVPixelBufferPool`
//! that carries `kCVPixelBufferIOSurfacePropertiesKey` and
//! `kCVPixelBufferMetalCompatibilityKey` — the same attributes the Swift
//! `PixelBufferPool` uses — so adoption still succeeds on the Swift side.

use std::ptr;

use anyhow::anyhow;
use ffmpeg_next::ffi;
use ffmpeg_next::util::frame::video::Video as FfmpegVideoFrame;

type CVPixelBufferRef = *mut std::ffi::c_void;
type CVPixelBufferPoolRef = *mut std::ffi::c_void;
type VTPixelTransferSessionRef = *mut std::ffi::c_void;
type OSStatus = i32;
type CFAllocatorRef = *mut std::ffi::c_void;
type CFDictionaryRef = *mut std::ffi::c_void;
type CFStringRef = *const std::ffi::c_void;
type CFNumberRef = *mut std::ffi::c_void;
type CFBooleanRef = *mut std::ffi::c_void;
type CFTypeRef = *mut std::ffi::c_void;

const K_CV_32BGRA: u32 = u32::from_be_bytes(*b"BGRA");

// --- CoreFoundation / CoreVideo / VideoToolbox FFI --------------------------

#[cfg(any(target_os = "macos", target_os = "ios"))]
#[link(name = "CoreVideo", kind = "framework")]
#[link(name = "CoreFoundation", kind = "framework")]
#[link(name = "VideoToolbox", kind = "framework")]
extern "C" {
    fn CFRelease(cf: *mut std::ffi::c_void);

    static kCFAllocatorDefault: CFAllocatorRef;
    static kCFBooleanTrue: CFBooleanRef;

    fn CFDictionaryCreate(
        allocator: CFAllocatorRef,
        keys: *const CFTypeRef,
        values: *const CFTypeRef,
        num_values: isize,
        key_callbacks: *const std::ffi::c_void,
        value_callbacks: *const std::ffi::c_void,
    ) -> CFDictionaryRef;

    static kCFTypeDictionaryKeyCallBacks: std::ffi::c_void;
    static kCFTypeDictionaryValueCallBacks: std::ffi::c_void;

    fn CFNumberCreate(
        allocator: CFAllocatorRef,
        the_type: i32,
        value_ptr: *const std::ffi::c_void,
    ) -> CFNumberRef;

    fn CVPixelBufferCreate(
        allocator: *mut std::ffi::c_void,
        width: usize,
        height: usize,
        pixel_format_type: u32,
        pixel_buffer_attributes: *mut std::ffi::c_void,
        pixel_buffer_out: *mut CVPixelBufferRef,
    ) -> OSStatus;

    fn CVPixelBufferRetain(pixel_buffer: CVPixelBufferRef) -> CVPixelBufferRef;
    fn CVPixelBufferGetPixelFormatType(pixel_buffer: CVPixelBufferRef) -> u32;
    fn CVPixelBufferGetWidth(pixel_buffer: CVPixelBufferRef) -> usize;
    fn CVPixelBufferGetHeight(pixel_buffer: CVPixelBufferRef) -> usize;

    fn CVPixelBufferPoolCreate(
        allocator: CFAllocatorRef,
        pool_attributes: CFDictionaryRef,
        pixel_buffer_attributes: CFDictionaryRef,
        pool_out: *mut CVPixelBufferPoolRef,
    ) -> OSStatus;

    fn CVPixelBufferPoolRelease(pool: CVPixelBufferPoolRef);

    fn CVPixelBufferPoolCreatePixelBuffer(
        allocator: CFAllocatorRef,
        pixel_buffer_pool: CVPixelBufferPoolRef,
        pixel_buffer_out: *mut CVPixelBufferRef,
    ) -> OSStatus;

    fn VTPixelTransferSessionCreate(
        allocator: *mut std::ffi::c_void,
        pixel_transfer_session_out: *mut VTPixelTransferSessionRef,
    ) -> OSStatus;

    fn VTPixelTransferSessionTransferImage(
        session: VTPixelTransferSessionRef,
        source_buffer: CVPixelBufferRef,
        destination_buffer: CVPixelBufferRef,
    ) -> OSStatus;
}

// CoreFoundation CFNumberType: kCFNumberSInt32Type = 3
#[cfg(any(target_os = "macos", target_os = "ios"))]
const CF_NUMBER_SINT32_TYPE: i32 = 3;

macro_rules! vt_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*)
    };
}

// --- IOSurface-compatible CVPixelBufferPool ----------------------------------

/// A `CVPixelBufferPool` that allocates IOSurface-backed, Metal-compatible BGRA
/// buffers at a fixed `(width, height)`. All buffers produced by this pool will
/// pass `canAdoptPixelBufferDirectly` in the Swift pixel_surface plugin.
#[cfg(any(target_os = "macos", target_os = "ios"))]
struct VtBgraPool {
    pool: CVPixelBufferPoolRef,
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
impl VtBgraPool {
    /// Create a pool for `width × height` BGRA buffers with IOSurface + Metal attrs.
    /// Returns `None` if the system denies pool creation.
    fn new(width: u32, height: u32) -> Option<Self> {
        // Build pixel-buffer attribute dict:
        //   { kCVPixelBufferIOSurfacePropertiesKey: {},   <- enables IOSurface backing
        //     kCVPixelBufferMetalCompatibilityKey:  true,
        //     kCVPixelFormatType:                   kCVPixelFormatType_32BGRA }
        //
        // We use CoreFoundation's C API directly because this crate has no
        // core-foundation-sys dependency and we want to avoid adding one.
        unsafe {
            // Empty inner dict for IOSurface properties key
            let empty_dict: CFDictionaryRef = CFDictionaryCreate(
                kCFAllocatorDefault,
                ptr::null(),
                ptr::null(),
                0,
                &kCFTypeDictionaryKeyCallBacks as *const _,
                &kCFTypeDictionaryValueCallBacks as *const _,
            );
            if empty_dict.is_null() {
                return None;
            }

            // CFNumber for the pixel format (K_CV_32BGRA = 0x42475241)
            let fmt_val: u32 = K_CV_32BGRA;
            let fmt_num: CFNumberRef = CFNumberCreate(
                kCFAllocatorDefault,
                CF_NUMBER_SINT32_TYPE,
                &fmt_val as *const u32 as *const std::ffi::c_void,
            );
            if fmt_num.is_null() {
                CFRelease(empty_dict);
                return None;
            }

            // Build the IOSurface + Metal + format attribute dict.
            // Keys and values must be CFType objects.
            // We use the string constants from CoreVideo.framework via their
            // raw CFStringRef addresses (symbol-linked via the framework).
            let iosurface_key = get_cv_key_iosurface_properties();
            let metal_key = get_cv_key_metal_compatibility();
            let format_key = get_cv_key_pixel_format();

            let keys: [CFTypeRef; 3] = [
                iosurface_key as CFTypeRef,
                metal_key as CFTypeRef,
                format_key as CFTypeRef,
            ];
            let vals: [CFTypeRef; 3] = [
                empty_dict as CFTypeRef,
                kCFBooleanTrue as CFTypeRef,
                fmt_num as CFTypeRef,
            ];

            let pb_attrs: CFDictionaryRef = CFDictionaryCreate(
                kCFAllocatorDefault,
                keys.as_ptr(),
                vals.as_ptr(),
                3,
                &kCFTypeDictionaryKeyCallBacks as *const _,
                &kCFTypeDictionaryValueCallBacks as *const _,
            );

            CFRelease(fmt_num);
            CFRelease(empty_dict);

            if pb_attrs.is_null() {
                return None;
            }

            // Pool attrs: keep ≥3 warm buffers so the first frame after a pool
            // flush does not pay a fresh IOSurface allocation penalty.
            let min_count: i32 = 3;
            let min_count_num: CFNumberRef = CFNumberCreate(
                kCFAllocatorDefault,
                CF_NUMBER_SINT32_TYPE,
                &min_count as *const i32 as *const std::ffi::c_void,
            );

            let pool_key = get_cvpool_key_min_buffer_count();
            let pool_keys: [CFTypeRef; 1] = [pool_key as CFTypeRef];
            let pool_vals: [CFTypeRef; 1] = [min_count_num as CFTypeRef];

            let pool_attrs: CFDictionaryRef = CFDictionaryCreate(
                kCFAllocatorDefault,
                pool_keys.as_ptr(),
                pool_vals.as_ptr(),
                1,
                &kCFTypeDictionaryKeyCallBacks as *const _,
                &kCFTypeDictionaryValueCallBacks as *const _,
            );

            CFRelease(min_count_num);

            let mut pool: CVPixelBufferPoolRef = ptr::null_mut();
            let status = CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                pool_attrs,
                pb_attrs,
                &mut pool,
            );

            if !pool_attrs.is_null() {
                CFRelease(pool_attrs);
            }
            if !pb_attrs.is_null() {
                CFRelease(pb_attrs);
            }

            if status != 0 || pool.is_null() {
                vt_log!("[VtPixelBuffer] CVPixelBufferPoolCreate failed OSStatus={}", status);
                return None;
            }
            vt_log!(
                "[VtPixelBuffer] CVPixelBufferPool created {}x{} BGRA (IOSurface+Metal)",
                width,
                height
            );
            Some(Self { pool })
        }
    }

    /// Allocate a buffer from the pool (+1 for the caller).
    fn create_pixel_buffer(&self) -> Option<CVPixelBufferRef> {
        unsafe {
            let mut pb: CVPixelBufferRef = ptr::null_mut();
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self.pool, &mut pb);
            if status != 0 || pb.is_null() {
                vt_log!("[VtPixelBuffer] CVPixelBufferPoolCreatePixelBuffer failed OSStatus={}", status);
                return None;
            }
            Some(pb)
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
impl Drop for VtBgraPool {
    fn drop(&mut self) {
        unsafe {
            if !self.pool.is_null() {
                CVPixelBufferPoolRelease(self.pool);
            }
        }
    }
}

// CoreVideo key accessors — link against the framework symbols so we get the
// correct CFStringRef pointers without an external crate dependency.
#[cfg(any(target_os = "macos", target_os = "ios"))]
extern "C" {
    static kCVPixelBufferIOSurfacePropertiesKey: CFStringRef;
    static kCVPixelBufferMetalCompatibilityKey: CFStringRef;
    static kCVPixelBufferPixelFormatTypeKey: CFStringRef;
    static kCVPixelBufferPoolMinimumBufferCountKey: CFStringRef;
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn get_cv_key_iosurface_properties() -> CFStringRef {
    kCVPixelBufferIOSurfacePropertiesKey
}
#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn get_cv_key_metal_compatibility() -> CFStringRef {
    kCVPixelBufferMetalCompatibilityKey
}
#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn get_cv_key_pixel_format() -> CFStringRef {
    kCVPixelBufferPixelFormatTypeKey
}
#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn get_cvpool_key_min_buffer_count() -> CFStringRef {
    kCVPixelBufferPoolMinimumBufferCountKey
}

// --- VtPreviewTransfer -------------------------------------------------------

pub fn vt_zero_copy_enabled() -> bool {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        !matches!(
            std::env::var("MEDIA_DISABLE_VT_ZERO_COPY").as_deref(),
            Ok("1") | Ok("true") | Ok("yes")
        )
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        false
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn cv_buffer_from_frame(frame: *const ffi::AVFrame) -> Option<CVPixelBufferRef> {
    if frame.is_null() {
        return None;
    }
    let buf = (*frame).data[3] as CVPixelBufferRef;
    if buf.is_null() {
        None
    } else {
        Some(buf)
    }
}

pub struct VtPreviewTransfer {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    session: VTPixelTransferSessionRef,
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    pool: Option<VtBgraPool>,
    pub out_w: u32,
    pub out_h: u32,
}

impl VtPreviewTransfer {
    pub fn new(out_w: u32, out_h: u32) -> Option<Self> {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            unsafe {
                let mut session: VTPixelTransferSessionRef = ptr::null_mut();
                let err = VTPixelTransferSessionCreate(ptr::null_mut(), &mut session);
                if err != 0 || session.is_null() {
                    vt_log!(
                        "[VtPixelBuffer] VTPixelTransferSessionCreate failed OSStatus={}",
                        err
                    );
                    return None;
                }
                // Pre-warm the IOSurface-backed pool for the copy fallback path.
                let pool = VtBgraPool::new(out_w, out_h);
                if pool.is_none() {
                    vt_log!("[VtPixelBuffer] VtBgraPool creation failed — will use direct alloc as fallback");
                }
                return Some(Self {
                    session,
                    pool,
                    out_w,
                    out_h,
                });
            }
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            let _ = (out_w, out_h);
            None
        }
    }

    /// VT decode frame → preview-sized BGRA `CVPixelBuffer` (+1 for Dart `presentPixelBuffer`).
    ///
    /// **Zero-copy fast path:** if the VT frame is already `kCVPixelFormatType_32BGRA`
    /// at the target size, retains and returns the decoder's own CVPixelBuffer directly.
    /// VideoToolbox hardware frames are IOSurface-backed, so Swift's
    /// `canAdoptPixelBufferDirectly` succeeds → **no CPU blit, no extra allocation**.
    ///
    /// **Copy path:** otherwise uses `VTPixelTransferSession` + the IOSurface pool
    /// so the destination buffer is still adoption-eligible.
    pub fn transfer_to_bgra(
        &self,
        src: &FfmpegVideoFrame,
    ) -> Result<CVPixelBufferRef, anyhow::Error> {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            unsafe { transfer_vt_frame_to_bgra_pixel_buffer(self, src) }
        }
        #[cfg(not(any(target_os = "macos", target_os = "ios")))]
        {
            let _ = src;
            Err(anyhow!("VT pixel buffer path is Apple-only"))
        }
    }
}

impl Drop for VtPreviewTransfer {
    fn drop(&mut self) {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        unsafe {
            if !self.session.is_null() {
                CFRelease(self.session);
            }
            // pool is dropped automatically via VtBgraPool::Drop
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn transfer_vt_frame_to_bgra_pixel_buffer(
    xfer: &VtPreviewTransfer,
    src: &FfmpegVideoFrame,
) -> Result<CVPixelBufferRef, anyhow::Error> {
    if xfer.session.is_null() {
        return Err(anyhow!("VTPixelTransferSession is null"));
    }
    let src_buf = cv_buffer_from_frame(src.as_ptr())
        .ok_or_else(|| anyhow!("VT frame missing CVPixelBuffer"))?;

    let src_fmt = CVPixelBufferGetPixelFormatType(src_buf);
    let src_w = CVPixelBufferGetWidth(src_buf) as u32;
    let src_h = CVPixelBufferGetHeight(src_buf) as u32;

    // ── Zero-copy fast path ───────────────────────────────────────────────────
    // VideoToolbox hardware-decode frames are always IOSurface-backed.
    // If the decoder outputs BGRA at the target preview size, we can retain
    // the frame's own CVPixelBuffer and hand it directly to Swift for
    // zero-copy adoption (no VTPixelTransferSession, no pool allocation).
    if src_fmt == K_CV_32BGRA && src_w == xfer.out_w && src_h == xfer.out_h {
        CVPixelBufferRetain(src_buf);
        vt_log!(
            "[VtPixelBuffer] zero-copy: retained VT BGRA frame {}x{} → handoff",
            xfer.out_w, xfer.out_h
        );
        return Ok(src_buf);
    }

    // ── Copy path: VTPixelTransferSession → IOSurface pool buffer ────────────
    // Allocate the destination from the pool so it is IOSurface-backed and
    // Metal-compatible — Swift's canAdoptPixelBufferDirectly will return true.
    let dst = if let Some(ref pool) = xfer.pool {
        match pool.create_pixel_buffer() {
            Some(pb) => pb,
            None => {
                // Pool exhausted: fall back to a single direct alloc with correct attrs.
                create_iosurface_bgra_buffer(xfer.out_w, xfer.out_h)?
            }
        }
    } else {
        create_iosurface_bgra_buffer(xfer.out_w, xfer.out_h)?
    };

    let xfer_err = VTPixelTransferSessionTransferImage(xfer.session, src_buf, dst);
    if xfer_err != 0 {
        CFRelease(dst);
        return Err(anyhow!(
            "VTPixelTransferSessionTransferImage→BGRA OSStatus={}",
            xfer_err
        ));
    }
    Ok(dst)
}

/// Fallback: allocate a single IOSurface-backed Metal-compatible BGRA buffer
/// without going through a pool. Used when the pool is absent or exhausted.
#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn create_iosurface_bgra_buffer(width: u32, height: u32) -> Result<CVPixelBufferRef, anyhow::Error> {
    // Build the minimum attribute dict that makes Swift adopt the buffer:
    //   { kCVPixelBufferIOSurfacePropertiesKey: {},
    //     kCVPixelBufferMetalCompatibilityKey:  true }
    let empty_dict: CFDictionaryRef = CFDictionaryCreate(
        kCFAllocatorDefault,
        ptr::null(),
        ptr::null(),
        0,
        &kCFTypeDictionaryKeyCallBacks as *const _,
        &kCFTypeDictionaryValueCallBacks as *const _,
    );
    if empty_dict.is_null() {
        return Err(anyhow!("CFDictionaryCreate (empty) failed"));
    }
    let keys: [CFTypeRef; 2] = [
        kCVPixelBufferIOSurfacePropertiesKey as CFTypeRef,
        kCVPixelBufferMetalCompatibilityKey as CFTypeRef,
    ];
    let vals: [CFTypeRef; 2] = [
        empty_dict as CFTypeRef,
        kCFBooleanTrue as CFTypeRef,
    ];
    let attrs: CFDictionaryRef = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys.as_ptr(),
        vals.as_ptr(),
        2,
        &kCFTypeDictionaryKeyCallBacks as *const _,
        &kCFTypeDictionaryValueCallBacks as *const _,
    );
    CFRelease(empty_dict);
    if attrs.is_null() {
        return Err(anyhow!("CFDictionaryCreate (attrs) failed"));
    }
    let mut dst: CVPixelBufferRef = ptr::null_mut();
    let err = CVPixelBufferCreate(
        ptr::null_mut(),
        width as usize,
        height as usize,
        K_CV_32BGRA,
        attrs as *mut std::ffi::c_void,
        &mut dst,
    );
    CFRelease(attrs);
    if err != 0 || dst.is_null() {
        return Err(anyhow!("CVPixelBufferCreate BGRA (IOSurface) OSStatus={err}"));
    }
    Ok(dst)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub unsafe fn release_pixel_buffer(pb: CVPixelBufferRef) {
    if !pb.is_null() {
        CFRelease(pb);
    }
}

/// Hand off to Flutter `presentPixelBuffer` (`takeRetainedValue` consumes +1 from create/retain).
#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn pixel_buffer_ptr_for_handoff(pb: CVPixelBufferRef) -> u64 {
    pb as u64
}
