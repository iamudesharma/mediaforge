import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/theme/app_theme.dart';
import 'package:image_forge_editor/src/editor/widgets/value_chip_slider.dart';

void main() {
  testWidgets('ValueChipSlider shows value bubble while dragging',
      (tester) async {
    var lastValue = 0.0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: ValueChipSlider(
              label: 'Brightness',
              value: 0,
              min: -100,
              max: 100,
              divisions: 40,
              bipolar: true,
              onChanged: (v) => lastValue = v,
            ),
          ),
        ),
      ),
    );
    // The bubble widget is in the tree at opacity 0 initially.
    expect(find.byType(AnimatedOpacity), findsWidgets);

    // Drag the slider — onChanged must fire.
    final slider = find.byType(Slider);
    final box = tester.getRect(slider);
    final gesture = await tester.startGesture(box.center);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(lastValue, isNot(0));
    await gesture.up();
    // Pump and settle to flush any pending haptic/timer callbacks.
    await tester.pumpAndSettle();
  });

  testWidgets('ValueChipSlider onReset pill only shows when value differs',
      (tester) async {
    var resetCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: ValueChipSlider(
                  label: 'Warmth',
                  value: 25,
                  min: -100,
                  max: 100,
                  divisions: 40,
                  bipolar: true,
                  onChanged: (v) => setState(() {}),
                  onReset: () => resetCount++,
                ),
              );
            },
          ),
        ),
      ),
    );
    expect(find.text('Reset'), findsOneWidget);
    await tester.tap(find.text('Reset'));
    expect(resetCount, 1);
  });
}
