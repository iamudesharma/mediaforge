#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Registers face platform channels. GPU [Texture] is `rust_gpu_texture`.
@objc public class RustImageCorePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = rust_image_link_rust_for_frb()
    RustImageFacePlugin.register(with: registrar)
  }
}

@_silgen_name("rust_image_link_rust_for_frb")
private func rust_image_link_rust_for_frb() -> Int64
