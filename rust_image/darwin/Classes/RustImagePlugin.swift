#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Registers face (and texture on macOS) platform channels for rust_image on Apple.
@objc public class RustImagePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
#if canImport(FlutterMacOS)
    RustImageTexturePlugin.register(with: registrar)
#endif
    RustImageFacePlugin.register(with: registrar)
  }
}
