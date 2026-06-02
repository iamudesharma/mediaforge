// Dart-side wrapper around the demuxer/decoder cache FFI.
//
// The cache itself lives in Rust (`crate::cache::DecoderCache`); this
// file exposes a tiny Dart helper so app code can read stats and
// drop the cache without going through the raw generated bindings.
//
// `clearDecoderCache` and `decoderCacheStats` (the raw FFI top-level
// functions) are re-exported from `package:video_forge/video_forge.dart`
// for callers that want the synchronous (sync FRB) variant.

import 'package:video_forge/src/frb_generated/api.dart' show
    DecoderCacheStatsDto, clearDecoderCache, decoderCacheStats;

/// Snapshot of the decoder cache state.
class DecoderCacheStats {
  const DecoderCacheStats({
    required this.hits,
    required this.misses,
    required this.evictions,
    required this.entries,
    required this.workingSetBytes,
  });

  final int hits;
  final int misses;
  final int evictions;
  final int entries;
  final int workingSetBytes;

  /// Hit ratio in `[0, 1]`. Returns 0 when there have been no lookups.
  double get hitRatio {
    final total = hits + misses;
    if (total == 0) return 0;
    return hits / total;
  }

  @override
  String toString() =>
      'DecoderCacheStats(hits: $hits, misses: $misses, evictions: $evictions, '
      'entries: $entries, workingSetBytes: $workingSetBytes)';
}

DecoderCacheStats _fromDto(DecoderCacheStatsDto dto) => DecoderCacheStats(
      hits: dto.hits.toInt(),
      misses: dto.misses.toInt(),
      evictions: dto.evictions.toInt(),
      entries: dto.entries.toInt(),
      workingSetBytes: dto.workingSetBytes.toInt(),
    );

/// Read the current decoder cache stats. Cheap; takes the Rust lock
/// briefly. The underlying FFI is sync (a `parking_lot::Mutex` read),
/// so we wrap it in a `Future` for API consistency with the rest of
/// the Dart bindings.
Future<DecoderCacheStats> readDecoderCacheStats() async {
  final dto = decoderCacheStats();
  return _fromDto(dto);
}

/// Drop every cached demuxer/decoder. Returns the number of entries
/// dropped. Use this in low-memory warnings or when a project is
/// closed. The underlying FFI is sync.
Future<int> dropDecoderCache() async {
  return clearDecoderCache().toInt();
}
