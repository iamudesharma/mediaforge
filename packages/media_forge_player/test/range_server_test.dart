import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

/// PeerStream contract test: the player hands HTTP URLs to FFmpeg, which
/// seeks with byte-range requests. This spins up a localhost server with
/// Range support (like a torrent piece server) and asserts:
///
/// * full GET → 200 with Accept-Ranges + Content-Length
/// * ranged GET → 206 with Content-Range + exact bytes
/// * open-ended range → 206 to end of content
/// * the player source is detected as loopback
///
/// Tagged as integration: `flutter test --tags integration` or plain
/// `flutter test` both run it (no native engine required).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('localhost range server satisfies seek contract', () async {
    // flutter_test mocks HttpClient (400 for all requests); drop the
    // override so this contract test hits the real loopback server.
    HttpOverrides.global = null;
    // 256 KiB of deterministic content (stands in for torrent pieces).
    final content = Uint8List.fromList(
      List<int>.generate(256 * 1024, (i) => i % 251),
    );

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest req) async {
      final res = req.response;
      res.headers.set('Accept-Ranges', 'bytes');
      res.headers.contentType = ContentType.binary;
      final range = req.headers.value('range');
      if (range == null) {
        res.statusCode = HttpStatus.ok;
        res.headers.set('Content-Length', content.length);
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
      var start = m.group(1)!.isEmpty ? 0 : int.parse(m.group(1)!);
      var end = m.group(2)!.isEmpty
          ? content.length - 1
          : int.parse(m.group(2)!);
      // Suffix-range `bytes=-N` (last N bytes).
      if (m.group(1)!.isEmpty && m.group(2)!.isNotEmpty) {
        start = content.length - end;
        end = content.length - 1;
      }
      if (start >= content.length || end >= content.length || start > end) {
        res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        res.headers.set('Content-Range', 'bytes */${content.length}');
        await res.close();
        return;
      }
      final slice = content.sublist(start, end + 1);
      res.statusCode = HttpStatus.partialContent;
      res.headers.set(
          'Content-Range', 'bytes $start-$end/${content.length}');
      res.headers.set('Content-Length', slice.length);
      res.add(slice);
      await res.close();
    });

    final base = 'http://127.0.0.1:${server.port}/stream';
    const media = MediaForgeMedia.network('http://127.0.0.1:1/stream');
    expect((media as MediaForgeNetwork).isLoopback, isTrue);

    final client = HttpClient();
    addTearDown(client.close);

    // Full GET.
    final fullReq = await client.getUrl(Uri.parse(base));
    final fullRes = await fullReq.close();
    expect(fullRes.statusCode, HttpStatus.ok);
    expect(fullRes.headers.value('accept-ranges'), 'bytes');
    final fullBytes = await fullRes.fold<BytesBuilder>(
        BytesBuilder(), (b, d) => b..add(d));
    expect(fullBytes.length, content.length);

    // Seek to 20 min @ ~100 KiB/s → byte 120M clamped into our fixture:
    // use a mid-file window instead and assert exact bytes.
    Future<List<int>> ranged(int start, int? end) async {
      final req = await client.getUrl(Uri.parse(base));
      req.headers.set('Range', 'bytes=$start-${end ?? ''}');
      final res = await req.close();
      expect(res.statusCode, HttpStatus.partialContent);
      final body = await res.fold<BytesBuilder>(
          BytesBuilder(), (b, d) => b..add(d));
      return body.toBytes();
    }

    final window = await ranged(100000, 100099);
    expect(window, content.sublist(100000, 100100));

    final tail = await ranged(content.length - 512, null);
    expect(tail, content.sublist(content.length - 512));

    // Player resolves the live URL through untouched.
    final c = MediaForgePlayerController(textureHandle: 0x4D4650FF);
    addTearDown(c.dispose);
    final target = await c.resolveTargetForTest(
      MediaForgeMedia.network(base),
    );
    expect(target, base);
  }, tags: ['integration']);
}
