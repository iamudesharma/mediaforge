# V0 — Video package split acceptance

Use before first pub.dev release of the video packages. See [VIDEO_PACKAGE_SPLIT.md](VIDEO_PACKAGE_SPLIT.md).

---

## Package demos

| Check | Command / path |
|-------|----------------|
| **video_forge** — probe + compress (FRB) | `cd packages/video_forge/example && flutter run -d macos` |
| **video_forge_kit** — full SDK demo | From repo root: `./scripts/run-video-macos.sh` |
| **video_forge_cache** — unit smoke | `cd packages/video_forge_cache && flutter test` |
| **media_studio** — unified photo/video studio | `cd examples/media_studio && flutter run` |

### Engine CLI (no Flutter UI)

```bash
cd packages/video_forge/rust
cargo run --release -p video_forge --bin vp_bench -- --help
```

---

## CI (monorepo root)

```bash
dart pub get && dart run melos bootstrap
dart run melos exec --scope=video_forge -- flutter analyze --no-fatal-infos
dart run melos exec --scope=video_forge_kit -- flutter test
dart run melos exec --scope=video_forge_cache -- flutter test
cd packages/video_forge && cargo test -p video_forge
```

---

## Dependency boundaries

- [x] `video_forge` has no `path_provider` / `crypto` / `uuid` in `pubspec.yaml`
- [x] `video_forge_kit` does not list `hooks` / `code_assets` (hook lives in core)
- [x] `video_forge_cache` has no FFI plugin / FFmpeg

---

## Docs per package

| Package | README | CHANGELOG | Example |
|---------|--------|-----------|---------|
| `video_forge` | [packages/video_forge/README.md](../packages/video_forge/README.md) | CHANGELOG.md | example/ |
| `video_forge_kit` | [packages/video_forge_kit/README.md](../packages/video_forge_kit/README.md) | CHANGELOG.md | example/ |
| `video_forge_cache` | [packages/video_forge_cache/README.md](../packages/video_forge_cache/README.md) | CHANGELOG.md | — |

---

## After V0 (Sprint V1)

Preview/playback track: [VIDEO_MEDIA_RUNTIME.md](VIDEO_MEDIA_RUNTIME.md) — implement **V1.1 → V1.7** one phase per PR ([ROADMAP.md](../ROADMAP.md) Sprint V1).

---

*Last updated: V0 + V1 tracker*
