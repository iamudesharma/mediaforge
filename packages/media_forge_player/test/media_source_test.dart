import 'package:flutter_test/flutter_test.dart';
import 'package:media_forge_player/media_forge_player.dart';

void main() {
  group('MediaForgeMedia', () {
    test('file source keeps path', () {
      const m = MediaForgeMedia.file('/tmp/a.mp4');
      expect(m, isA<MediaForgeFile>());
      expect((m as MediaForgeFile).path, '/tmp/a.mp4');
    });

    test('network source keeps url + headers', () {
      const m = MediaForgeMedia.network(
        'http://127.0.0.1:8080/stream',
        headers: {'Authorization': 'Bearer x'},
      );
      expect(m, isA<MediaForgeNetwork>());
      final n = m as MediaForgeNetwork;
      expect(n.url, 'http://127.0.0.1:8080/stream');
      expect(n.headers, {'Authorization': 'Bearer x'});
    });

    test('loopback detection covers PeerStream hosts', () {
      const v4 = MediaForgeMedia.network('http://127.0.0.1:1234/s');
      const local = MediaForgeMedia.network('http://localhost:1234/s');
      const v6 = MediaForgeMedia.network('http://[::1]:1234/s');
      const remote = MediaForgeMedia.network('https://cdn.example.com/v.mp4');
      expect((v4 as MediaForgeNetwork).isLoopback, isTrue);
      expect((local as MediaForgeNetwork).isLoopback, isTrue);
      expect((v6 as MediaForgeNetwork).isLoopback, isTrue);
      expect((remote as MediaForgeNetwork).isLoopback, isFalse);
    });

    test('asset source keeps key', () {
      const m = MediaForgeMedia.asset('assets/sample.mp4');
      expect((m as MediaForgeAsset).assetKey, 'assets/sample.mp4');
    });
  });
}
