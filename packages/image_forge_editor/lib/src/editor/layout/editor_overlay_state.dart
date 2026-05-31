import '../models/overlay_layer.dart';

/// In-stack editor overlay (replaces Navigator modals on mobile).
enum EditorOverlayKind {
  none,
  textEdit,
  shapeMask,
  blankCanvas,
}

class EditorOverlayState {
  const EditorOverlayState({
    this.kind = EditorOverlayKind.none,
    this.textLayer,
    this.shapeMaskImageCount = 1,
    this.shapeMaskTitle,
    this.shapeMaskInitial,
    this.onShapeMaskSelected,
  });

  const EditorOverlayState.none() : this();

  final EditorOverlayKind kind;
  final TextLayer? textLayer;
  final int shapeMaskImageCount;
  final String? shapeMaskTitle;
  final StickerShapeMask? shapeMaskInitial;
  final void Function(StickerShapeMask mask)? onShapeMaskSelected;

  EditorOverlayState copyWith({
    EditorOverlayKind? kind,
    TextLayer? textLayer,
    int? shapeMaskImageCount,
    String? shapeMaskTitle,
    StickerShapeMask? shapeMaskInitial,
    void Function(StickerShapeMask mask)? onShapeMaskSelected,
    bool clearShapeCallback = false,
  }) {
    return EditorOverlayState(
      kind: kind ?? this.kind,
      textLayer: textLayer ?? this.textLayer,
      shapeMaskImageCount: shapeMaskImageCount ?? this.shapeMaskImageCount,
      shapeMaskTitle: shapeMaskTitle ?? this.shapeMaskTitle,
      shapeMaskInitial: shapeMaskInitial ?? this.shapeMaskInitial,
      onShapeMaskSelected: clearShapeCallback
          ? null
          : (onShapeMaskSelected ?? this.onShapeMaskSelected),
    );
  }
}
