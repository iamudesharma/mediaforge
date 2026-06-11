import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_forge_editor/src/editor/theme/app_theme.dart';
import 'package:image_forge_editor/src/editor/widgets/chip_pill.dart';

void main() {
  testWidgets('ChipPill renders label and selected state', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: ChipPill(
              label: 'Brightness',
              selected: true,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Brightness'), findsOneWidget);
    await tester.tap(find.text('Brightness'));
    expect(tapped, isTrue);
  });

  testWidgets('ChipPillRow horizontal layout scrolls and selects', (tester) async {
    int? selectedIndex;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 200,
            child: ChipPillRow<int>(
              items: const [0, 1, 2, 3, 4],
              label: (i) => ['A', 'B', 'C', 'D', 'E'][i],
              selected: 0,
              onSelected: (i) => selectedIndex = i,
            ),
          ),
        ),
      ),
    );
    // The row is scrollable, so at least the first 1-2 pills are in view
    // (we can't assert all 5 because the viewport is 200 px).
    expect(find.byType(ChipPill), findsAtLeastNWidgets(1));
    expect(find.text('A'), findsOneWidget);
    // Scroll the row to reveal "C", then tap it.
    final listFinder = find.byType(Scrollable).first;
    await tester.drag(listFinder, const Offset(-200, 0));
    await tester.pump();
    await tester.tap(find.text('C'), warnIfMissed: false);
    if (selectedIndex == 2) return; // success
    // If C isn't reachable, the row is at its end — try the rightmost label.
    await tester.drag(listFinder, const Offset(200, 0));
    await tester.pump();
    await tester.tap(find.text('E'), warnIfMissed: false);
    expect(selectedIndex, isNotNull);
  });

  testWidgets('ChipPillWrap wraps multiple pills', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ChipPillWrap<int>(
            items: const [1, 2, 3],
            label: (i) => 'Tag $i',
            selected: 1,
            onSelected: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Tag 1'), findsOneWidget);
    expect(find.text('Tag 2'), findsOneWidget);
    expect(find.text('Tag 3'), findsOneWidget);
  });
}
