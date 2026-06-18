import 'package:flutter/material.dart' as material;
import 'package:video_forge/video_forge.dart' as vf;
import 'package:video_forge_kit/src/compositor/video_text_overlay_style.dart';
import 'package:video_forge_kit/src/compositor/video_text_presets.dart';

/// Maps Flutter text overlay specs to FRB [vf.TextOverlayData] for vector export.
class OverlayTextExport {
  OverlayTextExport._();

  static vf.TextOverlayData fromSpec({
    required String label,
    required VideoTextOverlayStyle style,
    required material.Offset anchor,
    required int videoWidth,
    required int videoHeight,
  }) {
    final maxWidthNorm = videoWidth > 0
        ? (style.maxWidth / videoWidth).clamp(0.1, 1.0)
        : 0.5;

    return vf.TextOverlayData(
      text: label,
      anchorX: anchor.dx,
      anchorY: anchor.dy,
      fontSize: style.fontSize,
      fontWeight: _fontWeightValue(style.fontWeight),
      italic: style.fontStyle == material.FontStyle.italic,
      colorR: style.color.red,
      colorG: style.color.green,
      colorB: style.color.blue,
      colorA: style.color.alpha,
      letterSpacing: style.letterSpacing,
      maxWidth: maxWidthNorm,
      padding: style.padding,
      cornerRadius: style.cornerRadius,
      showBackground: style.showBackground &&
          style.backgroundStyle != VideoTextBackgroundStyle.none,
      backgroundR: style.backgroundColor.red,
      backgroundG: style.backgroundColor.green,
      backgroundB: style.backgroundColor.blue,
      backgroundA: style.backgroundColor.alpha,
      glowIntensity: style.glowIntensity,
      textAlign: _mapTextAlign(style.textAlign),
      contentAnimation: _contentAnimation(style),
      contentAnimationDurationMs: BigInt.from(
        _contentDurationMs(style),
      ),
    );
  }

  static int _fontWeightValue(material.FontWeight w) {
    return switch (w) {
      material.FontWeight.w100 => 100,
      material.FontWeight.w200 => 200,
      material.FontWeight.w300 => 300,
      material.FontWeight.w400 => 400,
      material.FontWeight.w500 => 500,
      material.FontWeight.w600 => 600,
      material.FontWeight.w700 => 700,
      material.FontWeight.w800 => 800,
      material.FontWeight.w900 => 900,
      _ => 600,
    };
  }

  static vf.TextAlign _mapTextAlign(material.TextAlign align) {
    return switch (align) {
      material.TextAlign.left || material.TextAlign.start => vf.TextAlign.left,
      material.TextAlign.right || material.TextAlign.end => vf.TextAlign.right,
      _ => vf.TextAlign.center,
    };
  }

  static vf.TextContentAnimation _contentAnimation(VideoTextOverlayStyle style) {
    if (style.animation == VideoTextAnimation.typewriter &&
        style.lookPreset == VideoTextLookPreset.signature) {
      return vf.TextContentAnimation.characterStagger;
    }
    return switch (style.animation) {
      VideoTextAnimation.typewriter => vf.TextContentAnimation.typewriter,
      VideoTextAnimation.none ||
      VideoTextAnimation.popIn ||
      VideoTextAnimation.bounce ||
      VideoTextAnimation.fadeScale ||
      VideoTextAnimation.slideIn ||
      VideoTextAnimation.glitch =>
        vf.TextContentAnimation.none,
    };
  }

  static int _contentDurationMs(VideoTextOverlayStyle style) {
    final anim = _contentAnimation(style);
    if (anim == vf.TextContentAnimation.none) {
      return 0;
    }
    final scale = style.animationDurationScale.clamp(0.35, 2.5);
    final base = anim == vf.TextContentAnimation.characterStagger ? 1400 : 1200;
    return (base / scale).round().clamp(200, 8000);
  }
}
