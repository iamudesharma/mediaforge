//! CPU alpha-composite of pre-rasterized overlay PNGs during video encode (Sprint V1.5 burn-in).

use std::path::Path;

use ffmpeg_next::format::Pixel;
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags};
use ffmpeg_next::util::frame::video::Video;
use crate::error::{Result, VideoProcessorError};
use crate::ffmpeg::map_ffmpeg_error;
use crate::types::BurnInOverlay;

struct LoadedOverlay {
    pixels: Vec<u8>,
    width: u32,
    height: u32,
    start_ms: u64,
    end_ms: u64,
    anchor_x: f32,
    anchor_y: f32,
    fade_in_ms: u64,
    fade_out_ms: u64,
}

impl LoadedOverlay {
    fn from_spec(spec: &BurnInOverlay) -> Result<Self> {
        let path = spec.image_path.trim();
        if path.is_empty() {
            return Err(VideoProcessorError::InvalidInput(
                "burn-in overlay image_path is empty".into(),
            ));
        }
        if !Path::new(path).exists() {
            return Err(VideoProcessorError::InvalidInput(format!(
                "burn-in overlay not found: {path}"
            )));
        }
        let img = image::open(path)
            .map_err(|e| VideoProcessorError::IoError(format!("overlay {path}: {e}")))?;
        let rgba = img.to_rgba8();
        let (width, height) = rgba.dimensions();
        if width == 0 || height == 0 {
            return Err(VideoProcessorError::InvalidInput(format!(
                "overlay has zero size: {path}"
            )));
        }
        Ok(Self {
            pixels: rgba.into_raw(),
            width,
            height,
            start_ms: spec.start_ms,
            end_ms: spec.end_ms,
            anchor_x: spec.anchor_x.clamp(0.0, 1.0),
            anchor_y: spec.anchor_y.clamp(0.0, 1.0),
            fade_in_ms: spec.fade_in_ms,
            fade_out_ms: spec.fade_out_ms,
        })
    }

    fn is_visible_at(&self, frame_ms: u64) -> bool {
        frame_ms >= self.start_ms && frame_ms < self.end_ms
    }

    fn opacity_at(&self, frame_ms: u64) -> f32 {
        if !self.is_visible_at(frame_ms) {
            return 0.0;
        }
        let mut opacity = 1.0f32;
        if self.fade_in_ms > 0 {
            let since_start = frame_ms.saturating_sub(self.start_ms);
            if since_start < self.fade_in_ms {
                opacity = since_start as f32 / self.fade_in_ms as f32;
            }
        }
        if self.fade_out_ms > 0 {
            let until_end = self.end_ms.saturating_sub(frame_ms);
            if until_end < self.fade_out_ms {
                let fade = until_end as f32 / self.fade_out_ms as f32;
                opacity = opacity.min(fade);
            }
        }
        opacity.clamp(0.0, 1.0)
    }
}

/// Composites timeline overlays onto encoded video frames (YUV420P at output resolution).
pub struct OverlayCompositor {
    overlays: Vec<LoadedOverlay>,
    out_w: u32,
    out_h: u32,
    rgba_scratch: Vec<u8>,
    yuv_to_rgba: ScalerContext,
    rgba_to_yuv: ScalerContext,
    rgba_frame: Video,
}

impl OverlayCompositor {
    pub fn new(specs: &[BurnInOverlay], out_w: u32, out_h: u32) -> Result<Option<Self>> {
        if specs.is_empty() || out_w == 0 || out_h == 0 {
            return Ok(None);
        }
        let mut overlays = Vec::with_capacity(specs.len());
        for spec in specs {
            overlays.push(LoadedOverlay::from_spec(spec)?);
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
            overlays,
            out_w,
            out_h,
            rgba_scratch: vec![0u8; rgba_len],
            yuv_to_rgba,
            rgba_to_yuv,
            rgba_frame,
        }))
    }

    pub fn apply_on_yuv420(&mut self, frame: &mut Video, frame_ms: u64) -> Result<()> {
        if frame.width() != self.out_w || frame.height() != self.out_h {
            return Err(VideoProcessorError::Internal(format!(
                "overlay burn: expected {}x{}, got {}x{}",
                self.out_w,
                self.out_h,
                frame.width(),
                frame.height()
            )));
        }
        if frame.format() != Pixel::YUV420P {
            return Err(VideoProcessorError::Internal(format!(
                "overlay burn: expected YUV420P, got {:?}",
                frame.format()
            )));
        }

        self.yuv_to_rgba
            .run(frame, &mut self.rgba_frame)
            .map_err(map_ffmpeg_error)?;

        let stride = self.rgba_frame.stride(0);
        copy_rgba_plane(
            self.rgba_frame.data(0),
            stride,
            &mut self.rgba_scratch,
            self.out_w,
            self.out_h,
        );

        for overlay in &self.overlays {
            let opacity = overlay.opacity_at(frame_ms);
            if opacity <= 0.001 {
                continue;
            }
            let x = (overlay.anchor_x * self.out_w as f32 - overlay.width as f32 / 2.0).round() as i32;
            let y = (overlay.anchor_y * self.out_h as f32 - overlay.height as f32 / 2.0).round() as i32;
            blend_rgba(
                &mut self.rgba_scratch,
                self.out_w,
                self.out_h,
                &overlay.pixels,
                overlay.width,
                overlay.height,
                x,
                y,
                opacity,
            );
        }

        write_rgba_plane(
            &self.rgba_scratch,
            self.rgba_frame.data_mut(0),
            stride,
            self.out_w,
            self.out_h,
        );

        self.rgba_to_yuv
            .run(&self.rgba_frame, frame)
            .map_err(map_ffmpeg_error)?;
        Ok(())
    }
}

fn copy_rgba_plane(src: &[u8], src_stride: usize, dst: &mut [u8], w: u32, h: u32) {
    let row_bytes = (w as usize) * 4;
    for y in 0..h as usize {
        let si = y * src_stride;
        let di = y * row_bytes;
        dst[di..di + row_bytes].copy_from_slice(&src[si..si + row_bytes]);
    }
}

fn write_rgba_plane(src: &[u8], dst: &mut [u8], dst_stride: usize, w: u32, h: u32) {
    let row_bytes = (w as usize) * 4;
    for y in 0..h as usize {
        let si = y * row_bytes;
        let di = y * dst_stride;
        dst[di..di + row_bytes].copy_from_slice(&src[si..si + row_bytes]);
    }
}

fn blend_rgba(
    dst: &mut [u8],
    dst_w: u32,
    dst_h: u32,
    src: &[u8],
    src_w: u32,
    src_h: u32,
    origin_x: i32,
    origin_y: i32,
    opacity: f32,
) {
    let dst_w = dst_w as i32;
    let dst_h = dst_h as i32;
    for py in 0..src_h as i32 {
        let dy = origin_y + py;
        if dy < 0 || dy >= dst_h {
            continue;
        }
        for px in 0..src_w as i32 {
            let dx = origin_x + px;
            if dx < 0 || dx >= dst_w {
                continue;
            }
            let si = ((py as u32 * src_w + px as u32) * 4) as usize;
            if si + 3 >= src.len() {
                continue;
            }
            let sa = (src[si + 3] as f32 / 255.0) * opacity;
            if sa <= 0.001 {
                continue;
            }
            let di = ((dy as u32 * dst_w as u32 + dx as u32) * 4) as usize;
            if di + 3 >= dst.len() {
                continue;
            }
            let inv = 1.0 - sa;
            for c in 0..3 {
                dst[di + c] =
                    (src[si + c] as f32 * sa + dst[di + c] as f32 * inv).round() as u8;
            }
            dst[di + 3] = 255;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opacity_fade_matches_flutter() {
        let o = LoadedOverlay {
            pixels: vec![],
            width: 1,
            height: 1,
            start_ms: 0,
            end_ms: 1000,
            anchor_x: 0.5,
            anchor_y: 0.5,
            fade_in_ms: 200,
            fade_out_ms: 200,
        };
        assert!((o.opacity_at(0) - 0.0).abs() < 0.02);
        assert!((o.opacity_at(100) - 0.5).abs() < 0.06);
        assert!((o.opacity_at(500) - 1.0).abs() < 0.02);
        assert!((o.opacity_at(900) - 0.5).abs() < 0.06);
    }
}
