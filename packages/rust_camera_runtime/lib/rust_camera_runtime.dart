/// Live camera runtime for rust_image (Sprint P0.5).
///
/// Front-camera capture, permissions, and temporal landmark smoothing.
/// Beauty pipeline and editor UI stay in [rust_image_editor] / [rust_image_core].
library;

export 'package:camera/camera.dart'
    show CameraController, CameraDescription, CameraImage, CameraPreview;

export 'src/camera_permission.dart';
export 'src/live_camera_service.dart';
export 'src/temporal_face_smoother.dart';
