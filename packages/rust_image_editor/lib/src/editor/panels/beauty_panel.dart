import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rust_image_core/rust_image_core.dart';

import '../crop_controller.dart';
import '../editor_session.dart';
import '../models/beauty_params.dart';
import '../services/beauty_exclude_mask.dart';
import '../services/beauty_look_names.dart';
import '../services/face_analysis_service.dart';
import 'package:rust_camera_runtime/rust_camera_runtime.dart';
import '../services/mediapipe_model_service.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/control_widgets.dart';

/// Nexus B/C — one-tap looks + regional fine-tune sliders.
class BeautyPanel extends StatefulWidget {
  const BeautyPanel({
    super.key,
    required this.session,
    this.stripHostedExternally = false,
  });

  final EditorSession session;
  final bool stripHostedExternally;

  @override
  State<BeautyPanel> createState() => _BeautyPanelState();
}

class _BeautyPanelState extends State<BeautyPanel> {
  late BeautyParams _params;
  BeautyLookPreset? _selectedLook;
  bool _fineTuneExpanded = false;

  EditorSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _syncFromSession();
    if (s.hasImage && s.faceAnalysis == null && !s.faceAnalyzing) {
      unawaited(s.analyzeFaceForBeauty());
    }
  }

  void _syncFromSession() {
    _params = s.committedBeautyParams ?? BeautyParamsX.zero;
    _selectedLook = s.committedBeautyLook;
  }

  String get _statusLabel {
    if (s.faceAnalyzing) return 'Analyzing face…';
    if (s.liveCameraActive) {
      final look = s.previewBeautyLook ?? s.committedBeautyLook;
      final params = s.liveActiveBeautyParams;
      if (params != null && params.hasEffect) {
        if (s.liveBeautyPending) {
          final name = look != null ? beautyLookLabel(look) : 'Beauty';
          return '$name · detecting face…';
        }
        if (look != null) return 'Live · ${beautyLookLabel(look)} active';
        return 'Live · beauty active';
      }
      if (!FaceAnalysisService.isAnalysisValid(s.faceAnalysis)) {
        return 'Live · point camera at your face';
      }
      return 'Live · pick a look below';
    }
    final analysis = s.faceAnalysis;
    if (analysis == null) return 'Tap Re-analyze after import';
    if (!FaceAnalysisService.isAnalysisValid(analysis)) {
      return 'No face detected';
    }
    final n = analysis.landmarks.length;
    return '$n landmarks · mask ready';
  }

  bool get _canPickLook =>
      (s.hasImage || s.liveCameraActive) && !s.busy && !s.faceAnalyzing;

  bool get _canFineTune =>
      _canPickLook &&
      s.skinMask != null &&
      FaceAnalysisService.isAnalysisValid(s.faceAnalysis);

  void _live(BeautyParams next, {bool clearLook = true}) {
    setState(() {
      _params = next;
      if (clearLook) _selectedLook = null;
    });
    s.setBeautyParams(next, livePreview: true);
  }

  void _commit() {
    s.cancelDebounced();
    s.setBeautyParams(_params, commit: true);
    setState(() => _selectedLook = s.committedBeautyLook);
  }

  Future<void> _applyLook(BeautyLookPreset look) async {
    final params = beautyParamsForLookPreset(look);
    setState(() {
      _selectedLook = look;
      _params = params;
    });
    await s.setBeautyLook(look, commit: true);
  }

  Future<void> _clearLook() async {
    setState(() {
      _selectedLook = null;
      _params = BeautyParamsX.zero;
    });
    await s.setBeautyLook(null, commit: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s.faceChromeListenable,
      builder: (context, _) {
        // Keep chip highlight in sync after undo/redo / swipe commit.
        final matched = s.committedBeautyLook;
        if (matched != _selectedLook &&
            s.committedBeautyParams != null &&
            _params == s.committedBeautyParams) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedLook = matched);
          });
        }
        return _buildPanel(context);
      },
    );
  }

  Widget _buildPanel(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.stripHostedExternally)
          const SectionHeader(
            'Beauty',
            subtitle: 'Pick a look, then fine-tune eyes, lips, and skin',
          ),
        Row(
          children: [
            Expanded(
              child: Text(
                _statusLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: LuminaTokens.onSurfaceVariant,
                    ),
              ),
            ),
            if (FaceAnalysisService.isAnalysisValid(s.faceAnalysis))
              Chip(
                label: Text('${s.faceAnalysis!.landmarks.length} pts'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: LuminaTokens.padSm),
        if (s.enableMediaPipeDownloadPrompt)
          _MediaPipeDownloadBanner(session: s),
        if (s.enableLiveCameraBeauty && LiveCameraService.isSupported) ...[
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: s.busy || s.liveCameraTransitioning
                      ? null
                      : () {
                          if (s.liveCameraActive) {
                            unawaited(s.stopLiveCameraBeauty());
                          } else {
                            unawaited(s.startLiveCameraBeauty());
                          }
                        },
                  icon: Icon(
                    s.liveCameraActive ? Icons.videocam_off : Icons.videocam,
                  ),
                  label: Text(
                    s.liveCameraActive ? 'Stop live camera' : 'Live camera',
                  ),
                ),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Debug landmarks'),
            subtitle: const Text('Overlay face mesh on preview'),
            value: s.showDebugFaceLandmarks,
            onChanged: s.liveCameraActive || s.hasImage
                ? (v) {
                    s.showDebugFaceLandmarks = v;
                    s.previewListenable.value++;
                  }
                : null,
          ),
          const SizedBox(height: LuminaTokens.padSm),
          if (s.liveCameraActive) ...[
            Text(
              'Preview frame',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: LuminaTokens.padXs),
            ActionChipRow<CropAspect>(
              horizontal: true,
              items: const [
                CropAspect.original,
                CropAspect.square1x1,
                CropAspect.portrait4x5,
                CropAspect.story9x16,
                CropAspect.landscape16x9,
              ],
              label: (a) => a == CropAspect.original ? 'Full' : a.label,
              selected: s.livePreviewAspect,
              onSelected: s.busy ? (_) {} : s.setLivePreviewAspect,
            ),
            const SizedBox(height: LuminaTokens.padSm),
          ],
        ],
        OutlinedButton.icon(
          onPressed: s.busy ||
                  s.faceAnalyzing ||
                  s.liveCameraActive ||
                  !s.hasWorkingImage
              ? null
              : () => unawaited(s.analyzeFaceForBeauty(force: true)),
          icon: const Icon(Icons.face_retouching_natural),
          label: const Text('Re-analyze face'),
        ),
        const SizedBox(height: LuminaTokens.padMd),
        Text(
          'Looks',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: LuminaTokens.padXs),
        _LooksStrip(
          selected: _selectedLook,
          enabled: _canPickLook,
          onSelected: (look) {
            if (look == null) {
              unawaited(_clearLook());
            } else {
              unawaited(_applyLook(look));
            }
          },
        ),
        const SizedBox(height: LuminaTokens.padSm),
        _EraserSection(
          enabled: _canFineTune,
          eraserOn: s.beautyEraserMode,
          brushSize: s.beautyEraserRadius,
          hasStrokes: BeautyExcludeMask.hasEffect(s.beautyExcludeMask),
          onToggle: (on) => s.setBeautyEraserMode(on),
          onBrushSize: s.setBeautyEraserRadius,
          onClear: s.clearBeautyExclude,
        ),
        const SizedBox(height: LuminaTokens.padSm),
        InkWell(
          onTap: () => setState(() => _fineTuneExpanded = !_fineTuneExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: LuminaTokens.padXs),
            child: Row(
              children: [
                Text(
                  'Fine tune',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const Spacer(),
                Icon(
                  _fineTuneExpanded
                      ? Icons.expand_less
                      : Icons.expand_more,
                  size: 20,
                  color: LuminaTokens.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        if (_fineTuneExpanded) ...[
          _slider(
            label: 'Skin smooth',
            value: _params.skinSmooth * 100,
            onChanged: (v) => _live(_params.copyWith(skinSmooth: v / 100)),
          ),
          _slider(
            label: 'Eye brighten',
            value: _params.eyeBrighten * 100,
            onChanged: (v) => _live(_params.copyWith(eyeBrighten: v / 100)),
          ),
          const SizedBox(height: LuminaTokens.padSm),
          Text(
            'Lip color',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: LuminaTokens.padXs),
          _LipSwatches(
            selected: _params.lipTint,
            enabled: _canFineTune,
            onSelected: (t) {
              final next = _params.copyWith(
                lipTint: t,
                lipTintStrength: t == LipTintPreset.none
                    ? 0
                    : (_params.lipTintStrength > 0.001
                        ? _params.lipTintStrength
                        : 0.45),
              );
              _live(next);
              _commit();
            },
          ),
          if (_params.lipTint != LipTintPreset.none) ...[
            const SizedBox(height: LuminaTokens.padSm),
            _slider(
              label: 'Lip intensity',
              value: _params.lipTintStrength * 100,
              onChanged: (v) =>
                  _live(_params.copyWith(lipTintStrength: v / 100)),
            ),
          ],
          _slider(
            label: 'Lip plump',
            value: _params.lipPlump * 100,
            onChanged: (v) => _live(_params.copyWith(lipPlump: v / 100)),
          ),
          _slider(
            label: 'Blush',
            value: _params.blush * 100,
            onChanged: (v) => _live(_params.copyWith(blush: v / 100)),
          ),
          _slider(
            label: 'Under-eye',
            value: _params.underEye * 100,
            onChanged: (v) => _live(_params.copyWith(underEye: v / 100)),
          ),
          _slider(
            label: 'Teeth whiten',
            value: _params.teethWhiten * 100,
            onChanged: (v) => _live(_params.copyWith(teethWhiten: v / 100)),
          ),
        ],
      ],
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required ValueChanged<double>? onChanged,
  }) {
    return LabeledSlider(
      label: label,
      value: value,
      min: 0,
      max: 100,
      divisions: 20,
      display: '${value.round()}%',
      onChanged: _canFineTune ? onChanged : null,
      onChangeEnd: _canFineTune ? (_) => _commit() : null,
    );
  }
}

class _EraserSection extends StatelessWidget {
  const _EraserSection({
    required this.enabled,
    required this.eraserOn,
    required this.brushSize,
    required this.hasStrokes,
    required this.onToggle,
    required this.onBrushSize,
    required this.onClear,
  });

  final bool enabled;
  final bool eraserOn;
  final double brushSize;
  final bool hasStrokes;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onBrushSize;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Eraser',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            if (eraserOn)
              Text(
                'Paint on preview',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: LuminaTokens.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        const SizedBox(height: LuminaTokens.padXs),
        Row(
          children: [
            FilterChip(
              label: const Text('Remove overlay'),
              selected: eraserOn,
              onSelected: enabled ? onToggle : null,
              avatar: Icon(
                eraserOn ? Icons.brush : Icons.auto_fix_off,
                size: 18,
              ),
            ),
            const SizedBox(width: LuminaTokens.padXs),
            if (hasStrokes)
              TextButton(
                onPressed: enabled ? onClear : null,
                child: const Text('Clear'),
              ),
          ],
        ),
        if (eraserOn) ...[
          const SizedBox(height: LuminaTokens.padXs),
          LabeledSlider(
            label: 'Eraser size',
            value: brushSize,
            min: 8,
            max: 72,
            divisions: 16,
            display: '${brushSize.round()} px',
            onChanged: enabled ? onBrushSize : null,
          ),
          Text(
            'Brush over mustache, skin, or any area where the look bleeds outside the face.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: LuminaTokens.onSurfaceVariant,
                ),
          ),
        ],
      ],
    );
  }
}

class _LooksStrip extends StatelessWidget {
  const _LooksStrip({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final BeautyLookPreset? selected;
  final bool enabled;
  final void Function(BeautyLookPreset? look) onSelected;

  static const _lookGradients = <BeautyLookPreset, List<Color>>{
    BeautyLookPreset.natural: [Color(0xFFE8C4B8), Color(0xFFD4A574)],
    BeautyLookPreset.soft: [Color(0xFFF5D0D6), Color(0xFFE8B4BC)],
    BeautyLookPreset.glow: [Color(0xFFFFE0C2), Color(0xFFFFB88C)],
    BeautyLookPreset.glam: [Color(0xFF9B3D5C), Color(0xFF6B2D45)],
    BeautyLookPreset.clear: [Color(0xFFE8EDE8), Color(0xFFC8D8C8)],
    BeautyLookPreset.peach: [Color(0xFFFFD4B8), Color(0xFFFF9E7A)],
    BeautyLookPreset.bold: [Color(0xFFD42B2B), Color(0xFF8B1A1A)],
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _LookChip(
            label: 'Original',
            selected: selected == null,
            enabled: enabled,
            gradient: null,
            onTap: enabled ? () => onSelected(null) : null,
          ),
          for (final look in allBeautyLooks)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _LookChip(
                label: beautyLookLabel(look),
                selected: selected == look,
                enabled: enabled,
                gradient: _lookGradients[look],
                onTap: enabled ? () => onSelected(look) : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _LookChip extends StatelessWidget {
  const _LookChip({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final List<Color>? gradient;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: gradient != null
                ? LinearGradient(colors: gradient!)
                : null,
            color: gradient == null
                ? LuminaTokens.surfaceContainerHigh
                : null,
            border: Border.all(
              width: selected ? 2 : 1,
              color: selected ? scheme.primary : LuminaTokens.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: gradient != null && _isDarkGradient(gradient!)
                      ? Colors.white
                      : LuminaTokens.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }

  bool _isDarkGradient(List<Color> colors) =>
      colors.last.computeLuminance() < 0.35;
}

class _LipSwatches extends StatelessWidget {
  const _LipSwatches({
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final LipTintPreset selected;
  final bool enabled;
  final ValueChanged<LipTintPreset> onSelected;

  static const _swatches = <(LipTintPreset, Color, String)>[
    (LipTintPreset.none, Color(0xFF888888), 'None'),
    (LipTintPreset.nude, Color(0xFFC9867A), 'Nude'),
    (LipTintPreset.rose, Color(0xFFE07A8A), 'Rose'),
    (LipTintPreset.berry, Color(0xFF9B3D5C), 'Berry'),
    (LipTintPreset.coral, Color(0xFFE86B4A), 'Coral'),
    (LipTintPreset.red, Color(0xFFD42B2B), 'Red'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (preset, color, name) in _swatches)
          Tooltip(
            message: name,
            child: InkWell(
              onTap: enabled ? () => onSelected(preset) : null,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: preset == LipTintPreset.none
                      ? Colors.transparent
                      : color,
                  border: Border.all(
                    width: selected == preset ? 2.5 : 1,
                    color: selected == preset
                        ? Theme.of(context).colorScheme.primary
                        : LuminaTokens.outlineVariant,
                  ),
                ),
                child: preset == LipTintPreset.none
                    ? Icon(
                        Icons.block,
                        size: 18,
                        color: LuminaTokens.onSurfaceVariant,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _MediaPipeDownloadBanner extends StatefulWidget {
  const _MediaPipeDownloadBanner({required this.session});

  final EditorSession session;

  @override
  State<_MediaPipeDownloadBanner> createState() =>
      _MediaPipeDownloadBannerState();
}

class _MediaPipeDownloadBannerState extends State<_MediaPipeDownloadBanner> {
  bool _ready = false;
  bool _dismissed = false;
  bool _downloading = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (!MediaPipeModelService.isPlatformSupported) return;
    final ready = await MediaPipeModelService.isMediaPipeReady();
    final dismissed = await MediaPipeModelService.isPromptDismissed();
    if (!mounted) return;
    setState(() {
      _ready = ready;
      _dismissed = dismissed;
    });
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      await MediaPipeModelService.downloadModels(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) {
        setState(() => _ready = true);
        unawaited(widget.session.analyzeFaceForBeauty(force: true));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!MediaPipeModelService.isPlatformSupported ||
        _ready ||
        _dismissed) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: LuminaTokens.padSm),
      child: Padding(
        padding: const EdgeInsets.all(LuminaTokens.padSm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Better lip & eye masks (~${MediaPipeModelService.estimatedSizeMb} MB)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Download MediaPipe 468-point mesh (optional). Vision / ML Kit fallback stays available.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LuminaTokens.onSurfaceVariant,
                  ),
            ),
            if (_downloading) ...[
              const SizedBox(height: LuminaTokens.padSm),
              LinearProgressIndicator(value: _progress),
            ],
            const SizedBox(height: LuminaTokens.padSm),
            Row(
              children: [
                TextButton(
                  onPressed: _downloading
                      ? null
                      : () async {
                          await MediaPipeModelService.dismissPrompt();
                          if (mounted) setState(() => _dismissed = true);
                        },
                  child: const Text('Not now'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _downloading ? null : _download,
                  child: Text(_downloading ? 'Downloading…' : 'Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
