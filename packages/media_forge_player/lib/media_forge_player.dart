/// `media_forge_player` — polished Flutter player SDK.
///
/// Layering (do not bypass):
///
/// * `media_forge` = media engine (demux, decode, audio-master clock, seek,
///   HW accel, diagnostics).
/// * `pixel_surface` = GPU presentation bridge only.
/// * `media_forge_player` (this package) = public player API + widget.
///
/// Network design: FFmpeg inside `media_forge` reads HTTP URLs directly so
/// seeks become HTTP Range requests. Never fetch bytes in Dart and push
/// them over FFI.
library;

export 'src/buffered_range.dart';
export 'src/capabilities.dart';
export 'src/diagnostics.dart';
export 'src/fullscreen_controller.dart';
export 'src/media_source.dart';
export 'src/network_profile.dart';
export 'src/player_configuration.dart';
export 'src/player_controller.dart';
export 'src/player_ui/player_ui.dart';
export 'src/player_value.dart';
export 'src/texture_presenter.dart';
export 'src/track_info.dart';
export 'src/video_widget.dart';
