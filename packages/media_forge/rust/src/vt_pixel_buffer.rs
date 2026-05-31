//! Apple VideoToolbox decode → BGRA `CVPixelBuffer` for Flutter texture (no RGBA on hot path).

use std::ptr;

use anyhow::anyhow;
use ffmpeg_next::ffi;
use ffmpeg_next::util::frame::video::Video as FfmpegVideoFrame;

type CVPixelBufferRef = *mut std::ffi::c_void;
type VTPixelTransferSessionRef = *mut std::ffi::c_void;
type OSStatus = i32;

const K_CV_32BGRA: u32 = u32::from_be_bytes(*b"BGRA");

#[cfg(any(target_os = "macos", target_os = "ios"))]
#[link(name = "CoreVideo", kind = "framework")]
#[link(name = "CoreFoundation", kind = "framework")]
#[link(name = "VideoToolbox", kind = "framework")]
extern "C" {
    fn CFRelease(cf: *mut std::ffi::c_void);

    fn CVPixelBufferCreate(
        allocator: *mut std::ffi::c_void,
        width: usize,
        height: usize,
        pixel_format_type: u32,
        pixel_buffer_attributes: *mut std::ffi::c_void,
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

macro_rules! vt_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*);
    };
}

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
                return Some(Self {
                    session,
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
    pub fn transfer_to_bgra(
        &self,
        src: &FfmpegVideoFrame,
    ) -> Result<CVPixelBufferRef, anyhow::Error> {
        #[cfg(any(target_os = "macos", target_os = "ios"))]
        {
            unsafe {
                transfer_vt_frame_to_bgra_pixel_buffer(
                    self.session,
                    src,
                    self.out_w,
                    self.out_h,
                )
            }
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
        }
    }
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
unsafe fn transfer_vt_frame_to_bgra_pixel_buffer(
    session: VTPixelTransferSessionRef,
    src: &FfmpegVideoFrame,
    width: u32,
    height: u32,
) -> Result<CVPixelBufferRef, anyhow::Error> {
    if session.is_null() {
        return Err(anyhow!("VTPixelTransferSession is null"));
    }
    let src_buf = cv_buffer_from_frame(src.as_ptr())
        .ok_or_else(|| anyhow!("VT frame missing CVPixelBuffer"))?;

    let mut dst: CVPixelBufferRef = ptr::null_mut();
    let err = CVPixelBufferCreate(
        ptr::null_mut(),
        width as usize,
        height as usize,
        K_CV_32BGRA,
        ptr::null_mut(),
        &mut dst,
    );
    if err != 0 || dst.is_null() {
        return Err(anyhow!("CVPixelBufferCreate BGRA OSStatus={err}"));
    }

    let xfer = VTPixelTransferSessionTransferImage(session, src_buf, dst);
    if xfer != 0 {
        CFRelease(dst);
        return Err(anyhow!(
            "VTPixelTransferSessionTransferImage→BGRA OSStatus={xfer}"
        ));
    }
    Ok(dst)
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub unsafe fn release_pixel_buffer(pb: CVPixelBufferRef) {
    if !pb.is_null() {
        CFRelease(pb);
    }
}

/// Hand off to Flutter `presentPixelBuffer` (`takeRetainedValue` consumes +1 from create).
#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn pixel_buffer_ptr_for_handoff(pb: CVPixelBufferRef) -> u64 {
    pb as u64
}
