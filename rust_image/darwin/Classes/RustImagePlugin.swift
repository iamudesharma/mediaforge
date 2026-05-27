#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Registers face (and texture on macOS / iOS) platform channels for rust_image on Apple.
@objc public class RustImagePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Release Archive strips Rust symbols used only via Dart FFI unless the app
    // links them directly (see ios/rust_image.podspec force_load + linker stub).
    _ = rust_image_link_rust_for_frb()
#if canImport(FlutterMacOS)
    RustImageTexturePlugin.register(with: registrar)
#else
    RustImageTexturePlugin.register(with: registrar)
#endif
    RustImageFacePlugin.register(with: registrar)
  }
}

@_silgen_name("rust_image_link_rust_for_frb")
private func rust_image_link_rust_for_frb() -> Int64
