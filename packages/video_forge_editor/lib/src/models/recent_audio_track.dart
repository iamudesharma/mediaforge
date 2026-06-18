/// Recently picked audio track for the custom music sheet.
class RecentAudioTrack {
  const RecentAudioTrack({
    required this.path,
    required this.displayName,
    required this.durationMs,
    required this.pickedAt,
  });

  final String path;
  final String displayName;
  final int durationMs;
  final DateTime pickedAt;

  RecentAudioTrack copyWith({
    String? path,
    String? displayName,
    int? durationMs,
    DateTime? pickedAt,
  }) {
    return RecentAudioTrack(
      path: path ?? this.path,
      displayName: displayName ?? this.displayName,
      durationMs: durationMs ?? this.durationMs,
      pickedAt: pickedAt ?? this.pickedAt,
    );
  }
}
