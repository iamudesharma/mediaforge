import CoreGraphics
import Foundation

#if canImport(FlutterMacOS)
import FlutterMacOS
#else
import Flutter
#endif

/// Decode Flutter channel payloads into CGImage (Rust RGBA8888 + encoded stills).
enum RustImageImageDecode {
  static func dataFromChannel(_ value: Any?) -> Data? {
    if let typed = value as? FlutterStandardTypedData {
      return typed.data
    }
    if let data = value as? Data {
      return data
    }
    if let list = value as? [UInt8] {
      return Data(list)
    }
    return nil
  }

  /// Rust / Dart preview buffers are RGBA8888, top-left origin.
  static func cgImageFromRgba(_ data: Data, width: Int, height: Int) -> CGImage? {
    let expected = width * height * 4
    guard width > 0, height > 0, data.count >= expected else { return nil }

    var pixels = Data(count: expected)
    pixels.withUnsafeMutableBytes { dst in
      guard let dstBase = dst.baseAddress else { return }
      data.withUnsafeBytes { src in
        guard let srcBase = src.baseAddress else { return }
        memcpy(dstBase, srcBase, expected)
      }
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    return pixels.withUnsafeMutableBytes { raw -> CGImage? in
      guard let base = raw.baseAddress else { return nil }
      guard let ctx = CGContext(
        data: base,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return nil }
      return ctx.makeImage()
    }
  }

  static func cgImageFromEncoded(_ data: Data) -> CGImage? {
    #if canImport(UIKit)
    guard let img = UIImage(data: data) else { return nil }
    return img.cgImage
    #elseif canImport(AppKit)
    guard let img = NSImage(data: data) else { return nil }
    var rect = CGRect(origin: .zero, size: img.size)
    return img.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    #else
    return nil
    #endif
  }

  static func cgImage(
    from data: Data,
    pixelFormat: String,
    width: Int,
    height: Int
  ) -> CGImage? {
    if pixelFormat == "rgba" {
      return cgImageFromRgba(data, width: width, height: height)
    }
    return cgImageFromEncoded(data)
  }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
