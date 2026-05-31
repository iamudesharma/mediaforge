import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge/image_forge.dart';
import 'package:image_forge_editor/src/editor/services/swipe_look_names.dart';

void main() {
  test('swipe look indices round-trip', () {
    for (final p in SwipeLookPreset.values) {
      expect(swipeLookAtIndex(swipeLookIndex(p)), p);
      expect(swipeLookDisplayNameFor(p), isNotEmpty);
    }
    expect(swipeLookCount, SwipeLookPreset.values.length + 1);
    expect(swipeLookIndex(null), 0);
  });
}
