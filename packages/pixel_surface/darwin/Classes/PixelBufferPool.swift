import CoreVideo
import Foundation

/// Bucketed `CVPixelBufferPool` keyed by `(width, height, pixelFormat)`.
///
/// Pools are created lazily and reused across texture handles. The standard
/// `CVPixelBufferPool` is the canonical AVFoundation reuse primitive — backing
/// buffers are not actually freed on release; the pool retains a small ring
/// and hands the same memory back on the next
/// `CVPixelBufferPoolCreatePixelBuffer` call.
///
/// A `PixelBufferPool` is `Send`-safe only via external synchronization (the
/// plugin's `poolLock`); the underlying CFType is documented as thread-safe
/// for create/release, but the bucketing dictionary is not.
///
/// **Visibility:** `internal` so the plugin's XCTest target can
/// `@testable import pixel_surface` and exercise the pool directly.
final class PixelBufferPool {
  struct Key: Hashable {
    let width: Int
    let height: Int
    let format: OSType
  }

  private var pools: [Key: CVPixelBufferPool] = [:]
  /// Number of `CVPixelBufferPoolCreatePixelBuffer` calls served. Note
  /// that CVPixelBufferPool may internally reuse memory across calls —
  /// this counter is the *call count*, not the *fresh allocation
  /// count*. The actual reuse rate is opaque to the caller of the
  /// standard pool API.
  private(set) var createCount: Int = 0
  private var lastFlushMs: Double = 0

  init() {}

  /// Fetch (or create) a buffer for the given dimensions and format. The
  /// returned buffer has a `+1` retain owned by the caller.
  func dequeue(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
    let key = Key(width: width, height: height, format: format)
    let pool: CVPixelBufferPool
    if let existing = pools[key] {
      pool = existing
    } else {
      guard let new = Self.makePool(width: width, height: height, format: format) else {
        return nil
      }
      pools[key] = new
      pool = new
    }
    var pb: CVPixelBuffer?
    let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pb)
    createCount += 1
    guard status == kCVReturnSuccess, let pb else { return nil }
    return pb
  }

  /// Drop every cached buffer across every bucket. The pool itself stays
  /// alive; only its backlog of unclaimed buffers is freed. Safe to call
  /// from any code path that has locked the plugin.
  func flushAll() {
    let now = CFAbsoluteTimeGetCurrent() * 1000
    for pool in pools.values {
      CVPixelBufferPoolFlush(pool, CVPixelBufferPoolFlushFlags())
    }
    lastFlushMs = now
  }

  /// Drop every buffer not currently in use. Subsequent `dequeue` calls
  /// allocate fresh buffers of the new size.
  func flushNonReusable() {
    for pool in pools.values {
      CVPixelBufferPoolFlush(pool, CVPixelBufferPoolFlushFlags())
    }
  }

  /// Number of currently-cached pool buckets. Used by the plugin's
  /// `debugStats` MethodChannel call.
  var bucketCount: Int { pools.count }

  /// Returns a dictionary suitable for the Flutter `debugStats` payload.
  func snapshot() -> [String: Any] {
    return [
      "poolCount": pools.count,
      "createCount": createCount,
      "lastFlushMs": lastFlushMs,
    ]
  }

  private static func makePool(width: Int, height: Int, format: OSType) -> CVPixelBufferPool? {
    // Pixel buffer attributes the pool will use for new buffers.
    let pbAttrs: [String: Any] = [
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferPixelFormatTypeKey as String: format,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    // Pool tuning: keep 3 buffers warm, recycle anything older than 1s.
    let poolAttrs: [String: Any] = [
      kCVPixelBufferPoolMinimumBufferCountKey as String: 3,
      kCVPixelBufferPoolMaximumBufferAgeKey as String: 1.0,
    ]
    var pool: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(
      kCFAllocatorDefault,
      poolAttrs as CFDictionary,
      pbAttrs as CFDictionary,
      &pool
    )
    guard status == kCVReturnSuccess, let pool else { return nil }
    return pool
  }
}
