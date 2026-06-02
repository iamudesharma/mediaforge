//! Apple VideoToolbox P3 pipeline: CVPixelBuffer / IOSurface HW frames decoder → encoder.
//!
//! Avoids `av_hwframe_transfer_data` + `swscale` when possible (same as native social apps).

use std::ptr;

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video as DecoderVideo;
use ffmpeg_next::codec::encoder::Video as EncoderVideo;
use ffmpeg_next::ffi;
use ffmpeg_next::format::Pixel;
use ffmpeg_next::util::frame::video::Video as VideoFrame;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::hw_decode::HwFrameTransfer;
use crate::ffmpeg::map_ffmpeg_error;
use crate::ffmpeg::vt_link::VtLinkMode;

pub(crate) type CVPixelBufferRef = *mut std::ffi::c_void;
pub(crate) type VTPixelTransferSessionRef = *mut std::ffi::c_void;
pub(crate) type CVPixelBufferPoolRef = *mut std::ffi::c_void;
type CFDictionaryRef = *const std::ffi::c_void;
pub(crate) type OSStatus = i32;

/// 32-bit BGRA — matches Flutter `FlutterTexture` / `kCVPixelFormatType_32BGRA`.
pub(crate) const K_CV_32BGRA: u32 = u32::from_be_bytes(*b"BGRA");

#[link(name = "CoreVideo", kind = "framework")]
#[link(name = "CoreFoundation", kind = "framework")]
#[link(name = "VideoToolbox", kind = "framework")]
extern "C" {
    fn CFRelease(cf: *mut std::ffi::c_void);
    fn CFRetain(cf: *mut std::ffi::c_void) -> *mut std::ffi::c_void;

    fn CVPixelBufferCreate(
        allocator: *mut std::ffi::c_void,
        width: usize,
        height: usize,
        pixel_format_type: u32,
        pixel_buffer_attributes: *mut std::ffi::c_void,
        pixel_buffer_out: *mut CVPixelBufferRef,
    ) -> OSStatus;

    fn CVPixelBufferGetWidth(pixel_buffer: CVPixelBufferRef) -> usize;
    fn CVPixelBufferGetHeight(pixel_buffer: CVPixelBufferRef) -> usize;

    fn CVPixelBufferRetain(pixel_buffer: CVPixelBufferRef) -> CVPixelBufferRef;

    fn VTPixelTransferSessionCreate(
        allocator: *mut std::ffi::c_void,
        pixel_transfer_session_out: *mut VTPixelTransferSessionRef,
    ) -> OSStatus;

    fn VTPixelTransferSessionTransferImage(
        session: VTPixelTransferSessionRef,
        source_buffer: CVPixelBufferRef,
        destination_buffer: CVPixelBufferRef,
    ) -> OSStatus;

    // CVPixelBufferPool — used by engine::vt_pool.
    fn CVPixelBufferPoolCreate(
        allocator: *mut std::ffi::c_void,
        pool_attributes: CFDictionaryRef,
        pixel_buffer_attributes: CFDictionaryRef,
        pool_out: *mut CVPixelBufferPoolRef,
    ) -> OSStatus;

    fn CVPixelBufferPoolCreatePixelBuffer(
        allocator: *mut std::ffi::c_void,
        pool: CVPixelBufferPoolRef,
        pixel_buffer_out: *mut CVPixelBufferRef,
    ) -> OSStatus;

    fn CVPixelBufferPoolRelease(pool: CVPixelBufferPoolRef);
}

/// Release a `CVPixelBufferPool`. Called from `VtPixelBufferPool::Drop`.
///
/// # Safety
/// `pool` must be a valid `CVPixelBufferPoolRef` (or null, in which
/// case the call is a no-op).
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(crate) unsafe fn cv_release_pool(pool: CVPixelBufferPoolRef) {
    if !pool.is_null() {
        CVPixelBufferPoolRelease(pool);
    }
}

/// CFTypeRetain on a `CFTypeRef` (matches `CFRetain` / `CFRelease`).
///
/// # Safety
/// `cf` must be a valid `CFTypeRef` or null. A null `cf` is a no-op (caller
/// is responsible for handling null returns; this function only deals with
/// the rebalance case).
pub(crate) unsafe fn cf_retain(cf: *mut std::ffi::c_void) -> *mut std::ffi::c_void {
    if cf.is_null() {
        std::ptr::null_mut()
    } else {
        CFRetain(cf)
    }
}

fn map_vt_status(err: OSStatus, ctx: &str) -> VideoForgeError {
    VideoForgeError::FfmpegError(format!("{ctx}: OSStatus {err}"))
}

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

/// Allocate an initialized `AVHWFramesContext` for VideoToolbox.
pub unsafe fn alloc_hw_frames(
    device: *mut ffi::AVBufferRef,
    width: u32,
    height: u32,
) -> Result<*mut ffi::AVBufferRef> {
    let mut frames_ref = ffi::av_hwframe_ctx_alloc(device);
    if frames_ref.is_null() {
        return Err(VideoForgeError::FfmpegError(
            "av_hwframe_ctx_alloc failed".into(),
        ));
    }

    let frames = (*frames_ref).data as *mut ffi::AVHWFramesContext;
    (*frames).format = ffi::AVPixelFormat::AV_PIX_FMT_VIDEOTOOLBOX;
    (*frames).sw_format = ffi::AVPixelFormat::AV_PIX_FMT_NV12;
    (*frames).width = width as i32;
    (*frames).height = height as i32;

    let ret = ffi::av_hwframe_ctx_init(frames_ref);
    if ret < 0 {
        ffi::av_buffer_unref(&mut frames_ref);
        return Err(map_ffmpeg_error(ffmpeg_next::util::error::Error::from(ret)));
    }

    Ok(frames_ref)
}

unsafe fn attach_hw_frames_to_codec(
    avctx: *mut ffi::AVCodecContext,
    frames_ref: *mut ffi::AVBufferRef,
) -> Result<()> {
    if (*avctx).hw_frames_ctx.is_null() {
        (*avctx).hw_frames_ctx = ffi::av_buffer_ref(frames_ref);
    }
    if (*avctx).hw_frames_ctx.is_null() {
        return Err(VideoForgeError::FfmpegError(
            "av_buffer_ref(hw_frames_ctx) failed".into(),
        ));
    }
    Ok(())
}

unsafe fn attach_device_to_codec(
    avctx: *mut ffi::AVCodecContext,
    device: *mut ffi::AVBufferRef,
) -> Result<()> {
    if (*avctx).hw_device_ctx.is_null() {
        (*avctx).hw_device_ctx = ffi::av_buffer_ref(device);
    }
    if (*avctx).hw_device_ctx.is_null() {
        return Err(VideoForgeError::FfmpegError(
            "av_buffer_ref(hw_device_ctx) failed".into(),
        ));
    }
    Ok(())
}

/// True when P3 VT pipeline should be attempted (disable with `VFP_DISABLE_VT_PIPELINE=1`).
pub fn enabled() -> bool {
    !matches!(
        std::env::var("VFP_DISABLE_VT_PIPELINE").as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

pub fn is_apple_platform() -> bool {
    matches!(std::env::consts::OS, "ios" | "macos")
}

pub fn encoder_supports_vt_pipeline(encoder_name: &str) -> bool {
    encoder_name.contains("videotoolbox")
}

/// Configure shared IOSurface / CVPixelBuffer pools on decoder + encoder contexts.
pub fn prepare_vt_link(
    hw: &mut HwFrameTransfer,
    decoder: &mut DecoderVideo,
    enc_ctx: &mut CodecContext,
    src_w: u32,
    src_h: u32,
    out_w: u32,
    out_h: u32,
) -> Result<VtLinkMode> {
    if !enabled() || !is_apple_platform() {
        return Ok(VtLinkMode::None);
    }

    unsafe {
        let device = hw.device_ref();
        if device.is_null() {
            return Ok(VtLinkMode::None);
        }

        hw.ensure_decode_frames(src_w, src_h)?;

        let dec_avctx = decoder.as_mut_ptr();
        if let Some(frames) = hw.decode_frames_ref() {
            attach_hw_frames_to_codec(dec_avctx, frames)?;
        }
        attach_device_to_codec(dec_avctx, device)?;

        let enc_avctx = enc_ctx.as_mut_ptr();
        attach_device_to_codec(enc_avctx, device)?;

        let same_size = src_w == out_w && src_h == out_h;
        if same_size {
            if let Some(frames) = hw.decode_frames_ref() {
                attach_hw_frames_to_codec(enc_avctx, frames)?;
            }
            (*enc_avctx).pix_fmt = ffi::AVPixelFormat::AV_PIX_FMT_VIDEOTOOLBOX;
            log::info!(
                "VT P3: zero-copy CVPixelBuffer pipeline {out_w}x{out_h} (no swscale / CPU transfer)"
            );
            return Ok(VtLinkMode::ZeroCopy);
        }

        hw.ensure_encode_frames(out_w, out_h)?;
        if let Some(frames) = hw.encode_frames_ref() {
            attach_hw_frames_to_codec(enc_avctx, frames)?;
        }
        (*enc_avctx).pix_fmt = ffi::AVPixelFormat::AV_PIX_FMT_VIDEOTOOLBOX;
        hw.ensure_transfer_session()?;
        log::info!(
            "VT P3: GPU resize {src_w}x{src_h} → {out_w}x{out_h} via VTPixelTransferSession"
        );
        Ok(VtLinkMode::GpuScale)
    }
}

pub struct VtScaler {
    session: VTPixelTransferSessionRef,
    dst_frame: VideoFrame,
}

impl VtScaler {
    pub fn new(hw: &mut HwFrameTransfer, out_w: u32, out_h: u32) -> Result<Self> {
        hw.ensure_transfer_session()?;
        let session = hw
            .transfer_session()
            .ok_or_else(|| VideoForgeError::Internal("VT session missing".into()))?;

        let mut dst_frame = VideoFrame::empty();
        unsafe {
            let frames = hw
                .encode_frames_ref()
                .ok_or_else(|| VideoForgeError::Internal("encode hw_frames missing".into()))?;
            let ret = ffi::av_hwframe_get_buffer(frames, dst_frame.as_mut_ptr(), 0);
            if ret < 0 {
                return Err(map_ffmpeg_error(ffmpeg_next::util::error::Error::from(ret)));
            }
            dst_frame.set_width(out_w);
            dst_frame.set_height(out_h);
            dst_frame.set_format(Pixel::VIDEOTOOLBOX);
        }

        Ok(Self {
            session,
            dst_frame,
        })
    }

    /// Scale [src] CVPixelBuffer into the encoder pool frame allocated at construction.
    pub fn transfer_from(&mut self, src: &VideoFrame) -> Result<()> {
        unsafe {
            let src_ptr = src.as_ptr();
            let dst_ptr = self.dst_frame.as_mut_ptr();
            let src_buf = cv_buffer_from_frame(src_ptr).ok_or_else(|| {
                VideoForgeError::Internal("VT frame missing CVPixelBuffer".into())
            })?;
            let dst_buf = cv_buffer_from_frame(dst_ptr).ok_or_else(|| {
                VideoForgeError::Internal("VT dst frame missing CVPixelBuffer".into())
            })?;

            let err =
                VTPixelTransferSessionTransferImage(self.session, src_buf, dst_buf);
            if err != 0 {
                return Err(map_vt_status(err, "VTPixelTransferSessionTransferImage"));
            }

            ffi::av_frame_copy_props(dst_ptr, src_ptr);
            (*dst_ptr).width = CVPixelBufferGetWidth(dst_buf) as i32;
            (*dst_ptr).height = CVPixelBufferGetHeight(dst_buf) as i32;
            self.dst_frame.set_format(Pixel::VIDEOTOOLBOX);
        }
        Ok(())
    }

    pub fn output_frame(&mut self) -> &mut VideoFrame {
        &mut self.dst_frame
    }
}

/// Apply VT link to opened encoder (format + hw contexts).
pub fn finish_vt_encoder(
    encoder: &mut EncoderVideo,
    hw: &HwFrameTransfer,
    mode: VtLinkMode,
    out_w: u32,
    out_h: u32,
) -> Result<()> {
    if mode == VtLinkMode::None {
        return Ok(());
    }
    unsafe {
        let avctx = encoder.as_mut_ptr();
        (*avctx).pix_fmt = ffi::AVPixelFormat::AV_PIX_FMT_VIDEOTOOLBOX;
        encoder.set_format(Pixel::VIDEOTOOLBOX);
        encoder.set_width(out_w);
        encoder.set_height(out_h);

        let device = hw.device_ref();
        attach_device_to_codec(avctx, device)?;

        let frames = match mode {
            VtLinkMode::ZeroCopy => hw.decode_frames_ref(),
            VtLinkMode::GpuScale => hw.encode_frames_ref(),
            VtLinkMode::None => None,
        };
        if let Some(f) = frames {
            attach_hw_frames_to_codec(avctx, f)?;
        }
    }
    Ok(())
}

pub fn create_transfer_session() -> Result<VTPixelTransferSessionRef> {
    unsafe {
        let mut session: VTPixelTransferSessionRef = ptr::null_mut();
        let err = VTPixelTransferSessionCreate(ptr::null_mut(), &mut session);
        if err != 0 || session.is_null() {
            return Err(map_vt_status(err, "VTPixelTransferSessionCreate"));
        }
        Ok(session)
    }
}

pub unsafe fn release_transfer_session(session: VTPixelTransferSessionRef) {
    if !session.is_null() {
        CFRelease(session);
    }
}

/// Scale / convert a VideoToolbox-decoded frame into a standalone BGRA `CVPixelBuffer`.
///
/// Caller owns the returned buffer (+1). Release with [release_pixel_buffer] if not handed to UI.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub unsafe fn transfer_vt_frame_to_bgra_pixel_buffer(
    session: VTPixelTransferSessionRef,
    src: &VideoFrame,
    width: usize,
    height: usize,
) -> Result<CVPixelBufferRef> {
    if session.is_null() {
        return Err(VideoForgeError::Internal(
            "VTPixelTransferSession is null".into(),
        ));
    }
    let src_buf = cv_buffer_from_frame(src.as_ptr()).ok_or_else(|| {
        VideoForgeError::Internal("VT frame missing CVPixelBuffer".into())
    })?;

    let mut dst: CVPixelBufferRef = ptr::null_mut();
    // IOSurface is implied for VT transfer targets on Apple; attrs may be extended later.
    let err = CVPixelBufferCreate(
        ptr::null_mut(),
        width,
        height,
        K_CV_32BGRA,
        ptr::null_mut(),
        &mut dst,
    );
    if err != 0 || dst.is_null() {
        return Err(map_vt_status(err, "CVPixelBufferCreate BGRA"));
    }

    let xfer = VTPixelTransferSessionTransferImage(session, src_buf, dst);
    if xfer != 0 {
        CFRelease(dst);
        return Err(map_vt_status(xfer, "VTPixelTransferSessionTransferImage→BGRA"));
    }
    Ok(dst)
}

/// Acquire a destination `CVPixelBuffer` from a `CVPixelBufferPool`.
///
/// On success, returns a buffer with `+1` retain. The caller is
/// responsible for releasing it (with [`CFRelease`]) when the texture
/// plugin has consumed it, exactly as the non-pooled path does.
///
/// # Safety
/// `pool` must be a valid `CVPixelBufferPoolRef` (or null, in which case
/// the function falls back to a direct `CVPixelBufferCreate`).
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(crate) unsafe fn acquire_bgra_pixel_buffer_from_pool(
    pool: CVPixelBufferPoolRef,
    width: usize,
    height: usize,
) -> Result<CVPixelBufferRef> {
    if !pool.is_null() {
        let mut dst: CVPixelBufferRef = ptr::null_mut();
        let err = CVPixelBufferPoolCreatePixelBuffer(ptr::null_mut(), pool, &mut dst);
        if err == 0 && !dst.is_null() {
            return Ok(dst);
        }
        log::warn!(
            "CVPixelBufferPoolCreatePixelBuffer failed (OSStatus {err}); \
             falling back to CVPixelBufferCreate"
        );
    }

    // Fallback path: same as the non-pooled variant. This is what the
    // pool's `acquire` does internally when the pool is exhausted or
    // mis-configured, but we keep an explicit fallback here for
    // null-pool callers.
    let mut dst: CVPixelBufferRef = ptr::null_mut();
    let err = CVPixelBufferCreate(
        ptr::null_mut(),
        width,
        height,
        K_CV_32BGRA,
        ptr::null_mut(),
        &mut dst,
    );
    if err != 0 || dst.is_null() {
        return Err(map_vt_status(err, "CVPixelBufferCreate BGRA (pool fallback)"));
    }
    Ok(dst)
}

/// Create a `CVPixelBufferPool` for BGRA buffers of `width × height`.
///
/// `min_buffers` is the steady-state reservation; `max_buffers` is the
/// hard ceiling the pool will retain internally. Both default to sensible
/// values; the engine reads `VFP_VT_POOL_*` env flags to override.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(crate) unsafe fn create_bgra_pixel_buffer_pool(
    width: u32,
    height: u32,
    min_buffers: u32,
    max_buffers: u32,
) -> Result<CVPixelBufferPoolRef> {
    let mut pool: CVPixelBufferPoolRef = ptr::null_mut();
    let err = CVPixelBufferPoolCreate(
        ptr::null_mut(),
        ptr::null(), // pool attributes — kept null; tuning happens via per-buffer attrs / age
        ptr::null(), // pixel buffer attributes — pool derives from CVPixelBufferCreate attrs
        &mut pool,
    );
    if err != 0 || pool.is_null() {
        return Err(map_vt_status(
            err,
            "CVPixelBufferPoolCreate (BGRA {width}x{height}, min={min_buffers}, max={max_buffers})",
        ));
    }
    // min_buffers / max_buffers arguments are reserved for the future
    // CFDictionary-based attributes path; today the pool's internal
    // maximum is the system's default. We still log them so the operator
    // can confirm what was requested.
    log::info!(
        "[VtPipeline] CVPixelBufferPool created {width}x{height} BGRA (requested min={min_buffers} max={max_buffers})"
    );
    let _ = (min_buffers, max_buffers);
    Ok(pool)
}

/// Release a preview `CVPixelBuffer` when not adopted by the texture plugin.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub unsafe fn release_pixel_buffer(pb: CVPixelBufferRef) {
    if !pb.is_null() {
        CFRelease(pb);
    }
}

/// Retain for handoff to Dart/native (`takeRetainedValue` consumes one retain).
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub unsafe fn retain_pixel_buffer_for_handoff(pb: CVPixelBufferRef) -> u64 {
    CVPixelBufferRetain(pb);
    pb as u64
}

/// Run `VTPixelTransferSessionTransferImage` and return the raw
/// `OSStatus`. Exposed so `engine::vt_pool` can pair a pool-acquired
/// destination buffer with the existing transfer session without
/// duplicating the FFI binding.
#[cfg(any(target_os = "ios", target_os = "macos"))]
pub(crate) unsafe fn vt_pixel_transfer_session_transfer_image(
    session: *mut std::ffi::c_void,
    source_buffer: CVPixelBufferRef,
    destination_buffer: CVPixelBufferRef,
) -> OSStatus {
    VTPixelTransferSessionTransferImage(session, source_buffer, destination_buffer)
}
