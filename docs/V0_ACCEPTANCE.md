# V0 — Video package split acceptance

Use before first pub.dev release of the video packages. See [VIDEO_PACKAGE_SPLIT.md](VIDEO_PACKAGE_SPLIT.md).

---

## Package demos

| Check | Command / path |
|-------|----------------|
| **video_processor_core** — probe + compress (FRB) | `cd packages/video_processor_core/example && flutter run -d macos` |
| **flutter_video_processor** — full SDK demo | From repo root: `./scripts/run-video-macos.sh` |
| **video_thumbnail_cache** — unit smoke | `cd packages/video_thumbnail_cache && flutter test` |
| **media_studio** — unified photo/video studio | `cd examples/media_studio && flutter run` |

### Engine CLI (no Flutter UI)

```bash
cd packages/video_processor_core/rust
cargo run --release -p video_processor_core --bin vp_bench -- --help
```

---

## CI (monorepo root)

```bash
dart pub get && dart run melos bootstrap
dart run melos exec --scope=video_processor_core -- flutter analyze --no-fatal-infos
dart run melos exec --scope=flutter_video_processor -- flutter test
dart run melos exec --scope=video_thumbnail_cache -- flutter test
cd packages/video_processor_core && cargo test -p video_processor_core
```

---

## Dependency boundaries

- [x] `video_processor_core` has no `path_provider` / `crypto` / `uuid` in `pubspec.yaml`
- [x] `flutter_video_processor` does not list `hooks` / `code_assets` (hook lives in core)
- [x] `video_thumbnail_cache` has no FFI plugin / FFmpeg

---

## Docs per package

| Package | README | CHANGELOG | Example |
|---------|--------|-----------|---------|
| `video_processor_core` | [packages/video_processor_core/README.md](../packages/video_processor_core/README.md) | CHANGELOG.md | example/ |
| `flutter_video_processor` | [packages/flutter_video_processor/README.md](../packages/flutter_video_processor/README.md) | CHANGELOG.md | example/ |
| `video_thumbnail_cache` | [packages/video_thumbnail_cache/README.md](../packages/video_thumbnail_cache/README.md) | CHANGELOG.md | — |

---

## After V0 (Sprint V1)

Preview/playback track: [VIDEO_MEDIA_RUNTIME.md](VIDEO_MEDIA_RUNTIME.md) — implement **V1.1 → V1.7** one phase per PR ([ROADMAP.md](../ROADMAP.md) Sprint V1).

---

*Last updated: V0 + V1 tracker*
