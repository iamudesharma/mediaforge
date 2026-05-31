/// Shared timeline time formatting.
abstract final class TimelineFormat {
  static String ms(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    final h = m ~/ 60;
    if (h > 0) {
      return '${h}h ${m % 60}m ${s % 60}s';
    }
    if (m > 0) {
      return '${m}m ${s % 60}s';
    }
    return '${s}s';
  }

  static String clock(int ms) {
    final s = ms ~/ 1000;
    final m = s ~/ 60;
    return '${m.toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
