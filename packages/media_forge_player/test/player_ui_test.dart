import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

import 'fake_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var nextHandle = 0x60000000;

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
    ValueNotifier<MediaPlayerTorrentStats?>? torrentStats,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MediaPlayerScreen(
            controller: controller,
            title: 'Test Media',
            subtitle: 'S1 E1',
            torrentStats: torrentStats,
          ),
        ),
      ),
    );
    await tester.pump();
  }


  /// End-of-body cleanup: dispose + flush timers/frames.
  ///
  /// Must run inside the test body (invariant verification happens before
  /// `addTearDown` callbacks).
  Future<void> endTest(
    WidgetTester tester,
    MediaForgePlayerController controller,
  ) async {
    controller.dispose();
    await tester.pump(const Duration(seconds: 5));
  }

  group('MediaPlayerScreen', () {
    testWidgets('shows title and toggles play', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);

      expect(find.text('Test Media'), findsOneWidget);
      expect(find.text('S1 E1'), findsOneWidget);
      Finder playButton() => find.descendant(
            of: find.byType(PlayerBottomBar),
            matching: find.byIcon(Icons.play_arrow),
          );
      Finder pauseButton() => find.descendant(
            of: find.byType(PlayerBottomBar),
            matching: find.byIcon(Icons.pause),
          );
      expect(playButton(), findsOneWidget);
      await tester.tap(playButton());
      await tester.pump();
      expect(fake.playing, isTrue);
      await tester.tap(pauseButton());
      await tester.pump();
      expect(fake.playing, isFalse);
      await endTest(tester, controller);
    });

    testWidgets('timeline drag commits a seek', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);

      final timeline = find.byType(PlayerTimeline);
      expect(timeline, findsOneWidget);
      await tester.drag(timeline, const Offset(200, 0));
      await tester.pump();
      expect(fake.seekLog, isNotEmpty);
      await endTest(tester, controller);
    });

    testWidgets('speed sheet changes rate', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);

      // Wide layout (800px) shows the rate text button.
      await tester.tap(find.text('1×'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PlaybackSpeedPanel), findsOneWidget);
      await tester.tap(find.text('2×'));
      await tester.pump();
      expect(fake.rate, 2.0);
      await endTest(tester, controller);
    });

    testWidgets('subtitle quick panel selects a track', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);

      await tester.tap(find.byTooltip('Subtitles (S)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(SubtitleTracksPanel), findsOneWidget);
      await tester.tap(find.text('English').last);
      await tester.pump();
      expect(fake.subtitleSelectLog, contains(3));
      await endTest(tester, controller);
    });

    testWidgets('space key toggles playback', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.playing, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(fake.playing, isFalse);
      await endTest(tester, controller);
    });

    testWidgets('arrow keys seek, M mutes', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await pumpScreen(tester, controller);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(fake.seekLog, contains(10000));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(fake.muted, isTrue);
      await endTest(tester, controller);
    });

    testWidgets('error card offers retry', (tester) async {
      final (controller, _) = makeOpen();
      controller.value = controller.value.copyWith(
        errorDescription: 'boom: network unreachable',
      );
      await pumpScreen(tester, controller);

      expect(find.text('Playback failed'), findsOneWidget);
      expect(find.textContaining('boom'), findsOneWidget);
      await endTest(tester, controller);
    });

    testWidgets('completed state shows replay', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      controller.value = controller.value.copyWith(isCompleted: true);
      await pumpScreen(tester, controller);

      expect(find.byIcon(Icons.replay), findsOneWidget);
      await tester.tap(find.byIcon(Icons.replay));
      await tester.pump();
      expect(fake.openCount, 2); // default retry reopens
      await endTest(tester, controller);
    });

    testWidgets('torrent stats enable swarm section', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      final stats = ValueNotifier<MediaPlayerTorrentStats?>(
        const MediaPlayerTorrentStats(
          downloadSpeedBps: 125000,
          peers: 12,
          seeds: 3,
          downloadedBytes: 50 * 1024 * 1024,
          totalBytes: 100 * 1024 * 1024,
        ),
      );
      addTearDown(stats.dispose);
      await pumpScreen(tester, controller, torrentStats: stats);

      await tester.tap(find.byTooltip('Swarm stats'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pump();
      expect(find.text('Swarm (app-provided)'.toUpperCase()),
          findsOneWidget);
      expect(find.text('12'), findsWidgets);
      await endTest(tester, controller);
    });
  });

  group('standalone panels', () {
    testWidgets('audio panel lists tracks and selects', (tester) async {
      final (controller, fake) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: AudioTracksPanel(
              controller: controller,
              embeddedAudioMuted: false,
              onEmbeddedAudioMutedChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('English'), findsOneWidget);
      expect(find.text('Español'), findsOneWidget);
      await tester.tap(find.text('Español'));
      await tester.pump();
      expect(fake.audioSelectLog, contains(2));
      await endTest(tester, controller);
    });

    testWidgets('media information shows engine telemetry',
        (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      await controller.diagnosticsTickForTest();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MediaInformationPanel(controller: controller),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('h264-videotoolbox'), findsOneWidget);
      expect(find.text('Network stream'), findsOneWidget);
      // Stats rows live below the fold: scroll, then assert.
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
      expect(find.text('1.0 MB'), findsOneWidget);
      await endTest(tester, controller);
    });

    testWidgets('video settings switches fit', (tester) async {
      final (controller, _) = makeOpen();
      await controller.open(
        const MediaForgeMedia.network('http://127.0.0.1:8080/v'),
      );
      var fit = MediaPlayerFit.contain;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => VideoSettingsPanel(
                controller: controller,
                fit: fit,
                onFitChanged: (f) => setState(() => fit = f),
                displayQuarterTurns: 0,
                onDisplayRotationChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Fill'));
      await tester.pump();
      expect(fit, MediaPlayerFit.cover);
      await endTest(tester, controller);
    });
  });

  group('formatting utils', () {
    test('formatDuration', () {
      expect(formatDuration(Duration.zero), '0:00');
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(
          formatDuration(const Duration(hours: 2, minutes: 3, seconds: 4)),
          '2:03:04');
    });

    test('formatBitrate/formatBytes', () {
      expect(formatBitrate(0), '—');
      expect(formatBitrate(800000), '800 kb/s');
      expect(formatBitrate(12400000), '12.4 Mb/s');
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1048576), '1.0 MB');
    });

    test('formatChannels/formatSampleRate', () {
      expect(formatChannels(2), 'Stereo');
      expect(formatChannels(6), '5.1');
      expect(formatChannels(null), '—');
      expect(formatSampleRate(48000), '48.0 kHz');
    });
  });
}
