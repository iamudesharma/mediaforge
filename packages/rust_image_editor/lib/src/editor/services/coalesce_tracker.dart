/// Thrown when a coalesced operation was superseded by a newer request.
class CoalesceCancelledException implements Exception {}

/// Tracks in-flight operations by type; stale results are discarded via generation ids.
class CoalesceTracker {
  final Map<String, int> _generation = {};

  int nextRequestId(String opType) {
    final id = (_generation[opType] ?? 0) + 1;
    _generation[opType] = id;
    return id;
  }

  bool isCurrent(String opType, int requestId) =>
      _generation[opType] == requestId;

  void throwIfStale(String opType, int requestId) {
    if (!isCurrent(opType, requestId)) {
      throw CoalesceCancelledException();
    }
  }

  Future<T> execute<T>(
    String opType,
    Future<T> Function(int requestId) work,
  ) async {
    final requestId = nextRequestId(opType);
    final result = await work(requestId);
    throwIfStale(opType, requestId);
    return result;
  }
}
