import XCTest
import CoreVideo
@testable import pixel_surface

/// `PixelBufferPool` is the canonical Apple-side allocation primitive for
/// Flutter `Texture` backing buffers (BGRA8888 + IOSurface + Metal).
/// These tests run as part of `xcodebuild test` on the `pixel_surface`
/// pod's test target and cover the bucketing, flush, and snapshot
/// behaviour that the plugin relies on for its `resizeTexture`,
/// `flushPools`, and `debugStats` MethodChannel calls.
final class PixelBufferPoolTests: XCTestCase {
  // Pool buckets keyed on (width, height, format) — different sizes
  // should never share a bucket.
  func testDequeueCreatesOneBucketPerSizeKey() {
    let pool = PixelBufferPool()
    XCTAssertEqual(pool.bucketCount, 0)
    XCTAssertNotNil(pool.dequeue(width: 64, height: 64, format: kCVPixelFormatType_32BGRA))
    XCTAssertEqual(pool.bucketCount, 1)
    XCTAssertNotNil(pool.dequeue(width: 128, height: 128, format: kCVPixelFormatType_32BGRA))
    XCTAssertEqual(pool.bucketCount, 2)
    // Same (w, h, format) reuses the bucket, does not create a new one.
    XCTAssertNotNil(pool.dequeue(width: 64, height: 64, format: kCVPixelFormatType_32BGRA))
    XCTAssertEqual(pool.bucketCount, 2)
  }

  // CVPixelBufferPoolCreatePixelBuffer is the dequeue call site; the
  // counter must advance on every successful dequeue.
  func testDequeueAdvancesCreateCount() {
    let pool = PixelBufferPool()
    let initial = pool.createCount
    for _ in 0..<5 {
      _ = pool.dequeue(width: 32, height: 32, format: kCVPixelFormatType_32BGRA)
    }
    XCTAssertEqual(
      pool.createCount,
      initial + 5,
      "every dequeue should advance createCount by exactly 1"
    )
  }

  // The pool must serve a fresh buffer when all warm buffers are
  // outstanding. The standard `CVPixelBufferPool` API is opaque about
  // the actual reuse rate — we only assert the *count* of allocations
  // matches the dequeue count, which is the metric the
  // plugin's `debugStats` exposes.
  func testDequeueAfterReleaseAdvancesCreateCount() {
    let pool = PixelBufferPool()
    var bufferRefs: [Unmanaged<CVPixelBuffer>?] = []
    for _ in 0..<3 {
      let pb = pool.dequeue(width: 16, height: 16, format: kCVPixelFormatType_32BGRA)!
      bufferRefs.append(Unmanaged.passRetained(pb))
    }
    for ref in bufferRefs {
      _ = ref?.takeRetainedValue()
    }
    bufferRefs.removeAll()
    let before = pool.createCount
    for _ in 0..<3 {
      _ = pool.dequeue(width: 16, height: 16, format: kCVPixelFormatType_32BGRA)
    }
    XCTAssertEqual(
      pool.createCount,
      before + 3,
      "every dequeue should advance createCount, even if the pool reuses memory"
    )
  }

  // flushAll must not crash and must drop the non-reusable backlog
  // across every bucket. We assert via the bucketCount staying
  // constant (the pools themselves are not destroyed, only the
  // backlog is) and via the `lastFlushMs` field advancing.
  func testFlushAllIsIdempotentAndAdvancesLastFlushMs() {
    let pool = PixelBufferPool()
    _ = pool.dequeue(width: 8, height: 8, format: kCVPixelFormatType_32BGRA)
    _ = pool.dequeue(width: 8, height: 8, format: kCVPixelFormatType_32BGRA)
    let bucketCountBefore = pool.bucketCount
    let firstSnapshot = pool.snapshot()
    let firstFlush = firstSnapshot["lastFlushMs"] as? Double ?? 0
    pool.flushAll()
    let secondFlush = pool.snapshot()["lastFlushMs"] as? Double ?? 0
    XCTAssertEqual(pool.bucketCount, bucketCountBefore, "flush must not destroy buckets")
    XCTAssertGreaterThan(secondFlush, firstFlush, "flushAll must advance lastFlushMs")
    // Idempotency: a second flush in the same millisecond does not crash.
    pool.flushAll()
  }

  // flushNonReusable is the resize path. It must not destroy the
  // buckets either — only their backlog of unclaimed buffers.
  func testFlushNonReusablePreservesBuckets() {
    let pool = PixelBufferPool()
    _ = pool.dequeue(width: 4, height: 4, format: kCVPixelFormatType_32BGRA)
    let bucketCountBefore = pool.bucketCount
    pool.flushNonReusable()
    XCTAssertEqual(pool.bucketCount, bucketCountBefore)
  }

  // The snapshot payload is the JSON shape the plugin hands to Dart's
  // `debugStats`. The keys must be present and the types must match
  // what `PixelSurfaceStats.fromMap` expects.
  func testSnapshotShapeMatchesDebugStatsContract() {
    let pool = PixelBufferPool()
    _ = pool.dequeue(width: 10, height: 10, format: kCVPixelFormatType_32BGRA)
    let snap = pool.snapshot()
    XCTAssertNotNil(snap["poolCount"] as? Int)
    XCTAssertNotNil(snap["createCount"] as? Int)
    XCTAssertNotNil(snap["lastFlushMs"] as? Double)
  }

  // Hashable Key: same (w, h, format) must collapse to the same bucket.
  func testKeyEquality() {
    let a = PixelBufferPool.Key(width: 100, height: 200, format: 0x42475241)
    let b = PixelBufferPool.Key(width: 100, height: 200, format: 0x42475241)
    let c = PixelBufferPool.Key(width: 100, height: 201, format: 0x42475241)
    XCTAssertEqual(a, b, "identical (w, h, format) keys must be equal")
    XCTAssertNotEqual(a, c, "different height must produce different keys")
  }
}
