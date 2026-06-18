import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_editor/src/panels/music_picker_sheet.dart';

void main() {
  testWidgets('MusicPickerSheet shows browse actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MusicPickerSheet.show(
                context,
                recentTracks: const [],
                muteOriginalAudio: true,
                onMuteOriginalChanged: (_) {},
                onVolumeChanged: (_) {},
                onSourceStartChanged: (_) {},
                onRemoveTrack: () {},
                onTrackPicked: (_) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Add music'), findsOneWidget);
    expect(find.text('Music library'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
  });
}
