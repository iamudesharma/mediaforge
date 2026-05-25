import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Picks image bytes using the platform-appropriate API or a custom callback from
/// [RustImageEditorConfig].
abstract final class ImageSourcePicker {
  static Future<Uint8List?> Function()? _pickImage;
  static Future<Uint8List?> Function()? _pickFromCamera;

  /// Override pickers for [RustImageEditorWidget]. Call [reset] on dispose.
  static void configure({
    Future<Uint8List?> Function()? pickImage,
    Future<Uint8List?> Function()? pickFromCamera,
  }) {
    _pickImage = pickImage;
    _pickFromCamera = pickFromCamera;
  }

  static void reset() {
    _pickImage = null;
    _pickFromCamera = null;
  }

  static bool get isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static bool get supportsCamera => !isDesktop;

  static const _imageTypes = XTypeGroup(
    label: 'Images',
    extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'heic', 'avif'],
    mimeTypes: ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp', 'image/tiff'],
    uniformTypeIdentifiers: ['public.image'],
  );

  static Future<Uint8List?> pickImageBytes() async {
    final custom = _pickImage;
    if (custom != null) return custom();
    return _defaultPickImage();
  }

  /// Multi-select for sticker import (Sprint 8).
  static Future<List<Uint8List>> pickMultipleImageBytes({int max = 10}) async {
    return _defaultPickMultiple(max: max);
  }

  static Future<Uint8List?> pickFromCamera() async {
    final custom = _pickFromCamera;
    if (custom != null) return custom();
    return _defaultPickFromCamera();
  }

  static Future<Uint8List?> _defaultPickImage() async {
    if (isDesktop) {
      final file = await openFile(acceptedTypeGroups: [_imageTypes]);
      if (file == null) return null;
      return file.readAsBytes();
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 100,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  static Future<List<Uint8List>> _defaultPickMultiple({required int max}) async {
    if (isDesktop) {
      final files = await openFiles(acceptedTypeGroups: [_imageTypes]);
      if (files.isEmpty) return [];
      final out = <Uint8List>[];
      for (final f in files.take(max)) {
        out.add(await f.readAsBytes());
      }
      return out;
    }

    final picked = await ImagePicker().pickMultiImage(imageQuality: 100);
    if (picked.isEmpty) return [];
    final out = <Uint8List>[];
    for (final x in picked.take(max)) {
      out.add(await x.readAsBytes());
    }
    return out;
  }

  static Future<Uint8List?> _defaultPickFromCamera() async {
    if (!supportsCamera) return null;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }
}
