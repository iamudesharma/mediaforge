/// GPU-resident Flutter [Texture] bridge (Sprint P0.2).
///
/// Platform channels only — no `rust_image_core`. Use with your own GPU/Rust
/// pipeline or push RGBA frames from Dart for demos and custom renderers.
library;

export 'src/gpu_texture_preview.dart';
export 'src/gpu_texture_registry.dart';
