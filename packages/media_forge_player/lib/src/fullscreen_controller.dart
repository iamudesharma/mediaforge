import 'package:flutter/foundation.dart';

/// Reusable fullscreen state for `media_forge_player`.
///
/// Pure state + notifications: the package never assumes *how* fullscreen
/// is implemented (in-place immersive view, pushed route, or native window
/// fullscreen via a host callback). [MediaPlayerScreen] uses this
/// automatically; embedding apps may provide their own instance to observe
/// or drive fullscreen from outside, or override the behavior with
/// `onEnterFullscreen` / `onExitFullscreen` callbacks.
///
/// ```dart
/// final fullscreen = MediaForgeFullscreenController();
/// MediaPlayerScreen(
///   controller: playerController,
///   fullscreenController: fullscreen,
/// );
/// await fullscreen.enterFullscreen();
/// ```
class MediaForgeFullscreenController extends ChangeNotifier {
  MediaForgeFullscreenController({bool isFullscreen = false})
      : _isFullscreen = isFullscreen;

  bool _isFullscreen;

  /// Whether the player is currently fullscreen.
  bool get isFullscreen => _isFullscreen;

  /// Enter fullscreen (no-op when already fullscreen).
  Future<void> enterFullscreen() async {
    if (_isFullscreen) return;
    debugPrint('[MediaForgeFullscreen] enter');
    _isFullscreen = true;
    notifyListeners();
  }

  /// Exit fullscreen (no-op when already windowed).
  Future<void> exitFullscreen() async {
    if (!_isFullscreen) return;
    debugPrint('[MediaForgeFullscreen] exit');
    _isFullscreen = false;
    notifyListeners();
  }

  /// Toggle between fullscreen and windowed.
  Future<void> toggleFullscreen() {
    return _isFullscreen ? exitFullscreen() : enterFullscreen();
  }

  /// Test/host escape hatch: set state synchronously.
  @visibleForTesting
  void setFullscreenForTest(bool value) {
    if (_isFullscreen == value) return;
    _isFullscreen = value;
    notifyListeners();
  }
}
