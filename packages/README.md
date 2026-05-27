# Packages (monorepo)

| Package | Path | Role | Example |
|---------|------|------|---------|
| `rust_gpu_texture` | [`rust_gpu_texture/`](rust_gpu_texture/) | GPU Flutter `Texture` bridge (P0.2) | [example/](rust_gpu_texture/example/) |
| `rust_image_core` | [`rust_image_core/`](rust_image_core/) | Rust engine + FRB + face native (P0.3) | [example/](rust_image_core/example/) |
| `rust_image_editor` | [`rust_image_editor/`](rust_image_editor/) | Editor UI + assets (P0.4) | [rust_image/example/](../rust_image/example/) |
| `rust_camera_runtime` | [`rust_camera_runtime/`](rust_camera_runtime/) | Live camera stream (P0.5) | Editor Beauty → Live camera |
| `rust_image` (shim) | [`../rust_image/`](../rust_image/) | Re-exports `rust_image_editor` | Same as editor |
| `video_processor_core` | [`video_processor_core/`](video_processor_core/) | Video Rust engine + FRB + FFmpeg hook | [example/](video_processor_core/example/) |
| `flutter_video_processor` | [`flutter_video_processor/`](flutter_video_processor/) | Video compress / thumbnails SDK | [example/](flutter_video_processor/example/) |
| `video_thumbnail_cache` | [`video_thumbnail_cache/`](video_thumbnail_cache/) | Disk LRU thumbnail cache (optional) | — |

**Docs:** [PUB_PACKAGE_SPLIT.md](../docs/PUB_PACKAGE_SPLIT.md) · [P0_ACCEPTANCE.md](../docs/P0_ACCEPTANCE.md) · [VIDEO_PACKAGE_SPLIT.md](../docs/VIDEO_PACKAGE_SPLIT.md) · [V0_ACCEPTANCE.md](../docs/V0_ACCEPTANCE.md) · [PACKAGE_PLATFORM_MATRIX.md](../docs/PACKAGE_PLATFORM_MATRIX.md)

Workspace: from repo root run `dart pub get` then `dart run melos bootstrap` (Melos 7 + pub workspaces).
