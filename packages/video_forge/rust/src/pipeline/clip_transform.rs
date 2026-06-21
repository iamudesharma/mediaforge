//! Per-frame source-clip transform (zoom / pan / rotate) during export.

use ffmpeg_next::format::Pixel;
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags};
use ffmpeg_next::util::frame::video::Video;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::map_ffmpeg_error;
use crate::pipeline::overlay_transform::ResolvedTransform;
use crate::types::{ClipEffects, ClipTransformBase, TransformTracks};

/// Merge static [base] with keyframed [motion] at [local_ms] (ms from clip start).
pub fn resolve_clip_transform(
    base: &ClipTransformBase,
    motion: &TransformTracks,
    local_ms: u64,
) -> ResolvedTransform {
    let animated = ResolvedTransform::evaluate(motion, local_ms);
    ResolvedTransform {
        translate_x: base.translate_x + animated.translate_x,
        translate_y: base.translate_y + animated.translate_y,
        scale: base.scale * animated.scale,
        rotation: base.rotation + animated.rotation,
        opacity: animated.opacity,
    }
}

pub fn resolve_from_effects(effects: &ClipEffects, local_ms: u64) -> ResolvedTransform {
    resolve_clip_transform(&effects.base, &effects.motion, local_ms)
}

/// CPU YUV420P ↔ RGBA processor for clip transforms at encode resolution.
pub struct ClipTransformProcessor {
    out_w: u32,
    out_h: u32,
    rgba_scratch: Vec<u8>,
    yuv_to_rgba: ScalerContext,
    rgba_to_yuv: ScalerContext,
    rgba_frame: Video,
}

impl ClipTransformProcessor {
    pub fn new(out_w: u32, out_h: u32) -> Result<Option<Self>> {
        if out_w == 0 || out_h == 0 {
            return Ok(None);
        }
        let yuv_to_rgba = ScalerContext::get(
            Pixel::YUV420P,
            out_w,
            out_h,
            Pixel::RGBA,
            out_w,
            out_h,
            Flags::FAST_BILINEAR,
        )
        .map_err(map_ffmpeg_error)?;
        let rgba_to_yuv = ScalerContext::get(
            Pixel::RGBA,
            out_w,
            out_h,
            Pixel::YUV420P,
            out_w,
            out_h,
            Flags::FAST_BILINEAR,
        )
        .map_err(map_ffmpeg_error)?;
        let mut rgba_frame = Video::empty();
        rgba_frame.set_format(Pixel::RGBA);
        rgba_frame.set_width(out_w);
        rgba_frame.set_height(out_h);
        let rgba_len = (out_w as usize) * (out_h as usize) * 4;
        Ok(Some(Self {
            out_w,
            out_h,
            rgba_scratch: vec![0u8; rgba_len],
            yuv_to_rgba,
            rgba_to_yuv,
            rgba_frame,
        }))
    }

    pub fn apply_on_yuv420(
        &mut self,
        frame: &mut Video,
        transform: &ResolvedTransform,
    ) -> Result<()> {
        if transform.scale <= 1.001
            && transform.rotation.abs() < 0.01
            && transform.translate_x.abs() < 0.001
            && transform.translate_y.abs() < 0.001
        {
            return Ok(());
        }
        if frame.width() != self.out_w || frame.height() != self.out_h {
            return Err(VideoForgeError::Internal(format!(
                "clip transform: expected {}x{}, got {}x{}",
                self.out_w,
                self.out_h,
                frame.width(),
                frame.height()
            )));
        }
        if frame.format() != Pixel::YUV420P {
            return Err(VideoForgeError::Internal(format!(
                "clip transform: expected YUV420P, got {:?}",
                frame.format()
            )));
        }

        self.yuv_to_rgba
            .run(frame, &mut self.rgba_frame)
            .map_err(map_ffmpeg_error)?;
        let src = self.rgba_frame.data_mut(0);
        apply_affine_rgba(src, self.out_w, self.out_h, transform, &mut self.rgba_scratch);
        self.rgba_frame.data_mut(0).copy_from_slice(&self.rgba_scratch);
        self.rgba_to_yuv
            .run(&self.rgba_frame, frame)
            .map_err(map_ffmpeg_error)?;
        Ok(())
    }
}

fn apply_affine_rgba(
    src: &[u8],
    width: u32,
    height: u32,
    t: &ResolvedTransform,
    dst: &mut [u8],
) {
    let w = width as f32;
    let h = height as f32;
    let cx = w * 0.5;
    let cy = h * 0.5;
    let scale = t.scale.max(0.001);
    let rot = t.rotation.to_radians();
    let cos_r = rot.cos();
    let sin_r = rot.sin();
    let tx = t.translate_x * w;
    let ty = t.translate_y * h;

    for y in 0..height {
        for x in 0..width {
            let dx = x as f32 - cx - tx;
            let dy = y as f32 - cy - ty;
            let rx = dx * cos_r + dy * sin_r;
            let ry = -dx * sin_r + dy * cos_r;
            let sx = rx / scale + cx;
            let sy = ry / scale + cy;
            let di = ((y * width + x) * 4) as usize;
            if sx < 0.0 || sy < 0.0 || sx >= w - 1.0 || sy >= h - 1.0 {
                dst[di] = 0;
                dst[di + 1] = 0;
                dst[di + 2] = 0;
                dst[di + 3] = 255;
            } else {
                sample_bilinear_rgba(src, width, height, sx, sy, &mut dst[di..di + 4]);
            }
        }
    }
}

fn sample_bilinear_rgba(
    src: &[u8],
    width: u32,
    height: u32,
    x: f32,
    y: f32,
    out: &mut [u8],
) {
    let x0 = x.floor() as u32;
    let y0 = y.floor() as u32;
    let x1 = (x0 + 1).min(width - 1);
    let y1 = (y0 + 1).min(height - 1);
    let fx = x - x0 as f32;
    let fy = y - y0 as f32;
    let mut acc = [0.0f32; 4];
    for (sy, wy) in [(y0, 1.0 - fy), (y1, fy)] {
        for (sx, wx) in [(x0, 1.0 - fx), (x1, fx)] {
            let wgt = wx * wy;
            let si = ((sy * width + sx) * 4) as usize;
            for c in 0..4 {
                acc[c] += src[si + c] as f32 * wgt;
            }
        }
    }
    for c in 0..4 {
        out[c] = acc[c].round().clamp(0.0, 255.0) as u8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{AnimationTrack, Easing, TransformProperty};

    #[test]
    fn resolve_merges_base_and_motion() {
        let base = ClipTransformBase {
            scale: 2.0,
            ..Default::default()
        };
        let motion = TransformTracks {
            tracks: vec![AnimationTrack {
                property: TransformProperty::TranslateX,
                from: 0.0,
                to: 0.1,
                start_ms: 0,
                duration_ms: 100,
                easing: Easing::Linear,
            }],
        };
        let t = resolve_clip_transform(&base, &motion, 50);
        assert!((t.scale - 2.0).abs() < 0.01);
        assert!(t.translate_x > 0.04);
    }

    #[test]
    fn affine_scale_zooms_center() {
        let w = 4u32;
        let h = 4u32;
        let mut src = vec![0u8; (w * h * 4) as usize];
        // bright center pixel
        let ci = ((2 * w + 2) * 4) as usize;
        src[ci] = 255;
        src[ci + 1] = 255;
        src[ci + 2] = 255;
        src[ci + 3] = 255;
        let mut dst = vec![0u8; src.len()];
        let t = ResolvedTransform {
            scale: 2.0,
            ..Default::default()
        };
        apply_affine_rgba(&src, w, h, &t, &mut dst);
        // zoom 2x: center sample spreads — corner should get some brightness
        assert!(dst[0] > 0 || dst[((w * h - 1) * 4) as usize] > 0);
    }
}
