import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const _videoExtensions = ['mp4', 'm4v', 'mov', 'mkv', 'avi', 'webm'];

enum _IosVideoSource { photos, files }

/// Platform-appropriate single-video picker.
Future<FilePickerResult?> pickVideoWithPlatformPicker({
  BuildContext? context,
}) async {
  FilePickerResult? result;
  if (!kIsWeb && Platform.isIOS && context != null) {
    final source = await _showIosSourceSheet(context);
    if (source == null) return null;
    result = switch (source) {
      _IosVideoSource.photos => await _pickFromPhotoLibrary(),
      _IosVideoSource.files => await _pickFromFiles(),
    };
  } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    result = await _pickFromPhotoLibrary();
  } else {
    result = await _pickFromFiles();
  }
  return result;
}

/// Multi-select from gallery / files (WhatsApp Status–style).
///
/// Returns absolute paths, capped at [max] (default 8).
Future<List<String>> pickMultipleVideoPaths({
  BuildContext? context,
  int max = 8,
}) async {
  if (max < 1) return [];

  FilePickerResult? result;
  if (!kIsWeb && Platform.isIOS && context != null) {
    final source = await _showIosSourceSheet(context);
    if (source == null) return [];
    result = switch (source) {
      _IosVideoSource.photos => await _pickFromPhotoLibrary(allowMultiple: true),
      _IosVideoSource.files => await _pickFromFiles(allowMultiple: true),
    };
  } else if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    result = await _pickFromPhotoLibrary(allowMultiple: true);
  } else {
    result = await _pickFromFiles(allowMultiple: true);
  }

  return _pathsFromResult(result, max: max);
}

List<String> _pathsFromResult(FilePickerResult? result, {required int max}) {
  if (result == null || result.files.isEmpty) return [];

  final paths = <String>[];
  for (final file in result.files) {
    final path = file.path;
    if (path == null || path.isEmpty) continue;
    if (!kIsWeb && !File(path).existsSync()) continue;
    if (!_isVideoPath(path)) continue;
    paths.add(path);
    if (paths.length >= max) break;
  }
  return paths;
}

bool _isVideoPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return _videoExtensions.contains(ext);
}

Future<FilePickerResult?> _pickFromPhotoLibrary({bool allowMultiple = false}) {
  return FilePicker.platform.pickFiles(
    type: FileType.video,
    allowMultiple: allowMultiple,
    allowCompression: false,
  );
}

Future<FilePickerResult?> _pickFromFiles({bool allowMultiple = false}) {
  return FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _videoExtensions,
    allowMultiple: allowMultiple,
    allowCompression: false,
  );
}

Future<_IosVideoSource?> _showIosSourceSheet(BuildContext context) {
  return showModalBottomSheet<_IosVideoSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Photo Library'),
            subtitle: const Text('Videos in the Photos app'),
            onTap: () => Navigator.pop(ctx, _IosVideoSource.photos),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Browse Files'),
            subtitle: const Text('iCloud Drive, On My iPhone, etc.'),
            onTap: () => Navigator.pop(ctx, _IosVideoSource.files),
          ),
        ],
      ),
    ),
  );
}
