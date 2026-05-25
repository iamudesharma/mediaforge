import 'package:flutter/material.dart';

import '../editor_session.dart';
import '../services/blank_canvas_builder.dart';
import '../theme/lumina_tokens.dart';
import '../widgets/color_picker_panel.dart';
import '../widgets/control_widgets.dart';

/// Instagram-style blank canvas: aspect + solid / gradient / custom color.
class BlankCanvasSheet extends StatefulWidget {
  const BlankCanvasSheet({
    super.key,
    required this.session,
  });

  final EditorSession session;

  static Future<void> show(BuildContext context, EditorSession session) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    if (wide) {
      return showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: LuminaTokens.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
            child: BlankCanvasSheet(session: session),
          ),
        ),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LuminaTokens.surfaceContainerHigh,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(ctx).bottom),
        child: BlankCanvasSheet(session: session),
      ),
    );
  }

  @override
  State<BlankCanvasSheet> createState() => _BlankCanvasSheetState();
}

class _BlankCanvasSheetState extends State<BlankCanvasSheet> {
  BlankAspect _aspect = BlankAspect.square1x1;
  int _bgTab = 0;
  BlankBackground _background = const SolidBlankBackground(Colors.white);
  Color _customColor = Colors.white;
  bool _creating = false;

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      final bytes = await BlankCanvasBuilder.render(
        aspect: _aspect,
        background: _background,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.session.loadSource(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create canvas: $e')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(LuminaTokens.padMd),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Create blank canvas',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _creating ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SectionHeader('Aspect ratio'),
              ActionChipRow<BlankAspect>(
                items: BlankAspect.values,
                label: (a) => a.label,
                selected: _aspect,
                onSelected: _creating ? (_) {} : (a) => setState(() => _aspect = a),
              ),
              const SizedBox(height: 8),
              Text(
                _aspect.subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _AspectPreview(aspect: _aspect, background: _background),
              const SizedBox(height: 16),
              Row(
                children: [
                  _bgTabChip(0, 'Solid'),
                  const SizedBox(width: 8),
                  _bgTabChip(1, 'Gradient'),
                  const SizedBox(width: 8),
                  _bgTabChip(2, 'Custom'),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 220,
                child: SingleChildScrollView(
                  child: _bgTabBody(),
                ),
              ),
              const SizedBox(height: 12),
              PrimaryActionButton(
                icon: Icons.add,
                label: _creating ? 'Creating…' : 'Create canvas',
                enabled: !_creating,
                onPressed: _creating ? null : _create,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bgTabChip(int i, String label) {
    final selected = _bgTab == i;
    return Expanded(
      child: Material(
        color: selected
            ? LuminaTokens.primary.withValues(alpha: 0.2)
            : LuminaTokens.surfaceContainerLow,
        borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
        child: InkWell(
          onTap: _creating ? null : () => setState(() => _bgTab = i),
          borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: const [],
                color: selected ? LuminaTokens.primary : LuminaTokens.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bgTabBody() {
    return switch (_bgTab) {
      0 => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in BlankCanvasPresets.solidColors)
              _ColorSwatch(
                color: c,
                selected: _background is SolidBlankBackground &&
                    (_background as SolidBlankBackground).color == c,
                onTap: () => setState(
                  () => _background = SolidBlankBackground(c),
                ),
              ),
          ],
        ),
      1 => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < BlankCanvasPresets.gradients.length; i++)
              _GradientSwatch(
                background: BlankCanvasPresets.gradients[i],
                selected: identical(_background, BlankCanvasPresets.gradients[i]) ||
                    _gradientEquals(_background, BlankCanvasPresets.gradients[i]),
                onTap: () => setState(
                  () => _background = BlankCanvasPresets.gradients[i],
                ),
              ),
          ],
        ),
      _ => ColorPickerPanel(
          color: _customColor,
          onChanged: (c) => setState(() {
            _customColor = c;
            _background = SolidBlankBackground(c);
          }),
        ),
    };
  }

  bool _gradientEquals(BlankBackground a, BlankBackground b) {
    if (a.runtimeType != b.runtimeType) return false;
    if (a is LinearGradientBlankBackground && b is LinearGradientBlankBackground) {
      return a.colors.length == b.colors.length &&
          a.begin == b.begin &&
          a.end == b.end;
    }
    if (a is RadialGradientBlankBackground && b is RadialGradientBlankBackground) {
      return a.colors.length == b.colors.length;
    }
    return false;
  }
}

class _AspectPreview extends StatelessWidget {
  const _AspectPreview({
    required this.aspect,
    required this.background,
  });

  final BlankAspect aspect;
  final BlankBackground background;

  @override
  Widget build(BuildContext context) {
    final size = aspect.pixelSize;
    final ratio = size.width / size.height;
    const maxW = 200.0;
    final w = ratio >= 1 ? maxW : maxW * ratio;
    final h = ratio >= 1 ? maxW / ratio : maxW;

    return Center(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: LuminaTokens.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _BackgroundPainter(background),
          size: Size(w, h),
        ),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  _BackgroundPainter(this.background);
  final BlankBackground background;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint();
    switch (background) {
      case SolidBlankBackground(:final color):
        paint.color = color;
        canvas.drawRect(rect, paint);
      case LinearGradientBlankBackground(:final colors, :final begin, :final end):
        paint.shader = LinearGradient(
          begin: begin,
          end: end,
          colors: colors,
        ).createShader(rect);
        canvas.drawRect(rect, paint);
      case RadialGradientBlankBackground(:final colors, :final center, :final radius):
        paint.shader = RadialGradient(
          center: center,
          radius: radius,
          colors: colors,
        ).createShader(rect);
        canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BackgroundPainter old) => old.background != background;
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? LuminaTokens.primary : LuminaTokens.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _GradientSwatch extends StatelessWidget {
  const _GradientSwatch({
    required this.background,
    required this.selected,
    required this.onTap,
  });

  final BlankBackground background;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? LuminaTokens.primary : LuminaTokens.outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: _BackgroundPainter(background),
          size: const Size(56, 56),
        ),
      ),
    );
  }
}
