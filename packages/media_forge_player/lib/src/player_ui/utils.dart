/// Small formatting helpers shared by the player UI.
String formatDuration(Duration d) {
  final totalSeconds = d.inSeconds.clamp(0, 99 * 3600 + 3599);
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:$mm:$ss';
  return '$m:$ss';
}

/// `bits/s` → human label (`800 kb/s`, `12.4 Mb/s`).
String formatBitrate(int bps) {
  if (bps <= 0) return '—';
  if (bps < 1000) return '$bps b/s';
  if (bps < 1000000) return '${(bps / 1000).toStringAsFixed(0)} kb/s';
  return '${(bps / 1000000).toStringAsFixed(1)} Mb/s';
}

/// Byte count → human label (`1.4 MB`).
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var u = 0;
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  return '${v.toStringAsFixed(v < 10 && u > 0 ? 1 : 0)} ${units[u]}';
}

/// `48000` → `48.0 kHz`.
String formatSampleRate(int? hz) {
  if (hz == null || hz <= 0) return '—';
  if (hz < 1000) return '$hz Hz';
  return '${(hz / 1000).toStringAsFixed(1)} kHz';
}

/// Channel count → familiar layout label.
String formatChannels(int? channels) {
  switch (channels) {
    case 1:
      return 'Mono';
    case 2:
      return 'Stereo';
    case 6:
      return '5.1';
    case 8:
      return '7.1';
    case null:
    case 0:
      return '—';
    default:
      return '$channels ch';
  }
}
