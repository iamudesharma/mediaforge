//! Vector text rasterization via cosmic-text (v2 export).

use cosmic_text::{
    Attrs, Buffer, Color, Family, FontSystem, Metrics, Shaping, Stretch, Style, SwashCache, Weight,
};

use crate::error::Result;
use crate::pipeline::overlay_content::{content_reveal_progress, visible_text};
use crate::types::{TextAlign, TextContentAnimation, TextOverlayData};

const REF_HEIGHT: f32 = 1080.0;

/// Rasterize [spec] to RGBA at output resolution for [local_ms].
pub fn render_text_rgba(
    font_system: &mut FontSystem,
    swash_cache: &mut SwashCache,
    spec: &TextOverlayData,
    out_w: u32,
    out_h: u32,
    local_ms: u64,
) -> Result<(Vec<u8>, u32, u32)> {
    if spec.text.is_empty() {
        return Ok((vec![], 0, 0));
    }

    let scale = out_h as f32 / REF_HEIGHT;
    let font_size = spec.font_size * scale;
    let padding = spec.padding * scale;
    let max_w = (spec.max_width.clamp(0.1, 1.0) * out_w as f32).max(32.0);

    let progress = content_reveal_progress(
        spec.content_animation,
        local_ms,
        spec.content_animation_duration_ms,
    );
    let display_text = visible_text(&spec.text, spec.content_animation, progress);
    if display_text.is_empty() {
        return Ok((vec![], 0, 0));
    }

    let line_height = font_size * 1.25;
    let metrics = Metrics::new(font_size, line_height);
    let mut buffer = Buffer::new(font_system, metrics);
    buffer.set_size(font_system, Some(max_w), None);

    let weight = Weight(spec.font_weight.clamp(100, 900) as u16);
    let style = if spec.italic {
        Style::Italic
    } else {
        Style::Normal
    };

    let attrs = Attrs::new()
        .family(Family::SansSerif)
        .weight(weight)
        .style(style)
        .stretch(Stretch::Normal);

    buffer.set_text(font_system, &display_text, &attrs, Shaping::Advanced);
    buffer.shape_until_scroll(font_system, false);

    let mut min_x = i32::MAX;
    let mut min_y = i32::MAX;
    let mut max_x = i32::MIN;
    let mut max_y = i32::MIN;
    for run in buffer.layout_runs() {
        for glyph in run.glyphs {
            min_x = min_x.min(glyph.x as i32);
            min_y = min_y.min(glyph.y as i32);
            max_x = max_x.max(glyph.x as i32 + font_size as i32);
            max_y = max_y.max(glyph.y as i32 + line_height as i32);
        }
    }
    if min_x == i32::MAX {
        return Ok((vec![], 0, 0));
    }

    let text_w = (max_x - min_x).max(1) as u32;
    let text_h = (max_y - min_y).max(1) as u32;
    let box_w = text_w + (padding * 2.0).ceil() as u32;
    let box_h = text_h + (padding * 2.0).ceil() as u32;

    let mut pixels = vec![0u8; (box_w * box_h * 4) as usize];

    if spec.show_background && spec.background_a > 0 {
        fill_rounded_rect(
            &mut pixels,
            box_w,
            box_h,
            spec.background_r,
            spec.background_g,
            spec.background_b,
            spec.background_a,
            (spec.corner_radius * scale).max(0.0) as u32,
        );
    }

    let color = Color::rgba(spec.color_r, spec.color_g, spec.color_b, spec.color_a);
    let align_offset = match spec.text_align {
        TextAlign::Left => 0.0,
        TextAlign::Center => (box_w as f32 - text_w as f32) * 0.5,
        TextAlign::Right => box_w as f32 - text_w as f32 - padding,
    };
    let offset_x = padding + align_offset - min_x as f32;
    let offset_y = padding - min_y as f32;

    buffer.draw(
        font_system,
        swash_cache,
        color,
        |x, y, _w, _h, glyph_color| {
            draw_pixel(
                &mut pixels,
                box_w,
                box_h,
                x as f32 + offset_x,
                y as f32 + offset_y,
                glyph_color,
                spec.glow_intensity,
            );
        },
    );

    Ok((pixels, box_w, box_h))
}

fn fill_rounded_rect(
    pixels: &mut [u8],
    w: u32,
    h: u32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    radius: u32,
) {
    let radius = radius.min(w / 2).min(h / 2);
    for y in 0..h {
        for x in 0..w {
            if !in_rounded_rect(x, y, w, h, radius) {
                continue;
            }
            let i = ((y * w + x) * 4) as usize;
            if i + 3 >= pixels.len() {
                continue;
            }
            let alpha = a as f32 / 255.0;
            pixels[i] = blend_channel(pixels[i], r, alpha);
            pixels[i + 1] = blend_channel(pixels[i + 1], g, alpha);
            pixels[i + 2] = blend_channel(pixels[i + 2], b, alpha);
            pixels[i + 3] = blend_channel(pixels[i + 3], 255, alpha);
        }
    }
}

fn in_rounded_rect(x: u32, y: u32, w: u32, h: u32, r: u32) -> bool {
    if r == 0 {
        return true;
    }
    let corners = [
        (x, y),
        (w - 1 - x, y),
        (x, h - 1 - y),
        (w - 1 - x, h - 1 - y),
    ];
    for (cx, cy) in corners {
        if cx < r && cy < r {
            let dx = r as i32 - cx as i32;
            let dy = r as i32 - cy as i32;
            if (dx * dx + dy * dy) as u32 > r * r {
                return false;
            }
        }
    }
    true
}

fn blend_channel(dst: u8, src: u8, alpha: f32) -> u8 {
    (dst as f32 * (1.0 - alpha) + src as f32 * alpha).round() as u8
}

fn draw_pixel(
    pixels: &mut [u8],
    buf_w: u32,
    buf_h: u32,
    x: f32,
    y: f32,
    color: Color,
    glow: f32,
) {
    let dx = x.round() as i32;
    let dy = y.round() as i32;
    if dx < 0 || dy < 0 || dx >= buf_w as i32 || dy >= buf_h as i32 {
        return;
    }
    let [r, g, b, a] = color.as_rgba();
    if a == 0 {
        return;
    }
    let alpha = a as f32 / 255.0;
    let i = ((dy as u32 * buf_w + dx as u32) * 4) as usize;
    if i + 3 >= pixels.len() {
        return;
    }
    pixels[i] = blend_channel(pixels[i], r, alpha);
    pixels[i + 1] = blend_channel(pixels[i + 1], g, alpha);
    pixels[i + 2] = blend_channel(pixels[i + 2], b, alpha);
    pixels[i + 3] = blend_channel(pixels[i + 3], 255, alpha);

    if glow > 0.01 {
        for (ox, oy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            let gx = dx + ox;
            let gy = dy + oy;
            if gx < 0 || gy < 0 || gx >= buf_w as i32 || gy >= buf_h as i32 {
                continue;
            }
            let gi = ((gy as u32 * buf_w + gx as u32) * 4) as usize;
            if gi + 3 < pixels.len() {
                let ga = glow * 0.35 * alpha;
                pixels[gi] = blend_channel(pixels[gi], r, ga);
                pixels[gi + 1] = blend_channel(pixels[gi + 1], g, ga);
                pixels[gi + 2] = blend_channel(pixels[gi + 2], b, ga);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn renders_simple_text() {
        let mut font_system = FontSystem::new();
        let mut swash_cache = SwashCache::new();
        let spec = TextOverlayData {
            text: "Hi".into(),
            font_size: 48.0,
            ..Default::default()
        };
        let (px, w, h) =
            render_text_rgba(&mut font_system, &mut swash_cache, &spec, 640, 360, 0).unwrap();
        assert!(w > 0 && h > 0);
        assert!(px.iter().any(|&v| v > 0));
    }

    #[test]
    fn typewriter_empty_at_zero() {
        let mut font_system = FontSystem::new();
        let mut swash_cache = SwashCache::new();
        let spec = TextOverlayData {
            text: "Hello".into(),
            content_animation: TextContentAnimation::Typewriter,
            content_animation_duration_ms: 1000,
            ..Default::default()
        };
        let (px, w, h) =
            render_text_rgba(&mut font_system, &mut swash_cache, &spec, 640, 360, 0).unwrap();
        assert_eq!(w, 0);
        let _ = (px, h);
    }
}
