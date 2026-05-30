import 'package:flutter/material.dart';
import 'package:rust_media_runtime/rust_media_runtime.dart';

import '../services/rust_backend.dart';

/// Expandable diagnostics panel for the Rust MediaPlaybackEngine.
///
/// Shows decode capabilities, A/V drift, queue depths, and HW/SW path.
/// Only useful when the Rust backend is active.
class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({super.key, required this.backend});

  final RustBackend backend;

  @override
  Widget build(BuildContext context) {
    final diag = backend.lastDiagnostics;
    final engine = backend.engine;

    if (engine == null) {
      return const Center(
        child: Text(
          'Rust backend not active',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
      );
    }

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rust Media Runtime Diagnostics',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (diag != null) ...[
              _DiagnosticsRow(label: 'State', value: diag.state.name),
              _DiagnosticsRow(label: 'Media Time', value: '${diag.mediaTimeMs}ms'),
              _DiagnosticsRow(label: 'Audio Clock', value: '${diag.audioClockMs}ms'),
              _DiagnosticsRow(label: 'Wall Clock', value: '${diag.wallClockMs}ms'),
              _DiagnosticsRow(label: 'Presented PTS', value: '${diag.presentedPtsMs}ms'),
              _DiagnosticsRow(label: 'A/V Drift', value: '${diag.avDriftMs}ms'),
              const SizedBox(height: 8),
              const Text(
                'Queue Depths',
                style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              _DiagnosticsRow(label: 'Video Packets', value: '${diag.videoPacketsInQueue}'),
              _DiagnosticsRow(label: 'Audio Packets', value: '${diag.audioPacketsInQueue}'),
              _DiagnosticsRow(label: 'Video Frames', value: '${diag.videoFramesInQueue}'),
              _DiagnosticsRow(label: 'Audio Frames', value: '${diag.audioFramesInQueue}'),
              const SizedBox(height: 8),
              _DiagnosticsRow(
                label: 'Video Starved',
                value: diag.videoStarved ? 'YES' : 'no',
                isError: diag.videoStarved,
              ),
              _DiagnosticsRow(
                label: 'Healthy',
                value: diag.avDriftMs < 500 ? 'YES' : 'no',
                isError: diag.avDriftMs >= 500,
              ),
            ] else ...[
              const Text(
                'Waiting for diagnostics...',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
            FutureBuilder<DecodeCapabilities>(
              future: engine.getDecodeCapabilities(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final cap = snapshot.data!;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Decode Capabilities',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    _DiagnosticsRow(label: 'FFmpeg', value: cap.ffmpegVersion),
                    _DiagnosticsRow(
                      label: 'HEVC VideoToolbox',
                      value: cap.hevcVideotoolbox ? 'YES' : 'no',
                      isError: !cap.hevcVideotoolbox,
                    ),
                    _DiagnosticsRow(
                      label: 'H264 VideoToolbox',
                      value: cap.h264Videotoolbox ? 'YES' : 'no',
                      isError: !cap.h264Videotoolbox,
                    ),
                    _DiagnosticsRow(
                      label: 'HW Decode Disabled',
                      value: cap.hwDecodeDisabledEnv ? 'YES' : 'no',
                      isError: cap.hwDecodeDisabledEnv,
                    ),
                    _DiagnosticsRow(
                      label: 'Ready for 4K HEVC',
                      value: cap.readyForHevcHw ? 'YES' : 'no',
                      isError: !cap.readyForHevcHw,
                    ),
                    if (cap.hint.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        cap.hint,
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsRow extends StatelessWidget {
  const _DiagnosticsRow({
    required this.label,
    required this.value,
    this.isError = false,
  });

  final String label;
  final String value;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isError ? Colors.redAccent : Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
