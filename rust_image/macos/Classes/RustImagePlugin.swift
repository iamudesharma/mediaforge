#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Registers face platform channels for rust_image on Apple.
/// GPU [Texture] bridge lives in the `rust_gpu_texture` plugin.
@objc public class RustImagePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = rust_image_link_rust_for_frb()
    RustImageFacePlugin.register(with: registrar)
  }
}

@_silgen_name("rust_image_link_rust_for_frb")
private func rust_image_link_rust_for_frb() -> Int64
