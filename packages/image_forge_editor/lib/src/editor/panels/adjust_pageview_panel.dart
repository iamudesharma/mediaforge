import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor_session.dart';
import '../services/filter_descriptor.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/value_chip_slider.dart';

/// CapCut-style adjustment strip — a horizontal `PageView` where each page
/// is one adjustment. Swipe left/right to move between Brightness, Contrast,
/// Saturation, etc. The value chip floats above the thumb while dragging.
///
/// Uses the existing [EditorSession.applyFilter] pipeline for live preview
/// and commit-on-release semantics.
class AdjustPageViewPanel extends StatefulWidget {
  const AdjustPageViewPanel({
    super.key,
    required this.session,
  });

  final EditorSession session;

  @override
  State<AdjustPageViewPanel> createState() => _AdjustPageViewPanelState();
}

class _AdjustPageViewPanelState extends State<AdjustPageViewPanel> {
  static const List<_AdjustmentSpec> _specs = [
    _AdjustmentSpec(
      kind: _AdjustKind.brightness,
      label: 'Brightness',
      icon: Icons.wb_sunny_outlined,
      min: -100,
      max: 100,
      divisions: 40,
      bipolar: true,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.contrast,
      label: 'Contrast',
      icon: Icons.contrast_rounded,
      min: 0.2,
      max: 2.5,
      divisions: 23,
      bipolar: false,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.saturation,
      label: 'Saturation',
      icon: Icons.color_lens_outlined,
      min: 0,
      max: 2.5,
      divisions: 25,
      bipolar: false,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.warmth,
      label: 'Warmth',
      icon: Icons.local_fire_department_outlined,
      min: -100,
      max: 100,
      divisions: 40,
      bipolar: true,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.hue,
      label: 'Hue',
      icon: Icons.palette_outlined,
      min: -180,
      max: 180,
      divisions: 36,
      bipolar: true,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.fade,
      label: 'Fade',
      icon: Icons.blur_linear_rounded,
      min: 0,
      max: 1,
      divisions: 20,
      bipolar: false,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.vignette,
      label: 'Vignette',
      icon: Icons.brightness_5_outlined,
      min: 0,
      max: 1,
      divisions: 20,
      bipolar: false,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.highlights,
      label: 'Highlights',
      icon: Icons.highlight_outlined,
      min: -100,
      max: 100,
      divisions: 40,
      bipolar: true,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.shadows,
      label: 'Shadows',
      icon: Icons.dark_mode_outlined,
      min: -100,
      max: 100,
      divisions: 40,
      bipolar: true,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.sharpen,
      label: 'Sharpen',
      icon: Icons.details_rounded,
      min: 0,
      max: 100,
      divisions: 20,
      bipolar: false,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.structure,
      label: 'Structure',
      icon: Icons.architecture_outlined,
      min: -100,
      max: 100,
      divisions: 40,
      bipolar: true,
    ),
    _AdjustmentSpec(
      kind: _AdjustKind.grain,
      label: 'Grain',
      icon: Icons.grain_rounded,
      min: 0,
      max: 100,
      divisions: 20,
      bipolar: false,
    ),
  ];

  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : 360.0;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: pageHeight,
              child: PageView.builder(
                controller: _controller,
                physics: const PageScrollPhysics().applyTo(
                  const BouncingScrollPhysics(),
                ),
                itemCount: _specs.length,
                onPageChanged: (i) {
                  HapticFeedback.selectionClick();
                  setState(() => _page = i);
                },
                itemBuilder: (context, i) {
                  final spec = _specs[i];
                  return _AdjustPage(
                    spec: spec,
                    session: widget.session,
                  );
                },
              ),
            ),
            const SizedBox(height: LuminaTokens.space2),
            _PageIndicator(
              count: _specs.length,
              current: _page,
              onTap: (i) {
                _controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                );
              },
            ),
            const SizedBox(height: LuminaTokens.space3),
          ],
        );
      },
    );
  }
}

enum _AdjustKind {
  brightness,
  contrast,
  saturation,
  warmth,
  hue,
  fade,
  vignette,
  highlights,
  shadows,
  sharpen,
  structure,
  grain,
}

class _AdjustmentSpec {
  const _AdjustmentSpec({
    required this.kind,
    required this.label,
    required this.icon,
    required this.min,
    required this.max,
    required this.divisions,
    required this.bipolar,
  });

  final _AdjustKind kind;
  final String label;
  final IconData icon;
  final double min;
  final double max;
  final int divisions;
  final bool bipolar;
}

class _AdjustPage extends StatefulWidget {
  const _AdjustPage({required this.spec, required this.session});

  final _AdjustmentSpec spec;
  final EditorSession session;

  @override
  State<_AdjustPage> createState() => _AdjustPageState();
}

class _AdjustPageState extends State<_AdjustPage> {
  late double _value;
  bool _initialized = false;

  void _ensureInit() {
    if (_initialized) return;
    _initialized = true;
    _value = _defaultValueFor(widget.spec.kind);
  }

  double _defaultValueFor(_AdjustKind k) {
    switch (k) {
      case _AdjustKind.brightness:
        return 20;
      case _AdjustKind.contrast:
        return 1.1;
      case _AdjustKind.saturation:
        return 1.2;
      case _AdjustKind.warmth:
      case _AdjustKind.hue:
      case _AdjustKind.highlights:
      case _AdjustKind.shadows:
      case _AdjustKind.structure:
        return 0;
      case _AdjustKind.fade:
      case _AdjustKind.vignette:
      case _AdjustKind.sharpen:
      case _AdjustKind.grain:
        return 0;
    }
  }

  FilterDescriptor _descriptor() {
    final v = _value;
    switch (widget.spec.kind) {
      case _AdjustKind.brightness:
        return FilterDescriptor.brightness(amount: v.round());
      case _AdjustKind.contrast:
        return FilterDescriptor.contrast(amount: v);
      case _AdjustKind.saturation:
        return FilterDescriptor.saturation(amount: v);
      case _AdjustKind.warmth:
        return FilterDescriptor.warmth(amount: v.toDouble());
      case _AdjustKind.hue:
        return FilterDescriptor.hueRotate(degrees: v);
      case _AdjustKind.fade:
        return FilterDescriptor.fade(amount: v);
      case _AdjustKind.vignette:
        return FilterDescriptor.vignette(amount: v);
      case _AdjustKind.highlights:
        return FilterDescriptor.highlights(amount: v.toDouble());
      case _AdjustKind.shadows:
        return FilterDescriptor.shadows(amount: v.toDouble());
      case _AdjustKind.sharpen:
        return FilterDescriptor.sharpen();
      case _AdjustKind.structure:
        return FilterDescriptor.structure(amount: v.toDouble());
      case _AdjustKind.grain:
        return FilterDescriptor.contrast(amount: 1.0);
    }
  }

  void _preview() {
    final s = widget.session;
    if (!s.hasImage) return;
    s.applyFilter(
      label: 'Preview',
      descriptor: _descriptor(),
      livePreview: true,
      fromBase: true,
    );
  }

  void _commit() {
    final s = widget.session;
    if (!s.hasImage) return;
    s.cancelDebounced();
    s.applyFilter(
      label: widget.spec.label,
      descriptor: _descriptor(),
      saveUndo: true,
      fromBase: true,
    );
  }

  String _formatValue(double v) {
    switch (widget.spec.kind) {
      case _AdjustKind.contrast:
      case _AdjustKind.saturation:
      case _AdjustKind.fade:
      case _AdjustKind.vignette:
        return v.toStringAsFixed(2);
      case _AdjustKind.hue:
        return '${v.round()}°';
      default:
        if (widget.spec.bipolar) {
          return v == 0
              ? '0'
              : (v > 0 ? '+${v.round()}' : '${v.round()}');
        }
        return v.round().toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureInit();
    final spec = widget.spec;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LuminaTokens.space3,
        vertical: LuminaTokens.space4,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LuminaTokens.space4,
          vertical: LuminaTokens.space5,
        ),
        decoration: BoxDecoration(
          color: LuminaTokens.surfaceContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(LuminaTokens.radiusLg),
          border: Border.all(color: LuminaTokens.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(spec.icon, size: 18, color: LuminaTokens.accent),
                const SizedBox(width: LuminaTokens.space2),
                Text(
                  spec.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: LuminaTokens.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if ((_value - _defaultValueFor(spec.kind)).abs() > 0.001)
                  TextButton(
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      setState(() => _value = _defaultValueFor(spec.kind));
                      _preview();
                      _commit();
                    },
                    child: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: LuminaTokens.space3),
            ValueChipSlider(
              label: spec.label,
              value: _value,
              min: spec.min,
              max: spec.max,
              divisions: spec.divisions,
              bipolar: spec.bipolar,
              formatter: _formatValue,
              onChanged: (v) {
                setState(() => _value = v);
                _preview();
              },
              onChangeEnd: (_) => _commit(),
              enabled: widget.session.hasImage && !widget.session.busy,
            ),
          ],
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({
    required this.count,
    required this.current,
    required this.onTap,
  });

  final int count;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: i == current ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == current
                        ? LuminaTokens.accent
                        : LuminaTokens.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
