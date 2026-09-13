import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../buffered_range.dart';
import 'utils.dart';
import 'models.dart';

/// Timeline scrubber with played/buffered ranges and chapter markers.
///
/// Visual contract (YouTube/VLC style):
/// ```text
/// [======== played =====>|---- buffered ----|........ not loaded ........]
/// ```
/// * base/unbuffered track (empty)
/// * buffered/cache ranges (engine read-ahead merged with optional host
///   cache) — always visible, including while paused
/// * played progress + playhead knob
/// * chapter markers, hover timestamp + optional thumbnail
///
/// Drag (or tap) anywhere to preview, release to commit the seek via
/// [onSeekCommitted]; live position streams in through [position].
/// Desktop hover shows the hovered timestamp and, when [thumbnailBuilder]
/// is provided, a thumbnail preview.
///
/// [buffered] is the legacy single-point API (kept for backward compat).
/// Prefer [bufferedRanges]: non-contiguous ranges from seeks/sparse caches.
/// When [bufferedRanges] is non-empty it drives rendering; otherwise
/// [buffered] is used as a single `[0, buffered]` window.
///
/// Listening to [MediaForgePlayerController.bufferState] (a dedicated
/// notifier) instead of the full player value keeps timeline updates
/// lightweight: the video texture listens to the presenter and is never
/// rebuilt because buffering changed.
class PlayerTimeline extends StatefulWidget {
  const PlayerTimeline({
    super.key,
    required this.position,
    required this.buffered,
    required this.duration,
    required this.onSeekCommitted,
    this.bufferedRanges = const [],
    this.externalBufferedRanges = const [],
    this.chapters = const [],
    this.thumbnailBuilder,
    this.enabled = true,
  });

  final Duration position;

  /// Legacy contiguous buffered point (backward compat).
  final Duration buffered;
  final Duration duration;
  final ValueChanged<Duration> onSeekCommitted;

  /// Engine-derived availability (merged display ranges when combined with
  /// [externalBufferedRanges]). Empty = fall back to [buffered].
  final List<MediaForgeBufferedRange> bufferedRanges;

  /// Host-provided cache ranges (generic, e.g. torrent piece cache).
  /// Merged (union) with [bufferedRanges] for display, never double-counted.
  final List<MediaForgeBufferedRange> externalBufferedRanges;
  final List<MediaPlayerChapter> chapters;

  /// Optional async thumbnail for a position (`null` = no preview).
  final Future<Widget?> Function(Duration position)? thumbnailBuilder;
  final bool enabled;

  /// Merged display ranges (internal ∪ external, normalized).
  List<MediaForgeBufferedRange> get displayRanges {
    if (bufferedRanges.isEmpty && externalBufferedRanges.isEmpty) {
      if (buffered <= Duration.zero) return const [];
      return [MediaForgeBufferedRange(start: Duration.zero, end: buffered)];
    }
    return mergeBufferedRanges(bufferedRanges, externalBufferedRanges);
  }

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
    // Prefer merged ranges; fall back to legacy single point.
    final displayRanges = widget.displayRanges;
    final displayFractions = displayRanges
        .map((r) => (
              start: _fractionFor(r.start),
              end: _fractionFor(r.end),
            ))
        .toList();
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
                    bufferedSpans: displayFractions,
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
    required this.bufferedSpans,
    required this.chapters,
    required this.activeColor,
  });

  final double playedFraction;
  final double bufferedFraction;

  /// Merged buffered spans as (start, end) fractions. When non-empty these
  /// drive rendering; otherwise [bufferedFraction] is the fallback.
  final List<({double start, double end})> bufferedSpans;
  final List<double> chapters;
  final Color activeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    const trackH = 4.0;
    const radius = Radius.circular(2);

    // Base/unbuffered track.
    canvas.drawRRect(
      RRect.fromLTRBR(0, centerY - trackH / 2, size.width,
          centerY + trackH / 2, radius),
      Paint()..color = Colors.white24,
    );
    // Buffered/cache ranges (visible even while paused).
    final spans = bufferedSpans.isEmpty
        ? [
            if (bufferedFraction > 0)
              (start: 0.0, end: bufferedFraction.clamp(0.0, 1.0)),
          ]
        : bufferedSpans;
    for (final span in spans) {
      final s = span.start.clamp(0.0, 1.0);
      final e = span.end.clamp(0.0, 1.0);
      if (e <= s) continue;
      canvas.drawRRect(
        RRect.fromLTRBR(s * size.width, centerY - trackH / 2,
            e * size.width, centerY + trackH / 2, radius),
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
    // Playhead knob.
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
      !listEquals(old.chapters, chapters) ||
      !_spansEqual(old.bufferedSpans, bufferedSpans);

  static bool _spansEqual(
    List<({double start, double end})> a,
    List<({double start, double end})> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }
}
