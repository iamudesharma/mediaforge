use crate::api::image::RgbaImageBuffer;

/// Parse a Hald CLUT PNG into a packed 3D LUT buffer (RGBA) and return the LUT size.
pub fn parse_hald_clut(png_bytes: &[u8]) -> Result<(Vec<u8>, u32), String> {
    let img = image::load_from_memory_with_format(png_bytes, image::ImageFormat::Png)
        .map_err(|e| format!("Failed to decode PNG LUT: {e}"))?;
    let rgba = img.to_rgba8();
    let width = rgba.width();
    let height = rgba.height();

    // Check standard formats:
    // 1. Level 8 Hald CLUT: 512x512 pixels -> 64^3 LUT
    // 2. Level 4 Hald CLUT: 64x64 pixels -> 16^3 LUT
    // 3. Level 8 horizontal strip Hald CLUT: 4096x64 pixels -> 64^3 LUT
    // 4. Level 4 horizontal strip Hald CLUT: 256x16 pixels -> 16^3 LUT

    let (lut_size, tiles_x, _tiles_y, tile_size) = if width == 512 && height == 512 {
        (64, 8, 8, 64)
    } else if width == 64 && height == 64 {
        (16, 4, 4, 16)
    } else if width == 4096 && height == 64 {
        (64, 64, 1, 64)
    } else if width == 256 && height == 16 {
        (16, 16, 1, 16)
    } else {
        // Try to infer automatically if possible.
        let total_pixels = width * height;
        let s = (total_pixels as f64).powf(1.0 / 3.0).round() as u32;
        if s * s * s == total_pixels {
            if height == s {
                (s, s, 1, s)
            } else {
                let tiles = (s as f32).sqrt().round() as u32;
                if tiles * tiles == s && width == tiles * s && height == tiles * s {
                    (s, tiles, tiles, s)
                } else {
                    return Err(format!(
                        "Unsupported Hald CLUT dimensions: {}x{}",
                        width, height
                    ));
                }
            }
        } else {
            return Err(format!(
                "Unsupported Hald CLUT dimensions: {}x{}",
                width, height
            ));
        }
    };

    let size = lut_size as usize;
    let mut lut_data = vec![0u8; size * size * size * 4];

    for b in 0..size {
        let tile_col = b % tiles_x as usize;
        let tile_row = b / tiles_x as usize;

        let start_x = tile_col * tile_size as usize;
        let start_y = tile_row * tile_size as usize;

        for g in 0..size {
            for r in 0..size {
                let px = start_x + r;
                let py = start_y + g;

                let pixel = rgba.get_pixel(px as u32, py as u32);
                let idx = (r + g * size + b * size * size) * 4;
                lut_data[idx..idx + 4].copy_from_slice(&pixel.0);
            }
        }
    }

    Ok((lut_data, lut_size))
}

/// Apply a 3D LUT to a raw RGBA image buffer using trilinear interpolation on CPU.
pub fn apply_lut_3d_rgba(buffer: &mut RgbaImageBuffer, lut_data: &[u8], lut_size: u32) {
    use rayon::prelude::*;
    let size = lut_size as usize;
    let max_idx = lut_size - 1;
    let max_idx_f = max_idx as f32;

    buffer.pixels.par_chunks_exact_mut(4).for_each(|pixel| {
        let r = pixel[0] as f32 / 255.0 * max_idx_f;
        let g = pixel[1] as f32 / 255.0 * max_idx_f;
        let b = pixel[2] as f32 / 255.0 * max_idx_f;

        let r0 = r.floor() as usize;
        let r1 = (r0 + 1).min(max_idx as usize);
        let g0 = g.floor() as usize;
        let g1 = (g0 + 1).min(max_idx as usize);
        let b0 = b.floor() as usize;
        let b1 = (b0 + 1).min(max_idx as usize);

        let fr = r - r0 as f32;
        let fg = g - g0 as f32;
        let fb = b - b0 as f32;

        let get_color = |ri: usize, gi: usize, bi: usize| -> (f32, f32, f32) {
            let idx = (ri + gi * size + bi * size * size) * 4;
            (
                lut_data[idx] as f32,
                lut_data[idx + 1] as f32,
                lut_data[idx + 2] as f32,
            )
        };

        let c000 = get_color(r0, g0, b0);
        let c100 = get_color(r1, g0, b0);
        let c010 = get_color(r0, g1, b0);
        let c110 = get_color(r1, g1, b0);
        let c001 = get_color(r0, g0, b1);
        let c101 = get_color(r1, g0, b1);
        let c011 = get_color(r0, g1, b1);
        let c111 = get_color(r1, g1, b1);

        let c00_r = c000.0 * (1.0 - fr) + c100.0 * fr;
        let c00_g = c000.1 * (1.0 - fr) + c100.1 * fr;
        let c00_b = c000.2 * (1.0 - fr) + c100.2 * fr;

        let c01_r = c001.0 * (1.0 - fr) + c101.0 * fr;
        let c01_g = c001.1 * (1.0 - fr) + c101.1 * fr;
        let c01_b = c001.2 * (1.0 - fr) + c101.2 * fr;

        let c10_r = c010.0 * (1.0 - fr) + c110.0 * fr;
        let c10_g = c010.1 * (1.0 - fr) + c110.1 * fr;
        let c10_b = c010.2 * (1.0 - fr) + c110.2 * fr;

        let c11_r = c011.0 * (1.0 - fr) + c111.0 * fr;
        let c11_g = c011.1 * (1.0 - fr) + c111.1 * fr;
        let c11_b = c011.2 * (1.0 - fr) + c111.2 * fr;

        let c0m_r = c00_r * (1.0 - fg) + c10_r * fg;
        let c0m_g = c00_g * (1.0 - fg) + c10_g * fg;
        let c0m_b = c00_b * (1.0 - fg) + c10_b * fg;

        let c1m_r = c01_r * (1.0 - fg) + c11_r * fg;
        let c1m_g = c01_g * (1.0 - fg) + c11_g * fg;
        let c1m_b = c01_b * (1.0 - fg) + c11_b * fg;

        let final_r = c0m_r * (1.0 - fb) + c1m_r * fb;
        let final_g = c0m_g * (1.0 - fb) + c1m_g * fb;
        let final_b = c0m_b * (1.0 - fb) + c1m_b * fb;

        pixel[0] = final_r.round().clamp(0.0, 255.0) as u8;
        pixel[1] = final_g.round().clamp(0.0, 255.0) as u8;
        pixel[2] = final_b.round().clamp(0.0, 255.0) as u8;
    });
}

/// Apply a 3D LUT to a raw RGBA image buffer with configurable strength on CPU.
pub fn apply_lut_3d_with_strength_rgba(
    buffer: &mut RgbaImageBuffer,
    lut_data: &[u8],
    lut_size: u32,
    strength: f32,
) {
    let t = strength.clamp(0.0, 1.0);
    if t < 0.001 {
        return;
    }
    if t >= 0.999 {
        apply_lut_3d_rgba(buffer, lut_data, lut_size);
        return;
    }
    let orig = buffer.pixels.clone();
    apply_lut_3d_rgba(buffer, lut_data, lut_size);
    for (o, s) in buffer.pixels.iter_mut().zip(orig.iter()) {
        *o = (*o as f32 * t + *s as f32 * (1.0 - t))
            .round()
            .clamp(0.0, 255.0) as u8;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_and_apply_hald_clut() {
        // Create an identity level 4 Hald CLUT (64x64 pixels).
        // Level 4 -> 16^3 LUT. grid width/height = 4 tiles, tile_size = 16.
        let mut pixels = vec![0u8; 64 * 64 * 4];
        let tiles_x = 4;
        let tile_size = 16;
        for b in 0..16 {
            let tile_col = b % tiles_x;
            let tile_row = b / tiles_x;
            let start_x = tile_col * tile_size;
            let start_y = tile_row * tile_size;
            for g in 0..16 {
                for r in 0..16 {
                    let px = start_x + r;
                    let py = start_y + g;
                    let idx = (px + py * 64) * 4;
                    // Map index 0..15 to 0..255 color range
                    pixels[idx] = ((r as f32 / 15.0) * 255.0).round() as u8;
                    pixels[idx + 1] = ((g as f32 / 15.0) * 255.0).round() as u8;
                    pixels[idx + 2] = ((b as f32 / 15.0) * 255.0).round() as u8;
                    pixels[idx + 3] = 255;
                }
            }
        }

        // Encode raw pixels to PNG format bytes
        let img = image::ImageBuffer::<image::Rgba<u8>, _>::from_raw(64, 64, pixels).unwrap();
        let mut png_bytes = Vec::new();
        img.write_to(
            &mut std::io::Cursor::new(&mut png_bytes),
            image::ImageFormat::Png,
        )
        .unwrap();

        // Parse CLUT back
        let (lut_data, lut_size) = parse_hald_clut(&png_bytes).unwrap();
        assert_eq!(lut_size, 16);
        assert_eq!(lut_data.len(), 16 * 16 * 16 * 4);

        // Apply identity CLUT to sample pixels
        let mut test_buf = RgbaImageBuffer {
            width: 2,
            height: 2,
            pixels: vec![
                50, 100, 150, 255, 200, 120, 80, 255, 10, 20, 30, 255, 255, 255, 255, 255,
            ],
        };
        let orig = test_buf.pixels.clone();
        apply_lut_3d_rgba(&mut test_buf, &lut_data, lut_size);

        // Check if output pixels closely match input (within trilinear rounding tolerance of 2 units)
        for (o, t) in orig.iter().zip(test_buf.pixels.iter()) {
            assert!(
                (*o as i16 - *t as i16).abs() <= 2,
                "original: {o}, processed: {t}"
            );
        }
    }
}
