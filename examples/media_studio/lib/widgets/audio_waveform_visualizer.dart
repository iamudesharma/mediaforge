import 'dart:async';
import 'package:flutter/material.dart';
import '../services/rust_backend.dart';

/// Real-time audio waveform visualizer for Rust engine playback.
///
/// Periodically polls the sliding-window amplitude floats from the Rust engine
/// and paints them as a premium, smooth visualizer.
class AudioWaveformVisualizer extends StatefulWidget {
  const AudioWaveformVisualizer({
    super.key,
    required this.backend,
    this.height = 50,
  });

  final RustBackend backend;
  final double height;

  @override
  State<AudioWaveformVisualizer> createState() => _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<AudioWaveformVisualizer> {
  Timer? _timer;
  List<double> _waveform = List.filled(20, 5.0);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant AudioWaveformVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backend != widget.backend) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
  }

  void _tick() async {
    if (!mounted) return;

    final engine = widget.backend.engine;
    final isPlaying = widget.backend.isPlaying;

    if (engine == null || !isPlaying) {
      // Smoothly decay/fade down to idle state (5.0) when paused or stopped
      setState(() {
        for (int i = 0; i < _waveform.length; i++) {
          if (_waveform[i] > 5.05) {
            _waveform[i] = _waveform[i] * 0.8 + 5.0 * 0.2;
          } else {
            _waveform[i] = 5.0;
          }
        }
      });
      return;
    }

    try {
      final raw = await engine.getAudioWaveform();
      if (!mounted) return;

      setState(() {
        if (_waveform.length != raw.length) {
          _waveform = List<double>.from(raw);
        } else {
          for (int i = 0; i < raw.length; i++) {
            // Apply a low-pass filter (interpolation) for fluid animations
            _waveform[i] = _waveform[i] * 0.5 + raw[i] * 0.5;
          }
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.center,
      child: CustomPaint(
        size: Size(double.infinity, widget.height),
        painter: _WaveformPainter(
          waveform: _waveform,
          maxVal: 45.0, // Waveform values range between 5.0 and 45.0
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.maxVal,
  });

  final List<double> waveform;
  final double maxVal;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;

    final count = waveform.length;
    final spacing = 4.0;
    final totalSpacing = spacing * (count - 1);
    final barWidth = (size.width - totalSpacing) / count;

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = const LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          Color(0xFF10B981), // Emerald green
          Color(0xFF06B6D4), // Cyan
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    for (int i = 0; i < count; i++) {
      // Map waveform value (5.0 to 45.0) to height of the canvas
      final rawVal = waveform[i].clamp(5.0, maxVal);
      // Normalize to 0.0 -> 1.0 range
      final normalized = (rawVal - 5.0) / (maxVal - 5.0);
      
      // Calculate height (at least a minimum thickness so it looks active)
      final minHeight = 4.0;
      final barHeight = minHeight + normalized * (size.height - minHeight);

      final left = i * (barWidth + spacing);
      final top = (size.height - barHeight) / 2.0; // Center vertically

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barWidth, barHeight),
        Radius.circular(barWidth / 2),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform;
  }
}
