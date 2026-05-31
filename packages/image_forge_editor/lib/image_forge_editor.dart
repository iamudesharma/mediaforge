/// Drop-in Instagram-style image editor (Sprint P0.4).
///
/// Rust engine: [image_forge]. GPU [Texture]: [pixel_surface].
/// Live camera: [image_forge_camera].
library;

export 'package:pixel_surface/pixel_surface.dart';
export 'package:image_forge/image_forge.dart';
export 'package:image_forge_camera/image_forge_camera.dart';

export 'src/image_forge_editor.dart';
export 'src/editor/editor_session.dart';
export 'src/editor/editor_screen.dart' show RustImageEditorView, EditorScreen;
export 'src/editor/panels/tool_panels.dart' show EditorTool;
export 'src/editor/image_forge_editor_config.dart';
export 'src/editor/layout/editor_layout.dart';
export 'src/editor/models/operation_profile.dart';
export 'src/editor/image_forge_editor_widget.dart';
export 'src/editor/services/face_analysis_service.dart';
export 'src/editor/services/filter_descriptor.dart';
export 'src/editor/services/image_export_saver.dart';
export 'src/editor/services/rust_worker.dart';
export 'src/editor/theme/app_theme.dart';
export 'src/editor/models/overlay_layer.dart'
    show TextBackgroundStyle, TextFillMode;
export 'src/editor/models/text_style_draft.dart';
export 'src/editor/widgets/control_widgets.dart';
export 'src/editor/widgets/lumina_color_picker.dart';
export 'src/editor/widgets/text_style_controls.dart';
