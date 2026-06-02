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

/// Pixel byte order for `updateTexture`. Mirrors the Dart `PixelLayout`.
private enum UploadLayout: String {
  case rgba8888
  case bgra8888
  static let `default`: UploadLayout = .rgba8888
}

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
  private let pool = PixelBufferPool()
  private let poolLock = NSLock()

  /// Last time we got a memory / thermal warning. Used by `debugStats`
  /// to confirm the warning handler fired.
  private var lastMemoryWarningMs: Double = 0

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
    instance.installMemoryWarningObservers()
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
      let pb = dequeueFromPool(width: width, height: height)
        ?? Self.createPixelBufferDirect(width: width, height: height)
      tex.pixelBuffer = pb
      let texId = registry.register(tex)
      textures[handle] = tex
      textureIds[handle] = texId
      NSLog("[PixelSurface] create handle=%lld %dx%d id=%lld",
            handle, width, height, texId)
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
      let layout = Self.layoutFromArgs(args["layout"])
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
      src.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        guard let baseAddr = raw.baseAddress else { return }
        let srcPtr = baseAddr.assumingMemoryBound(to: UInt8.self)
        let dst = base.assumingMemoryBound(to: UInt8.self)
        switch layout {
        case .bgra8888:
          // BGRA8888 upload: natural byte order for the CVPixelBuffer. No
          // channel swap; per-row memcpy handles non-contiguous strides.
          if rowBytes == width * 4 {
            memcpy(dst, srcPtr, expected)
          } else {
            for y in 0..<height {
              memcpy(
                dst.advanced(by: y * rowBytes),
                srcPtr.advanced(by: y * width * 4),
                width * 4
              )
            }
          }
        case .rgba8888:
          // RGBA8888 upload: vectorized channel swap (R/B) via vImage
          // Accelerate. ~1 GB/s on Apple Silicon, also vectorized on iOS
          // (see Phase 2.2 — the iOS copy of this plugin previously used a
          // scalar loop, which is the case Phase 2.2 unifies).
          if rowBytes == width * 4 {
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
            // Non-contiguous stride: per-row vImage call. vImage is still
            // ~10× faster than the previous scalar Swift loop.
            for y in 0..<height {
              var srcBuf = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: srcPtr.advanced(by: y * width * 4)),
                height: vImagePixelCount(1),
                width: vImagePixelCount(width),
                rowBytes: width * 4
              )
              var dstBuf = vImage_Buffer(
                data: dst.advanced(by: y * rowBytes),
                height: vImagePixelCount(1),
                width: vImagePixelCount(width),
                rowBytes: rowBytes
              )
              let permute: [UInt8] = [2, 1, 0, 3]
              vImagePermuteChannels_ARGB8888(&srcBuf, &dstBuf, permute, vImage_Flags(kvImageNoFlags))
            }
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
        // Zero-copy adoption: the Flutter display texture's pixel buffer
        // is now backed by the caller's BGRA/IOSurface/Metal-compatible
        // buffer. The next frame is the caller's bytes verbatim.
        tex.pixelBuffer = srcPb
        registry.textureFrameAvailable(texId)
        NSLog("[PixelSurface] present adopted handle=%lld %dx%d", handle, width, height)
        result(nil)
        return
      }

      guard let dstPb = dequeueFromPool(width: width, height: height)
        ?? Self.createPixelBufferDirect(width: width, height: height) else {
        result(FlutterError(code: "create_failed", message: "Metal CVPixelBuffer alloc failed", details: nil))
        return
      }
      // The pool handed us a +1; release our local handle when the
      // reference goes out of scope, and assign to the Flutter texture.
      tex.pixelBuffer = dstPb
      if !Self.copyPixelBufferContents(from: srcPb, to: dstPb) {
        result(FlutterError(code: "blit_failed", message: "CVPixelBuffer copy failed", details: nil))
        return
      }
      registry.textureFrameAvailable(texId)
      NSLog("[PixelSurface] present copied handle=%lld %dx%d", handle, width, height)
      result(nil)

    case "resizeTexture":
      guard let args = call.arguments as? [String: Any],
            let handle = Self.handleFromArgs(args["handle"]),
            let width = args["width"] as? Int,
            let height = args["height"] as? Int,
            let tex = textures[handle],
            let registry = textureRegistry
      else {
        result(FlutterError(code: "bad_args", message: "handle/width/height required", details: nil))
        return
      }
      let newPb = dequeueFromPool(width: width, height: height)
        ?? Self.createPixelBufferDirect(width: width, height: height)
      guard let newPb else {
        result(FlutterError(code: "create_failed", message: "Metal CVPixelBuffer alloc failed", details: nil))
        return
      }
      tex.pixelBuffer = newPb
      // Drop every buffer that the new pool is not actively using; the
      // Flutter side does not keep a +1 on the old buffer once we
      // overwrite the pointer, so a non-reusable flush is safe.
      poolLock.lock()
      pool.flushNonReusable()
      poolLock.unlock()
      let texId = textureIds[handle] ?? -1
      registry.textureFrameAvailable(texId)
      NSLog("[PixelSurface] resize handle=%lld %dx%d", handle, width, height)
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

    case "debugStats":
      poolLock.lock()
      let poolSnapshot = pool.snapshot()
      poolLock.unlock()
      result([
        "handleCount": textures.count,
        "poolCount": poolSnapshot["poolCount"] ?? 0,
        "createCount": poolSnapshot["createCount"] ?? 0,
        "lastFlushMs": poolSnapshot["lastFlushMs"] ?? 0,
        "lastMemoryWarningMs": lastMemoryWarningMs,
      ])

    case "flushPools":
      // Operator-driven flush (e.g. a "release memory" debug action).
      poolLock.lock()
      pool.flushAll()
      let snapshot = pool.snapshot()
      poolLock.unlock()
      metalTextureCacheLock.lock()
      if let cache = metalTextureCache {
        CVMetalTextureCacheFlush(cache, 0)
      }
      metalTextureCacheLock.unlock()
      NSLog("[PixelSurface] flushPools pools=%d", snapshot["poolCount"] as? Int ?? 0)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // ----- Private helpers ------------------------------------------------------

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

  private static func layoutFromArgs(_ value: Any?) -> UploadLayout {
    guard let raw = value as? String else { return .default }
    return UploadLayout(rawValue: raw) ?? .default
  }

  /// IOSurface + Metal compatibility — required for Flutter macOS/iOS `Texture` (avoids CVReturn -6660).
  private static func metalPixelBufferAttributes() -> CFDictionary {
    [
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ] as CFDictionary
  }

  /// Fallback path: build a CVPixelBuffer directly when the pool is not
  /// warm yet (first frame) or pool creation failed.
  private static func createPixelBufferDirect(width: Int, height: Int) -> CVPixelBuffer? {
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
    return pb
  }

  /// Try the bucketed pool first; fall back to direct allocation. Lock
  /// only around the pool mutating calls (the pool dict is not thread-safe).
  private func dequeueFromPool(width: Int, height: Int) -> CVPixelBuffer? {
    poolLock.lock()
    let pb = pool.dequeue(width: width, height: height, format: kCVPixelFormatType_32BGRA)
    poolLock.unlock()
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

  // ----- Memory pressure handling --------------------------------------------

  /// Hook the platform-specific "we're about to OOM" signal. We flush
  /// the pool (drop non-reusable buffers) and the Metal cache (release
  /// cached texture wrappers). The Flutter-side `TextureRegistry` keeps
  /// its own strong references to the in-flight `RustGpuPixelTexture`
  /// objects, so dropping here is safe.
  private func installMemoryWarningObservers() {
    let center = NotificationCenter.default
    #if canImport(UIKit)
      center.addObserver(
        self,
        selector: #selector(handleMemoryWarning),
        name: UIApplication.didReceiveMemoryWarningNotification,
        object: nil
      )
    #else
      // macOS: thermal state change is the closest analogue. ProcessInfo
      // posts `thermalStateDidChangeNotification` when the system moves
      // into .serious / .critical. We also subscribe to
      // `NSApplication.didResignActiveNotification` so we drop backlog
      // when the user backgrounds the app.
      center.addObserver(
        self,
        selector: #selector(handleMemoryWarning),
        name: ProcessInfo.thermalStateDidChangeNotification,
        object: nil
      )
      center.addObserver(
        self,
        selector: #selector(handleMemoryWarning),
        name: NSApplication.didResignActiveNotification,
        object: nil
      )
    #endif
  }

  @objc private func handleMemoryWarning() {
    let now = CFAbsoluteTimeGetCurrent() * 1000
    lastMemoryWarningMs = now
    poolLock.lock()
    pool.flushAll()
    let poolCount = pool.snapshot()["poolCount"] as? Int ?? 0
    poolLock.unlock()
    metalTextureCacheLock.lock()
    if let cache = metalTextureCache {
      CVMetalTextureCacheFlush(cache, 0)
    }
    metalTextureCacheLock.unlock()
    NSLog("[PixelSurface] memory warning -> flush pools=%d", poolCount)
  }
}
