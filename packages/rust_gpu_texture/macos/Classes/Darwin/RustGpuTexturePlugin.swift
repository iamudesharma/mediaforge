import CoreVideo
import VideoToolbox

#if canImport(FlutterMacOS)
import Cocoa
import FlutterMacOS
#else
import Flutter
#endif

private final class RustGpuPixelTexture: NSObject, FlutterTexture {
  var pixelBuffer: CVPixelBuffer?

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let pixelBuffer else { return nil }
    return Unmanaged.passRetained(pixelBuffer)
  }
}

public class RustGpuTexturePlugin: NSObject, FlutterPlugin {
  private var textures: [Int64: RustGpuPixelTexture] = [:]
  private var textureIds: [Int64: Int64] = [:]
  private weak var textureRegistry: FlutterTextureRegistry?

  public static func register(with registrar: FlutterPluginRegistrar) {
#if canImport(FlutterMacOS)
    let messenger = registrar.messenger
#else
    let messenger = registrar.messenger()
#endif
    let channel = FlutterMethodChannel(
      name: "rust_gpu_texture/texture",
      binaryMessenger: messenger
    )
    let instance = RustGpuTexturePlugin()
#if canImport(FlutterMacOS)
    instance.textureRegistry = registrar.textures
#else
    instance.textureRegistry = registrar.textures()
#endif
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
      let tex = RustGpuPixelTexture()
      var pb: CVPixelBuffer?
      let attrs = Self.metalPixelBufferAttributes()
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        attrs,
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

    case "presentPixelBuffer":
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let ptr = Self.ptrFromArgs(args["pixelBufferPtr"]),
            let tex = textures[handle],
            let registry = textureRegistry,
            let texId = textureIds[handle]
      else {
        result(FlutterError(code: "bad_args", message: "handle/pixelBufferPtr required", details: nil))
        return
      }
      let raw = UnsafeRawPointer(bitPattern: UInt(truncatingIfNeeded: ptr))!
      let srcPb = Unmanaged<CVPixelBuffer>.fromOpaque(raw).takeRetainedValue()
      let width = CVPixelBufferGetWidth(srcPb)
      let height = CVPixelBufferGetHeight(srcPb)
      guard let dstPb = Self.ensureMetalPixelBuffer(tex: tex, width: width, height: height) else {
        result(FlutterError(code: "create_failed", message: "Metal CVPixelBuffer alloc failed", details: nil))
        return
      }
      if !Self.copyPixelBufferContents(from: srcPb, to: dstPb) {
        result(FlutterError(code: "blit_failed", message: "CVPixelBuffer copy failed", details: nil))
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

  private static func ptrFromArgs(_ value: Any?) -> Int64? {
    if let ptr = value as? Int64 { return ptr }
    if let ptr = value as? Int { return Int64(ptr) }
    if let number = value as? NSNumber { return number.uint64Value > 0 ? number.int64Value : nil }
    return nil
  }

  /// IOSurface + Metal compatibility — required for Flutter macOS/iOS `Texture` (avoids CVReturn -6660).
  private static func metalPixelBufferAttributes() -> CFDictionary {
    [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ] as CFDictionary
  }

  private static func ensureMetalPixelBuffer(
    tex: RustGpuPixelTexture,
    width: Int,
    height: Int
  ) -> CVPixelBuffer? {
    if let existing = tex.pixelBuffer,
       CVPixelBufferGetWidth(existing) == width,
       CVPixelBufferGetHeight(existing) == height {
      return existing
    }
    var pb: CVPixelBuffer?
    let err = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      metalPixelBufferAttributes(),
      &pb
    )
    guard err == kCVReturnSuccess, let pb else { return nil }
    tex.pixelBuffer = pb
    return pb
  }

  /// Copies [src] into the Flutter-registered Metal-compatible [dst] (does not replace [dst]).
  private static func copyPixelBufferContents(from src: CVPixelBuffer, to dst: CVPixelBuffer) -> Bool {
    let sw = CVPixelBufferGetWidth(src)
    let sh = CVPixelBufferGetHeight(src)
    let dw = CVPixelBufferGetWidth(dst)
    let dh = CVPixelBufferGetHeight(dst)
    guard sw == dw, sh == dh else { return false }

    if CVPixelBufferGetPixelFormatType(src) == kCVPixelFormatType_32BGRA,
       CVPixelBufferGetPixelFormatType(dst) == kCVPixelFormatType_32BGRA {
      return copyBgraLocked(src: src, dst: dst)
    }

    var session: VTPixelTransferSession?
    guard VTPixelTransferSessionCreate(
      allocator: kCFAllocatorDefault,
      pixelTransferSessionOut: &session
    ) == noErr,
      let session
    else {
      return false
    }
    defer { VTPixelTransferSessionInvalidate(session) }
    let err = VTPixelTransferSessionTransferImage(session, from: src, to: dst)
    return err == noErr
  }

  private static func copyBgraLocked(src: CVPixelBuffer, dst: CVPixelBuffer) -> Bool {
    CVPixelBufferLockBaseAddress(src, .readOnly)
    CVPixelBufferLockBaseAddress(dst, [])
    defer {
      CVPixelBufferUnlockBaseAddress(src, .readOnly)
      CVPixelBufferUnlockBaseAddress(dst, [])
    }
    guard let srcBase = CVPixelBufferGetBaseAddress(src),
          let dstBase = CVPixelBufferGetBaseAddress(dst)
    else {
      return false
    }
    let width = CVPixelBufferGetWidth(src)
    let height = CVPixelBufferGetHeight(src)
    let srcRow = CVPixelBufferGetBytesPerRow(src)
    let dstRow = CVPixelBufferGetBytesPerRow(dst)
    let rowBytes = width * 4
    for y in 0..<height {
      memcpy(
        dstBase.advanced(by: y * dstRow),
        srcBase.advanced(by: y * srcRow),
        rowBytes
      )
    }
    return true
  }
}
