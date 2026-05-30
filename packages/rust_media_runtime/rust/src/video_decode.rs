//! Video decode pipelines with adaptive swscale and reopen-on-flush (post-seek recovery).

use ffmpeg_next::codec::context::Context as CodecContext;
use ffmpeg_next::codec::decoder::Video;
use ffmpeg_next::format::Pixel;
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags as ScalerFlags};
use ffmpeg_next::util::frame::video::Video as MediaVideoFrameImpl;
use ffmpeg_next::Rational;

use crate::api::runtime::{FrameQueue, MediaVideoFrame};

macro_rules! decode_log {
    ($($arg:tt)*) => {
        eprintln!($($arg)*);
    };
}
use crate::vt_hw_decode::{self, HwFrameTransfer};

/// Phase 3: skip non-keyframes when decode lags audio by this much.
pub const CATCHUP_SKIP_NON_KEYFRAME_MS: u64 = 500;
/// Phase 3: only accept keyframes when lag exceeds this.
pub const CATCHUP_KEYFRAME_ONLY_MS: u64 = 1500;

/// Recreates swscale when resolution or pixel format changes (common after seek / HW transfer).
pub struct RgbaScaler {
    scaler: Option<ScalerContext>,
    src_fmt: Option<Pixel>,
    src_w: u32,
    src_h: u32,
    dst_w: u32,
    dst_h: u32,
}

impl RgbaScaler {
    pub fn new(dst_w: u32, dst_h: u32) -> Self {
        Self {
            scaler: None,
            src_fmt: None,
            src_w: 0,
            src_h: 0,
            dst_w,
            dst_h,
        }
    }

    fn needs_reinit(&self, fmt: Pixel, w: u32, h: u32) -> bool {
        self.scaler.is_none()
            || self.src_fmt != Some(fmt)
            || self.src_w != w
            || self.src_h != h
    }

    pub fn ensure(&mut self, fmt: Pixel, w: u32, h: u32) -> bool {
        if !self.needs_reinit(fmt, w, h) {
            return true;
        }
        match ScalerContext::get(fmt, w, h, Pixel::RGBA, self.dst_w, self.dst_h, ScalerFlags::LANCZOS)
        {
            Ok(scaler) => {
                if self.scaler.is_some() {
                    decode_log!(
                        "[VideoDecoder] Scaler reinit {}x{} {:?} → {}x{} RGBA",
                        w,
                        h,
                        fmt,
                        self.dst_w,
                        self.dst_h
                    );
                }
                self.scaler = Some(scaler);
                self.src_fmt = Some(fmt);
                self.src_w = w;
                self.src_h = h;
                true
            }
            Err(e) => {
                decode_log!("[VideoDecoder] Scaler init failed: {:?}", e);
                self.scaler = None;
                false
            }
        }
    }

    pub fn run(&mut self, src: &MediaVideoFrameImpl, dst: &mut MediaVideoFrameImpl) -> bool {
        let fmt = src.format();
        let w = src.width();
        let h = src.height();
        if w == 0 || h == 0 {
            return false;
        }
        if !self.ensure(fmt, w, h) {
            return false;
        }
        match self.scaler.as_mut().unwrap().run(src, dst) {
            Ok(()) => true,
            Err(e) => {
                decode_log!("[VideoDecoder] Scaler run error: {:?} — reinit next frame", e);
                self.scaler = None;
                false
            }
        }
    }
}

pub type SwPipeline = (Video, RgbaScaler, Rational, u32, u32);

/// VideoToolbox decode with optional GPU BGRA handoff (Apple) + RGBA fallback scaler.
pub struct HwPipeline {
    pub dec: Video,
    pub xfer: HwFrameTransfer,
    pub vt: Option<crate::vt_pixel_buffer::VtPreviewTransfer>,
    pub rgba_scaler: RgbaScaler,
    pub tb: Rational,
    pub out_w: u32,
    pub out_h: u32,
}

fn output_dims(in_w: u32, in_h: u32, max_edge: u32) -> (u32, u32) {
    if in_w > in_h {
        if in_w > max_edge {
            (max_edge, (in_h as f64 * max_edge as f64 / in_w as f64) as u32)
        } else {
            (in_w, in_h)
        }
    } else if in_h > max_edge {
        ((in_w as f64 * max_edge as f64 / in_h as f64) as u32, max_edge)
    } else {
        (in_w, in_h)
    }
}

pub fn open_hw_pipeline(
    params: &ffmpeg_next::codec::Parameters,
    tb: Rational,
    max_edge: u32,
) -> Option<HwPipeline> {
    let (hw_dec, hw_xfer) = vt_hw_decode::try_open_vt_video_decoder(params)?;
    let in_w = hw_dec.width();
    let in_h = hw_dec.height();
    let pix_fmt = hw_xfer.sw_format;
    let (out_w, out_h) = output_dims(in_w, in_h, max_edge);
    let mut rgba_scaler = RgbaScaler::new(out_w, out_h);
    if in_w > 0 && in_h > 0 {
        let _ = rgba_scaler.ensure(pix_fmt, in_w, in_h);
    }
    let vt = if crate::vt_pixel_buffer::vt_zero_copy_enabled() {
        crate::vt_pixel_buffer::VtPreviewTransfer::new(out_w, out_h)
    } else {
        None
    };
    if vt.is_some() {
        decode_log!(
            "[VideoDecoder] Hardware decode (VideoToolbox): {}x{} -> {}x{} VT→CVPixelBuffer (zero-copy UI)",
            in_w,
            in_h,
            out_w,
            out_h
        );
    } else {
        decode_log!(
            "[VideoDecoder] Hardware decode (VideoToolbox): {}x{} -> {}x{} (sw_fmt={:?} RGBA fallback)",
            in_w,
            in_h,
            out_w,
            out_h,
            pix_fmt
        );
    }
    Some(HwPipeline {
        dec: hw_dec,
        xfer: hw_xfer,
        vt,
        rgba_scaler,
        tb,
        out_w,
        out_h,
    })
}

pub fn open_sw_pipeline(
    params: &ffmpeg_next::codec::Parameters,
    tb: Rational,
    max_edge: u32,
) -> Option<SwPipeline> {
    let mut dec_ctx = CodecContext::from_parameters(params.clone()).ok()?;
    dec_ctx.set_threading(ffmpeg_next::codec::threading::Config {
        kind: ffmpeg_next::codec::threading::Type::Frame,
        count: 0,
        ..Default::default()
    });
    if dec_ctx.id() == ffmpeg_next::codec::Id::HEVC {
        unsafe {
            let avctx = dec_ctx.as_mut_ptr();
            if !avctx.is_null() {
                (*avctx).flags |= ffmpeg_next::ffi::AV_CODEC_FLAG_LOW_DELAY as i32;
                (*avctx).flags2 |= ffmpeg_next::ffi::AV_CODEC_FLAG2_FAST as i32;
            }
        }
    }
    let dec = dec_ctx.decoder().video().ok()?;
    let in_w = dec.width();
    let in_h = dec.height();
    let (out_w, out_h) = output_dims(in_w, in_h, max_edge);
    let mut scaler = RgbaScaler::new(out_w, out_h);
    if in_w > 0 && !scaler.ensure(dec.format(), in_w, in_h) {
        return None;
    }
    decode_log!(
        "[VideoDecoder] Software decoder: {}x{} -> {}x{} (fmt={:?})",
        in_w,
        in_h,
        out_w,
        out_h,
        dec.format()
    );
    Some((dec, scaler, tb, out_w, out_h))
}

pub fn open_video_pipelines(
    params: &ffmpeg_next::codec::Parameters,
    tb: Rational,
    max_edge: u32,
    hw_enabled: bool,
) -> (Option<HwPipeline>, Option<SwPipeline>) {
    let mut hw = None;
    if hw_enabled {
        hw = open_hw_pipeline(params, tb, max_edge);
    }
    let sw = if hw.is_none() {
        open_sw_pipeline(params, tb, max_edge)
    } else {
        None
    };
    (hw, sw)
}

pub fn flush_decoder(dec: &mut Video) {
    let _ = dec.send_eof();
    let mut tmp = MediaVideoFrameImpl::empty();
    while dec.receive_frame(&mut tmp).is_ok() {}
    unsafe {
        ffmpeg_next::ffi::avcodec_flush_buffers(dec.as_mut_ptr());
    }
}

/// Whether a compressed video packet should be dropped during catch-up decode.
pub fn packet_dropped_in_catchup(is_keyframe: bool, lag_ms: u64, require_keyframe: bool) -> bool {
    let keyframe_only = lag_ms > CATCHUP_KEYFRAME_ONLY_MS;
    let skip_non_key = lag_ms > CATCHUP_SKIP_NON_KEYFRAME_MS || keyframe_only || require_keyframe;
    if require_keyframe && !is_keyframe {
        return true;
    }
    if skip_non_key && !is_keyframe {
        return true;
    }
    false
}

pub fn catchup_mode_label(lag_ms: u64) -> &'static str {
    if lag_ms > CATCHUP_KEYFRAME_ONLY_MS {
        "keyframe-only"
    } else if lag_ms > CATCHUP_SKIP_NON_KEYFRAME_MS {
        "skip-non-key"
    } else {
        "normal"
    }
}

fn pts_ms_from_frame(decoded: &MediaVideoFrameImpl, packet_pts_ms: u64, tb: Rational) -> u64 {
    decoded
        .pts()
        .map(|pts| (pts as f64 * tb.0 as f64 / tb.1 as f64 * 1000.0) as u64)
        .unwrap_or(packet_pts_ms)
}

/// Apple HW path: scale/convert on GPU via VT → retained BGRA `CVPixelBuffer` (no RGBA vec).
#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn push_vt_pixel_frame(
    decoded: &MediaVideoFrameImpl,
    packet_pts_ms: u64,
    vt: &crate::vt_pixel_buffer::VtPreviewTransfer,
    tb: Rational,
    out_w: u32,
    out_h: u32,
    frame_queue: &FrameQueue<MediaVideoFrame>,
) -> bool {
    if !vt_hw_decode::is_hw_pixel_format(decoded.format()) {
        return false;
    }
    let frame_pts_ms = pts_ms_from_frame(decoded, packet_pts_ms, tb);
    match vt.transfer_to_bgra(decoded) {
        Ok(pb) => {
            let ptr = crate::vt_pixel_buffer::pixel_buffer_ptr_for_handoff(pb);
            let vf = MediaVideoFrame {
                pts_ms: frame_pts_ms,
                width: out_w,
                height: out_h,
                pixels: Vec::new(),
                pixel_buffer_ptr: ptr,
            };
            let _ = frame_queue.enqueue_video(vf);
            true
        }
        Err(e) => {
            decode_log!(
                "[VideoDecoder] VT→BGRA failed pts={}ms: {e} — falling back to RGBA",
                frame_pts_ms
            );
            false
        }
    }
}

#[cfg(not(any(target_os = "macos", target_os = "ios")))]
pub fn push_vt_pixel_frame(
    _decoded: &MediaVideoFrameImpl,
    _packet_pts_ms: u64,
    _vt: &crate::vt_pixel_buffer::VtPreviewTransfer,
    _tb: Rational,
    _out_w: u32,
    _out_h: u32,
    _frame_queue: &FrameQueue<MediaVideoFrame>,
) -> bool {
    false
}

pub fn push_rgba_frame(
    decoded: &MediaVideoFrameImpl,
    pts_ms: u64,
    scaler: &mut RgbaScaler,
    out_w: u32,
    out_h: u32,
    tb: Rational,
    frame_queue: &FrameQueue<MediaVideoFrame>,
) {
    let frame_pts_ms = pts_ms_from_frame(decoded, pts_ms, tb);
    let mut rgba_frame = MediaVideoFrameImpl::empty();
    if !scaler.run(decoded, &mut rgba_frame) {
        return;
    }
    let pixels = rgba_frame.data(0).to_vec();
    let vf = MediaVideoFrame {
        pts_ms: frame_pts_ms,
        width: out_w,
        height: out_h,
        pixels,
        pixel_buffer_ptr: 0,
    };
    let _ = frame_queue.enqueue_video(vf);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catchup_drops_non_key_when_lagging() {
        assert!(packet_dropped_in_catchup(false, 600, false));
        assert!(!packet_dropped_in_catchup(true, 600, false));
        assert!(!packet_dropped_in_catchup(false, 100, false));
    }

    #[test]
    fn catchup_keyframe_only_mode() {
        assert!(packet_dropped_in_catchup(false, 1600, false));
        assert!(!packet_dropped_in_catchup(true, 1600, false));
        assert_eq!(catchup_mode_label(1600), "keyframe-only");
        assert_eq!(catchup_mode_label(600), "skip-non-key");
        assert_eq!(catchup_mode_label(100), "normal");
    }

    #[test]
    fn catchup_requires_keyframe_after_seek() {
        assert!(packet_dropped_in_catchup(false, 0, true));
        assert!(!packet_dropped_in_catchup(true, 0, true));
    }
}
