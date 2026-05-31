import 'package:image_forge_editor/src/image_forge_editor.dart';

/// User-facing label for a swipe mood filter.
String moodFilterDisplayName(MoodFilterPreset preset) {
  return switch (preset) {
    MoodFilterPreset.rose => 'Rose',
    MoodFilterPreset.clarendon => 'Clarendon',
    MoodFilterPreset.juno => 'Juno',
    MoodFilterPreset.valencia => 'Valencia',
    MoodFilterPreset.lark => 'Lark',
    MoodFilterPreset.reyes => 'Reyes',
    MoodFilterPreset.gingham => 'Gingham',
    MoodFilterPreset.loFi => 'Lo-Fi',
    MoodFilterPreset.moon => 'Moon',
    MoodFilterPreset.aden => 'Aden',
    MoodFilterPreset.perpetua => 'Perpetua',
    MoodFilterPreset.mayfair => 'Mayfair',
    MoodFilterPreset.hudson => 'Hudson',
    MoodFilterPreset.sierra => 'Sierra',
    MoodFilterPreset.willow => 'Willow',
    MoodFilterPreset.inkwell => 'Inkwell',
  };
}

/// 0 = Original; 1…N = [MoodFilterPreset.values] in order.
int moodFilterIndex(MoodFilterPreset? preset) {
  if (preset == null) return 0;
  return MoodFilterPreset.values.indexOf(preset) + 1;
}

MoodFilterPreset? moodFilterAtIndex(int index) {
  if (index <= 0) return null;
  final presets = MoodFilterPreset.values;
  if (index > presets.length) return null;
  return presets[index - 1];
}

int get moodFilterCount => MoodFilterPreset.values.length + 1;
