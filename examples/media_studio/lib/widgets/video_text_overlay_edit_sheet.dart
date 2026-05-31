import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

import 'video_text_style_bridge.dart';

/// Full text styling UI (presets, gradient, background, width) for video overlays.
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
      backgroundColor: const Color(0xFF1A1A1A),
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
  late TextStyleDraft _style;
  late VideoTextBackgroundStyle _bgStyle;
  late Color _bgColor;
  late double _padding;
  late double _cornerRadius;
  late double _maxWidth;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSpec.style;
    _textCtrl = TextEditingController(text: widget.initialSpec.label);
    _style = draftFromVideoStyle(s);
    _bgStyle = s.backgroundStyle;
    _bgColor = s.backgroundColor;
    _padding = s.padding;
    _cornerRadius = s.cornerRadius;
    _maxWidth = s.maxWidth;
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
      style: videoStyleFromDraft(
        _style,
        backgroundStyle: _bgStyle,
        backgroundColor: _bgColor,
        padding: _padding,
        cornerRadius: _cornerRadius,
        maxWidth: _maxWidth,
      ),
    );
  }

  void _apply() {
    final label = _textCtrl.text.trim();
    if (label.isEmpty) {
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
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Style updates live on the video preview',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: VideoTextOverlayContent(spec: previewSpec),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _textCtrl,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Caption',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: const Color(0xFF252525),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Theme(
              data: ThemeData.dark(),
              child: TextStyleControls(
                value: _style,
                onChanged: (d) => setState(() => _style = d),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Background',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Theme(
              data: ThemeData.dark(),
              child: ActionChipRow<TextBackgroundStyle>(
                items: TextBackgroundStyle.values,
                label: (s) => switch (s) {
                  TextBackgroundStyle.none => 'None',
                  TextBackgroundStyle.solid => 'Solid',
                  TextBackgroundStyle.rounded => 'Rounded',
                },
                selected: editorBackgroundStyle(_bgStyle),
                onSelected: (s) => setState(
                  () => _bgStyle = videoBackgroundStyle(s),
                ),
              ),
            ),
            if (_bgStyle != VideoTextBackgroundStyle.none) ...[
              const SizedBox(height: 8),
              const Text(
                'Background color & opacity',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Theme(
                data: ThemeData.dark(),
                child: LuminaColorSwatchRow(
                  selected: _bgColor,
                  presets: const [
                    Color(0xE6000000),
                    Color(0x99FFFFFF),
                    Color(0xE6FF4081),
                    Color(0xE600D4AA),
                    Color(0x00000000),
                  ],
                  onSelected: (c) => setState(() => _bgColor = c),
                ),
              ),
            ],
            const SizedBox(height: 12),
            _slider(
              label: 'Box width',
              value: _maxWidth,
              min: 120,
              max: 480,
              display: '${_maxWidth.round()}px',
              onChanged: (v) => setState(() => _maxWidth = v),
            ),
            _slider(
              label: 'Padding',
              value: _padding,
              min: 0,
              max: 32,
              display: '${_padding.round()}px',
              onChanged: (v) => setState(() => _padding = v),
            ),
            if (_bgStyle == VideoTextBackgroundStyle.rounded)
              _slider(
                label: 'Corner radius',
                value: _cornerRadius,
                min: 0,
                max: 32,
                display: '${_cornerRadius.round()}px',
                onChanged: (v) => setState(() => _cornerRadius = v),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _apply,
              child: const Text('Done'),
            ),
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
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const Spacer(),
              Text(display, style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Inline editor for the overlays tab when a text layer is selected.
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
  late TextStyleDraft _style;
  late VideoTextBackgroundStyle _bgStyle;
  late Color _bgColor;
  late double _padding;
  late double _cornerRadius;
  late double _maxWidth;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
    _loadFromSpec(widget.spec);
  }

  void _loadFromSpec(VideoTextOverlaySpec spec) {
    final s = spec.style;
    _textCtrl.text = spec.label;
    _style = draftFromVideoStyle(s);
    _bgStyle = s.backgroundStyle;
    _bgColor = s.backgroundColor;
    _padding = s.padding;
    _cornerRadius = s.cornerRadius;
    _maxWidth = s.maxWidth;
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
        style: videoStyleFromDraft(
          _style,
          backgroundStyle: _bgStyle,
          backgroundColor: _bgColor,
          padding: _padding,
          cornerRadius: _cornerRadius,
          maxWidth: _maxWidth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Text style',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _textCtrl,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            onChanged: (_) {
              setState(() {});
              _emit();
            },
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF252525),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextStyleControls(
            value: _style,
            onChanged: (d) {
              setState(() => _style = d);
              _emit();
            },
          ),
          const SizedBox(height: 8),
          const Text('Background', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ActionChipRow<TextBackgroundStyle>(
            horizontal: true,
            items: TextBackgroundStyle.values,
            label: (s) => switch (s) {
              TextBackgroundStyle.none => 'None',
              TextBackgroundStyle.solid => 'Solid',
              TextBackgroundStyle.rounded => 'Rounded',
            },
            selected: editorBackgroundStyle(_bgStyle),
            onSelected: (s) {
              setState(() => _bgStyle = videoBackgroundStyle(s));
              _emit();
            },
          ),
          if (_bgStyle != VideoTextBackgroundStyle.none) ...[
            const SizedBox(height: 6),
            LuminaColorSwatchRow(
              selected: _bgColor,
              presets: const [
                Color(0xE6000000),
                Color(0x99FFFFFF),
                Color(0xE6FF4081),
                Color(0xE600D4AA),
              ],
              onSelected: (c) {
                setState(() => _bgColor = c);
                _emit();
              },
            ),
          ],
          _compactSlider(
            'Width',
            _maxWidth,
            120,
            480,
            (v) {
              setState(() => _maxWidth = v);
              _emit();
            },
          ),
          _compactSlider(
            'Padding',
            _padding,
            0,
            32,
            (v) {
              setState(() => _padding = v);
              _emit();
            },
          ),
        ],
      ),
    );
  }

  Widget _compactSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
