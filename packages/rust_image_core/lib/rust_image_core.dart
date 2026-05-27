/// Rust image engine — FRB bindings only (Sprint P0.3).
///
/// Editor UI lives in `rust_image`. GPU Flutter [Texture] bridge is
/// `rust_gpu_texture`.
library;

export 'src/rust/api/advanced.dart';
export 'src/rust/api/face.dart';
export 'src/rust/api/image.dart';
export 'src/rust/api/layers.dart';
export 'src/rust/api/temporal.dart';
export 'src/rust/api/texture.dart';
export 'src/rust/frb_generated.dart' show RustLib;
