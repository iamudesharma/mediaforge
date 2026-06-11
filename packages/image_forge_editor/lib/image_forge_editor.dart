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
export 'src/editor/widgets/value_chip_slider.dart';
export 'src/editor/widgets/tool_button.dart';
export 'src/editor/widgets/chip_pill.dart';
export 'src/editor/widgets/frosted_bar.dart';
export 'src/editor/widgets/categorized_tool_rail.dart';
export 'src/editor/widgets/inspector_panel.dart';
export 'src/editor/widgets/filter_thumbnail.dart';
export 'src/editor/theme/lumina_tokens.dart';
export 'src/editor/theme/app_typography.dart';
export 'src/editor/theme/editor_motion.dart';
export 'src/editor/theme/editor_icons.dart';
export 'src/editor/panels/adjust_pageview_panel.dart';
