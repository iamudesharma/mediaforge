import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show PlatformInt64;
import 'package:rust_image_core/rust_image_core.dart';

/// Dart wrapper for Rust [TemporalSmoother] (Nexus A live camera).
final class TemporalFaceSmoother {
  TemporalFaceSmoother({double alpha = 0.25})
      : _id = temporalSmootherCreate(alpha: alpha);

  final PlatformInt64 _id;

  FaceAnalysisResult smooth(FaceAnalysisResult raw) =>
      temporalSmootherSmooth(id: _id, raw: raw);

  void reset() => temporalSmootherReset(id: _id);

  void dispose() => temporalSmootherDestroy(id: _id);
}
