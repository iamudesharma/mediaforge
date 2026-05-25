use image::GenericImageView;

use crate::api::image::{OutputFormat, ProcessingBackend, ResizeAlgorithm};
use crate::resize;
use crate::utils;

pub fn thumbnail(
    bytes: &[u8],
    max_edge: u32,
    format: OutputFormat,
    quality: u8,
    algorithm: ResizeAlgorithm,
    backend: ProcessingBackend,
) -> Result<Vec<u8>, String> {
    if max_edge == 0 {
        return Err("max_edge must be greater than zero".into());
    }

    let img = utils::decode(bytes)?;
    let (w, h) = img.dimensions();
    let (tw, th) = fit_within(w, h, max_edge);
    let resized = resize::resize(img, tw, th, algorithm, backend)?;
    utils::encode(&resized, format, quality)
}

fn fit_within(width: u32, height: u32, max_edge: u32) -> (u32, u32) {
    let max_edge = max_edge as f64;
    let w = width as f64;
    let h = height as f64;
    let scale = if w >= h {
        max_edge / w
    } else {
        max_edge / h
    };
    (
        (w * scale).round().max(1.0) as u32,
        (h * scale).round().max(1.0) as u32,
    )
}
