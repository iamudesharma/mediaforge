use crate::api::image::RgbaImageBuffer;
use crate::layers::{bake_overlay_layers, PaintStroke, RasterLayer};

#[derive(Debug, Clone)]
pub struct RasterLayerInput {
    pub pixels: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub center_x: f32,
    pub center_y: f32,
    pub scale: f32,
    pub rotation_rad: f32,
    pub opacity: f32,
}

#[derive(Debug, Clone)]
pub struct PaintStrokeInput {
    pub points: Vec<(f32, f32)>,
    pub color_r: u8,
    pub color_g: u8,
    pub color_b: u8,
    pub color_a: u8,
    pub width: f32,
    pub opacity: f32,
}

#[flutter_rust_bridge::frb(sync)]
pub fn bake_layers_on_rgba(
    buffer: RgbaImageBuffer,
    raster_layers: Vec<RasterLayerInput>,
    paint_strokes: Vec<PaintStrokeInput>,
) -> Result<RgbaImageBuffer, String> {
    let layers: Vec<RasterLayer> = raster_layers
        .into_iter()
        .map(|l| RasterLayer {
            pixels: l.pixels,
            width: l.width,
            height: l.height,
            center_x: l.center_x,
            center_y: l.center_y,
            scale: l.scale,
            rotation_rad: l.rotation_rad,
            opacity: l.opacity,
        })
        .collect();

    let strokes: Vec<PaintStroke> = paint_strokes
        .into_iter()
        .map(|s| PaintStroke {
            points: s.points,
            color_r: s.color_r,
            color_g: s.color_g,
            color_b: s.color_b,
            color_a: s.color_a,
            width: s.width,
            opacity: s.opacity,
        })
        .collect();

    bake_overlay_layers(buffer, layers, strokes)
}
