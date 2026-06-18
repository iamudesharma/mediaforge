//! CPU alpha-composite of overlay layers during video encode (image PNG + vector text).

use std::path::Path;

use cosmic_text::{FontSystem, SwashCache};
use ffmpeg_next::format::Pixel;
use ffmpeg_next::software::scaling::{context::Context as ScalerContext, flag::Flags};
use ffmpeg_next::util::frame::video::Video;

use crate::error::{Result, VideoForgeError};
use crate::ffmpeg::map_ffmpeg_error;
use crate::pipeline::overlay_effects::apply_overlay_effects;
use crate::pipeline::overlay_text::render_text_rgba;
use crate::pipeline::overlay_transform::ResolvedTransform;
use crate::types::{
    BurnInOverlay, ImageOverlayData, OverlayContent, OverlayEffects, TextOverlayData,
    TransformTracks,
};

enum LoadedOverlay {
    Image {
        pixels: Vec<u8>,
        width: u32,
        height: u32,
        anchor_x: f32,
        anchor_y: f32,
        start_ms: u64,
        end_ms: u64,
        transform: TransformTracks,
        effects: OverlayEffects,
    },
    Text {
        spec: TextOverlayData,
        start_ms: u64,
        end_ms: u64,
        transform: TransformTracks,
        effects: OverlayEffects,
    },
}

impl LoadedOverlay {
    fn from_spec(spec: &BurnInOverlay) -> Result<Self> {
        match &spec.content {
            OverlayContent::Image(data) => Self::load_image(data, spec),
            OverlayContent::Text(text) => Ok(LoadedOverlay::Text {
                spec: text.clone(),
                start_ms: spec.start_ms,
                end_ms: spec.end_ms,
                transform: spec.transform.clone(),
                effects: spec.effects.clone(),
            }),
        }
    }

    fn load_image(data: &ImageOverlayData, spec: &BurnInOverlay) -> Result<Self> {
        let path = data.path.trim();
        if path.is_empty() {
            return Err(VideoForgeError::InvalidInput(
                "burn-in overlay image path is empty".into(),
            ));
        }
        if !Path::new(path).exists() {
            return Err(VideoForgeError::InvalidInput(format!(
                "burn-in overlay not found: {path}"
            )));
        }
        let img = image::open(path)
            .map_err(|e| VideoForgeError::IoError(format!("overlay {path}: {e}")))?;
        let rgba = img.to_rgba8();
        let (width, height) = rgba.dimensions();
        if width == 0 || height == 0 {
            return Err(VideoForgeError::InvalidInput(format!(
                "overlay has zero size: {path}"
            )));
        }
        Ok(LoadedOverlay::Image {
            pixels: rgba.into_raw(),
            width,
            height,
            anchor_x: data.anchor_x.clamp(0.0, 1.0),
            anchor_y: data.anchor_y.clamp(0.0, 1.0),
            start_ms: spec.start_ms,
            end_ms: spec.end_ms,
            transform: spec.transform.clone(),
            effects: spec.effects.clone(),
        })
    }

    fn is_visible_at(&self, frame_ms: u64) -> bool {
        let (start, end) = match self {
            LoadedOverlay::Image { start_ms, end_ms, .. } => (*start_ms, *end_ms),
            LoadedOverlay::Text { start_ms, end_ms, .. } => (*start_ms, *end_ms),
        };
        frame_ms >= start && frame_ms < end
    }

    fn resolved_transform(&self, frame_ms: u64) -> ResolvedTransform {
        if !self.is_visible_at(frame_ms) {
            return ResolvedTransform {
                opacity: 0.0,
                ..Default::default()
            };
        }
        let (start, tracks) = match self {
            LoadedOverlay::Image {
                start_ms,
                transform,
                ..
            } => (*start_ms, transform),
            LoadedOverlay::Text {
                start_ms,
                transform,
                ..
            } => (*start_ms, transform),
        };
        let local_ms = frame_ms.saturating_sub(start);
        ResolvedTransform::evaluate(tracks, local_ms)
    }
}

/// Composites timeline overlays onto encoded video frames (YUV420P at output resolution).
pub struct OverlayCompositor {
    overlays: Vec<LoadedOverlay>,
    out_w: u32,
    out_h: u32,
    rgba_scratch: Vec<u8>,
    overlay_scratch: Vec<u8>,
    font_system: FontSystem,
    swash_cache: SwashCache,
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
            overlay_scratch: Vec::new(),
            font_system: FontSystem::new(),
            swash_cache: SwashCache::new(),
            yuv_to_rgba,
            rgba_to_yuv,
            rgba_frame,
        }))
    }

    pub fn apply_on_yuv420(&mut self, frame: &mut Video, frame_ms: u64) -> Result<()> {
        if frame.width() != self.out_w || frame.height() != self.out_h {
            return Err(VideoForgeError::Internal(format!(
                "overlay burn: expected {}x{}, got {}x{}",
                self.out_w,
                self.out_h,
                frame.width(),
                frame.height()
            )));
        }
        if frame.format() != Pixel::YUV420P {
            return Err(VideoForgeError::Internal(format!(
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

        for i in 0..self.overlays.len() {
            let transform = self.overlays[i].resolved_transform(frame_ms);
            if transform.opacity <= 0.001 {
                continue;
            }

            let local_ms = match &self.overlays[i] {
                LoadedOverlay::Image { start_ms, .. } | LoadedOverlay::Text { start_ms, .. } => {
                    frame_ms.saturating_sub(*start_ms)
                }
            };

            let (anchor_x, anchor_y, width, height, use_scratch) = match &self.overlays[i] {
                LoadedOverlay::Image {
                    pixels,
                    width,
                    height,
                    anchor_x,
                    anchor_y,
                    effects,
                    ..
                } => {
                    if !effects.effects.is_empty() {
                        self.overlay_scratch.clear();
                        self.overlay_scratch.extend_from_slice(pixels);
                        apply_overlay_effects(
                            &mut self.overlay_scratch,
                            *width,
                            *height,
                            &effects.effects,
                            local_ms,
                        );
                        (*anchor_x, *anchor_y, *width, *height, true)
                    } else {
                        (*anchor_x, *anchor_y, *width, *height, false)
                    }
                }
                LoadedOverlay::Text { spec, effects, .. } => {
                    let (px, w, h) = render_text_rgba(
                        &mut self.font_system,
                        &mut self.swash_cache,
                        spec,
                        self.out_w,
                        self.out_h,
                        local_ms,
                    )?;
                    self.overlay_scratch.clear();
                    self.overlay_scratch.extend_from_slice(&px);
                    if !effects.effects.is_empty() {
                        apply_overlay_effects(
                            &mut self.overlay_scratch,
                            w,
                            h,
                            &effects.effects,
                            local_ms,
                        );
                    }
                    (spec.anchor_x, spec.anchor_y, w, h, true)
                }
            };

            if width == 0 || height == 0 {
                continue;
            }

            let src_pixels = if use_scratch {
                self.overlay_scratch.as_slice()
            } else if let LoadedOverlay::Image { pixels, .. } = &self.overlays[i] {
                pixels.as_slice()
            } else {
                self.overlay_scratch.as_slice()
            };

            let center_x =
                anchor_x * self.out_w as f32 + transform.translate_x * self.out_w as f32;
            let center_y =
                anchor_y * self.out_h as f32 + transform.translate_y * self.out_h as f32;

            blend_rgba_transformed(
                &mut self.rgba_scratch,
                self.out_w,
                self.out_h,
                src_pixels,
                width,
                height,
                center_x,
                center_y,
                transform.scale,
                transform.rotation,
                transform.opacity,
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

fn sample_rgba(src: &[u8], src_w: u32, src_h: u32, u: f32, v: f32) -> [f32; 4] {
    if src_w == 0 || src_h == 0 {
        return [0.0; 4];
    }
    let u = u.clamp(0.0, src_w as f32 - 1.0);
    let v = v.clamp(0.0, src_h as f32 - 1.0);
    let x0 = u.floor() as u32;
    let y0 = v.floor() as u32;
    let x1 = (x0 + 1).min(src_w - 1);
    let y1 = (y0 + 1).min(src_h - 1);
    let tx = u - x0 as f32;
    let ty = v - y0 as f32;

    let mut out = [0.0f32; 4];
    for c in 0..4usize {
        let c00 = src[((y0 * src_w + x0) * 4 + c as u32) as usize] as f32;
        let c10 = src[((y0 * src_w + x1) * 4 + c as u32) as usize] as f32;
        let c01 = src[((y1 * src_w + x0) * 4 + c as u32) as usize] as f32;
        let c11 = src[((y1 * src_w + x1) * 4 + c as u32) as usize] as f32;
        let top = c00 * (1.0 - tx) + c10 * tx;
        let bot = c01 * (1.0 - tx) + c11 * tx;
        out[c] = top * (1.0 - ty) + bot * ty;
    }
    out
}

fn blend_rgba_transformed(
    dst: &mut [u8],
    dst_w: u32,
    dst_h: u32,
    src: &[u8],
    src_w: u32,
    src_h: u32,
    center_x: f32,
    center_y: f32,
    scale: f32,
    rotation: f32,
    opacity: f32,
) {
    if opacity <= 0.001 || scale <= 0.001 {
        return;
    }

    let half_w = src_w as f32 * scale * 0.5;
    let half_h = src_h as f32 * scale * 0.5;
    let cos_r = rotation.cos();
    let sin_r = rotation.sin();

    let min_x = (center_x - half_w - half_h).floor() as i32;
    let max_x = (center_x + half_w + half_h).ceil() as i32;
    let min_y = (center_y - half_w - half_h).floor() as i32;
    let max_y = (center_y + half_w + half_h).ceil() as i32;

    let dst_w_i = dst_w as i32;
    let dst_h_i = dst_h as i32;

    for dy in min_y..=max_y {
        if dy < 0 || dy >= dst_h_i {
            continue;
        }
        for dx in min_x..=max_x {
            if dx < 0 || dx >= dst_w_i {
                continue;
            }
            let px = dx as f32 + 0.5;
            let py = dy as f32 + 0.5;
            let lx = px - center_x;
            let ly = py - center_y;
            let rx = (lx * cos_r + ly * sin_r) / scale;
            let ry = (-lx * sin_r + ly * cos_r) / scale;
            let su = rx + src_w as f32 * 0.5;
            let sv = ry + src_h as f32 * 0.5;
            if su < 0.0 || sv < 0.0 || su > src_w as f32 || sv > src_h as f32 {
                continue;
            }
            let rgba = sample_rgba(src, src_w, src_h, su, sv);
            let sa = (rgba[3] / 255.0) * opacity;
            if sa <= 0.001 {
                continue;
            }
            let di = ((dy as u32 * dst_w + dx as u32) * 4) as usize;
            if di + 3 >= dst.len() {
                continue;
            }
            let inv = 1.0 - sa;
            for c in 0..3 {
                dst[di + c] =
                    (rgba[c] * sa + dst[di + c] as f32 * inv).round().clamp(0.0, 255.0) as u8;
            }
            dst[di + 3] = 255;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::{
        AnimationTrack, BurnInOverlay, Easing, ImageOverlayData, OverlayContent, TransformProperty,
        TransformTracks,
    };

    #[test]
    fn loads_png_overlay_file() {
        let dir = tempfile::tempdir().expect("tempdir");
        let path = dir.path().join("overlay.png");
        image::RgbaImage::from_pixel(4, 4, image::Rgba([10, 20, 30, 200]))
            .save(&path)
            .expect("write png");

        let spec = BurnInOverlay {
            content: OverlayContent::Image(ImageOverlayData {
                path: path.to_string_lossy().into_owned(),
                anchor_x: 0.5,
                anchor_y: 0.5,
            }),
            start_ms: 0,
            end_ms: 1000,
            transform: TransformTracks::default(),
            effects: Default::default(),
        };
        let comp = OverlayCompositor::new(&[spec], 640, 360).expect("compositor");
        assert!(comp.is_some());
    }

    #[test]
    fn opacity_track_fades() {
        let o = LoadedOverlay::Image {
            pixels: vec![],
            width: 1,
            height: 1,
            anchor_x: 0.5,
            anchor_y: 0.5,
            start_ms: 0,
            end_ms: 1000,
            transform: TransformTracks {
                tracks: vec![
                    AnimationTrack {
                        property: TransformProperty::Opacity,
                        from: 0.0,
                        to: 1.0,
                        start_ms: 0,
                        duration_ms: 200,
                        easing: Easing::Linear,
                    },
                    AnimationTrack {
                        property: TransformProperty::Opacity,
                        from: 1.0,
                        to: 0.0,
                        start_ms: 800,
                        duration_ms: 200,
                        easing: Easing::Linear,
                    },
                ],
            },
            effects: Default::default(),
        };
        assert!((o.resolved_transform(0).opacity - 0.0).abs() < 0.02);
        assert!((o.resolved_transform(100).opacity - 0.5).abs() < 0.06);
        assert!((o.resolved_transform(500).opacity - 1.0).abs() < 0.02);
        assert!((o.resolved_transform(900).opacity - 0.5).abs() < 0.06);
    }
}
