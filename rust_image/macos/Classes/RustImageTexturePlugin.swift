import CoreVideo

#if canImport(FlutterMacOS)
import Cocoa
import FlutterMacOS
#else
import Flutter
#endif

private final class RustImagePixelTexture: NSObject, FlutterTexture {
  var pixelBuffer: CVPixelBuffer?

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let pixelBuffer else { return nil }
    return Unmanaged.passRetained(pixelBuffer)
  }
}

public class RustImageTexturePlugin: NSObject, FlutterPlugin {
  private var textures: [Int64: RustImagePixelTexture] = [:]
  private var textureIds: [Int64: Int64] = [:]
  private weak var textureRegistry: FlutterTextureRegistry?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "rust_image/texture",
      binaryMessenger: registrar.messenger
    )
    let instance = RustImageTexturePlugin()
    instance.textureRegistry = registrar.textures
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "createTexture":
      guard let args = call.arguments as? [String: Any],
            let width = args["width"] as? Int,
            let height = args["height"] as? Int,
            let handle = Self.handleFromArgs(args["handle"]),
            let registry = textureRegistry
      else {
        result(FlutterError(code: "bad_args", message: "width/height/handle required", details: nil))
        return
      }
      let tex = RustImagePixelTexture()
      var pb: CVPixelBuffer?
      let attrs: [String: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey as String: [:],
      ]
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs as CFDictionary,
        &pb
      )
      tex.pixelBuffer = pb
      let texId = registry.register(tex)
      textures[handle] = tex
      textureIds[handle] = texId
      result(texId)

    case "updateTexture":
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let data = args["pixels"] as? FlutterStandardTypedData,
            let tex = textures[handle],
            let pb = tex.pixelBuffer,
            let registry = textureRegistry,
            let texId = textureIds[handle]
      else {
        result(FlutterError(code: "bad_args", message: "handle/pixels required", details: nil))
        return
      }
      CVPixelBufferLockBaseAddress(pb, [])
      defer { CVPixelBufferUnlockBaseAddress(pb, []) }
      guard let base = CVPixelBufferGetBaseAddress(pb) else {
        result(FlutterError(code: "lock_failed", message: "CVPixelBuffer lock failed", details: nil))
        return
      }
      let width = CVPixelBufferGetWidth(pb)
      let height = CVPixelBufferGetHeight(pb)
      let rowBytes = CVPixelBufferGetBytesPerRow(pb)
      let src = data.data
      let expected = width * height * 4
      if src.count < expected {
        result(FlutterError(code: "size_mismatch", message: "pixel buffer too small", details: nil))
        return
      }
      // RGBA → BGRA for CVPixelBuffer.
      src.withUnsafeBytes { raw in
        guard let srcPtr = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        let dst = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
          for x in 0..<width {
            let si = (y * width + x) * 4
            let di = y * rowBytes + x * 4
            dst[di + 0] = srcPtr[si + 2]
            dst[di + 1] = srcPtr[si + 1]
            dst[di + 2] = srcPtr[si + 0]
            dst[di + 3] = srcPtr[si + 3]
          }
        }
      }
      registry.textureFrameAvailable(texId)
      result(nil)

    case "notifyFrameAvailable":
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let registry = textureRegistry,
            let texId = textureIds[handle]
      else {
        result(FlutterError(code: "bad_args", message: "handle required", details: nil))
        return
      }
      registry.textureFrameAvailable(texId)
      result(nil)

    case "disposeTexture":
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let registry = textureRegistry,
            let texId = textureIds.removeValue(forKey: handle)
      else {
        result(nil)
        return
      }
      textures.removeValue(forKey: handle)
      registry.unregisterTexture(texId)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func handleFromArgs(_ value: Any?) -> Int64? {
    if let handle = value as? Int64 { return handle }
    if let handle = value as? Int { return Int64(handle) }
    if let number = value as? NSNumber { return number.int64Value }
    return nil
  }
}
