/// Timing breakdown for a single editor operation (Phase 0 metrics).
class OperationProfile {
  const OperationProfile({
    required this.totalMs,
    required this.filterMs,
    required this.previewEncodeMs,
    required this.executionPath,
  });

  final int totalMs;
  final int filterMs;
  final int previewEncodeMs;

  /// `gpu_adjust`, `cpu_photon`, or `cpu_bytes`.
  final String executionPath;

  String statusSuffix() {
    if (totalMs <= 0 && filterMs <= 0) return '';
    final parts = <String>[];
    if (executionPath.isNotEmpty) parts.add(executionPath);
    if (filterMs > 0) parts.add('filter ${filterMs}ms');
    if (previewEncodeMs > 0) parts.add('preview ${previewEncodeMs}ms');
    return parts.isEmpty ? '' : ' · ${parts.join(' · ')}';
  }
}
