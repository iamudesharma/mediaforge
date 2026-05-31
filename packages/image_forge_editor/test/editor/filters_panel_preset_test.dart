import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/services/filter_descriptor.dart';
import 'package:image_forge_editor/src/image_forge_editor.dart';

void main() {
  test('preset descriptor carries strength to ImageFilter', () {
    final d = FilterDescriptor.preset(FilterPreset.dramatic, strength: 0.5);
    expect(d.presetStrength, 0.5);
    final f = d.toImageFilter();
    expect(
      f,
      isA<ImageFilter_Preset>().having(
        (p) => p.strength,
        'strength',
        0.5,
      ),
    );
  });
}
