import 'package:rust_image_editor/src/rust_image_editor.dart';

/// Loads Rust FFI for `flutter test` when a release dylib exists or
/// [RUST_IMAGE_DYLIB] is set. Returns false if no library is available.
Future<bool> ensureTestFrbInitialized() async {
  try {
    await RustImageEditor.ensureInitialized();
    return true;
  } catch (_) {
    return false;
  }
}
