/// Complete player UI for `media_forge_player` (VLC-grade features,
///
/// premium dark cinematic styling). Consumes only the public controller,
///
/// value and diagnostics APIs — no FFmpeg/Rust logic in widgets.
library;

export 'center_playback_controls.dart';
export 'media_controls_overlay.dart';
export 'media_player_screen.dart';
export 'models.dart';
export 'panels/audio_tracks_panel.dart';
export 'panels/media_information_panel.dart';
export 'panels/playback_speed_panel.dart';
export 'panels/player_settings_panel.dart';
export 'panels/subtitle_tracks_panel.dart';
export 'panels/video_settings_panel.dart';
export 'player_caption_overlay.dart';
export 'player_timeline.dart';
export 'utils.dart';
export 'widgets/player_icon_button.dart';
export 'widgets/player_slider.dart';
export 'widgets/setting_tile.dart';
export 'widgets/track_tile.dart';
