import 'package:flutter/material.dart';

import '../player_controller.dart';
import 'models.dart';

/// Caption overlay honouring [MediaPlayerSubtitleStyle].
///
/// Polls [MediaForgePlayerController.subtitleTextAt] whenever the
/// controller value changes (position cadence ~2 Hz) and renders the
/// active cue. Shows nothing when no subtitle track is selected.
class PlayerCaptionOverlay extends StatefulWidget {
  const PlayerCaptionOverlay({
    super.key,
    required this.controller,
    required this.style,
  });

  final MediaForgePlayerController controller;
  final MediaPlayerSubtitleStyle style;

  @override
  State<PlayerCaptionOverlay> createState() => _PlayerCaptionOverlayState();
}

class _PlayerCaptionOverlayState extends State<PlayerCaptionOverlay> {
  String? _text;
  Duration _polledFor = Duration.zero;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_maybePoll);
    _maybePoll();
  }

  @override
  void didUpdateWidget(covariant PlayerCaptionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_maybePoll);
      widget.controller.addListener(_maybePoll);
      _polledFor = Duration.zero;
      _maybePoll();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_maybePoll);
    super.dispose();
  }

  void _maybePoll() {
    final v = widget.controller.value;
    // Same gate as MediaForgePlayerController.subtitleTextAt
    // (MediaForgePlayerValue.hasActiveSubtitles): enabled + a selected track.
    if (!v.hasActiveSubtitles) {
      if (_text != null && mounted) setState(() => _text = null);
      return;
    }
    if (_polling || v.position == _polledFor) return;
    _polling = true;
    final pos = v.position;
    widget.controller.subtitleTextAt(pos).then((text) {
      _polling = false;
      if (!mounted) return;
      setState(() {
        _text = (text == null || text.isEmpty) ? null : text;
        _polledFor = pos;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    if (text == null) return const SizedBox.shrink();
    final style = widget.style;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: style.backgroundOpacity),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: style.fontSize,
          height: 1.35,
          fontWeight: style.bold ? FontWeight.w700 : FontWeight.w500,
          shadows: const [
            Shadow(
              color: Colors.black87,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
