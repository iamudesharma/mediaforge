import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'utils.dart';
import 'models.dart';

/// Timeline scrubber with played/buffered ranges and chapter markers.
///
/// * Drag (or tap) anywhere to preview, release to commit the seek via
///   [onSeekCommitted]; live position streams in through [position].
/// * Desktop hover shows the hovered timestamp and, when
///   [thumbnailBuilder] is provided, a thumbnail preview.
/// * [chapters] are app-provided markers; the engine exposes none.
class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.onSeekCommitted,
    this.chapters = const [],
    this.thumbnailBuilder,
    this.enabled = true,
  });

  final Duration position;
  final Duration buffered;
  final Duration duration;
  final ValueChanged<Duration> onSeekCommitted;
  final List<MediaPlayerChapter> chapters;

  /// Optional async thumbnail for a position (`null` = no preview).
  final Future<Widget?> Function(Duration position)? thumbnailBuilder;
  final bool enabled;

  @override
  State<PlayerTimeline> createState() => _PlayerTimelineState();
}

class _PlayerTimelineState extends State<PlayerTimeline> {
  double? _dragFraction;
  double? _hoverFraction;
  Widget? _hoverThumbnail;
  Duration? _hoverThumbnailFor;
  int _thumbRequest = 0;

  double get _maxMs => widget.duration.inMilliseconds
      .clamp(1, 1 << 62)
      .toDouble();

  double _fractionFor(Duration d) =>
      (d.inMilliseconds / _maxMs).clamp(0.0, 1.0);

  Duration _durationFor(double fraction) => Duration(
        milliseconds: (fraction.clamp(0.0, 1.0) * _maxMs).round(),
      );

  void _updateDrag(Offset local, double width) {
    if (width <= 0) return;
    setState(() => _dragFraction = (local.dx / width).clamp(0.0, 1.0));
  }

  void _commitDrag() {
    final f = _dragFraction;
    setState(() => _dragFraction = null);
    if (f != null) widget.onSeekCommitted(_durationFor(f));
  }

  void _updateHover(Offset local, double width) {
    if (width <= 0) return;
    final f = (local.dx / width).clamp(0.0, 1.0);
    setState(() => _hoverFraction = f);
    final builder = widget.thumbnailBuilder;
    if (builder == null) return;
    final pos = _durationFor(f);
    // Coarse dedupe: re-request at most once per second of media.
    if (_hoverThumbnailFor != null &&
        (pos - _hoverThumbnailFor!).abs() < const Duration(seconds: 1)) {
      return;
    }
    final request = ++_thumbRequest;
    builder(pos).then((w) {
      if (!mounted || request != _thumbRequest) return;
      setState(() {
        _hoverThumbnail = w;
        _hoverThumbnailFor = pos;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final shownFraction =
        _dragFraction ?? _fractionFor(widget.position);
    final bufferedFraction = _fractionFor(widget.buffered);
    final hoverFraction = _hoverFraction;
    final accent = Theme.of(context).colorScheme.primary;

    // Desktop hover is forwarded by [_HoverWrapper]; touch uses drag only.
    return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled
            ? (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                widget.onSeekCommitted(
                  _durationFor(
                      (d.localPosition.dx / box.size.width).clamp(0.0, 1.0)),
                );
              }
            : null,
        onHorizontalDragStart: widget.enabled
            ? (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                _updateDrag(d.localPosition, box.size.width);
              }
            : null,
        onHorizontalDragUpdate: widget.enabled
            ? (d) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;
                _updateDrag(d.localPosition, box.size.width);
              }
            : null,
        onHorizontalDragEnd: widget.enabled ? (_) => _commitDrag() : null,
        onHorizontalDragCancel: () => setState(() => _dragFraction = null),
        child: _HoverWrapper(
          onHover: (local, width) => _updateHover(local, width),
          onExit: () => setState(() {
            _hoverFraction = null;
            _hoverThumbnail = null;
            _hoverThumbnailFor = null;
          }),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  painter: _TimelinePainter(
                    playedFraction: shownFraction,
                    bufferedFraction: bufferedFraction,
                    chapters: widget.chapters
                        .map((c) => _fractionFor(c.position))
                        .toList(),
                    activeColor: accent,
                  ),
                  size: Size.infinite,
                ),
                if (hoverFraction != null &&
                    _dragFraction == null &&
                    widget.enabled)
                  _HoverBubble(
                    fraction: hoverFraction,
                    label: formatDuration(_durationFor(hoverFraction)),
                    thumbnail: _hoverThumbnail,
                  ),
                if (_dragFraction != null)
                  _HoverBubble(
                    fraction: _dragFraction!,
                    label: formatDuration(_durationFor(_dragFraction!)),
                    thumbnail: null,
                  ),
              ],
            ),
          ),
        ),
    );
  }
}

/// Desktop-only hover forwarder (no-op on touch platforms).
class _HoverWrapper extends StatelessWidget {
  const _HoverWrapper({
    required this.child,
    required this.onHover,
    required this.onExit,
  });

  final Widget child;
  final void Function(Offset local, double width) onHover;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return MouseRegion(
          onHover: (e) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            onHover(
              box.globalToLocal(e.position),
              box.size.width,
            );
          },
          onExit: (_) => onExit(),
          child: child,
        );
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return child;
    }
  }
}

/// Floating timestamp (+ optional thumbnail) above the timeline.
class _HoverBubble extends StatelessWidget {
  const _HoverBubble({
    required this.fraction,
    required this.label,
    required this.thumbnail,
  });

  final double fraction;
  final String label;
  final Widget? thumbnail;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: FractionallySizedBox(
        alignment: Alignment(fraction * 2 - 1, 0),
        widthFactor: 1,
        child: Align(
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (thumbnail != null)
                Container(
                  width: 120,
                  height: 68,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: thumbnail,
                ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.playedFraction,
    required this.bufferedFraction,
    required this.chapters,
    required this.activeColor,
  });

  final double playedFraction;
  final double bufferedFraction;
  final List<double> chapters;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackH = 4.0;
    const radius = Radius.circular(2);

    // Base track.
    canvas.drawRRect(
      RRect.fromLTRBR(0, centerY - trackH / 2, size.width,
          centerY + trackH / 2, radius),
      Paint()..color = Colors.white24,
    );
    // Buffered range.
    final bufferedW = size.width * bufferedFraction.clamp(0.0, 1.0);
    if (bufferedW > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, centerY - trackH / 2, bufferedW,
            centerY + trackH / 2, radius),
        Paint()..color = Colors.white38,
      );
    }
    // Played range.
    final playedW = size.width * playedFraction.clamp(0.0, 1.0);
    if (playedW > 0) {
      canvas.drawRRect(
        RRect.fromLTRBR(0, centerY - trackH / 2, playedW,
            centerY + trackH / 2, radius),
        Paint()..color = activeColor,
      );
    }
    // Chapter markers.
    for (final f in chapters) {
      final x = size.width * f.clamp(0.0, 1.0);
      canvas.drawCircle(
        Offset(x, centerY),
        2.2,
        Paint()..color = Colors.white70,
      );
    }
    // Knob.
    canvas.drawCircle(
      Offset(playedW, centerY),
      6.5,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      Offset(playedW, centerY),
      6.5,
      Paint()
        ..color = activeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.playedFraction != playedFraction ||
      old.bufferedFraction != bufferedFraction ||
      old.activeColor != activeColor ||
      !listEquals(old.chapters, chapters);
}
