import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_forge_editor/src/services/media_ingest.dart';
import 'package:video_forge_editor/src/services/remote_ingest_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('remote_ingest_cache_test_');
    RemoteIngestCache.testDirOverride = tempDir;
  });

  tearDown(() async {
    RemoteIngestCache.testDirOverride = null;
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  group('RemoteIngestCache.cacheKeyFor', () {
    test('stable for same URL, distinct per URL', () {
      final a = RemoteIngestCache.cacheKeyFor('https://cdn.example.com/v.mp4');
      final b = RemoteIngestCache.cacheKeyFor('https://cdn.example.com/v.mp4');
      final c = RemoteIngestCache.cacheKeyFor('https://cdn.example.com/w.mp4');
      expect(a, b);
      expect(a, isNot(c));
      expect(a.contains(RegExp(r'^[a-z0-9-]{1,24}_[0-9a-f]{16}$')), isTrue);
    });

    test('streaming sources are detected', () {
      expect(
        RemoteIngestCache.isStreamingSource('https://x.example.com/v.m3u8'),
        isTrue,
      );
      expect(
        RemoteIngestCache.isStreamingSource('https://x.example.com/v.mpd'),
        isTrue,
      );
      expect(
        RemoteIngestCache.isStreamingSource('https://x.example.com/v.mp4'),
        isFalse,
      );
    });

    test('streaming source throws without network', () async {
      expect(
        () => RemoteIngestCache.fetch('https://x.example.com/live.m3u8'),
        throwsA(isA<RemoteCacheStreamingSource>()),
      );
    });
  });

  group('fetch against localhost range server', () {
    late HttpServer server;
    late Uint8List content;
    late List<({String method, String? range})> requests;
    late String base;

    setUp(() async {
      // flutter_test mocks HttpClient (400 for all requests); drop the
      // override so this hits the real loopback server.
      HttpOverrides.global = null;
      content = Uint8List.fromList(
        List<int>.generate(256 * 1024, (i) => i % 251),
      );
      requests = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}/video.mp4';
      server.listen((HttpRequest req) async {
        requests.add((
          method: req.method,
          range: req.headers.value(HttpHeaders.rangeHeader),
        ));
        final res = req.response;
        res.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        res.headers.contentType = ContentType.binary;
        if (req.method == 'HEAD') {
          res.statusCode = HttpStatus.ok;
          res.headers.set(HttpHeaders.contentLengthHeader, content.length);
          await res.close();
          return;
        }
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range == null) {
          res.statusCode = HttpStatus.ok;
          res.headers.set(HttpHeaders.contentLengthHeader, content.length);
          res.add(content);
          await res.close();
          return;
        }
        final m = RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
        if (m == null) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          await res.close();
          return;
        }
        final start = int.parse(m.group(1)!);
        final end = m.group(2)!.isEmpty
            ? content.length - 1
            : int.parse(m.group(2)!);
        if (start >= content.length) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(
              HttpHeaders.contentRangeHeader, 'bytes */${content.length}');
          await res.close();
          return;
        }
        final slice = content.sublist(start, end + 1);
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${content.length}');
        res.headers.set(HttpHeaders.contentLengthHeader, slice.length);
        res.add(slice);
        await res.close();
      });
      addTearDown(() => server.close(force: true));
    });

    test('full download then cache hit with no new requests', () async {
      final first = await RemoteIngestCache.fetch(base);
      expect(first.cacheHit, isFalse);
      expect(first.resumedFromBytes, 0);
      expect(first.totalBytes, content.length);
      final bytes = await File(first.filePath).readAsBytes();
      expect(bytes, content);

      final seen = requests.length;
      expect(seen, greaterThan(0));
      final second = await RemoteIngestCache.fetch(base);
      expect(second.cacheHit, isTrue);
      expect(second.filePath, first.filePath);
      // Cache hit performs zero network requests.
      expect(requests.length, seen);
    });

    test('partial .part resumes with Range request', () async {
      final key = RemoteIngestCache.cacheKeyFor(base);
      final half = content.length ~/ 2;
      await File('${tempDir.path}/$key.part')
          .writeAsBytes(content.sublist(0, half));

      final entry = await RemoteIngestCache.fetch(base);
      expect(entry.cacheHit, isFalse);
      expect(entry.resumedFromBytes, half);
      final bytes = await File(entry.filePath).readAsBytes();
      expect(bytes, content);
      // At least one request carried a Range header starting at half.
      expect(
        requests.any((r) => r.range == 'bytes=$half-'),
        isTrue,
      );
    });

    test('server ignoring Range restarts cleanly (no corrupt concat)',
        () async {
      // Dedicated server that always returns 200 full body.
      final plain = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => plain.close(force: true));
      plain.listen((HttpRequest req) async {
        final res = req.response;
        res.statusCode = HttpStatus.ok;
        res.headers.set(HttpHeaders.contentLengthHeader, content.length);
        res.add(content);
        await res.close();
      });
      final url = 'http://127.0.0.1:${plain.port}/flat.mp4';
      final key = RemoteIngestCache.cacheKeyFor(url);
      await File('${tempDir.path}/$key.part')
          .writeAsBytes(content.sublist(0, 1024));

      final entry = await RemoteIngestCache.fetch(url);
      final bytes = await File(entry.filePath).readAsBytes();
      expect(bytes, content);
      expect(entry.resumedFromBytes, 0);
    });
  });

  group('playback position memory', () {
    test('save/load roundtrip per key', () async {
      expect(await RemoteIngestCache.lastPositionMs('nope'), 0);
      await RemoteIngestCache.savePosition('key-a', 285000);
      expect(await RemoteIngestCache.lastPositionMs('key-a'), 285000);
      await RemoteIngestCache.savePosition('key-a', 300000);
      expect(await RemoteIngestCache.lastPositionMs('key-a'), 300000);
      expect(await RemoteIngestCache.lastPositionMs('key-b'), 0);
    });
  });

  group('MediaIngestResult cache fields', () {
    test('defaults preserve backward compat', () {
      const r = MediaIngestResult(phase: MediaIngestPhase.ready);
      expect(r.cacheKey, isNull);
      expect(r.resumePositionMs, 0);
      expect(r.cacheHit, isFalse);
    });

    test('copyWith carries cache fields', () {
      const r = MediaIngestResult(phase: MediaIngestPhase.ready);
      final c = r.copyWith(
        cacheKey: 'host_abc123',
        resumePositionMs: 5000,
        cacheHit: true,
      );
      expect(c.cacheKey, 'host_abc123');
      expect(c.resumePositionMs, 5000);
      expect(c.cacheHit, isTrue);
    });
  });
}
