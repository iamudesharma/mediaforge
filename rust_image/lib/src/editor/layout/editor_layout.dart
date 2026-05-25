/// Layout mode for [RustImageEditorView].
enum EditorLayoutMode {
  /// Sidebar on wide screens (≥900px), immersive mobile stack on narrow.
  auto,

  /// Always use sidebar + side panel (desktop-style).
  sidebar,

  /// Always use full-bleed image + bottom tool sheet (mobile-style).
  immersive,
}

/// Where the primary tool icon rail is placed (immersive layout only).
enum EditorToolBarPlacement {
  auto,
  bottom,
  top,
}
