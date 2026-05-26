#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Registers texture + face platform channels for rust_image on macOS.
public class RustImagePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    RustImageTexturePlugin.register(with: registrar)
    RustImageFacePlugin.register(with: registrar)
  }
}
