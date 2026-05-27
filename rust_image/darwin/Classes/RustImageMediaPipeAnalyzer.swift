import CoreGraphics
import Foundation

#if canImport(MediaPipeTasksVision)
import MediaPipeTasksVision
#endif

#if canImport(UIKit)
import UIKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// MediaPipe Face Landmarker (468 pts) + selfie segmenter TFLite when models are on disk.
enum RustImageMediaPipeAnalyzer {
  private static let minLandmarksForValid = 468

  static func modelsReady(at modelDir: String?) -> Bool {
    guard let dir = modelDir, !dir.isEmpty else { return false }
    let base = URL(fileURLWithPath: dir, isDirectory: true)
    let face = base.appendingPathComponent("face_landmarker.task")
    let seg = base.appendingPathComponent("selfie_segmenter.tflite")
    return FileManager.default.fileExists(atPath: face.path)
      && FileManager.default.fileExists(atPath: seg.path)
  }

  static func analyze(
    imageData: Data,
    pixelFormat: String,
    targetWidth: Int,
    targetHeight: Int,
    modelDir: String
  ) throws -> [String: Any] {
    #if canImport(MediaPipeTasksVision)
    guard modelsReady(at: modelDir) else {
      throw NSError(
        domain: "rust_image",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "MediaPipe models not found"]
      )
    }
    guard let cgImage = RustImageImageDecode.cgImage(
      from: imageData,
      pixelFormat: pixelFormat,
      width: targetWidth,
      height: targetHeight
    ) else {
      throw NSError(domain: "rust_image", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not decode image"])
    }
    let tw = max(1, targetWidth)
    let th = max(1, targetHeight)
    guard let scaled = resize(cgImage, width: tw, height: th) else {
      throw NSError(domain: "rust_image", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not scale image"])
    }

    let facePath = URL(fileURLWithPath: modelDir).appendingPathComponent("face_landmarker.task").path
    let segPath = URL(fileURLWithPath: modelDir).appendingPathComponent("selfie_segmenter.tflite").path

    let landmarks = try detectLandmarks(cgImage: scaled, modelPath: facePath, width: tw, height: th)
    let mask = try segmentSelfie(cgImage: scaled, modelPath: segPath, width: tw, height: th)

    let confidence: Float = landmarks.count >= minLandmarksForValid ? 0.98 : 0.0
    let landmarkMaps: [[String: Double]] = landmarks.map {
      ["x": Double($0.x), "y": Double($0.y), "z": Double($0.z)]
    }

    return [
      "landmarks": landmarkMaps,
      "confidence": confidence,
      "faceContourCount": FACE_OVAL_COUNT,
      "regionCounts": [Int](),
      "mask": [
        "width": tw,
        "height": th,
        "bytes": FlutterStandardTypedData(bytes: mask),
      ],
      "meshKind": "mediapipe468",
    ]
    #else
    throw NSError(
      domain: "rust_image",
      code: 11,
      userInfo: [NSLocalizedDescriptionKey: "MediaPipeTasksVision not linked"]
    )
    #endif
  }

  private static let FACE_OVAL_COUNT = 36

  #if canImport(MediaPipeTasksVision)
  private static func makeMPImage(cgImage: CGImage) throws -> MPImage {
    #if canImport(UIKit)
    return try MPImage(uiImage: UIImage(cgImage: cgImage))
    #else
    throw NSError(domain: "rust_image", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unsupported platform for MPImage"])
    #endif
  }

  private static func detectLandmarks(
    cgImage: CGImage,
    modelPath: String,
    width: Int,
    height: Int
  ) throws -> [(x: Float, y: Float, z: Float)] {
    let landmarker = try FaceLandmarker(modelPath: modelPath)
    let mpImage = try makeMPImage(cgImage: cgImage)
    let result = try landmarker.detect(image: mpImage)
    guard let face = result.faceLandmarks.first else { return [] }

    return face.map { lm in
      (
        x: Float(lm.x),
        y: Float(lm.y),
        z: Float(lm.z)
      )
    }
  }

  private static func segmentSelfie(
    cgImage: CGImage,
    modelPath: String,
    width: Int,
    height: Int
  ) throws -> Data {
    let segmenterOptions = ImageSegmenterOptions()
    segmenterOptions.baseOptions = BaseOptions()
    segmenterOptions.baseOptions.modelAssetPath = modelPath
    segmenterOptions.runningMode = .image
    segmenterOptions.shouldOutputCategoryMask = true
    segmenterOptions.shouldOutputConfidenceMasks = false
    let segmenter = try ImageSegmenter(options: segmenterOptions)
    let mpImage = try makeMPImage(cgImage: cgImage)
    let result = try segmenter.segment(image: mpImage)
    guard let mask = result.categoryMask else {
      return Data(repeating: 0, count: width * height)
    }
    let w = mask.width
    let h = mask.height
    var out = Data(count: width * height)
    out.withUnsafeMutableBytes { dstRaw in
      guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
      for y in 0..<height {
        let sy = y * h / height
        for x in 0..<width {
          let sx = x * w / width
          let idx = sy * w + sx
          let v = mask.uint8Data[idx]
          dst[y * width + x] = v > 0 ? 255 : 0
        }
      }
    }
    return out
  }
  #endif

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
}

#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif
