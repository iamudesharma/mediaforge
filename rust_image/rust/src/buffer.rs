use image::{DynamicImage, Rgba, RgbaImage};

use crate::api::image::{
    BlendMode, DrawCircle, DrawLine, ImageFilter, OutputFormat, PreviewQuality, ProcessingBackend,
    RgbaImageBuffer, ResizeAlgorithm, TextOverlay,
};
use crate::backend::EffectiveBackend;
use crate::resize;
use crate::utils;

impl RgbaImageBuffer {
    pub fn from_dynamic(img: DynamicImage) -> Self {
        let rgba = img.to_rgba8();
        let (width, height) = rgba.dimensions();
        Self {
            width,
            height,
            pixels: rgba.into_raw(),
        }
    }

    pub fn to_dynamic(&self) -> Result<DynamicImage, String> {
        let img = RgbaImage::from_raw(self.width, self.height, self.pixels.clone())
            .ok_or_else(|| "invalid RGBA buffer dimensions".to_string())?;
        Ok(DynamicImage::ImageRgba8(img))
    }

    pub fn into_dynamic(self) -> Result<DynamicImage, String> {
        let img = RgbaImage::from_raw(self.width, self.height, self.pixels)
            .ok_or_else(|| "invalid RGBA buffer dimensions".to_string())?;
        Ok(DynamicImage::ImageRgba8(img))
    }

    pub fn crop_direct(self, x: u32, y: u32, w: u32, h: u32) -> Result<Self, String> {
        if x + w > self.width || y + h > self.height {
            return Err("crop dimensions out of bounds".to_string());
        }
        if w == 0 || h == 0 {
            return Err("crop dimensions must be greater than zero".to_string());
        }
        if x == 0 && y == 0 && w == self.width && h == self.height {
            return Ok(self);
        }
        let src_stride = self.width as usize * 4;
        let dest_stride = w as usize * 4;

        let dest_len = dest_stride * h as usize;
        let mut dest_pixels = crate::pool::acquire_buffer(dest_len);
        dest_pixels.resize(dest_len, 0);

        for (dst_row, row) in (0..h).map(|r| y + r).enumerate() {
            let src_start = row as usize * src_stride + x as usize * 4;
            let dst_start = dst_row * dest_stride;
            dest_pixels[dst_start..dst_start + dest_stride]
                .copy_from_slice(&self.pixels[src_start..src_start + dest_stride]);
        }

        crate::pool::release_buffer(self.pixels);

        Ok(Self {
            width: w,
            height: h,
            pixels: dest_pixels,
        })
    }

    pub fn byte_len(&self) -> usize {
        self.pixels.len()
    }
}

pub fn decode_to_rgba(bytes: &[u8], fix_exif: bool, max_edge: Option<u32>) -> Result<RgbaImageBuffer, String> {
    let img = utils::decode(bytes)?;
    let img = if fix_exif {
        crate::exif::apply_orientation(img, bytes)?
    } else {
        img
    };
    let img = if let Some(max) = max_edge {
        crate::decode::fit_max_edge(&img, max)?
    } else {
        img
    };
    Ok(RgbaImageBuffer::from_dynamic(img))
}

pub fn encode_from_rgba(
    buffer: RgbaImageBuffer,
    format: OutputFormat,
    quality: u8,
) -> Result<Vec<u8>, String> {
    let img = buffer.into_dynamic()?;
    utils::encode(&img, format, quality)
}

/// Fast JPEG preview for interactive edits (no oxipng).
pub fn encode_rgba_preview(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    quality: u8,
    preview_quality: PreviewQuality,
) -> Result<Vec<u8>, String> {
    let _span = crate::perf::PerfSpan::new("encode_rgba_preview");
    let buffer = downscale_rgba_for_preview(buffer, max_edge, preview_quality)?;
    let img = buffer.into_dynamic()?;
    let out = crate::compress::encode_jpeg_optimized(&img, quality, preview_quality)?;
    _span.finish();
    Ok(out)
}

/// Downscale for live editing (Phase 1 preview pipeline).
pub fn fit_max_edge_rgba(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    preview_quality: PreviewQuality,
) -> Result<RgbaImageBuffer, String> {
    downscale_rgba_for_preview(buffer, max_edge, preview_quality)
}

fn downscale_rgba_for_preview(
    buffer: RgbaImageBuffer,
    max_edge: u32,
    preview_quality: PreviewQuality,
) -> Result<RgbaImageBuffer, String> {
    if max_edge == 0 {
        return Ok(buffer);
    }
    let max_dim = buffer.width.max(buffer.height);
    if max_dim <= max_edge {
        return Ok(buffer);
    }
    let scale = max_edge as f32 / max_dim as f32;
    let w = ((buffer.width as f32 * scale).round() as u32).max(1);
    let h = ((buffer.height as f32 * scale).round() as u32).max(1);
    let algo = match preview_quality {
        PreviewQuality::Fast => ResizeAlgorithm::Nearest,
        PreviewQuality::Quality => ResizeAlgorithm::Mitchell,
    };
    resize_rgba(buffer, w, h, algo, ProcessingBackend::Cpu)
}

pub fn draw_line_rgba(buffer: RgbaImageBuffer, line: DrawLine) -> Result<RgbaImageBuffer, String> {
    let w = buffer.width;
    let h = buffer.height;
    let rgba = RgbaImage::from_raw(w, h, buffer.pixels)
        .ok_or_else(|| "invalid RGBA buffer dimensions".to_string())?;
    let drawn = crate::draw::draw_line(rgba, line)?;
    Ok(RgbaImageBuffer {
        width: w,
        height: h,
        pixels: drawn.into_raw(),
    })
}

pub fn draw_circle_rgba(buffer: RgbaImageBuffer, circle: DrawCircle) -> Result<RgbaImageBuffer, String> {
    let w = buffer.width;
    let h = buffer.height;
    let rgba = RgbaImage::from_raw(w, h, buffer.pixels)
        .ok_or_else(|| "invalid RGBA buffer dimensions".to_string())?;
    let drawn = crate::draw::draw_circle(rgba, circle)?;
    Ok(RgbaImageBuffer {
        width: w,
        height: h,
        pixels: drawn.into_raw(),
    })
}

pub fn draw_text_rgba(buffer: RgbaImageBuffer, overlay: TextOverlay) -> Result<RgbaImageBuffer, String> {
    let w = buffer.width;
    let h = buffer.height;
    let rgba = RgbaImage::from_raw(w, h, buffer.pixels)
        .ok_or_else(|| "invalid RGBA buffer dimensions".to_string())?;
    let drawn = crate::draw::draw_text(rgba, overlay)?;
    Ok(RgbaImageBuffer {
        width: w,
        height: h,
        pixels: drawn.into_raw(),
    })
}

pub fn resize_rgba(
    buffer: RgbaImageBuffer,
    width: u32,
    height: u32,
    algorithm: ResizeAlgorithm,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    match crate::backend::resolve(backend)? {
        EffectiveBackend::Gpu => {
            #[cfg(feature = "gpu")]
            {
                crate::gpu::resize_rgba(buffer, width, height, algorithm)
            }
            #[cfg(not(feature = "gpu"))]
            {
                let _ = (buffer, width, height, algorithm);
                Err("GPU feature not enabled".into())
            }
        }
        EffectiveBackend::Cpu => resize::resize_rgba_buffer(buffer, width, height, algorithm),
    }
}

pub fn filter_rgba_with_backend(
    buffer: RgbaImageBuffer,
    filter: ImageFilter,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    let _path = crate::perf::resolve_rgba_filter_path(&filter, backend);
    let _span = crate::perf::PerfSpan::new("filter_rgba");
    let out = filter_rgba_with_backend_inner(buffer, filter, backend)?;
    _span.finish();
    Ok(out)
}

fn filter_rgba_with_backend_inner(
    buffer: RgbaImageBuffer,
    filter: ImageFilter,
    backend: ProcessingBackend,
) -> Result<RgbaImageBuffer, String> {
    if let EffectiveBackend::Gpu = crate::backend::resolve(backend)? {
        #[cfg(feature = "gpu")]
        {
            if matches!(
                filter,
                ImageFilter::Brightness { .. }
                    | ImageFilter::Contrast { .. }
                    | ImageFilter::Saturation { .. }
                    | ImageFilter::HueRotate { .. }
                    | ImageFilter::Blur { .. }
                    | ImageFilter::Sharpen
            ) {
                return crate::gpu::filter_rgba(buffer, filter);
            }
        }
    }
    filter_rgba(buffer, filter)
}

pub fn crop_rgba(
    buffer: RgbaImageBuffer,
    x: u32,
    y: u32,
    width: u32,
    height: u32,
) -> Result<RgbaImageBuffer, String> {
    buffer.crop_direct(x, y, width, height)
}

pub fn filter_rgba(buffer: RgbaImageBuffer, filter: ImageFilter) -> Result<RgbaImageBuffer, String> {
    crate::filters::apply_rgba(buffer, filter)
}

pub fn blend_pixel(base: Rgba<u8>, overlay: Rgba<u8>, mode: BlendMode) -> Rgba<u8> {
    let (br, bg, bb, ba) = (base[0], base[1], base[2], base[3]);
    let (or, og, ob, oa) = (overlay[0], overlay[1], overlay[2], overlay[3]);
    if oa == 0 {
        return base;
    }
    let af = oa as f32 / 255.0;
    let blend_chan = |b: u8, o: u8| -> u8 {
        let b = b as f32 / 255.0;
        let o = o as f32 / 255.0;
        let v = match mode {
            BlendMode::Normal => o,
            BlendMode::Multiply => b * o,
            BlendMode::Screen => 1.0 - (1.0 - b) * (1.0 - o),
            BlendMode::Overlay => {
                if b < 0.5 {
                    2.0 * b * o
                } else {
                    1.0 - 2.0 * (1.0 - b) * (1.0 - o)
                }
            }
            BlendMode::Add => (b + o).min(1.0),
        };
        (v * 255.0).round().clamp(0.0, 255.0) as u8
    };
    let r = blend_chan(br, or);
    let g = blend_chan(bg, og);
    let b = blend_chan(bb, ob);
    let out_a = (ba as f32 + oa as f32 * (1.0 - ba as f32 / 255.0)).min(255.0) as u8;
    let inv = 1.0 - af;
    Rgba([
        (r as f32 * af + br as f32 * inv).round() as u8,
        (g as f32 * af + bg as f32 * inv).round() as u8,
        (b as f32 * af + bb as f32 * inv).round() as u8,
        out_a,
    ])
}
