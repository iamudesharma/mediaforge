import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_processor_core/video_processor_core.dart';

import '../compositor/video_overlay_item.dart';
import '../models/compression_preset.dart';

/// Rasterizes Flutter [VideoOverlayItem] widgets to PNGs for Rust burn-in export.
class OverlayRasterExporter {
  OverlayRasterExporter._();

  /// Max longest edge used when scaling overlay bake size to match encode output.
  static int maxEncodeEdgeForPreset(CompressionPreset preset) => switch (preset) {
        CompressionPreset.whatsapp => 720,
        CompressionPreset.lowBandwidth => 720,
        CompressionPreset.telegram => 1280,
        CompressionPreset.standard => 1080,
        CompressionPreset.instagram => 1080,
        CompressionPreset.youtube => 1080,
        CompressionPreset.lossless => 2160,
      };

  static (int width, int height) encodeDimensions({
    required int sourceWidth,
    required int sourceHeight,
    required int maxEdge,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return (maxEdge, maxEdge);
    }
    final maxDim = sourceWidth > sourceHeight ? sourceWidth : sourceHeight;
    if (maxDim <= maxEdge) {
      return (sourceWidth, sourceHeight);
    }
    final scale = maxEdge / maxDim;
    return (
      (sourceWidth * scale).round().clamp(2, 8192),
      (sourceHeight * scale).round().clamp(2, 8192),
    );
  }

  /// Bakes [overlays] to temp PNGs and returns FRB [BurnInOverlay] descriptors.
  static Future<List<BurnInOverlay>> rasterizeForExport({
    required List<VideoOverlayItem> overlays,
    required int sourceWidth,
    required int sourceHeight,
    required CompressionPreset preset,
  }) async {
    if (overlays.isEmpty) return const [];

    final dir = await Directory.systemTemp.createTemp('vfp_overlay_burn_');
    final baked = <BurnInOverlay>[];

    for (var i = 0; i < overlays.length; i++) {
      final item = overlays[i];
      final path = '${dir.path}/overlay_$i.png';
      final png = await _captureOverlayPng(item.child);
      await File(path).writeAsBytes(png, flush: true);
      baked.add(
        BurnInOverlay(
          imagePath: path,
          startMs: BigInt.from(item.startMs),
          endMs: BigInt.from(item.endMs),
          anchorX: item.anchor.dx,
          anchorY: item.anchor.dy,
          fadeInMs: BigInt.from(item.fadeInMs),
          fadeOutMs: BigInt.from(item.fadeOutMs),
        ),
      );
    }

    return baked;
  }

  static Future<Uint8List> _captureOverlayPng(Widget child) async {
    WidgetsFlutterBinding.ensureInitialized();
    final view = ui.PlatformDispatcher.instance.views.first;

    const maxW = 900.0;
    const maxH = 700.0;

    final repaintBoundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaintBoundary,
      ),
      configuration: ViewConfiguration(
        physicalConstraints: const BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
        ),
        logicalConstraints: const BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
        ),
        devicePixelRatio: 1.0,
      ),
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(maxW, maxH)),
          child: Material(
            type: MaterialType.transparency,
            child: child,
          ),
        ),
      ),
    );
    final element = root.attachToRenderTree(buildOwner);
    buildOwner
      ..buildScope(element)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final image = await repaintBoundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (bytes == null) {
      throw StateError('Failed to encode overlay PNG');
    }
    return bytes.buffer.asUint8List();
  }
}
