/// Drop-in Instagram-style image editor (Sprint P0.4).
///
/// Rust engine: [rust_image_core]. GPU [Texture]: [rust_gpu_texture].
/// Live camera: [rust_camera_runtime].
library;

export 'package:rust_gpu_texture/rust_gpu_texture.dart';
export 'package:rust_image_core/rust_image_core.dart';
export 'package:rust_camera_runtime/rust_camera_runtime.dart';

export 'src/rust_image_editor.dart';
export 'src/editor/editor_session.dart';
export 'src/editor/editor_screen.dart' show RustImageEditorView, EditorScreen;
export 'src/editor/panels/tool_panels.dart' show EditorTool;
export 'src/editor/rust_image_editor_config.dart';
export 'src/editor/layout/editor_layout.dart';
export 'src/editor/models/operation_profile.dart';
export 'src/editor/rust_image_editor_widget.dart';
export 'src/editor/services/face_analysis_service.dart';
export 'src/editor/services/filter_descriptor.dart';
export 'src/editor/services/image_export_saver.dart';
export 'src/editor/services/rust_worker.dart';
export 'src/editor/theme/app_theme.dart';
