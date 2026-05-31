# image_forge_camera

Live front-camera SDK for the rust_image monorepo (Sprint P0.5).

## Platform matrix

| Platform | Support |
|----------|---------|
| Android | Yes — API **21+**, `CAMERA` permission |
| iOS | Yes — **15+**, `NSCameraUsageDescription` in host app |
| macOS / desktop / web | No — `LiveCameraService.isSupported` is false |

Full matrix: [docs/PACKAGE_PLATFORM_MATRIX.md](../../docs/PACKAGE_PLATFORM_MATRIX.md).

## Scope

| In this package | Elsewhere |
|-----------------|-----------|
| `LiveCameraService` — YUV420 stream, front camera | Beauty WGSL / edit graph → `image_forge` |
| `CameraPermission` — `permission_handler` | Editor panels → `image_forge_editor` |
| `TemporalFaceSmoother` — FRB wrapper for live landmarks | Still-image face analyze → `image_forge` |
| Re-export `CameraController` / `CameraPreview` | GPU `Texture` display → `pixel_surface` |

## Usage

```dart
import 'package:image_forge_camera/image_forge_camera.dart';

if (LiveCameraService.isSupported) {
  await LiveCameraService.start(
    maxWidth: 720,
    onFrame: (image) { /* CameraImage YUV */ },
  );
}
```

End-to-end live beauty UI: use `image_forge_editor` (Beauty → Live camera).

## Host app setup (iOS)

Add to `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is required for live preview.</string>
```

## Verify

```bash
cd packages/image_forge_camera && flutter test
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Workspace

From repo root: `dart pub get` then `dart run melos bootstrap`.
