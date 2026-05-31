# Packages (mediaforge monorepo)

| Package | Path | Role | Example |
|---------|------|------|---------|
| `pixel_surface` | [`pixel_surface/`](pixel_surface/) | GPU Flutter `Texture` bridge (P0.2) | [example/](pixel_surface/example/) |
| `image_forge` | [`image_forge/`](image_forge/) | Rust engine + FRB + face native (P0.3) | [example/](image_forge/example/) |
| `image_forge_editor` | [`image_forge_editor/`](image_forge_editor/) | Editor UI + assets (P0.4) | [mediaforge/example/](../mediaforge/example/) |
| `image_forge_camera` | [`image_forge_camera/`](image_forge_camera/) | Live camera stream (P0.5) | Editor Beauty → Live camera |
| `image_forge_editor` (shim) | [`../mediaforge/`](../mediaforge/) | Re-exports `image_forge_editor` | Same as editor |
| `video_forge` | [`video_forge/`](video_forge/) | Video Rust engine + FRB + FFmpeg hook | [example/](video_forge/example/) |
| `video_forge_kit` | [`video_forge_kit/`](video_forge_kit/) | Video compress / thumbnails SDK | [example/](video_forge_kit/example/) |
| `video_forge_cache` | [`video_forge_cache/`](video_forge_cache/) | Disk LRU thumbnail cache (optional) | — |

**Docs:** [PUB_PACKAGE_SPLIT.md](../docs/PUB_PACKAGE_SPLIT.md) · [P0_ACCEPTANCE.md](../docs/P0_ACCEPTANCE.md) · [VIDEO_PACKAGE_SPLIT.md](../docs/VIDEO_PACKAGE_SPLIT.md) · [V0_ACCEPTANCE.md](../docs/V0_ACCEPTANCE.md) · [PACKAGE_PLATFORM_MATRIX.md](../docs/PACKAGE_PLATFORM_MATRIX.md)

Workspace: from repo root run `dart pub get` then `dart run melos bootstrap` (Melos 7 + pub workspaces).
