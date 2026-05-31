use crate::api::image::RgbaImageBuffer;
use crate::layers::{bake_overlay_layers, PaintStroke, RasterLayer};

/// Input representation for a raster overlay layer (e.g. sticker or image badge).
#[derive(Debug, Clone)]
pub struct RasterLayerInput {
    /// Decoded raw pixels of the overlay image.
    pub pixels: Vec<u8>,
    /// Width of the overlay image in pixels.
    pub width: u32,
    /// Height of the overlay image in pixels.
    pub height: u32,
    /// Horizontal center position relative to base image width.
    pub center_x: f32,
    /// Vertical center position relative to base image height.
    pub center_y: f32,
    /// Scale factor of the overlay.
    pub scale: f32,
    /// Rotation angle of the overlay in radians.
    pub rotation_rad: f32,
    /// Opacity factor (0.0 to 1.0) of the overlay.
    pub opacity: f32,
}

/// Input representation for a vector paint stroke.
#[derive(Debug, Clone)]
pub struct PaintStrokeInput {
    /// List of 2D points along the stroke path.
    pub points: Vec<(f32, f32)>,
    /// Color red channel.
    pub color_r: u8,
    /// Color green channel.
    pub color_g: u8,
    /// Color blue channel.
    pub color_b: u8,
    /// Color alpha channel.
    pub color_a: u8,
    /// Stroke width/thickness in pixels.
    pub width: f32,
    /// Opacity factor (0.0 to 1.0) of the stroke.
    pub opacity: f32,
    /// When true, clears painted pixels along the stroke (Sprint 9 eraser).
    pub erase: bool,
    /// Brush kind index (0=pen, 1=marker, 2=highlighter, 3=eraser, 4=neon).
    pub brush_kind: u8,
    /// True if the shape/stroke is filled.
    pub filled: bool,
}

/// Bakes multiple raster overlay layers and vector paint strokes onto a base RGBA buffer.
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
            erase: s.erase,
            brush_kind: s.brush_kind,
            filled: s.filled,
        })
        .collect();

    bake_overlay_layers(buffer, layers, strokes)
}
