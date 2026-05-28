import 'dart:io';

import 'package:flutter/material.dart';

/// Timeline filmstrip with draggable start/end handles (inspired by [video_trimmer](https://github.com/sbis04/video_trimmer)).
class FilmstripTrimmer extends StatelessWidget {
  const FilmstripTrimmer({
    super.key,
    required this.thumbPaths,
    required this.durationSeconds,
    required this.startSeconds,
    required this.endSeconds,
    required this.onRangeChanged,
    this.height = 56,
    this.cacheWidth,
  });

  /// Cached JPEG/WebP paths on disk (see [VideoProcessor.batchThumbnailPathsCached]).
  final List<String> thumbPaths;
  final double durationSeconds;
  final double startSeconds;
  final double endSeconds;
  final void Function(double start, double end) onRangeChanged;
  final double height;
  final int? cacheWidth;

  static double _minGap(double durationSeconds) {
    if (durationSeconds <= 0) return 0.01;
    return (durationSeconds * 0.05).clamp(0.01, 0.25);
  }

  static double _safeClamp(double value, double lower, double upper) {
    if (lower > upper) return lower;
    return value.clamp(lower, upper);
  }

  @override
  Widget build(BuildContext context) {
    if (thumbPaths.isEmpty || durationSeconds <= 0) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('Generating filmstrip…', style: TextStyle(color: Colors.white70))),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final gap = _minGap(durationSeconds);
        final startFrac = _safeClamp(startSeconds / durationSeconds, 0.0, 1.0);
        final endFrac = _safeClamp(endSeconds / durationSeconds, 0.0, 1.0);
        final left = width * startFrac;
        final right = width * (1 - endFrac);

        return SizedBox(
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    for (final path in thumbPaths)
                      Expanded(
                        child: _ThumbTile(path: path, cacheWidth: cacheWidth),
                      ),
                  ],
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.black.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                width: left,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
                ),
              ),
              Positioned(
                right: 0,
                width: right,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.55)),
                ),
              ),
              Positioned(
                left: left - 12,
                top: 0,
                bottom: 0,
                child: _Handle(
                  label: _formatTime(startSeconds),
                  onDrag: (dx) {
                    final delta = dx / width * durationSeconds;
                    final next = _safeClamp(
                      startSeconds + delta,
                      0.0,
                      endSeconds - gap,
                    );
                    onRangeChanged(next, endSeconds);
                  },
                ),
              ),
              Positioned(
                right: right - 12,
                top: 0,
                bottom: 0,
                child: _Handle(
                  label: _formatTime(endSeconds),
                  alignRight: true,
                  onDrag: (dx) {
                    final delta = dx / width * durationSeconds;
                    final next = _safeClamp(
                      endSeconds + delta,
                      startSeconds + gap,
                      durationSeconds,
                    );
                    onRangeChanged(startSeconds, next);
                  },
                ),
              ),
              Positioned(
                left: left,
                right: right,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({required this.path, this.cacheWidth});

  final String path;
  final int? cacheWidth;

  @override
  Widget build(BuildContext context) {
    return Image.file(
      File(path),
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: cacheWidth,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: Color(0xFF303030),
        child: Icon(Icons.broken_image_outlined, color: Colors.white38, size: 18),
      ),
    );
  }
}

class _Handle extends StatefulWidget {
  const _Handle({
    required this.onDrag,
    required this.label,
    this.alignRight = false,
  });

  final void Function(double dx) onDrag;
  final String label;
  final bool alignRight;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  double _accum = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        _accum += d.delta.dx;
        if (_accum.abs() > 2) {
          widget.onDrag(_accum);
          _accum = 0;
        }
      },
      child: Center(
        child: Container(
          width: 24,
          height: heightFromContext(context),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.horizontal(
              left: widget.alignRight ? Radius.zero : const Radius.circular(4),
              right: widget.alignRight ? const Radius.circular(4) : Radius.zero,
            ),
          ),
          child: Icon(
            widget.alignRight ? Icons.chevron_right : Icons.chevron_left,
            size: 18,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  double heightFromContext(BuildContext context) {
    final h = (context.findAncestorWidgetOfExactType<FilmstripTrimmer>()?.height ?? 56) - 8;
    return h.clamp(40.0, 72.0);
  }
}
