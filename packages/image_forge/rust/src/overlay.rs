use image::imageops::FilterType;

use crate::api::image::{BlendMode, RgbaImageBuffer};
use crate::buffer::blend_pixel;

pub fn composite(
    mut base: RgbaImageBuffer,
    overlay_bytes: &[u8],
    x: i32,
    y: i32,
    blend_mode: BlendMode,
    target_width: u32,
    target_height: u32,
) -> Result<RgbaImageBuffer, String> {
    let overlay_img = image::load_from_memory(overlay_bytes).map_err(|e| e.to_string())?;
    let mut overlay = overlay_img.to_rgba8();
    let (mut ow, mut oh) = overlay.dimensions();

    if target_width > 0 && target_height > 0 && (target_width != ow || target_height != oh) {
        overlay =
            image::imageops::resize(&overlay, target_width, target_height, FilterType::Triangle);
        ow = target_width;
        oh = target_height;
    }

    let overlay_raw = overlay.into_raw();
    let (bw, bh) = (base.width, base.height);
    let base_stride = bw as usize * 4;
    let overlay_stride = ow as usize * 4;

    for oy in 0..oh {
        let by = y + oy as i32;
        if by < 0 || by >= bh as i32 {
            continue;
        }
        let row_idx = by as usize;
        if row_idx >= bh as usize {
            continue;
        }
        let base_row_start = row_idx * base_stride;
        let base_row = &mut base.pixels[base_row_start..base_row_start + base_stride];

        let overlay_row_offset = oy as usize * overlay_stride;
        let overlay_row = &overlay_raw[overlay_row_offset..overlay_row_offset + overlay_stride];

        for ox in 0..ow {
            let bx = x + ox as i32;
            if bx < 0 || bx >= bw as i32 {
                continue;
            }
            let base_col_idx = bx as usize;
            let b_idx = base_col_idx * 4;
            let o_idx = ox as usize * 4;

            let base_px = image::Rgba([
                base_row[b_idx],
                base_row[b_idx + 1],
                base_row[b_idx + 2],
                base_row[b_idx + 3],
            ]);
            let over_px = image::Rgba([
                overlay_row[o_idx],
                overlay_row[o_idx + 1],
                overlay_row[o_idx + 2],
                overlay_row[o_idx + 3],
            ]);

            let blended = blend_pixel(base_px, over_px, blend_mode);

            base_row[b_idx] = blended[0];
            base_row[b_idx + 1] = blended[1];
            base_row[b_idx + 2] = blended[2];
            base_row[b_idx + 3] = blended[3];
        }
    }

    Ok(base)
}
