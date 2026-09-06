import 'package:flutter/material.dart';

import 'widgets/player_icon_button.dart';

/// Large center transport cluster: replay-10 · play/pause · forward-10.
class CenterPlaybackControls extends StatelessWidget {
  const CenterPlaybackControls({
    super.key,
    required this.isPlaying,
    required this.onPlayPause,
    required this.onReplay10,
    required this.onForward10,
    this.enabled = true,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback onReplay10;
  final VoidCallback onForward10;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlayerIconButton(
          icon: Icons.replay_10,
          tooltip: 'Back 10 seconds (Left arrow)',
          onPressed: enabled ? onReplay10 : null,
          size: 56,
          iconSize: 30,
        ),
        const SizedBox(width: 8),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.45),
          ),
          alignment: Alignment.center,
          child: PlayerIconButton(
            icon: isPlaying ? Icons.pause : Icons.play_arrow,
            tooltip: isPlaying
                ? 'Pause (Space)'
                : 'Play (Space)',
            onPressed: enabled ? onPlayPause : null,
            size: 68,
            iconSize: 40,
          ),
        ),
        const SizedBox(width: 8),
        PlayerIconButton(
          icon: Icons.forward_10,
          tooltip: 'Forward 10 seconds (Right arrow)',
          onPressed: enabled ? onForward10 : null,
          size: 56,
          iconSize: 30,
        ),
      ],
    );
  }
}
