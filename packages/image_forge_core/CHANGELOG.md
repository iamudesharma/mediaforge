## 1.0.0

- Initial release: lightweight Rust image processing engine for Flutter.
- Core operations: resize, crop, rotate, compress, thumbnails, EXIF, blurhash.
- Basic filters: blur, sharpen, brightness, contrast, saturation, hue, warmth, fade, vignette, highlights, shadows, structure, oil, frosted glass, pixelize, solarize, classic presets.
- Drawing: text, lines, circles, watermark overlays with blend modes.
- RGBA buffer pipeline for zero-intermediate-encode editing.
- GPU compute (wgpu Metal/Vulkan) for resize, blur, sharpen, and color adjustments.
- Multi-format encode/decode: JPEG (MozJPEG), PNG (oxipng), WebP, AVIF.
- Progressive decode: low-res preview + full-res buffer.
- Buffer pool for zero-allocation render loops.
