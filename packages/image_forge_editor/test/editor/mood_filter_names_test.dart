import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/services/mood_filter_names.dart';
import 'package:image_forge_editor/image_forge_editor.dart';

void main() {
  test('mood filter index round-trip', () {
    expect(moodFilterIndex(null), 0);
    expect(moodFilterAtIndex(0), isNull);
    for (final p in MoodFilterPreset.values) {
      final i = moodFilterIndex(p);
      expect(i, greaterThan(0));
      expect(moodFilterAtIndex(i), p);
      expect(moodFilterDisplayName(p), isNotEmpty);
    }
  });
}
