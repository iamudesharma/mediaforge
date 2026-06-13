import 'dart:io';

/// Helpers for local paths and remote video URLs passed to the native processor.
abstract final class VideoInput {
  /// Matches Rust [normalize_remote_input] (HTTP → HTTPS for Google CDN hosts).
  static String normalizeUrl(String value) {
    final trimmed = value.trim();
    final lower = trimmed.toLowerCase();
    if (trimmed.startsWith('http://') &&
        (lower.contains('googleapis.com') ||
            lower.contains('googleusercontent.com') ||
            lower.contains('gstatic.com'))) {
      return trimmed.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
    }
    return trimmed;
  }

  static bool isNetworkUrl(String value) {
    final trimmed = value.trim().toLowerCase();
    return trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('rtmp://') ||
        trimmed.startsWith('rtsp://') ||
        trimmed.startsWith('ftp://');
  }

  static bool isValid(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    if (isNetworkUrl(trimmed)) return true;
    return File(trimmed).existsSync();
  }

  static String displayName(String value) {
    final trimmed = value.trim();
    if (isNetworkUrl(trimmed)) {
      final withoutQuery = trimmed.split('?').first;
      final segment = withoutQuery.split('/').where((s) => s.isNotEmpty).lastOrNull;
      return segment ?? 'Remote video';
    }
    return trimmed.split(Platform.pathSeparator).last;
  }

  static String safeStem(String value) {
    final name = displayName(value);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return stem.replaceAll(RegExp(r'[^\w\-.]'), '_');
  }
}
