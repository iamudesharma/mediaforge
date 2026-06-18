import 'package:flutter/material.dart';
import 'package:video_forge_kit/video_forge_kit.dart';

import '../theme/lumina_tokens.dart';
import '../widgets/frosted_bar.dart';

/// Instagram-style inline text editor overlay (presets + format row).
class InlineTextEditorOverlay extends StatefulWidget {
  const InlineTextEditorOverlay({
    super.key,
    required this.initialSpec,
    required this.onDone,
    required this.onCancel,
  });

  final VideoTextOverlaySpec initialSpec;
  final ValueChanged<VideoTextOverlaySpec> onDone;
  final VoidCallback onCancel;

  @override
  State<InlineTextEditorOverlay> createState() => _InlineTextEditorOverlayState();
}

class _InlineTextEditorOverlayState extends State<InlineTextEditorOverlay> {
  late final TextEditingController _textCtrl;
  late VideoTextOverlayStyle _style;
  int _replayToken = 0;

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

  VideoTextOverlaySpec get _previewSpec => VideoTextOverlaySpec(
        label: _textCtrl.text.trim().isEmpty ? 'Text' : _textCtrl.text.trim(),
        style: _style,
      );

  void _applyPreset(VideoTextLookPreset preset) {
    setState(() {
      _style = styleForLookPreset(preset, base: _style);
      _replayToken++;
    });
  }

  void _done() {
    final label = _textCtrl.text.trim();
    if (label.isEmpty) return;
    widget.onDone(VideoTextOverlaySpec(label: label, style: _style));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onCancel,
              child: Container(color: Colors.black26),
            ),
          ),
          Center(
            child: IgnorePointer(
              child: AnimatedVideoTextOverlayContent(
                spec: _previewSpec,
                replayToken: _replayToken,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FrostedBar(
              borderTop: true,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: LuminaTokens.space4,
                    right: LuminaTokens.space4,
                    bottom: MediaQuery.viewInsetsOf(context).bottom + LuminaTokens.space2,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: _style.showBackground
                                ? 'Hide background'
                                : 'Show background',
                            onPressed: () {
                              setState(() {
                                final next = !_style.showBackground;
                                _style = _style.copyWith(
                                  showBackground: next,
                                  backgroundStyle: next
                                      ? VideoTextBackgroundStyle.rounded
                                      : VideoTextBackgroundStyle.none,
                                );
                                _replayToken++;
                              });
                            },
                            icon: Icon(
                              _style.showBackground
                                  ? Icons.crop_square
                                  : Icons.crop_square_outlined,
                              color: LuminaTokens.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _done,
                            child: const Text(
                              'Done',
                              style: TextStyle(
                                color: LuminaTokens.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: VideoTextLookPreset.values.map((preset) {
                            final selected = _style.lookPreset == preset;
                            return Padding(
                              padding: const EdgeInsets.only(right: LuminaTokens.space2),
                              child: ChoiceChip(
                                label: Text(labelForLookPreset(preset)),
                                selected: selected,
                                onSelected: (_) => _applyPreset(preset),
                                selectedColor: LuminaTokens.accentContainer,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? LuminaTokens.onAccentContainer
                                      : LuminaTokens.onSurface,
                                  fontWeight: FontWeight.w600,
                                ),
                                backgroundColor: LuminaTokens.surfaceContainerHigh,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: LuminaTokens.space2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _FormatButton(
                            icon: Icons.palette_outlined,
                            tooltip: 'Color',
                            onTap: () => _showColorPicker(context),
                          ),
                          _FormatButton(
                            icon: Icons.format_italic,
                            tooltip: 'Italic',
                            selected: _style.fontStyle == FontStyle.italic,
                            onTap: () {
                              setState(() {
                                _style = _style.copyWith(
                                  fontStyle: _style.fontStyle == FontStyle.italic
                                      ? FontStyle.normal
                                      : FontStyle.italic,
                                );
                                _replayToken++;
                              });
                            },
                          ),
                          _FormatButton(
                            icon: Icons.format_align_left,
                            tooltip: 'Align left',
                            selected: _style.textAlign == TextAlign.left,
                            onTap: () => setState(() {
                              _style = _style.copyWith(textAlign: TextAlign.left);
                              _replayToken++;
                            }),
                          ),
                          _FormatButton(
                            icon: Icons.format_align_center,
                            tooltip: 'Align center',
                            selected: _style.textAlign == TextAlign.center,
                            onTap: () => setState(() {
                              _style = _style.copyWith(textAlign: TextAlign.center);
                              _replayToken++;
                            }),
                          ),
                          _FormatButton(
                            icon: Icons.format_align_right,
                            tooltip: 'Align right',
                            selected: _style.textAlign == TextAlign.right,
                            onTap: () => setState(() {
                              _style = _style.copyWith(textAlign: TextAlign.right);
                              _replayToken++;
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: LuminaTokens.space2),
                      TextField(
                        controller: _textCtrl,
                        autofocus: true,
                        maxLines: 2,
                        style: const TextStyle(color: LuminaTokens.onSurface),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Type something…',
                          hintStyle: const TextStyle(color: LuminaTokens.onSurfaceMuted),
                          filled: true,
                          fillColor: LuminaTokens.surfaceContainerHigh,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(LuminaTokens.radiusMd),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: LuminaTokens.surfaceContainer,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(LuminaTokens.space4),
          child: Wrap(
            spacing: LuminaTokens.space3,
            runSpacing: LuminaTokens.space3,
            children: videoTextAccentColors.map((c) {
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _style = _style.copyWith(
                      color: c,
                      fillMode: VideoTextFillMode.solid,
                    );
                    _replayToken++;
                  });
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: LuminaTokens.outlineVariant),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(
        icon,
        color: selected ? LuminaTokens.accent : LuminaTokens.onSurfaceVariant,
      ),
    );
  }
}
