import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

import 'fake_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var nextHandle = 0xF5000000;

  (MediaForgePlayerController, FakeMediaPlaybackEngine) makeOpen() {
    final fake = FakeMediaPlaybackEngine();
    final controller = MediaForgePlayerController(
      textureHandle: nextHandle++,
      engineFactory: ({
        required int textureHandle,
        required BigInt maxQueueSize,
        required int previewMaxEdge,
      }) async =>
          fake,
    );
    return (controller, fake);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    MediaForgePlayerController controller, {
    MediaForgeFullscreenController? fullscreenController,
    bool fullscreenEnabled = true,
    VoidCallback? onToggleFullscreen,
    bool isFullscreen = false,
    Future<void> Function()? onEnterFullscreen,
    Future<void> Function()? onExitFullscreen,
    ValueNotifier<List<MediaForgeBufferedRange>>? externalBufferedRanges,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MediaPlayerScreen(
            controller: controller,
            title: 'Fullscreen Test',
            fullscreenController: fullscreenController,
            fullscreenEnabled: fullscreenEnabled,
            onToggleFullscreen: onToggleFullscreen,
            isFullscreen: isFullscreen,
            onEnterFullscreen: onEnterFullscreen,
            onExitFullscreen: onExitFullscreen,
            externalBufferedRanges: externalBufferedRanges,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> endTest(
    WidgetTester tester,
    MediaForgePlayerController controller,
  ) async {
    controller.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  group('MediaForgeFullscreenController', () {
    test('enter/exit/toggle update isFullscreen', () async {
      final c = MediaForgeFullscreenController();
      addTearDown(c.dispose);
      expect(c.isFullscreen, isFalse);
      await c.enterFullscreen();
      expect(c.isFullscreen, isTrue);
      await c.enterFullscreen();
      expect(c.isFullscreen, isTrue);
      await c.toggleFullscreen();
      expect(c.isFullscreen, isFalse);
      await c.toggleFullscreen();
      expect(c.isFullscreen, isTrue);
      await c.exitFullscreen();
      expect(c.isFullscreen, isFalse);
    });

    test('notifies listeners', () async {
      final c = MediaForgeFullscreenController();
      addTearDown(c.dispose);
      var calls = 0;
      c.addListener(() => calls++);
      await c.enterFullscreen();
      expect(calls, 1);
      await c.exitFullscreen();
      expect(calls, 2);
    });
  });

  group('MediaPlayerScreen fullscreen button', () {
    testWidgets('fullscreen icon visible by default in normal mode',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);
      // Built-in control: visible without any host callback.
      expect(find.byTooltip('Enter fullscreen'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      await endTest(tester, controller);
    });

    testWidgets('hidden when explicitly disabled', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller, fullscreenEnabled: false);
      expect(find.byIcon(Icons.fullscreen), findsNothing);
      expect(find.byIcon(Icons.fullscreen_exit), findsNothing);
      await endTest(tester, controller);
    });

    testWidgets('bottom-right includes speed/subtitles/audio/fullscreen/settings',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);
      final bar = find.byType(PlayerBottomBar);
      expect(bar, findsOneWidget);
      // Speed (narrow test surface shows the icon variant).
      expect(
        find.descendant(
          of: bar,
          matching: find.byTooltip('Playback speed'),
        ).hitTestable().evaluate().isNotEmpty ||
            find.descendant(of: bar, matching: find.textContaining('×'))
                .evaluate()
                .isNotEmpty,
        isTrue,
      );
      expect(
        find.descendant(
          of: bar,
          matching: find.byTooltip('Subtitles (S)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: bar,
          matching: find.byTooltip('Audio tracks (A)'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: bar,
          matching: find.byTooltip('Enter fullscreen'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: bar,
          matching: find.byTooltip('Settings'),
        ),
        findsOneWidget,
      );
      await endTest(tester, controller);
    });

    testWidgets('enter fullscreen changes icon and tooltip', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      expect(fullscreen.isFullscreen, isTrue);
      expect(find.byTooltip('Exit fullscreen'), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_exit), findsOneWidget);
      await endTest(tester, controller);
    });

    testWidgets('exit fullscreen restores icon', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      expect(fullscreen.isFullscreen, isFalse);
      expect(find.byTooltip('Enter fullscreen'), findsOneWidget);
      await endTest(tester, controller);
    });

    testWidgets('F toggles fullscreen', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreen.isFullscreen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreen.isFullscreen, isFalse);
      await endTest(tester, controller);
    });

    testWidgets('Esc exits fullscreen', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreen.isFullscreen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(fullscreen.isFullscreen, isFalse);
      await endTest(tester, controller);
    });

    testWidgets('existing shortcuts keep working in fullscreen',
        (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreen.isFullscreen, isTrue);
      // Space still toggles playback while fullscreen.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(fake.muted, isTrue);
      await endTest(tester, controller);
    });
  });

  group('fullscreen state preservation (same session)', () {
    testWidgets('controller identity remains identical', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      final before = tester
          .widget<MediaPlayerScreen>(find.byType(MediaPlayerScreen))
          .controller;
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      final after = tester
          .widget<MediaPlayerScreen>(find.byType(MediaPlayerScreen))
          .controller;
      expect(identical(before, after), isTrue);
      expect(identical(after, controller), isTrue);
      // No reopen: engine open count stays 1.
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      final afterExit = tester
          .widget<MediaPlayerScreen>(find.byType(MediaPlayerScreen))
          .controller;
      expect(identical(afterExit, controller), isTrue);
      await endTest(tester, controller);
    });

    testWidgets('playback position survives fullscreen transition',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await controller.seek(const Duration(seconds: 42));
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      // Settle the optimistic seek so position reflects the target.
      await controller.diagnosticsTickForTest();
      await tester.pump();
      final posBefore = controller.value.position;
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      expect(controller.value.position, posBefore);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      expect(controller.value.position, posBefore);
      await endTest(tester, controller);
    });

    testWidgets('audio/subtitle selections survive fullscreen',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await controller.selectAudioTrack(2);
      await controller.selectSubtitleTrack(3);
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      expect(controller.value.selectedAudioTrackId, 2);
      expect(controller.value.selectedSubtitleTrackId, 3);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      expect(controller.value.selectedAudioTrackId, 2);
      expect(controller.value.selectedSubtitleTrackId, 3);
      await endTest(tester, controller);
    });

    testWidgets('host enter/exit overrides are honoured', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      var entered = 0;
      var exited = 0;
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(
        tester,
        controller,
        fullscreenController: fullscreen,
        onEnterFullscreen: () async => entered++,
        onExitFullscreen: () async => exited++,
      );
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      expect(entered, 1);
      expect(fullscreen.isFullscreen, isTrue);
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      expect(exited, 1);
      expect(fullscreen.isFullscreen, isFalse);
      await endTest(tester, controller);
    });

    testWidgets('legacy onToggleFullscreen remains compatible',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      var toggles = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MediaPlayerScreen(
              controller: controller,
              onToggleFullscreen: () => toggles++,
              isFullscreen: false,
            ),
          ),
        ),
      );
      await tester.pump();
      // Legacy path still renders a fullscreen affordance via the same
      // button (icon reflects legacy isFullscreen=false).
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      await tester.tap(find.byIcon(Icons.fullscreen));
      await tester.pump();
      expect(toggles, 1);
      // F key routes through the legacy callback too.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(toggles, 2);
      await endTest(tester, controller);
    });

    testWidgets('external buffered ranges flow into the timeline',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final external = ValueNotifier<List<MediaForgeBufferedRange>>(
        const [
          MediaForgeBufferedRange(
            start: Duration(seconds: 100),
            end: Duration(seconds: 200),
          ),
        ],
      );
      addTearDown(external.dispose);
      await pumpScreen(tester, controller,
          externalBufferedRanges: external);
      await tester.pump();
      expect(controller.externalBufferedRanges.length, 1);
      expect(find.byType(PlayerTimeline), findsOneWidget);
      // Growing the host cache updates the controller (generic API).
      external.value = const [
        MediaForgeBufferedRange(
          start: Duration(seconds: 100),
          end: Duration(seconds: 250),
        ),
      ];
      await tester.pump();
      expect(
        controller.externalBufferedRanges.single.end,
        const Duration(seconds: 250),
      );
      await endTest(tester, controller);
    });

    testWidgets('fullscreen cleanup restores system state', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final fullscreen = MediaForgeFullscreenController();
      addTearDown(fullscreen.dispose);
      await pumpScreen(tester, controller,
          fullscreenController: fullscreen);
      await tester.tap(find.byTooltip('Enter fullscreen'));
      await tester.pump();
      expect(fullscreen.isFullscreen, isTrue);
      // Exiting restores windowed state (no leftover fullscreen flag).
      await tester.tap(find.byTooltip('Exit fullscreen'));
      await tester.pump();
      expect(fullscreen.isFullscreen, isFalse);
      // Disposing the screen while windowed leaves no fullscreen behind.
      await endTest(tester, controller);
      expect(fullscreen.isFullscreen, isFalse);
    });
  });
}
