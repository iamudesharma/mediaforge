## 0.2.0

UI modernization pass (P1). Dark theme only, single mint accent.

### New widgets
- `ValueChipSlider` — CapCut-style slider with value chip floating above the thumb, center-detent haptic, double-tap-to-reset, inline Reset pill.
- `ChipPill` / `ChipPillRow` / `ChipPillWrap` — single-select rounded pills replacing the older `ActionChipRow` / `ChoiceChip` usages.
- `ToolButton` — 44-pt tap target with filled/outlined icon swap, animated scale, accent underline on selection, optional label.
- `FrostedBar` — `BackdropFilter`-blurred translucent bar for mobile chrome and desktop inspector header.
- `CategorizedToolRail` — left-side desktop rail with section headers (Edit / Decorate / Manage).
- `InspectorPanel` — titled right-side panel with header (tool name + Reset/Done), animated body, scroll fades, and a status footer.
- `FilterThumbnail` + `FilterThumbnailCache` — real filter thumbnails keyed by `(filterId, sourceHash, canvasW)` with an LRU cache.
- `AdjustPageViewPanel` — CapCut-style horizontal `PageView` adjustment strip replacing the vertical `AdjustPanel`.

### New theme tokens (`LuminaTokens`)
- Single mint accent (`#4EDEA3`) with `accent` / `accentContainer` / `onAccent` / `onAccentContainer` / `accentSurface` ramp.
- 4-pt spacing scale (`space1`...`space8`).
- Centralized breakpoints (`breakpointPhone = 600`, `breakpointTablet = 900`, `breakpointDesktop = 1100`, `breakpointLarge = 1440`).
- `iconSize` (`inline = 20`, `row = 24`, `primary = 28`) and `touchTarget = 44` (Apple HIG).
- Slider geometry (`trackHeight = 4`, `thumbRadius = 11`).
- Mobile bar heights (`mobileTopBarHeight = 52`, `mobileBottomBarHeight = 64`).

### Mobile shell
- `MobileEditorLayout` rewritten with:
  - 5 curated primary tools (Crop, Filters, Adjust, Stickers, Paint) + a "More" overflow sheet.
  - Frosted title bar showing the active tool name (sentence case, no more all-caps).
  - Draggable tool sheet with grabber and independent scroll.
  - Shader mask fading the bottom of the canvas into the toolbar.
- `EditorOverlayPanel` and `_MobileEditControlsPanel` migrated to the new tokens.
- `ToolContextStrip` slimmed to only Filters and Paint (adjust is in the new `PageView`, transform lives in the panel).

### Desktop shell
- Categorized rail with 11-pt caps section headers.
- Titled inspector with tool name, Reset/Done buttons, scroll fades, and status footer.
- Grouped top bar with `[title] | [status] | [history] | [compare] | [export]` zones separated by 1-px dividers.
- `desktopInspectorWidth` widened on ≥1440-px displays.

### Polish
- Section headers now use VSCO-style 11-pt caps with 0.4 letter-spacing.
- `LuminaFilterStrip` accepts real thumbnails; falls back to a labeled placeholder if not provided.
- `LayersPanel` empty state, chip pill selection, `ToolButton` filled/outlined, `SegmentedButton` for paint eraser mode and sticker tabs.
- Removed `ToggleButtons` (Material 2) and the legacy "Watermark" stub in `LayersPanel`.
- Removed deprecated `enableSwipeMoodFilters` / `swipeMoodFilterStrength` exports.
- Legacy `LuminaTokens.primary` / `primaryContainer` / `secondary` are now aliases of `accent` / `accentContainer` so existing widgets keep compiling.

### Animation
- New `PulseDot` and `FadeMask` helpers in `editor_animations.dart`.
- `EditorMotion` is now `fastOutSlowIn` (Material 3 standard easing) with explicit `fast/medium/slow` and `sheetEnter` durations.

### Breaking changes
None at the public API surface — `EditorTool`, `EditorSession`, `RustImageEditorWidget`, and `RustImageEditorConfig` keep their existing shape.

### Tests
- 118 widget and service tests pass (up from 106).
- New: `chip_pill_test.dart`, `tool_button_test.dart`, `value_chip_slider_test.dart`, `inspector_panel_test.dart`.
- `editor_view_stack_test.dart` updated for the new bottom-nav (icon-only `ToolButton`s, dismiss via Cancel) and the new `CategorizedToolRail`.

## 0.1.0

- Initial release: Instagram-style editor UI (panels, crop, beauty, filters, layers).
- Depends on `image_forge`, `pixel_surface`, `image_forge_camera`.
- Riverpod internal shell; 100+ widget tests with FRB dylib discovery.
- Studio demo via `rust_image` compatibility shim (P0.4 / P0.6).
