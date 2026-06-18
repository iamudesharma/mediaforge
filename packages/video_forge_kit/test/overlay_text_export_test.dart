import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge/video_forge.dart' as vf;
import 'package:video_forge_kit/src/compositor/video_text_overlay_style.dart';
import 'package:video_forge_kit/src/compositor/video_text_presets.dart';
import 'package:video_forge_kit/src/export/overlay_text_export.dart';

void main() {
  test('typewriter maps to typewriter content animation', () {
    final data = OverlayTextExport.fromSpec(
      label: 'Hello',
      style: VideoTextOverlayStyle.defaults.copyWith(
        animation: VideoTextAnimation.typewriter,
      ),
      anchor: const Offset(0.5, 0.5),
      videoWidth: 1080,
      videoHeight: 1920,
    );
    expect(data.contentAnimation, vf.TextContentAnimation.typewriter);
    expect(data.contentAnimationDurationMs, greaterThan(BigInt.zero));
  });

  test('signature script preset uses character stagger', () {
    final data = OverlayTextExport.fromSpec(
      label: 'Hello',
      style: VideoTextOverlayStyle.defaults.copyWith(
        lookPreset: VideoTextLookPreset.signature,
        animation: VideoTextAnimation.typewriter,
      ),
      anchor: const Offset(0.5, 0.5),
      videoWidth: 1080,
      videoHeight: 1920,
    );
    expect(data.contentAnimation, vf.TextContentAnimation.characterStagger);
  });

  test('maps Flutter text align to export enum', () {
    final data = OverlayTextExport.fromSpec(
      label: 'Hi',
      style: VideoTextOverlayStyle.defaults.copyWith(
        textAlign: TextAlign.right,
      ),
      anchor: const Offset(0.5, 0.5),
      videoWidth: 1080,
      videoHeight: 1920,
    );
    expect(data.textAlign, vf.TextAlign.right);
  });
}
