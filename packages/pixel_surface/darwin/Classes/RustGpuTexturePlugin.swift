import CoreVideo
import VideoToolbox
import Accelerate

#if canImport(FlutterMacOS)
import Cocoa
import FlutterMacOS
import Metal
#else
import Flutter
import Metal
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
  private var metalTextureCache: CVMetalTextureCache?
  private let metalTextureCacheLock = NSLock()

  public static func register(with registrar: FlutterPluginRegistrar) {
#if canImport(FlutterMacOS)
    let messenger = registrar.messenger
#else
    let messenger = registrar.messenger()
#endif
    let channel = FlutterMethodChannel(
      name: "pixel_surface/texture",
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
        if rowBytes == width * 4 {
          // Tightly packed rows: vectorized BGRA swap (R/B per pixel) via
          // vImagePermuteChannels_ARGB8888 — ~1 GB/s on Apple Silicon.
          var srcBuf = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: srcPtr),
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: width * 4
          )
          var dstBuf = vImage_Buffer(
            data: dst,
            height: vImagePixelCount(height),
            width: vImagePixelCount(width),
            rowBytes: rowBytes
          )
          let permute: [UInt8] = [2, 1, 0, 3]
          vImagePermuteChannels_ARGB8888(&srcBuf, &dstBuf, permute, vImage_Flags(kvImageNoFlags))
        } else {
          for y in 0..<height {
            let si = y * width * 4
            let di = y * rowBytes
            swapBgraRow(
              src: srcPtr.advanced(by: si),
              dst: dst.advanced(by: di),
              count: width
            )
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

      if Self.canAdoptPixelBufferDirectly(srcPb) {
        tex.pixelBuffer = srcPb
        registry.textureFrameAvailable(texId)
        result(nil)
        return
      }

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

    case "getMetalTexturePtr":
      // Returns the raw MTLTexture* + CVPixelBuffer* of the Flutter display
      // texture for the given handle. Rust uses these to import the same
      // IOSurface-backed GPU resource as a wgpu::Texture and write beauty
      // output into it without any CPU readback.
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let tex = textures[handle],
            let pb = tex.pixelBuffer
      else {
        result(FlutterError(code: "bad_args", message: "handle/pixelBuffer not found", details: nil))
        return
      }
      guard let cache = acquireMetalTextureCache() else {
        result(FlutterError(code: "no_cache", message: "CVMetalTextureCache unavailable", details: nil))
        return
      }
      let width = CVPixelBufferGetWidth(pb)
      let height = CVPixelBufferGetHeight(pb)
      var cvTexture: CVMetalTexture?
      let status = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, cache, pb, nil,
        MTLPixelFormat.bgra8Unorm, width, height, 0, &cvTexture
      )
      guard status == kCVReturnSuccess, let cvTexture, let mtlTexture = CVMetalTextureGetTexture(cvTexture) else {
        result(FlutterError(code: "create_failed", message: "CVMetalTextureCacheCreateTextureFromImage failed: status=\(status)", details: nil))
        return
      }
      // Retain +1 each so the caller (Rust) gets its own reference.
      let pbUnmanaged = Unmanaged<CVPixelBuffer>.passRetained(pb)
      let texUnmanaged = Unmanaged<MTLTexture>.passRetained(mtlTexture)
      let pbPtr = UInt(bitPattern: pbUnmanaged.toOpaque())
      let texPtr = UInt(bitPattern: texUnmanaged.toOpaque())
      result([
        "metalTexturePtr": NSNumber(value: texPtr),
        "pixelBufferPtr": NSNumber(value: pbPtr),
      ])

    case "attachOutputTexture":
      // No-op on the Swift side: Rust already holds the +1 retain. Just
      // make sure the next frame is visible.
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let tex = textures[handle],
            let _ = tex.pixelBuffer,
            let registry = textureRegistry,
            let texId = textureIds[handle]
      else {
        result(FlutterError(code: "bad_args", message: "handle/pixelBuffer required", details: nil))
        return
      }
      let _ = registry.textureFrameAvailable(texId)
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

  private static func canAdoptPixelBufferDirectly(_ pb: CVPixelBuffer) -> Bool {
    guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_32BGRA else {
      return false
    }
    guard CVPixelBufferGetIOSurface(pb) != nil else {
      return false
    }
    if let attrs = CVPixelBufferCopyCreationAttributes(pb) as? [String: Any],
       let metal = attrs[kCVPixelBufferMetalCompatibilityKey as String] as? Bool {
      return metal
    }
    return true
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

  /// Per-row R/B channel swap (BGRA ↔ RGBA) for a tightly packed row of
  /// [count] pixels. Used when CVPixelBuffer rows are not contiguous.
  @inline(__always)
  private static func swapBgraRow(src: UnsafePointer<UInt8>, dst: UnsafeMutablePointer<UInt8>, count: Int) {
    var si = 0
    var di = 0
    for _ in 0..<count {
      dst[di + 0] = src[si + 2]
      dst[di + 1] = src[si + 1]
      dst[di + 2] = src[si + 0]
      dst[di + 3] = src[si + 3]
      si += 4
      di += 4
    }
  }

  /// Lazily-create the plugin's `CVMetalTextureCache`. Thread-safe via lock.
  private func acquireMetalTextureCache() -> CVMetalTextureCache? {
    metalTextureCacheLock.lock()
    defer { metalTextureCacheLock.unlock() }
    if let cache = metalTextureCache { return cache }
    let device = MTLCreateSystemDefaultDevice()
    guard let device else { return nil }
    var cache: CVMetalTextureCache?
    let err = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
    guard err == kCVReturnSuccess, let cache else { return nil }
    metalTextureCache = cache
    return cache
  }
}
