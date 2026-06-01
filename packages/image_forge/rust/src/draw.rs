use ab_glyph::{FontRef, PxScale};
use image::{Rgba, RgbaImage};
use imageproc::drawing::{draw_filled_circle_mut, draw_line_segment_mut, draw_text_mut};

use crate::api::image::{DrawCircle, DrawLine, TextOverlay};

static FONT_BYTES: &[u8] = include_bytes!("../assets/DejaVuSans.ttf");

fn font() -> Result<FontRef<'static>, String> {
    FontRef::try_from_slice(FONT_BYTES).map_err(|_| "failed to load embedded font".to_string())
}

pub fn draw_text(mut rgba: RgbaImage, overlay: TextOverlay) -> Result<RgbaImage, String> {
    let font = font()?;
    let scale = PxScale::from(overlay.font_size);
    let color = Rgba([
        overlay.color_r,
        overlay.color_g,
        overlay.color_b,
        overlay.color_a,
    ]);

    draw_text_mut(
        &mut rgba,
        color,
        overlay.x as i32,
        overlay.y as i32,
        scale,
        &font,
        &overlay.text,
    );
    Ok(rgba)
}

pub fn draw_line(mut rgba: RgbaImage, line: DrawLine) -> Result<RgbaImage, String> {
    let color = Rgba([line.color_r, line.color_g, line.color_b, line.color_a]);
    draw_line_segment_mut(
        &mut rgba,
        (line.x0 as f32, line.y0 as f32),
        (line.x1 as f32, line.y1 as f32),
        color,
    );
    Ok(rgba)
}

pub fn draw_circle(mut rgba: RgbaImage, circle: DrawCircle) -> Result<RgbaImage, String> {
    let color = Rgba([
        circle.color_r,
        circle.color_g,
        circle.color_b,
        circle.color_a,
    ]);
    draw_filled_circle_mut(
        &mut rgba,
        (circle.center_x as i32, circle.center_y as i32),
        circle.radius as i32,
        color,
    );
    Ok(rgba)
}
