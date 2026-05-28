import CoreGraphics
import Foundation
import Vision

#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

/// Sprint 12 — face landmarks + person mask for regional beauty (Vision on Apple).
/// MediaPipe `.task` models can replace this path when bundled; see `scripts/download_mediapipe_models.sh`.
public final class RustImageFacePlugin: NSObject, FlutterPlugin {
  private static let minLandmarksForValid = 68

  public static func register(with registrar: FlutterPluginRegistrar) {
#if canImport(FlutterMacOS)
    let messenger = registrar.messenger
#else
    let messenger = registrar.messenger()
#endif
    let channel = FlutterMethodChannel(
      name: "rust_image/face",
      binaryMessenger: messenger
    )
    let instance = RustImageFacePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isAvailable":
      if #available(macOS 12.0, iOS 15.0, *) {
        result(true)
      } else {
        result(false)
      }

    case "isMediaPipeReady":
      let args = call.arguments as? [String: Any]
      let modelDir = args?["modelDir"] as? String
      result(RustImageMediaPipeAnalyzer.modelsReady(at: modelDir))

    case "analyzeImage":
      guard let args = call.arguments as? [String: Any],
            let imageData = RustImageImageDecode.dataFromChannel(args["bytes"]),
            let width = args["width"] as? Int,
            let height = args["height"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "bytes/width/height required", details: nil))
        return
      }
      let maxEdge = args["maxEdge"] as? Int ?? 1280
      let pixelFormat = args["pixelFormat"] as? String ?? "jpeg"
      let modelDir = args["modelDir"] as? String
      if #available(macOS 12.0, iOS 15.0, *) {
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let payload: [String: Any]
            if let dir = modelDir, RustImageMediaPipeAnalyzer.modelsReady(at: dir) {
              do {
                payload = try RustImageMediaPipeAnalyzer.analyze(
                  imageData: imageData,
                  pixelFormat: pixelFormat,
                  targetWidth: width,
                  targetHeight: height,
                  modelDir: dir
                )
              } catch {
                payload = try Self.analyzeVision(
                  imageData: imageData,
                  pixelFormat: pixelFormat,
                  targetWidth: width,
                  targetHeight: height,
                  maxEdge: maxEdge
                )
              }
            } else {
              payload = try Self.analyzeVision(
                imageData: imageData,
                pixelFormat: pixelFormat,
                targetWidth: width,
                targetHeight: height,
                maxEdge: maxEdge
              )
            }
            DispatchQueue.main.async { result(payload) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "analyze_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      } else {
        result(FlutterError(code: "unavailable", message: "Vision face requires macOS 12+ / iOS 15+", details: nil))
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(macOS 12.0, iOS 15.0, *)
  private static func analyzeVision(
    imageData: Data,
    pixelFormat: String,
    targetWidth: Int,
    targetHeight: Int,
    maxEdge: Int
  ) throws -> [String: Any] {
    let tw = max(1, targetWidth)
    let th = max(1, targetHeight)
    guard let cgImage = RustImageImageDecode.cgImage(
      from: imageData,
      pixelFormat: pixelFormat,
      width: tw,
      height: th
    ) else {
      let detail = pixelFormat == "rgba"
        ? "Could not decode RGBA (\(imageData.count) bytes, \(tw)×\(th))"
        : "Could not decode image"
      throw NSError(domain: "rust_image", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
    }
    guard let scaled = Self.resize(cgImage, width: tw, height: th) else {
      throw NSError(domain: "rust_image", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not scale image"])
    }

    let landmarks = try detectLandmarks(in: scaled, width: tw, height: th)
    let mask = try segmentPerson(in: scaled, width: tw, height: th)

    let confidence: Float = landmarks.points.count >= minLandmarksForValid ? 0.95 : 0.0
    let landmarkMaps: [[String: Double]] = landmarks.points.map {
      ["x": Double($0.x), "y": Double($0.y), "z": Double($0.z)]
    }

    return [
      "landmarks": landmarkMaps,
      "confidence": confidence,
      "faceContourCount": landmarks.contourCount,
      "regionCounts": landmarks.regionCounts,
      "mask": [
        "width": tw,
        "height": th,
        "bytes": FlutterStandardTypedData(bytes: mask),
      ],
    ]
  }

  private static func resize(_ image: CGImage, width: Int, height: Int) -> CGImage? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
  }

  @available(macOS 12.0, iOS 15.0, *)
  private static func detectLandmarks(in image: CGImage, width: Int, height: Int) throws -> (points: [(x: Float, y: Float, z: Float)], contourCount: Int, regionCounts: [Int]) {
    let request = VNDetectFaceLandmarksRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    guard let face = request.results?.first as? VNFaceObservation,
          let lm = face.landmarks
    else {
      return ([], 0, [])
    }

    var points: [(Float, Float, Float)] = []
    var contourCount = 0
    var regionCounts: [Int] = []
    let bbox = face.boundingBox

    func addRegion(_ region: VNFaceLandmarkRegion2D?) {
      let before = points.count
      if let region {
        let pts = region.normalizedPoints
        for p in pts {
          // Landmarks are normalized to the face bbox; map to full-image 0–1 (top-left origin).
          let imagePoint = VNImagePointForFaceLandmarkPoint(
            vector_float2(Float(p.x), Float(p.y)),
            bbox,
            width,
            height
          )
          let x = Float(imagePoint.x) / Float(width)
          let y = 1.0 - Float(imagePoint.y) / Float(height)
          points.append((x, y, 0))
        }
      }
      // Always record count (0 when region missing) so Rust region indices stay aligned.
      regionCounts.append(points.count - before)
    }

    let beforeContour = points.count
    addRegion(lm.faceContour)
    contourCount = points.count - beforeContour
    // Face contour count is in faceContourCount only — regionCounts are the 11 feature regions.
    if !regionCounts.isEmpty {
      regionCounts.removeFirst()
    }
    addRegion(lm.leftEye)
    addRegion(lm.rightEye)
    addRegion(lm.leftEyebrow)
    addRegion(lm.rightEyebrow)
    addRegion(lm.nose)
    addRegion(lm.noseCrest)
    addRegion(lm.medianLine)
    addRegion(lm.outerLips)
    addRegion(lm.innerLips)
    addRegion(lm.leftPupil)
    addRegion(lm.rightPupil)

    return (points, contourCount, regionCounts)
  }

  @available(macOS 12.0, iOS 15.0, *)
  private static func segmentPerson(in image: CGImage, width: Int, height: Int) throws -> Data {
    let request = VNGeneratePersonSegmentationRequest()
    request.qualityLevel = .balanced
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    guard let obs = request.results?.first as? VNPixelBufferObservation else {
      return Data(repeating: 0, count: width * height)
    }
    let pb = obs.pixelBuffer
    CVPixelBufferLockBaseAddress(pb, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

    let pw = CVPixelBufferGetWidth(pb)
    let ph = CVPixelBufferGetHeight(pb)
    let rowBytes = CVPixelBufferGetBytesPerRow(pb)
    guard let base = CVPixelBufferGetBaseAddress(pb) else {
      return Data(repeating: 0, count: width * height)
    }

    var out = Data(count: width * height)
    out.withUnsafeMutableBytes { dstRaw in
      guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      let src = base.assumingMemoryBound(to: UInt8.self)
      for y in 0..<height {
        let sy = y * ph / height
        for x in 0..<width {
          let sx = x * pw / width
          let si = sy * rowBytes + sx
          let di = y * width + x
          dst[di] = src[si]
        }
      }
    }
    return out
  }
}
