// In-memory fixture generators for `rust_image` integration tests.
//
// All fixtures use `dart:ui` to render tiny images directly into PNG bytes —
// no asset shipping, no disk IO. They are intentionally cheap so they can be
// re-used across `setUpAll` blocks, but tests should still cache them in a
// `late` field rather than regenerating per-test.
//
// IMPORTANT: [tinyJpeg] re-encodes through `RustImageEditor.compress`, so the
// FRB bridge MUST be initialized before calling it. A test setUpAll should
// call:
//
//     IntegrationTestWidgetsFlutterBinding.ensureInitialized();
//     await RustImageEditor.ensureInitialized();
//
// before invoking [tinyJpeg]. [tinyPng] and [tinyOverlayPng] are pure
// `dart:ui`, so they do not need the Rust bridge — but the Flutter binding
// must still be live for the engine to service `picture.toImage`.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart' show Color;
import 'package:image_forge_editor/image_forge_editor.dart';

/// Renders a tiny `width × height` PNG with a deterministic colored gradient.
///
/// Output is a genuine PNG (RGBA, ZLIB-compressed) decodable by any image
/// library. Hue varies with `x` so the bytes change with `width`/`height`.
Future<Uint8List> tinyPng({int width = 64, int height = 48}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const Color(0xFF202428),
  );

  for (var x = 0; x < width; x++) {
    final t = x / (width - 1).clamp(1, 1 << 30);
    final r = (t * 255).round().clamp(0, 255);
    final g = ((1.0 - t) * 200 + 30).round().clamp(0, 255);
    final b = ((t * 0.5 + 0.25) * 255).round().clamp(0, 255);
    canvas.drawRect(
      ui.Rect.fromLTWH(x.toDouble(), 0, 1, height.toDouble()),
      ui.Paint()..color = Color.fromARGB(255, r, g, b),
    );
  }

  canvas.drawLine(
    const ui.Offset(0, 0),
    ui.Offset(width.toDouble(), height.toDouble()),
    ui.Paint()
      ..color = const Color(0xFF000000)
      ..strokeWidth = 1.0,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('toByteData(png) returned null');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

/// Produces a tiny JPEG by encoding [tinyPng] through the Rust compress path.
///
/// Requires `RustImageEditor.ensureInitialized()` to have been awaited.
Future<Uint8List> tinyJpeg({
  int width = 64,
  int height = 48,
  int quality = 85,
}) async {
  final png = await tinyPng(width: width, height: height);
  return RustImageEditor.compress(
    bytes: png,
    format: OutputFormat.jpeg,
    quality: quality,
  );
}

/// A tiny solid-color PNG with a contrasting inner square, suitable for use
/// as an overlay / watermark in BlendMode tests.
Future<Uint8List> tinyOverlayPng({int size = 24}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..color = const Color(0xFFE53935),
  );

  final inset = (size / 4).clamp(1, size.toDouble());
  canvas.drawRect(
    ui.Rect.fromLTWH(
      inset.toDouble(),
      inset.toDouble(),
      (size - 2 * inset).toDouble(),
      (size - 2 * inset).toDouble(),
    ),
    ui.Paint()..color = const Color(0xFFFFFFFF),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('toByteData(png) returned null');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}
