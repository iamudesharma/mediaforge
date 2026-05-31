import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor_session.dart';

/// Injected session from [RustImageEditorConfig.session]; disposed by widget when owned.
final editorSessionProvider = Provider<EditorSession>((ref) {
  throw UnimplementedError(
    'editorSessionProvider must be overridden in ProviderScope',
  );
});

/// Canvas / [LivePreview] — preview pixels, GPU texture id, live frame.
final editorPreviewListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).previewListenable;
});

/// Canvas overlays (paint, stickers, text) + filtered preview pixels.
final editorCanvasListenableProvider = Provider<Listenable>((ref) {
  final session = ref.watch(editorSessionProvider);
  return Listenable.merge([
    session.previewListenable,
    session.layerListenable,
  ]);
});

/// Status line, FPS chip (throttled during live camera).
final editorStatusListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).statusListenable;
});

/// Layers panel + floating chrome layer list.
final editorLayerListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).layerListenable;
});

/// Light processing indicator on preview.
final editorProcessingListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).processingListenable;
});

/// Full-screen blocking overlay (initial decode).
final editorBlockingListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).blockingListenable;
});

/// Tool panels, export format, backend — excludes preview ticks.
final editorChromeListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).editorChromeListenable;
});

/// Beauty panel analyzing / landmark status.
final editorFaceChromeListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).faceChromeListenable;
});

/// Swipe combo look label chip (preset browse, not every preview pixel).
final editorSwipeLookPreviewListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).swipeLookPreviewListenable;
});

/// Swipe mood label chip (Filters tab mood browse).
final editorMoodPreviewListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).moodPreviewListenable;
});

/// Swipe beauty look label chip.
final editorBeautyPreviewListenableProvider = Provider<Listenable>((ref) {
  return ref.watch(editorSessionProvider).beautyPreviewListenable;
});

/// Shell chrome: layers, processing, blocking, status, export — not preview.
Listenable editorShellListenable(EditorSession session) {
  return session.editorChromeListenable;
}
