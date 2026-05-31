//! Hardware video decode via FFmpeg `hw_device_ctx` (VideoToolbox / MediaCodec).
//!
//! `ffmpeg-next` does not expose HW device APIs; we use `ffmpeg_next::ffi` directly.

use std::ffi::c_void;
use std::ptr;

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video;
use ffmpeg_next::codec::Id;
use ffmpeg_next::ffi;
use ffmpeg_next::format::Pixel;
use ffmpeg_next::util::frame::video::Video as VideoFrame;
use crate::error::{Result, VideoProcessorError};
use crate::ffmpeg::map_ffmpeg_error;

fn map_av_err(ret: i32) -> VideoProcessorError {
    map_ffmpeg_error(ffmpeg_next::util::error::Error::from(ret))
}

/// Set `VFP_DISABLE_HW_DECODE=1` to force software decode (debug).
pub fn enabled() -> bool {
    !matches!(
        std::env::var("VFP_DISABLE_HW_DECODE").as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

/// HW decode when compressing with HW encode. Disabled on Android (MediaCodec decode+encode is unstable).
pub fn prefer_hw_decode_with_encode() -> bool {
    if !enabled() {
        return false;
    }
    if std::env::consts::OS == "android" {
        return matches!(
            std::env::var("VFP_ENABLE_HW_DECODE").as_deref(),
            Ok("1") | Ok("true") | Ok("yes")
        );
    }
    true
}

pub fn platform_device_name() -> &'static str {
    match std::env::consts::OS {
        "ios" | "macos" => "videotoolbox",
        "android" => "mediacodec",
        _ => "none",
    }
}

/// Per-decoder state stored in `AVCodecContext.opaque` (safe for concurrent jobs).
struct HwDecodeState {
    hw_pix: ffi::AVPixelFormat,
}

unsafe fn hw_decode_pix_from(avctx: *mut ffi::AVCodecContext) -> ffi::AVPixelFormat {
    if avctx.is_null() {
        return ffi::AVPixelFormat::AV_PIX_FMT_NONE;
    }
    let opaque = (*avctx).opaque;
    if opaque.is_null() {
        return ffi::AVPixelFormat::AV_PIX_FMT_NONE;
    }
    (*(opaque as *const HwDecodeState)).hw_pix
}

unsafe fn pix_fmt_is_hw(fmt: ffi::AVPixelFormat) -> bool {
    if fmt == ffi::AVPixelFormat::AV_PIX_FMT_NONE {
        return false;
    }
    let desc = ffi::av_pix_fmt_desc_get(fmt);
    if desc.is_null() {
        return false;
    }
    ((*desc).flags as i32 & ffi::AV_PIX_FMT_FLAG_HWACCEL) != 0
}

unsafe extern "C" fn hw_get_format(
    avctx: *mut ffi::AVCodecContext,
    pix_fmts: *const ffi::AVPixelFormat,
) -> ffi::AVPixelFormat {
    log::info!("hw_get_format callback invoked");
    let target = hw_decode_pix_from(avctx);
    let mut p = pix_fmts;
    let mut offered = Vec::new();
    let mut first_hw = ffi::AVPixelFormat::AV_PIX_FMT_NONE;

    while !p.is_null() && *p != ffi::AVPixelFormat::AV_PIX_FMT_NONE {
        offered.push(*p);
        if first_hw == ffi::AVPixelFormat::AV_PIX_FMT_NONE && pix_fmt_is_hw(*p) {
            first_hw = *p;
        }
        p = p.add(1);
    }

    let chosen = if target != ffi::AVPixelFormat::AV_PIX_FMT_NONE
        && offered.contains(&target)
    {
        target
    } else if first_hw != ffi::AVPixelFormat::AV_PIX_FMT_NONE {
        log::info!(
            "HW get_format: using first HW format {:?} (target was {:?})",
            first_hw,
            target
        );
        first_hw
    } else {
        log::warn!(
            "HW get_format: no HW format in offered list {:?}, using default",
            offered
        );
        return ffi::avcodec_default_get_format(avctx, pix_fmts);
    };

    if chosen != ffi::AVPixelFormat::AV_PIX_FMT_NONE {
        log::info!("HW decode: selected pixel format {:?}", chosen);
        return chosen;
    }

    ffi::avcodec_default_get_format(avctx, pix_fmts)
}

fn platform_device_type() -> Option<ffi::AVHWDeviceType> {
    match std::env::consts::OS {
        "ios" | "macos" => Some(ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX),
        "android" => Some(ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_MEDIACODEC),
        _ => None,
    }
}

struct DeviceBuffer {
    ptr: *mut ffi::AVBufferRef,
}

impl DeviceBuffer {
    unsafe fn from_create(type_: ffi::AVHWDeviceType) -> Option<Self> {
        let mut ptr: *mut ffi::AVBufferRef = ptr::null_mut();
        let err = ffi::av_hwdevice_ctx_create(
            &mut ptr,
            type_,
            ptr::null(),
            ptr::null_mut(),
            0,
        );
        if err < 0 {
            log::warn!(
                "av_hwdevice_ctx_create({type_:?}) failed: {}",
                err
            );
            return None;
        }
        if ptr.is_null() {
            return None;
        }
        Some(Self { ptr })
    }
}

impl Drop for DeviceBuffer {
    fn drop(&mut self) {
        unsafe {
            if !self.ptr.is_null() {
                ffi::av_buffer_unref(&mut self.ptr);
            }
        }
    }
}

/// Keeps the HW device alive and transfers decoded HW frames to system memory.
pub struct HwFrameTransfer {
    _device: DeviceBuffer,
    device_type: ffi::AVHWDeviceType,
    pub sw_format: Pixel,
    opaque: *mut HwDecodeState,
    decode_frames: Option<FramesBuffer>,
    encode_frames: Option<FramesBuffer>,
    #[cfg(any(target_os = "ios", target_os = "macos"))]
    vt_transfer_session: Option<VtSession>,
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
use crate::ffmpeg::vt_pipeline;

#[cfg(any(target_os = "ios", target_os = "macos"))]
struct VtSession {
    ptr: VTPixelTransferSessionRef,
}

#[cfg(any(target_os = "ios", target_os = "macos"))]
type VTPixelTransferSessionRef = *mut std::ffi::c_void;

struct FramesBuffer {
    ptr: *mut ffi::AVBufferRef,
}

impl FramesBuffer {
    unsafe fn from_init(ptr: *mut ffi::AVBufferRef) -> Self {
        Self { ptr }
    }
}

impl Drop for FramesBuffer {
    fn drop(&mut self) {
        unsafe {
            if !self.ptr.is_null() {
                ffi::av_buffer_unref(&mut self.ptr);
            }
        }
    }
}

impl Drop for HwFrameTransfer {
    fn drop(&mut self) {
        if !self.opaque.is_null() {
            unsafe {
                drop(Box::from_raw(self.opaque));
            }
            self.opaque = ptr::null_mut();
        }
        #[cfg(any(target_os = "ios", target_os = "macos"))]
        if let Some(session) = self.vt_transfer_session.take() {
            unsafe {
                vt_pipeline::release_transfer_session(session.ptr);
            }
        }
    }
}

impl HwFrameTransfer {
    pub fn device_ref(&self) -> *mut ffi::AVBufferRef {
        self._device.ptr
    }

    pub fn decode_frames_ref(&self) -> Option<*mut ffi::AVBufferRef> {
        self.decode_frames.as_ref().map(|f| f.ptr)
    }

    pub fn encode_frames_ref(&self) -> Option<*mut ffi::AVBufferRef> {
        self.encode_frames.as_ref().map(|f| f.ptr)
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn transfer_session(&self) -> Option<VTPixelTransferSessionRef> {
        self.vt_transfer_session.as_ref().map(|s| s.ptr)
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn ensure_decode_frames(&mut self, width: u32, height: u32) -> Result<()> {
        if self.decode_frames.is_some() {
            return Ok(());
        }
        if self.device_type != ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX {
            return Ok(());
        }
        unsafe {
            let frames = vt_pipeline::alloc_hw_frames(self.device_ref(), width, height)?;
            self.decode_frames = Some(FramesBuffer::from_init(frames));
        }
        Ok(())
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    pub fn ensure_decode_frames(&mut self, _width: u32, _height: u32) -> Result<()> {
        Ok(())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn ensure_encode_frames(&mut self, width: u32, height: u32) -> Result<()> {
        if self.encode_frames.is_some() {
            return Ok(());
        }
        if self.device_type != ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX {
            return Ok(());
        }
        unsafe {
            let frames = vt_pipeline::alloc_hw_frames(self.device_ref(), width, height)?;
            self.encode_frames = Some(FramesBuffer::from_init(frames));
        }
        Ok(())
    }

    #[cfg(not(any(target_os = "ios", target_os = "macos")))]
    pub fn ensure_encode_frames(&mut self, _width: u32, _height: u32) -> Result<()> {
        Ok(())
    }

    #[cfg(any(target_os = "ios", target_os = "macos"))]
    pub fn ensure_transfer_session(&mut self) -> Result<()> {
        if self.vt_transfer_session.is_some() {
            return Ok(());
        }
        let ptr = vt_pipeline::create_transfer_session()?;
        self.vt_transfer_session = Some(VtSession { ptr });
        Ok(())
    }
}

impl HwFrameTransfer {
    /// Download a HW-decoded frame into `dst` (allocated by FFmpeg if needed).
    pub fn transfer_to_sw(&self, src: &VideoFrame, dst: &mut VideoFrame) -> Result<()> {
        if !is_hw_pixel_format(src.format()) {
            return Err(VideoProcessorError::Internal(
                "transfer_to_sw called on non-HW frame".into(),
            ));
        }
        unsafe {
            let ret = ffi::av_hwframe_transfer_data(dst.as_mut_ptr(), src.as_ptr(), 0);
            if ret < 0 {
                return Err(map_av_err(ret));
            }
            ffi::av_frame_copy_props(dst.as_mut_ptr(), src.as_ptr());
        }
        Ok(())
    }

    pub fn device_type_name(&self) -> &'static str {
        match self.device_type {
            ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX => "videotoolbox",
            ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_MEDIACODEC => "mediacodec",
            _ => "hw",
        }
    }
}

pub fn is_hw_pixel_format(format: Pixel) -> bool {
    matches!(format, Pixel::VIDEOTOOLBOX | Pixel::MEDIACODEC)
}

pub fn decoder_outputs_hw_frames(decoder: &Video) -> bool {
    is_hw_pixel_format(decoder.format())
}

/// Attach platform HW device to decoder context before `avcodec_open2`.
pub fn attach_hw_device_ctx(dec_ctx: &mut CodecContext) -> Result<Option<HwFrameTransfer>> {
    let device_type = match platform_device_type() {
        Some(t) => t,
        None => return Ok(None),
    };

    let codec_id = dec_ctx.id();
    if !matches!(codec_id, Id::H264 | Id::HEVC) {
        return Ok(None);
    }

    unsafe {
        let codec = ffi::avcodec_find_decoder(codec_id.into());
        if codec.is_null() {
            return Ok(None);
        }

        let mut hw_pix = ffi::AVPixelFormat::AV_PIX_FMT_NONE;
        if !codec_has_hw_device_config(codec, device_type, &mut hw_pix) {
            log::warn!(
                "codec {:?} has no HW_DEVICE_CTX for {:?} — software decode only; \
                 P3 vt_gpu_scale disabled. Rebuild iOS/macOS FFmpeg with \
                 --enable-hwaccel=h264_videotoolbox,hevc_videotoolbox (see tools/ffmpeg/apple-ios-device.sh)",
                codec_id,
                device_type
            );
            return Ok(None);
        }

        let device = match DeviceBuffer::from_create(device_type) {
            Some(d) => d,
            None => return Ok(None),
        };

        let avctx = dec_ctx.as_mut_ptr();

        let state = Box::new(HwDecodeState { hw_pix });
        let opaque = Box::into_raw(state);
        (*avctx).opaque = opaque as *mut c_void;
        (*avctx).get_format = Some(hw_get_format);
        (*avctx).extra_hw_frames = 8;

        (*avctx).hw_device_ctx = ffi::av_buffer_ref(device.ptr);
        if (*avctx).hw_device_ctx.is_null() {
            drop(Box::from_raw(opaque));
            return Err(VideoProcessorError::FfmpegError(
                "av_buffer_ref(hw_device_ctx) failed".into(),
            ));
        }

        let sw_format = preferred_sw_format(device_type, hw_pix);

        log::info!(
            "attached HW decode device {:?} (hw_pix={:?}, sw_transfer={:?})",
            device_type,
            hw_pix,
            sw_format
        );

        Ok(Some(HwFrameTransfer {
            _device: device,
            device_type,
            sw_format,
            opaque,
            decode_frames: None,
            encode_frames: None,
            #[cfg(any(target_os = "ios", target_os = "macos"))]
            vt_transfer_session: None,
        }))
    }
}

unsafe fn codec_has_hw_device_config(
    codec: *const ffi::AVCodec,
    device_type: ffi::AVHWDeviceType,
    hw_pix: *mut ffi::AVPixelFormat,
) -> bool {
    let method = ffi::AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX as i32;
    let mut i = 0;
    loop {
        let config = ffi::avcodec_get_hw_config(codec, i);
        if config.is_null() {
            break;
        }
        if (*config).device_type == device_type && ((*config).methods & method) != 0 {
            *hw_pix = (*config).pix_fmt;
            return true;
        }
        i += 1;
    }
    false
}

fn preferred_sw_format(
    device_type: ffi::AVHWDeviceType,
    _hw_pix: ffi::AVPixelFormat,
) -> Pixel {
    match device_type {
        ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_MEDIACODEC => Pixel::NV12,
        _ => Pixel::YUV420P,
    }
}

fn open_decoder_with_hw(
    dec_ctx: CodecContext,
    hw: HwFrameTransfer,
) -> Result<(Video, Option<HwFrameTransfer>)> {
    use ffmpeg_next::codec::threading::{Config, Type};

    let mut dec_ctx = dec_ctx;
    dec_ctx.set_threading(Config {
        kind: Type::None,
        count: 1,
        ..Default::default()
    });

    let codec_id = dec_ctx.id();
    // HW decode uses hw_device_ctx + get_format; no legacy hwaccel dictionary needed.

    let mut decoder = if let Some(codec) = ffmpeg_next::codec::decoder::find(codec_id) {
        dec_ctx
            .decoder()
            .open_as(codec)
            .map_err(map_ffmpeg_error)?
            .video()
            .map_err(map_ffmpeg_error)?
    } else {
        dec_ctx.decoder().video().map_err(map_ffmpeg_error)?
    };

    // `get_format` only runs during open; clear ctx.opaque so Drop does not alias a live ctx.
    unsafe {
        let avctx = decoder.as_mut_ptr();
        if !avctx.is_null() {
            (*avctx).opaque = ptr::null_mut();
        }
    }

    if decoder_outputs_hw_frames(&decoder) {
        log::info!(
            "hardware video decode active ({}, {}x{})",
            hw.device_type_name(),
            decoder.width(),
            decoder.height()
        );
        Ok((decoder, Some(hw)))
    } else {
        log::info!(
            "HW device attached; decoder reports {:?} (HW frames may appear per packet)",
            decoder.format()
        );
        Ok((decoder, Some(hw)))
    }
}

/// Open a video decoder, preferring HW when `prefer_hw` and the platform supports it.
pub fn open_video_decoder(
    parameters: ffmpeg_next::codec::Parameters,
    prefer_hw: bool,
) -> Result<(Video, Option<HwFrameTransfer>)> {
    if prefer_hw && enabled() {
        let mut dec_ctx =
            CodecContext::from_parameters(parameters.clone()).map_err(map_ffmpeg_error)?;
        if let Some(hw) = attach_hw_device_ctx(&mut dec_ctx)? {
            match open_decoder_with_hw(dec_ctx, hw) {
                Ok(pair) => return Ok(pair),
                Err(e) => {
                    log::warn!("HW decode open failed ({e}); falling back to software");
                }
            }
        }
    }

    let mut dec_ctx = CodecContext::from_parameters(parameters).map_err(map_ffmpeg_error)?;
    crate::ffmpeg::apply_video_decoder_threading(&mut dec_ctx);
    let decoder = dec_ctx.decoder().video().map_err(map_ffmpeg_error)?;
    Ok((decoder, None))
}
