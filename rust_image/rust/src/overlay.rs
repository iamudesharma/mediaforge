use rayon::prelude::*;

use crate::api::image::{BlendMode, RgbaImageBuffer};
use crate::buffer::blend_pixel;

pub fn composite(
    mut base: RgbaImageBuffer,
    overlay_bytes: &[u8],
    x: i32,
    y: i32,
    blend_mode: BlendMode,
) -> Result<RgbaImageBuffer, String> {
    let overlay_img = image::load_from_memory(overlay_bytes).map_err(|e| e.to_string())?;
    let overlay = overlay_img.to_rgba8();
    let (ow, oh) = overlay.dimensions();
    let overlay_raw = overlay.into_raw();

    let (bw, bh) = (base.width, base.height);
    let start_x = x.max(0);
    let start_y = y.max(0);
    let end_x = (x + ow as i32).min(bw as i32);
    let end_y = (y + oh as i32).min(bh as i32);

    if start_x >= end_x || start_y >= end_y {
        return Ok(base);
    }

    let base_stride = bw as usize * 4;
    let overlay_stride = ow as usize * 4;

    base.pixels
        .chunks_mut(base_stride)
        .enumerate()
        .filter(|(r_idx, _)| *r_idx >= start_y as usize && *r_idx < end_y as usize)
        .collect::<Vec<_>>()
        .into_par_iter()
        .for_each(|(r_idx, base_row)| {
            let oy = r_idx as i32 - y;
            let start_ox = (start_x - x) as usize;
            let end_ox = (end_x - x) as usize;

            let overlay_row_offset = oy as usize * overlay_stride;
            let overlay_row = &overlay_raw[overlay_row_offset..overlay_row_offset + overlay_stride];

            for ox in start_ox..end_ox {
                let base_col_idx = ox + x as usize;
                let b_idx = base_col_idx * 4;
                let o_idx = ox * 4;

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
        });

    Ok(base)
}
