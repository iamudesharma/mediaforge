import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';

/// Full text styling UI for video overlays (no image_forge_editor dependency).
class VideoTextOverlayEditSheet extends StatefulWidget {
  const VideoTextOverlayEditSheet({
    super.key,
    required this.initialSpec,
    this.title = 'Add text',
  });

  final VideoTextOverlaySpec initialSpec;
  final String title;

  static Future<VideoTextOverlaySpec?> show(
    BuildContext context, {
    required VideoTextOverlaySpec initialSpec,
    String title = 'Add text',
  }) {
    return showModalBottomSheet<VideoTextOverlaySpec>(
      context: context,
      isScrollControlled: true,
      backgroundColor: LuminaTokens.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: VideoTextOverlayEditSheet(
          initialSpec: initialSpec,
          title: title,
        ),
      ),
    );
  }

  @override
  State<VideoTextOverlayEditSheet> createState() =>
      _VideoTextOverlayEditSheetState();
}

class _VideoTextOverlayEditSheetState extends State<VideoTextOverlayEditSheet> {
  late final TextEditingController _textCtrl;
  late VideoTextOverlayStyle _style;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialSpec.label);
    _style = widget.initialSpec.style;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  VideoTextOverlaySpec _buildSpec() {
    final label = _textCtrl.text.trim();
    return VideoTextOverlaySpec(
      label: label.isEmpty ? 'Text' : label,
      style: _style,
    );
  }

  void _apply() {
    if (_textCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter some text')),
      );
      return;
    }
    Navigator.pop(context, _buildSpec());
  }

  @override
  Widget build(BuildContext context) {
    final previewSpec = _buildSpec();

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                color: LuminaTokens.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: LuminaTokens.outlineVariant),
                ),
                child: VideoTextOverlayContent(spec: previewSpec),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              style: const TextStyle(color: LuminaTokens.onSurface),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Caption',
                labelStyle: const TextStyle(color: LuminaTokens.onSurfaceVariant),
                filled: true,
                fillColor: LuminaTokens.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _slider(
              label: 'Font size',
              value: _style.fontSize,
              min: 16,
              max: 72,
              display: '${_style.fontSize.round()}px',
              onChanged: (v) => setState(() => _style = _style.copyWith(fontSize: v)),
            ),
            _slider(
              label: 'Box width',
              value: _style.maxWidth,
              min: 120,
              max: 480,
              display: '${_style.maxWidth.round()}px',
              onChanged: (v) => setState(() => _style = _style.copyWith(maxWidth: v)),
            ),
            _slider(
              label: 'Padding',
              value: _style.padding,
              min: 0,
              max: 32,
              display: '${_style.padding.round()}px',
              onChanged: (v) => setState(() => _style = _style.copyWith(padding: v)),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: VideoTextBackgroundStyle.values.map((bg) {
                final selected = _style.backgroundStyle == bg;
                return ChoiceChip(
                  label: Text(switch (bg) {
                    VideoTextBackgroundStyle.none => 'None',
                    VideoTextBackgroundStyle.solid => 'Solid',
                    VideoTextBackgroundStyle.rounded => 'Rounded',
                  }),
                  selected: selected,
                  onSelected: (_) => setState(
                    () => _style = _style.copyWith(backgroundStyle: bg),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _apply, child: const Text('Done')),
          ],
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(color: LuminaTokens.onSurfaceVariant, fontSize: 12)),
              const Spacer(),
              Text(display, style: const TextStyle(color: LuminaTokens.onSurfaceMuted, fontSize: 11)),
            ],
          ),
          Slider(value: value.clamp(min, max), min: min, max: max, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Inline editor for the inspector when a text layer is selected.
class VideoTextOverlayEditPanel extends StatefulWidget {
  const VideoTextOverlayEditPanel({
    super.key,
    required this.spec,
    required this.onChanged,
  });

  final VideoTextOverlaySpec spec;
  final ValueChanged<VideoTextOverlaySpec> onChanged;

  @override
  State<VideoTextOverlayEditPanel> createState() =>
      _VideoTextOverlayEditPanelState();
}

class _VideoTextOverlayEditPanelState extends State<VideoTextOverlayEditPanel> {
  late final TextEditingController _textCtrl;
  late VideoTextOverlayStyle _style;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.spec.label);
    _style = widget.spec.style;
  }

  @override
  void didUpdateWidget(covariant VideoTextOverlayEditPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) {
      _textCtrl.text = widget.spec.label;
      _style = widget.spec.style;
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      VideoTextOverlaySpec(
        label: _textCtrl.text.trim().isEmpty ? 'Text' : _textCtrl.text,
        style: _style,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Text style',
          style: TextStyle(color: LuminaTokens.onSurface, fontWeight: FontWeight.w600, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _textCtrl,
          style: const TextStyle(color: LuminaTokens.onSurface, fontSize: 12),
          onChanged: (_) {
            setState(() {});
            _emit();
          },
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: LuminaTokens.surfaceContainerHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        Slider(
          value: _style.fontSize.clamp(16, 72),
          min: 16,
          max: 72,
          onChanged: (v) {
            setState(() => _style = _style.copyWith(fontSize: v));
            _emit();
          },
        ),
      ],
    );
  }
}
