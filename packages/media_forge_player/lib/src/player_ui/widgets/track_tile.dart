import 'package:flutter/material.dart';

import '../../track_info.dart';
import '../utils.dart';

/// Human label for a track (`Title · lang`, falling back to codec/kind).
String trackDisplayName(MediaForgeTrack track) {
  final label = track.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final lang = track.language?.trim();
  final codec = track.codec?.trim();
  final kind = switch (track.kind) {
    MediaTrackKind.audio => 'Audio',
    MediaTrackKind.subtitle => 'Subtitle',
    MediaTrackKind.video => 'Video',
  };
  if (lang != null && lang.isNotEmpty && codec != null && codec.isNotEmpty) {
    return '$lang · $codec';
  }
  if (lang != null && lang.isNotEmpty) return '$lang $kind';
  if (codec != null && codec.isNotEmpty) return '$kind · $codec';
  return '$kind ${track.id}';
}

/// Detail line for an audio track (channels · rate · bitrate · flags).
String audioTrackDetails(MediaForgeAudioTrack track) {
  final parts = <String>[
    formatChannels(track.channels),
    formatSampleRate(track.sampleRate),
    if (track.bitrate > 0) formatBitrate(track.bitrate),
  ];
  final flags = trackFlags(track);
  if (flags.isNotEmpty) parts.add(flags);
  return parts.join(' · ');
}

/// Detail line for a subtitle track (codec · flags · source).
String subtitleTrackDetails(MediaForgeSubtitleTrack track) {
  final parts = <String>[
    if (track.codec?.isNotEmpty ?? false) track.codec!,
    if (!track.isEmbedded) 'external',
  ];
  final flags = trackFlags(track);
  if (flags.isNotEmpty) parts.add(flags);
  return parts.join(' · ');
}

/// `Default`, `Forced` flag labels (empty when neither).
String trackFlags(MediaForgeTrack track) {
  final flags = <String>[
    if (track.isDefault) 'Default',
    if (track.isForced) 'Forced',
  ];
  return flags.join(', ');
}

/// Radio-style selectable track row shared by audio/subtitle/video lists.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.leading,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: leading ??
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 20,
            color: selected ? accent : Colors.white54,
          ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          color: selected ? accent : Colors.white,
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: subtitle == null || subtitle!.isEmpty
          ? null
          : Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
      onTap: onTap,
    );
  }
}
