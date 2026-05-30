# Platform matrix (monorepo packages)

Requirements for **host apps** integrating each package. All packages need **Flutter 3.3+** and **Dart 3.12+**.

---

## Summary

| Package | Android | iOS | macOS | Linux | Windows | Web |
|---------|---------|-----|-------|-------|---------|-----|
| **rust_gpu_texture** | API 21+ | 12+ | 12+ | — | — | — |
| **rust_image_core** | API 21+ + NDK + Rust targets | 15+ + Rust | 12+ + Rust | Rust + GPU optional | Rust + GPU optional | Not supported |
| **rust_image_editor** | Same as core + camera runtime | Same | Same (no live cam) | Core only, reduced UX | Core only | Not supported |
| **rust_camera_runtime** | API 21+ + camera permission | 15+ + `NSCameraUsageDescription` | — | — | — | — |
| **video_processor_core** | API 24+ + NDK + FFmpeg | 13+ + FFmpeg | 10.15+ + FFmpeg | FFmpeg | FFmpeg | — |
| **flutter_video_processor** | Same as core | Same | Same | Same | Same | — |
| **video_thumbnail_cache** | Dart only | Dart only | Dart only | Dart only | Dart only | — |

---

## rust_gpu_texture

| Requirement | Notes |
|-------------|--------|
| Native plugin | `RustGpuTexturePlugin` — CVPixelBuffer (Apple), `SurfaceTexture` (Android) |
| Rust / NDK | **Not required** — RGBA upload from Dart or your own engine |
| minSdk (Android) | 21 (host app) |
| macOS deployment | 12.0 (podspec) |

---

## rust_image_core

| Requirement | Notes |
|-------------|--------|
| Rust toolchain | [rustup](https://rustup.rs) — do not use Homebrew `rustc` on macOS for cross-compile |
| Android | `rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android`; NDK via `local.properties` / `ANDROID_NDK_HOME` |
| iOS | `platform :ios, '15.0'` in Podfile; Release: avoid stripping Rust symbols (see [rust_image/README.md](../rust_image/README.md)) |
| macOS | 12+; Apple Vision for face analysis; MediaPipe optional on iOS only |
| Features | Default `gpu` feature — Metal / Vulkan via wgpu |
| Face (still) | Vision (Apple); ML Kit (Android); optional MediaPipe `.task` download |

---

## rust_image_editor

| Requirement | Notes |
|-------------|--------|
| Transitive | `rust_image_core`, `rust_gpu_texture`, `rust_camera_runtime` |
| Permissions | Gallery/export via `gal`; live camera via camera runtime (mobile) |
| Riverpod | Internal only — host apps use `RustImageEditorWidget` without adding Riverpod |

---

## rust_camera_runtime

| Requirement | Notes |
|-------------|--------|
| Platforms | Android + iOS only (`LiveCameraService.isSupported`) |
| Android | `CAMERA` permission in manifest (merged from `permission_handler` / `camera`) |
| iOS | `NSCameraUsageDescription` in host `Info.plist` |
| Deps | `camera`, `permission_handler`, `rust_image_core` (temporal FRB) |

---

## video_processor_core / flutter_video_processor

| Requirement | Notes |
|-------------|--------|
| Rust + FFmpeg | Prebuilt artifacts or local build — see [`tools/ffmpeg/`](../tools/ffmpeg/) |
| Android minSdk | 24 (plugin); host app ≥ 24 recommended |
| iOS | 13+; vendored `video_processor_core.framework` |
| Hook | Native library via `video_processor_core` CodeAsset hook |

## video_thumbnail_cache

| Requirement | Notes |
|-------------|--------|
| Transitive | `video_processor_core` only |
| Storage | App temp dir via `path_provider` |

---

## References

- Setup detail: [rust_image/README.md](../rust_image/README.md)
- Split plan: [PUB_PACKAGE_SPLIT.md](PUB_PACKAGE_SPLIT.md)
- Video split: [VIDEO_PACKAGE_SPLIT.md](VIDEO_PACKAGE_SPLIT.md)
- Acceptance: [P0_ACCEPTANCE.md](P0_ACCEPTANCE.md) · [V0_ACCEPTANCE.md](V0_ACCEPTANCE.md)
