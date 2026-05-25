import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:rust_image/src/rust_image_editor.dart';

import '../models/operation_profile.dart';
import 'filter_descriptor.dart';

/// Long-lived isolate for Rust image work so the UI thread stays responsive.
abstract final class RustWorker {
  static SendPort? _commands;
  static Isolate? _isolate;
  static int _requestId = 0;
  static final Map<int, Completer<Object?>> _pending = {};
  static ReceivePort? _replyPort;

  static Future<void> ensureStarted() async {
    if (_commands != null) return;

    _replyPort = ReceivePort();
    _replyPort!.listen((raw) {
      final id = raw[0] as int;
      final result = raw[1];
      _pending.remove(id)?.complete(result);
    });

    final initPort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateMain, initPort.sendPort);
    _commands = await initPort.first as SendPort;
    initPort.close();
  }

  static Future<T> _request<T>(Object message) async {
    await ensureStarted();
    final id = ++_requestId;
    final completer = Completer<Object?>();
    _pending[id] = completer;

    _commands!.send([id, message, _replyPort!.sendPort]);

    final result = await completer.future;
    if (result is String && result.startsWith('error:')) {
      throw StateError(result.substring(6));
    }
    return result as T;
  }

  static Future<Uint8List> filterBytes({
    required Uint8List bytes,
    required FilterDescriptor filter,
    required OutputFormat format,
    required int quality,
  }) {
    return _request<Uint8List>([
      'filterBytes',
      TransferableTypedData.fromList([bytes]),
      filter.kind,
      filter.params,
      format.index,
      quality,
    ]);
  }

  /// Replay [ops] on [base] (Sprint 3 edit graph). Optional JPEG for legacy preview.
  static Future<
      ({
        RgbaImageBuffer buffer,
        Uint8List? preview,
        OperationProfile? profile,
      })> replayEditPipeline({
    required RgbaImageBuffer base,
    required List<EditOp> ops,
    required ProcessingBackend backend,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = false,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'replayEditPipeline',
      base.width,
      base.height,
      TransferableTypedData.fromList([base.pixels]),
      ops,
      backend.index,
      previewMaxEdge,
      previewQuality,
      encodePreviewJpeg,
    ]);
    OperationProfile? profile;
    if (raw.containsKey('filter_ms')) {
      profile = OperationProfile(
        totalMs: (raw['total_ms'] as num?)?.toInt() ?? 0,
        filterMs: (raw['filter_ms'] as num).toInt(),
        previewEncodeMs: (raw['preview_ms'] as num?)?.toInt() ?? 0,
        executionPath: raw['path'] as String? ?? '',
      );
    }
    final previewPayload = raw['preview'];
    return (
      buffer: _bufferFromPayload(raw),
      preview: previewPayload == null
          ? null
          : _bytesFromPayload(previewPayload),
      profile: profile,
    );
  }

  /// Full-resolution replay for export (no preview JPEG).
  static Future<RgbaImageBuffer> applyEditPipelineFull({
    required RgbaImageBuffer base,
    required List<EditOp> ops,
    required ProcessingBackend backend,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'applyEditPipelineFull',
      base.width,
      base.height,
      TransferableTypedData.fromList([base.pixels]),
      ops,
      backend.index,
    ]);
    return _bufferFromPayload(raw);
  }

  static Future<
      ({
        RgbaImageBuffer buffer,
        Uint8List? preview,
        OperationProfile? profile,
      })> filterRgba({
    required RgbaImageBuffer buffer,
    required FilterDescriptor filter,
    required ProcessingBackend backend,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'filterRgba',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      filter.kind,
      filter.params,
      backend.index,
      previewMaxEdge,
      previewQuality,
      encodePreviewJpeg,
    ]);
    OperationProfile? profile;
    if (raw.containsKey('filter_ms')) {
      profile = OperationProfile(
        totalMs: (raw['total_ms'] as num?)?.toInt() ?? 0,
        filterMs: (raw['filter_ms'] as num).toInt(),
        previewEncodeMs: (raw['preview_ms'] as num).toInt(),
        executionPath: raw['path'] as String? ?? '',
      );
    }
    final previewPayload = raw['preview'];
    return (
      buffer: _bufferFromPayload(raw),
      preview: previewPayload == null
          ? null
          : _bytesFromPayload(previewPayload),
      profile: profile,
    );
  }

  static Future<Uint8List> encodePreview({
    required RgbaImageBuffer buffer,
    required int previewMaxEdge,
    required int quality,
  }) {
    return _request<Uint8List>([
      'encodePreview',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      previewMaxEdge,
      quality,
    ]);
  }

  /// Full-resolution encode for export (runs in worker isolate).
  static Future<Uint8List> encodeFullRgba({
    required RgbaImageBuffer buffer,
    required OutputFormat format,
    required int quality,
  }) {
    return _request<Uint8List>([
      'encodeFullRgba',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      format.index,
      quality,
    ]);
  }

  static Future<String> blurHashEncode(Uint8List bytes) {
    return _request<String>([
      'blurHashEncode',
      TransferableTypedData.fromList([bytes]),
    ]);
  }

  static Future<
      ({
        RgbaImageBuffer previewRgba,
        RgbaImageBuffer buffer,
        ImageInfo info,
      })> decodeProgressive({
    required Uint8List bytes,
    int previewMaxEdge = 200,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'decodeProgressive',
      TransferableTypedData.fromList([bytes]),
      previewMaxEdge,
    ]);
    final previewRgba = RgbaImageBuffer(
      width: raw['preview_width']! as int,
      height: raw['preview_height']! as int,
      pixels: _bytesFromPayload(raw['preview_rgba']!),
    );
    return (
      previewRgba: previewRgba,
      buffer: _bufferFromPayload(raw),
      info: ImageInfo(
        width: raw['info_width']! as int,
        height: raw['info_height']! as int,
        format: raw['info_format'] as String?,
      ),
    );
  }

  static Future<Uint8List> batchResizeDemo({
    required Uint8List bytes,
    required ProcessingBackend backend,
  }) {
    return _request<Uint8List>([
      'batchResizeDemo',
      TransferableTypedData.fromList([bytes]),
      backend.index,
    ]);
  }

  static Future<({RgbaImageBuffer buffer, Uint8List preview})> resizeRgba({
    required RgbaImageBuffer buffer,
    required int width,
    required int height,
    required ProcessingBackend backend,
    required int previewMaxEdge,
    required int previewQuality,
    ResizeAlgorithm algorithm = ResizeAlgorithm.lanczos3,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'resizeRgba',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      width,
      height,
      algorithm.index,
      backend.index,
      previewMaxEdge,
      previewQuality,
    ]);
    return (
      buffer: _bufferFromPayload(raw),
      preview: _bytesFromPayload(raw['preview']!),
    );
  }

  /// Heavy byte-path ops off the UI thread (compress, crop, resize, …).
  static Future<Uint8List> bytesTransform({
    required Uint8List bytes,
    required String op,
    required Map<String, Object?> params,
  }) {
    return _request<Uint8List>([
      'bytesTransform',
      op,
      TransferableTypedData.fromList([bytes]),
      params,
    ]);
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> drawLine({
    required RgbaImageBuffer buffer,
    required DrawLine line,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'drawLine',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      line.x0,
      line.y0,
      line.x1,
      line.y1,
      line.colorR,
      line.colorG,
      line.colorB,
      line.colorA,
      previewMaxEdge,
      previewQuality,
      encodePreviewJpeg,
    ]);
    final previewPayload = raw['preview'];
    return (
      buffer: _bufferFromPayload(raw),
      preview: previewPayload == null
          ? null
          : _bytesFromPayload(previewPayload),
    );
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> drawCircle({
    required RgbaImageBuffer buffer,
    required DrawCircle circle,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'drawCircle',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      circle.centerX,
      circle.centerY,
      circle.radius,
      circle.colorR,
      circle.colorG,
      circle.colorB,
      circle.colorA,
      previewMaxEdge,
      previewQuality,
      encodePreviewJpeg,
    ]);
    final previewPayload = raw['preview'];
    return (
      buffer: _bufferFromPayload(raw),
      preview: previewPayload == null
          ? null
          : _bytesFromPayload(previewPayload),
    );
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> drawText({
    required RgbaImageBuffer buffer,
    required TextOverlay overlay,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'drawText',
      buffer.width,
      buffer.height,
      TransferableTypedData.fromList([buffer.pixels]),
      overlay.text,
      overlay.x,
      overlay.y,
      overlay.fontSize,
      overlay.colorR,
      overlay.colorG,
      overlay.colorB,
      overlay.colorA,
      previewMaxEdge,
      previewQuality,
      encodePreviewJpeg,
    ]);
    final previewPayload = raw['preview'];
    return (
      buffer: _bufferFromPayload(raw),
      preview: previewPayload == null
          ? null
          : _bytesFromPayload(previewPayload),
    );
  }

  static Future<({RgbaImageBuffer buffer, Uint8List? preview})> overlayComposite({
    required RgbaImageBuffer base,
    required Uint8List overlayBytes,
    required int x,
    required int y,
    required BlendMode blendMode,
    required int previewMaxEdge,
    required int previewQuality,
    bool encodePreviewJpeg = true,
  }) async {
    final raw = await _request<Map<String, Object>>([
      'overlayRgba',
      base.width,
      base.height,
      TransferableTypedData.fromList([base.pixels]),
      TransferableTypedData.fromList([overlayBytes]),
      x,
      y,
      blendMode.index,
      previewMaxEdge,
      previewQuality,
      encodePreviewJpeg,
    ]);
    final previewPayload = raw['preview'];
    return (
      buffer: _bufferFromPayload(raw),
      preview: previewPayload == null
          ? null
          : _bytesFromPayload(previewPayload),
    );
  }

  static Future<RgbaImageBuffer> decodeRgba(Uint8List bytes) async {
    final raw = await _request<Map<String, Object>>([
      'decodeRgba',
      TransferableTypedData.fromList([bytes]),
    ]);
    return _bufferFromPayload(raw);
  }

  static RgbaImageBuffer _bufferFromPayload(Map<String, Object> raw) {
    return RgbaImageBuffer(
      width: raw['width']! as int,
      height: raw['height']! as int,
      pixels: _bytesFromPayload(raw['pixels']!),
    );
  }

  static Uint8List _bytesFromPayload(Object payload) {
    return (payload as TransferableTypedData).materialize().asUint8List();
  }

  static Future<void> shutdown() async {
    if (_commands == null) return;
    try {
      await _request<void>('shutdown');
    } catch (_) {}
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
    _replyPort?.close();
    _replyPort = null;
  }
}

const _coalesceOps = {'replayEditPipeline', 'filterRgba', 'overlayRgba'};

@pragma('vm:entry-point')
Future<void> _isolateMain(SendPort mainSendPort) async {
  await RustLib.init();

  final commands = ReceivePort();
  mainSendPort.send(commands.sendPort);

  List<Object?>? _coalescePending;
  var _coalesceBusy = false;

  Future<void> _drainCoalesce() async {
    if (_coalesceBusy) return;
    _coalesceBusy = true;
    while (_coalescePending != null) {
      final raw = _coalescePending!;
      _coalescePending = null;
      final id = raw[0] as int;
      final message = raw[1];
      final replyTo = raw[2] as SendPort;
      try {
        final result = await _handleMessage(message as Object);
        replyTo.send([id, result]);
      } catch (e, st) {
        debugPrint('RustWorker error: $e\n$st');
        replyTo.send([id, 'error:$e']);
      }
    }
    _coalesceBusy = false;
  }

  void _enqueueCoalesce(List<Object?> raw) {
    _coalescePending = raw;
    scheduleMicrotask(_drainCoalesce);
  }

  await for (final raw in commands) {
    final id = raw[0] as int;
    final message = raw[1];
    final replyTo = raw[2] as SendPort;

    try {
      if (message == 'shutdown') {
        replyTo.send([id, null]);
        break;
      }
      if (message is List && _coalesceOps.contains(message[0])) {
        _enqueueCoalesce(raw);
        continue;
      }
      final result = await _handleMessage(message);
      replyTo.send([id, result]);
    } catch (e, st) {
      debugPrint('RustWorker error: $e\n$st');
      replyTo.send([id, 'error:$e']);
    }
  }
}

Future<Object?> _handleMessage(Object message) async {
  if (message is! List) return null;
  final op = message[0] as String;

  switch (op) {
    case 'filterBytes':
      final bytes = message[1] as TransferableTypedData;
      final filter = FilterDescriptor(
        message[2] as String,
        Map<String, num>.from(message[3] as Map),
      );
      final format = OutputFormat.values[message[4] as int];
      final quality = message[5] as int;
      return RustImageEditor.filter(
        bytes: bytes.materialize().asUint8List(),
        filter: filter.toImageFilter(),
        format: format,
        quality: quality,
      );

    case 'filterRgba':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final filter = FilterDescriptor(
        message[4] as String,
        Map<String, num>.from(message[5] as Map),
      );
      final backend = ProcessingBackend.values[message[6] as int];
      final previewMaxEdge = message[7] as int;
      final previewQuality = message[8] as int;
      final encodePreviewJpeg = message[9] as bool;

      final total = Stopwatch()..start();
      var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      final filterSw = Stopwatch()..start();
      buffer = RustImageEditor.filterRgba(
        buffer,
        filter.toImageFilter(),
        backend: backend,
      );
      final filterMs = filterSw.elapsedMilliseconds;
      var previewMs = 0;
      TransferableTypedData? previewTd;
      if (encodePreviewJpeg) {
        final previewSw = Stopwatch()..start();
        final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
        previewMs = previewSw.elapsedMilliseconds;
        previewTd = TransferableTypedData.fromList([preview]);
      }
      final path = RustImageEditor.filterExecutionPath(
        filter.toImageFilter(),
        backend,
      );
      return {
        'width': buffer.width,
        'height': buffer.height,
        'pixels': TransferableTypedData.fromList([buffer.pixels]),
        if (previewTd != null) 'preview': previewTd,
        'filter_ms': filterMs,
        'preview_ms': previewMs,
        'path': path,
        'total_ms': total.elapsedMilliseconds,
      };

    case 'replayEditPipeline':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final ops = (message[4] as List).cast<EditOp>();
      final backend = ProcessingBackend.values[message[5] as int];
      final previewMaxEdge = message[6] as int;
      final previewQuality = message[7] as int;
      final encodePreviewJpeg = message[8] as bool;

      final total = Stopwatch()..start();
      var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      final filterSw = Stopwatch()..start();
      if (ops.isNotEmpty) {
        buffer = RustImageEditor.applyEditGraph(
          buffer,
          ops,
          backend: backend,
        );
      }
      final filterMs = filterSw.elapsedMilliseconds;
      var previewMs = 0;
      TransferableTypedData? previewTd;
      if (encodePreviewJpeg) {
        final previewSw = Stopwatch()..start();
        final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
        previewMs = previewSw.elapsedMilliseconds;
        previewTd = TransferableTypedData.fromList([preview]);
      }
      return {
        'width': buffer.width,
        'height': buffer.height,
        'pixels': TransferableTypedData.fromList([buffer.pixels]),
        if (previewTd != null) 'preview': previewTd,
        'filter_ms': filterMs,
        'preview_ms': previewMs,
        'path': ops.isEmpty ? '' : 'pipeline',
        'total_ms': total.elapsedMilliseconds,
      };

    case 'applyEditPipelineFull':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final ops = (message[4] as List).cast<EditOp>();
      final backend = ProcessingBackend.values[message[5] as int];
      var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      if (ops.isNotEmpty) {
        buffer = RustImageEditor.applyEditGraph(
          buffer,
          ops,
          backend: backend,
        );
      }
      return {
        'width': buffer.width,
        'height': buffer.height,
        'pixels': TransferableTypedData.fromList([buffer.pixels]),
      };

    case 'overlayRgba':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final overlayBytes =
          (message[4] as TransferableTypedData).materialize().asUint8List();
      final x = message[5] as int;
      final y = message[6] as int;
      final blend = BlendMode.values[message[7] as int];
      final previewMaxEdge = message[8] as int;
      final previewQuality = message[9] as int;
      final encodePreviewJpeg = message[10] as bool;

      var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      buffer = RustImageEditor.overlayRgba(
        buffer,
        overlayBytes,
        x: x,
        y: y,
        blendMode: blend,
      );
      TransferableTypedData? previewTd;
      if (encodePreviewJpeg) {
        final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
        previewTd = TransferableTypedData.fromList([preview]);
      }
      return {
        'width': buffer.width,
        'height': buffer.height,
        'pixels': TransferableTypedData.fromList([buffer.pixels]),
        if (previewTd != null) 'preview': previewTd,
      };

    case 'decodeRgba':
      final bytes = (message[1] as TransferableTypedData).materialize().asUint8List();
      final decoded = RustImageEditor.decodeToRgba(bytes, fixExif: true);
      return {
        'width': decoded.width,
        'height': decoded.height,
        'pixels': TransferableTypedData.fromList([decoded.pixels]),
      };

    case 'drawLine':
      return _drawOp(
        message,
        (buffer, line) => RustImageEditor.drawLineRgba(buffer, line: line),
        DrawLine(
          x0: message[4] as int,
          y0: message[5] as int,
          x1: message[6] as int,
          y1: message[7] as int,
          colorR: message[8] as int,
          colorG: message[9] as int,
          colorB: message[10] as int,
          colorA: message[11] as int,
        ),
        message[12] as int,
        message[13] as int,
        message[14] as bool,
      );

    case 'drawCircle':
      return _drawOp(
        message,
        (buffer, circle) => RustImageEditor.drawCircleRgba(buffer, circle: circle),
        DrawCircle(
          centerX: message[4] as int,
          centerY: message[5] as int,
          radius: message[6] as int,
          colorR: message[7] as int,
          colorG: message[8] as int,
          colorB: message[9] as int,
          colorA: message[10] as int,
        ),
        message[11] as int,
        message[12] as int,
        message[13] as bool,
      );

    case 'drawText':
      return _drawOp(
        message,
        (buffer, overlay) => RustImageEditor.drawTextRgba(buffer, overlay: overlay),
        TextOverlay(
          text: message[4] as String,
          x: message[5] as int,
          y: message[6] as int,
          fontSize: message[7] as double,
          colorR: message[8] as int,
          colorG: message[9] as int,
          colorB: message[10] as int,
          colorA: message[11] as int,
        ),
        message[12] as int,
        message[13] as int,
        message[14] as bool,
      );

    case 'encodePreview':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final previewMaxEdge = message[4] as int;
      final quality = message[5] as int;
      final buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      return _encodePreviewBuffer(buffer, previewMaxEdge, quality);

    case 'encodeFullRgba':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final format = OutputFormat.values[message[4] as int];
      final quality = message[5] as int;
      final buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      return RustImageEditor.encodeRgba(
        buffer,
        format: format,
        quality: quality,
      );

    case 'bytesTransform':
      final transformOp = message[1] as String;
      final bytes = (message[2] as TransferableTypedData).materialize().asUint8List();
      final params = Map<String, Object?>.from(message[3] as Map);
      return _bytesTransform(bytes, transformOp, params);

    case 'blurHashEncode':
      final bytes = (message[1] as TransferableTypedData).materialize().asUint8List();
      return RustImageEditor.blurHashEncode(bytes);

    case 'decodeProgressive':
      final bytes = (message[1] as TransferableTypedData).materialize().asUint8List();
      final previewMaxEdge = message[2] as int;
      final prog = RustImageEditor.decodeProgressive(
        bytes,
        previewMaxEdge: previewMaxEdge,
        fixExif: true,
      );
      return {
        'width': prog.buffer.width,
        'height': prog.buffer.height,
        'pixels': TransferableTypedData.fromList([prog.buffer.pixels]),
        'preview_rgba': TransferableTypedData.fromList([prog.previewRgba.pixels]),
        'preview_width': prog.previewRgba.width,
        'preview_height': prog.previewRgba.height,
        'info_width': prog.info.width,
        'info_height': prog.info.height,
        'info_format': prog.info.format,
      };

    case 'batchResizeDemo':
      final bytes = (message[1] as TransferableTypedData).materialize().asUint8List();
      final backend = ProcessingBackend.values[message[2] as int];
      final out = RustImageEditor.batchResize(
        items: [
          BatchResizeItem(bytes: bytes, width: 256, height: 256),
          BatchResizeItem(bytes: bytes, width: 512, height: 512),
        ],
        backend: backend,
      );
      return out.last;

    case 'resizeRgba':
      final width = message[1] as int;
      final height = message[2] as int;
      final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
      final targetW = message[4] as int;
      final targetH = message[5] as int;
      final algorithm = ResizeAlgorithm.values[message[6] as int];
      final backend = ProcessingBackend.values[message[7] as int];
      final previewMaxEdge = message[8] as int;
      final previewQuality = message[9] as int;
      var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
      buffer = RustImageEditor.resizeRgba(
        buffer,
        width: targetW,
        height: targetH,
        algorithm: algorithm,
        backend: backend,
      );
      final preview = _encodePreviewBuffer(buffer, previewMaxEdge, previewQuality);
      return {
        'width': buffer.width,
        'height': buffer.height,
        'pixels': TransferableTypedData.fromList([buffer.pixels]),
        'preview': TransferableTypedData.fromList([preview]),
      };

    default:
      throw UnsupportedError('Unknown op: $op');
  }
}

Map<String, Object> _drawOp<T>(
  List<Object?> message,
  RgbaImageBuffer Function(RgbaImageBuffer buffer, T param) draw,
  T param,
  int previewMaxEdge,
  int previewQuality,
  bool encodePreviewJpeg,
) {
  final width = message[1] as int;
  final height = message[2] as int;
  final pixels = (message[3] as TransferableTypedData).materialize().asUint8List();
  var buffer = RgbaImageBuffer(width: width, height: height, pixels: pixels);
  buffer = draw(buffer, param);
  TransferableTypedData? previewTd;
  if (encodePreviewJpeg) {
    final preview = RustImageEditor.encodeRgbaPreview(
      buffer,
      maxEdge: previewMaxEdge,
      quality: previewQuality,
    );
    previewTd = TransferableTypedData.fromList([preview]);
  }
  return {
    'width': buffer.width,
    'height': buffer.height,
    'pixels': TransferableTypedData.fromList([buffer.pixels]),
    if (previewTd != null) 'preview': previewTd,
  };
}

Uint8List _bytesTransform(
  Uint8List bytes,
  String op,
  Map<String, Object?> params,
) {
  switch (op) {
    case 'compress':
      return RustImageEditor.compress(
        bytes: bytes,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'resize':
      return RustImageEditor.resize(
        bytes: bytes,
        width: params['width']! as int,
        height: params['height']! as int,
        algorithm: ResizeAlgorithm.values[params['algorithm']! as int],
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
        backend: ProcessingBackend.values[params['backend']! as int],
      );
    case 'thumbnail':
      return RustImageEditor.thumbnail(
        bytes: bytes,
        maxEdge: params['maxEdge']! as int,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
        backend: ProcessingBackend.values[params['backend']! as int],
      );
    case 'crop':
      return RustImageEditor.crop(
        bytes: bytes,
        x: params['x']! as int,
        y: params['y']! as int,
        width: params['width']! as int,
        height: params['height']! as int,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'rotate':
      return RustImageEditor.rotate(
        bytes: bytes,
        rotation: Rotation.values[params['rotation']! as int],
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'fixExif':
      return RustImageEditor.fixExif(
        bytes: bytes,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    case 'blurHashDecode':
      return RustImageEditor.blurHashDecode(
        hash: params['hash']! as String,
        width: params['width']! as int,
        height: params['height']! as int,
        format: OutputFormat.values[params['format']! as int],
        quality: params['quality']! as int,
      );
    default:
      throw UnsupportedError('bytesTransform: $op');
  }
}

Uint8List _encodePreviewBuffer(RgbaImageBuffer buffer, int previewMaxEdge, int quality) {
  var b = buffer;
  final maxDim = b.width > b.height ? b.width : b.height;
  if (maxDim > previewMaxEdge) {
    final scale = previewMaxEdge / maxDim;
    final w = (b.width * scale).round().clamp(1, b.width);
    final h = (b.height * scale).round().clamp(1, b.height);
    b = RustImageEditor.resizeRgba(
      b,
      width: w,
      height: h,
      algorithm: ResizeAlgorithm.box,
      backend: ProcessingBackend.cpu,
    );
  }
  return RustImageEditor.encodeRgbaPreview(
    b,
    maxEdge: previewMaxEdge,
    quality: quality,
  );
}
