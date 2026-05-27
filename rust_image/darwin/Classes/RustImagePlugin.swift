#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Registers face platform channels for rust_image on Apple.
/// GPU [Texture] bridge lives in the `rust_gpu_texture` plugin.
@objc public class RustImagePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Release Archive strips Rust symbols used only via Dart FFI unless the app
    // links them directly (see ios/rust_image.podspec force_load + linker stub).
    _ = rust_image_link_rust_for_frb()
    RustImageFacePlugin.register(with: registrar)
  }
}

@_silgen_name("rust_image_link_rust_for_frb")
private func rust_image_link_rust_for_frb() -> Int64
