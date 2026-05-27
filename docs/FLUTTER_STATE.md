# Flutter editor state (Sprint 14 — Riverpod)

Internal state architecture for the drop-in editor UI. **Host apps do not need Riverpod** — `RustImageEditorWidget` wraps a `ProviderScope` automatically.

---

## Provider map

| Provider | Rebuild scope | Source |
|----------|---------------|--------|
| `editorSessionProvider` | Imperative API (read in actions, avoid wide `watch`) | `EditorSession` lifecycle |
| `editorPreviewListenableProvider` | Filtered preview pixels only | `session.previewListenable` |
| `editorCanvasListenableProvider` | `LivePreview` (preview + layer overlays) | `previewListenable` + `layerListenable` |
| `editorStatusListenableProvider` | Status line, meta chips | `session.statusListenable` |
| `editorLayerListenableProvider` | Layers panel, floating chrome | `session.layerListenable` |
| `editorProcessingListenableProvider` | Processing spinner overlay | `session.processingListenable` |
| `editorBlockingListenableProvider` | Full-screen blocking overlay | `session.blockingListenable` |
| `editorChromeListenableProvider` | Tool panels, export settings, backend | `session.chromeListenable` (no preview) |
| `editorFaceChromeListenableProvider` | Beauty panel status | `session.faceChromeListenable` |
| `editorSwipeLookPreviewListenableProvider` | Swipe combo look label chip | look preset + preview tick |
| `editorMoodPreviewListenableProvider` | Filters tab mood browse chip | mood preset + preview tick |
| `editorBeautyPreviewListenableProvider` | Swipe beauty label chip | beauty look + preview tick |

Shell chrome merges **layer + processing + blocking + status + chrome** — **not** preview.

---

## Rebuild rules

1. **Preview canvas** → `editorCanvasListenableProvider` (`ListenableBuilder` around `LivePreview` — pixels + paint/sticker layers).
2. **Status / FPS (live camera)** → `statusListenable`; throttled in session (~4 Hz) so shell does not rebuild at frame rate.
3. **Tool panels** → `chromeListenable` or `Consumer` with `select` on export/backend fields — never `previewListenable`.
4. **Side effects** (placement sync, `onImageChanged`) → `ref.listen` on `imageInfo` / `displayBytes` — no widget rebuild.
5. **Swipe overlays** → dedicated mood/beauty preview listenables, not full `EditorSession`.

---

## DevTools baseline (14.0)

Record before/after Sprint 14 changes in **Flutter DevTools → Performance → Track widget rebuilds**.

### Scenario B — Adjust brightness live (768×1152)

1. Import image, open **Adjust**, drag brightness slider continuously for ~3 s.
2. **Expect after 14.3:** `LivePreview` / `RgbaPreviewImage` rebuilds debounced with preview; `ToolPanelHost` / adjust strip stable (no rebuild per preview tick).
3. **Red flag:** `MobileEditorLayout` or `EditorToolRail` rebuild every frame.

### Scenario G — Beauty lip color live drag (768×1024 portrait)

1. Beauty tab → face analyzed → drag **Lip color** strength.
2. **Expect:** Beauty panel slider subtree + preview; filters rail and unrelated panels idle.

### Scenario H — Live camera skin smooth (720p front)

1. Beauty → **Live camera**, pick a look with skin smooth.
2. **Expect after 14.3:** Preview/texture updates at stream rate; status chip / FPS text ≤ ~4 Hz; bottom nav and tool sheet not repainting at 24–30 fps.
3. **Red flag:** Full `Scaffold` body `build` on every camera frame.

### Quick checklist

| Widget / area | B adjust | G beauty | H live |
|---------------|----------|----------|--------|
| `LivePreview` | Should rebuild | Should rebuild | Should rebuild |
| `ToolPanelHost` | Should not | Should not | Should not |
| `EditorToolRail` / bottom nav | Should not | Should not | Should not |
| Status / meta chips | Occasional | Occasional | Throttled only |

---

## Injecting a session

```dart
final session = EditorSession();
RustImageEditorWidget(
  config: RustImageEditorConfig(
    session: session,
    // ...
  ),
)
```

`editorSessionProvider` is overridden inside `ProviderScope` — same instance, disposed only if the widget owns it (`config.session == null`).

---

## References

- Roadmap: [ROADMAP.md](../ROADMAP.md) — Sprint 14
- Providers: [`packages/rust_image_editor/lib/src/editor/state/editor_providers.dart`](../packages/rust_image_editor/lib/src/editor/state/editor_providers.dart)
- Plugin README: [rust_image/README.md](../rust_image/README.md)

*Last updated: Sprint 14.0–14.4*
