//! VideoToolbox hardware decode via FFmpeg `hw_device_ctx` (FFmpeg 7+/8).
//! Internal module — not exposed to flutter_rust_bridge (`rust_input: crate::api`).

use std::ffi::c_void;
use std::ptr;

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video;
use ffmpeg_next::codec::Id;
use ffmpeg_next::ffi;
use ffmpeg_next::format::Pixel;
use ffmpeg_next::util::frame::video::Video as FfmpegVideoFrame;

struct HwDecodeState {
    hw_pix: ffi::AVPixelFormat,
}

struct DeviceBuffer {
    ptr: *mut ffi::AVBufferRef,
}

impl DeviceBuffer {
    unsafe fn create(type_: ffi::AVHWDeviceType) -> Option<Self> {
        let mut ptr: *mut ffi::AVBufferRef = ptr::null_mut();
        if ffi::av_hwdevice_ctx_create(&mut ptr, type_, ptr::null(), ptr::null_mut(), 0) < 0
            || ptr.is_null()
        {
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

pub struct HwFrameTransfer {
    _device: DeviceBuffer,
    pub sw_format: Pixel,
    opaque: *mut HwDecodeState,
}

impl Drop for HwFrameTransfer {
    fn drop(&mut self) {
        if !self.opaque.is_null() {
            unsafe {
                drop(Box::from_raw(self.opaque));
            }
        }
    }
}

impl HwFrameTransfer {
    pub fn transfer_to_sw(&self, src: &FfmpegVideoFrame, dst: &mut FfmpegVideoFrame) -> bool {
        unsafe {
            if ffi::av_hwframe_transfer_data(dst.as_mut_ptr(), src.as_ptr(), 0) < 0 {
                return false;
            }
            ffi::av_frame_copy_props(dst.as_mut_ptr(), src.as_ptr());
            true
        }
    }
}

pub fn is_hw_pixel_format(format: Pixel) -> bool {
    matches!(format, Pixel::VIDEOTOOLBOX | Pixel::MEDIACODEC)
}

fn platform_device_type() -> Option<ffi::AVHWDeviceType> {
    #[cfg(any(target_os = "macos", target_os = "ios"))]
    {
        Some(ffi::AVHWDeviceType::AV_HWDEVICE_TYPE_VIDEOTOOLBOX)
    }
    #[cfg(not(any(target_os = "macos", target_os = "ios")))]
    {
        None
    }
}

unsafe fn codec_has_hw_device_config(
    codec: *const ffi::AVCodec,
    device_type: ffi::AVHWDeviceType,
) -> bool {
    let method = ffi::AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX as i32;
    let mut i = 0;
    loop {
        let config = ffi::avcodec_get_hw_config(codec, i);
        if config.is_null() {
            break;
        }
        if (*config).device_type == device_type && ((*config).methods & method) != 0 {
            return true;
        }
        i += 1;
    }
    false
}

pub fn hevc_videotoolbox_hw_available() -> bool {
    hw_available_for_codec(Id::HEVC)
}

pub fn h264_videotoolbox_hw_available() -> bool {
    hw_available_for_codec(Id::H264)
}

fn hw_available_for_codec(codec_id: Id) -> bool {
    let device_type = match platform_device_type() {
        Some(t) => t,
        None => return false,
    };
    unsafe {
        let codec = ffi::avcodec_find_decoder(codec_id.into());
        !codec.is_null() && codec_has_hw_device_config(codec, device_type)
    }
}

unsafe extern "C" fn hw_get_format(
    avctx: *mut ffi::AVCodecContext,
    pix_fmts: *const ffi::AVPixelFormat,
) -> ffi::AVPixelFormat {
    let target = if avctx.is_null() || (*avctx).opaque.is_null() {
        ffi::AVPixelFormat::AV_PIX_FMT_NONE
    } else {
        (*( (*avctx).opaque as *const HwDecodeState)).hw_pix
    };

    let mut p = pix_fmts;
    let mut first_hw = ffi::AVPixelFormat::AV_PIX_FMT_NONE;
    while !p.is_null() && *p != ffi::AVPixelFormat::AV_PIX_FMT_NONE {
        if target != ffi::AVPixelFormat::AV_PIX_FMT_NONE && *p == target {
            return target;
        }
        if first_hw == ffi::AVPixelFormat::AV_PIX_FMT_NONE {
            let desc = ffi::av_pix_fmt_desc_get(*p);
            if !desc.is_null()
                && ((*desc).flags as i32 & ffi::AV_PIX_FMT_FLAG_HWACCEL) != 0
            {
                first_hw = *p;
            }
        }
        p = p.add(1);
    }
    if first_hw != ffi::AVPixelFormat::AV_PIX_FMT_NONE {
        return first_hw;
    }
    ffi::avcodec_default_get_format(avctx, pix_fmts)
}

fn attach_hw_device_ctx(dec_ctx: &mut CodecContext) -> Option<HwFrameTransfer> {
    let device_type = platform_device_type()?;
    let codec_id = dec_ctx.id();
    if !matches!(codec_id, Id::H264 | Id::HEVC) {
        return None;
    }

    unsafe {
        let codec = ffi::avcodec_find_decoder(codec_id.into());
        if codec.is_null() {
            return None;
        }

        let mut hw_pix = ffi::AVPixelFormat::AV_PIX_FMT_NONE;
        let method = ffi::AV_CODEC_HW_CONFIG_METHOD_HW_DEVICE_CTX as i32;
        let mut i = 0;
        let mut found = false;
        loop {
            let config = ffi::avcodec_get_hw_config(codec, i);
            if config.is_null() {
                break;
            }
            if (*config).device_type == device_type && ((*config).methods & method) != 0 {
                hw_pix = (*config).pix_fmt;
                found = true;
                break;
            }
            i += 1;
        }
        if !found {
            return None;
        }

        let device = DeviceBuffer::create(device_type)?;
        let avctx = dec_ctx.as_mut_ptr();
        let state = Box::new(HwDecodeState { hw_pix });
        let opaque = Box::into_raw(state);
        (*avctx).opaque = opaque as *mut c_void;
        (*avctx).get_format = Some(hw_get_format);
        (*avctx).extra_hw_frames = 8;
        (*avctx).hw_device_ctx = ffi::av_buffer_ref(device.ptr);
        if (*avctx).hw_device_ctx.is_null() {
            drop(Box::from_raw(opaque));
            return None;
        }

        Some(HwFrameTransfer {
            _device: device,
            sw_format: Pixel::YUV420P,
            opaque,
        })
    }
}

fn hw_decode_enabled() -> bool {
    !matches!(
        std::env::var("VFP_DISABLE_HW_DECODE").as_deref(),
        Ok("1") | Ok("true") | Ok("yes")
    )
}

pub fn try_open_vt_video_decoder(
    params: &ffmpeg_next::codec::Parameters,
) -> Option<(Video, HwFrameTransfer)> {
    if !hw_decode_enabled() {
        return None;
    }

    let mut dec_ctx = CodecContext::from_parameters(params.clone()).ok()?;
    let hw = attach_hw_device_ctx(&mut dec_ctx)?;

    dec_ctx.set_threading(ffmpeg_next::codec::threading::Config {
        kind: ffmpeg_next::codec::threading::Type::None,
        count: 1,
        ..Default::default()
    });

    let codec_id = dec_ctx.id();
    let mut decoder = if let Some(codec) = ffmpeg_next::codec::decoder::find(codec_id) {
        dec_ctx.decoder().open_as(codec).ok()?.video().ok()?
    } else {
        dec_ctx.decoder().video().ok()?
    };

    unsafe {
        let avctx = decoder.as_mut_ptr();
        if !avctx.is_null() {
            (*avctx).opaque = ptr::null_mut();
        }
    }

    Some((decoder, hw))
}
