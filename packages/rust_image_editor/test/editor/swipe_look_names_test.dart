import 'package:flutter_test/flutter_test.dart';
import 'package:rust_image_core/rust_image_core.dart';
import 'package:rust_image_editor/src/editor/services/swipe_look_names.dart';

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
