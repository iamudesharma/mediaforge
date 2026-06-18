import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_forge/video_forge.dart' as vf;

import '../compositor/video_overlay_item.dart';
import '../compositor/video_text_presets.dart';
import '../models/compression_preset.dart';
import 'overlay_effects_export.dart';
import 'overlay_text_export.dart';
import 'overlay_transform_tracks.dart';

/// Rasterizes Flutter [VideoOverlayItem] widgets for Rust burn-in export.
///
/// Text overlays use vector [OverlayContent.text] (v2).
/// Stickers/emojis use baked PNG [OverlayContent.image].
class OverlayRasterExporter {
  OverlayRasterExporter._();

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

  static Future<List<vf.BurnInOverlay>> rasterizeForExport({
    required List<VideoOverlayItem> overlays,
    required int sourceWidth,
    required int sourceHeight,
    required CompressionPreset preset,
  }) async {
    if (overlays.isEmpty) return const [];

    final dir = await Directory.systemTemp.createTemp('vfp_overlay_burn_');
    final baked = <vf.BurnInOverlay>[];

    for (var i = 0; i < overlays.length; i++) {
      final item = overlays[i];
      final spec = item.resolvedTextSpec;
      final transform = spec != null
          ? OverlayTransformTracks.forOverlay(
              style: spec.style,
              fadeInMs: item.fadeInMs,
              fadeOutMs: item.fadeOutMs,
              visibleDurationMs: item.durationMs,
            )
          : _fadeTracks(item);
      final effects = spec != null
          ? OverlayEffectsExport.forStyle(spec.style)
          : const vf.OverlayEffects(effects: []);

      final vf.OverlayContent content;
      if (spec != null) {
        content = vf.OverlayContent.text(
          OverlayTextExport.fromSpec(
            label: spec.label,
            style: spec.style,
            anchor: item.anchor,
            videoWidth: sourceWidth,
            videoHeight: sourceHeight,
          ),
        );
        debugPrint(
          '[OverlayExport] text id=${item.id} anim=${spec.style.animation} '
          'content=${spec.style.animation == VideoTextAnimation.typewriter}',
        );
      } else {
        final path = '${dir.path}/overlay_$i.png';
        final png = await _captureOverlayPng(item.child);
        await File(path).writeAsBytes(png, flush: true);
        content = vf.OverlayContent.image(
          vf.ImageOverlayData(
            path: path,
            anchorX: item.anchor.dx,
            anchorY: item.anchor.dy,
          ),
        );
        debugPrint('[OverlayExport] image id=${item.id} path=$path');
      }

      baked.add(
        vf.BurnInOverlay(
          content: content,
          startMs: BigInt.from(item.startMs),
          endMs: BigInt.from(item.endMs),
          transform: transform,
          effects: effects,
        ),
      );
    }

    return baked;
  }

  static vf.TransformTracks _fadeTracks(VideoOverlayItem item) {
    return vf.TransformTracks(
      tracks: [
        if (item.fadeInMs > 0)
          vf.AnimationTrack(
            property: vf.TransformProperty.opacity,
            from: 0,
            to: 1,
            startMs: BigInt.zero,
            durationMs: BigInt.from(item.fadeInMs),
            easing: vf.Easing.linear,
          ),
        if (item.fadeOutMs > 0 && item.durationMs > item.fadeOutMs)
          vf.AnimationTrack(
            property: vf.TransformProperty.opacity,
            from: 1,
            to: 0,
            startMs: BigInt.from(item.durationMs - item.fadeOutMs),
            durationMs: BigInt.from(item.fadeOutMs),
            easing: vf.Easing.linear,
          ),
      ],
    );
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
