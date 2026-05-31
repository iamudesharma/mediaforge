import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge/media_forge.dart';

void main() {
  testWidgets('MediaVideoSurface builds with empty presenter', (tester) async {
    final presenter = MediaPlaybackPresenter(textureHandle: 99);
    addTearDown(presenter.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaVideoSurface(
            presenter: presenter,
            placeholder: const Text('placeholder'),
          ),
        ),
      ),
    );

    expect(find.text('placeholder'), findsOneWidget);
    expect(find.byType(MediaVideoSurface), findsOneWidget);
  });
}
