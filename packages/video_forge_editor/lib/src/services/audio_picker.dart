import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const _audioExtensions = ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'flac'];

enum AudioPickSource { musicLibrary, files }

/// Result from a platform audio pick.
class AudioPickResult {
  const AudioPickResult({
    required this.path,
    required this.source,
    this.displayName,
  });

  final String path;
  final AudioPickSource source;
  final String? displayName;
}

enum _IosAudioSource { musicLibrary, files }

/// Platform-appropriate single-audio picker (Music library + Files).
Future<AudioPickResult?> pickAudioWithPlatformPicker({
  BuildContext? context,
  AudioPickSource? forceSource,
}) async {
  FilePickerResult? result;
  AudioPickSource source = AudioPickSource.files;

  if (forceSource != null) {
    result = switch (forceSource) {
      AudioPickSource.musicLibrary => await _pickFromMusicLibrary(),
      AudioPickSource.files => await _pickFromFiles(),
    };
    source = forceSource;
  } else if (!kIsWeb && Platform.isIOS && context != null) {
    final iosSource = await _showIosSourceSheet(context);
    if (iosSource == null) return null;
    result = switch (iosSource) {
      _IosAudioSource.musicLibrary => await _pickFromMusicLibrary(),
      _IosAudioSource.files => await _pickFromFiles(),
    };
    source = iosSource == _IosAudioSource.musicLibrary
        ? AudioPickSource.musicLibrary
        : AudioPickSource.files;
  } else if (!kIsWeb && Platform.isAndroid) {
    result = await _pickFromMusicLibrary();
    source = AudioPickSource.musicLibrary;
  } else {
    result = await _pickFromFiles();
    source = AudioPickSource.files;
  }

  if (result == null || result.files.isEmpty) return null;
  final file = result.files.single;
  final path = file.path;
  if (path == null || path.isEmpty) return null;
  if (!kIsWeb && !File(path).existsSync()) return null;

  final displayName = file.name.isNotEmpty ? file.name : null;
  debugPrint(
    '[AudioPicker] picked source=$source path=$path name=$displayName',
  );
  return AudioPickResult(
    path: path,
    source: source,
    displayName: displayName,
  );
}

Future<FilePickerResult?> _pickFromMusicLibrary() {
  return FilePicker.platform.pickFiles(
    type: FileType.audio,
    allowCompression: false,
  );
}

Future<FilePickerResult?> _pickFromFiles() {
  return FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: _audioExtensions,
    allowCompression: false,
  );
}

Future<_IosAudioSource?> _showIosSourceSheet(BuildContext context) {
  return showModalBottomSheet<_IosAudioSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.library_music_outlined),
            title: const Text('Music library'),
            subtitle: const Text('Songs on this device'),
            onTap: () => Navigator.pop(ctx, _IosAudioSource.musicLibrary),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Browse files'),
            subtitle: const Text('iCloud Drive, On My iPhone, etc.'),
            onTap: () => Navigator.pop(ctx, _IosAudioSource.files),
          ),
        ],
      ),
    ),
  );
}

bool isSupportedAudioPath(String path) {
  final ext = path.split('.').last.toLowerCase();
  return _audioExtensions.contains(ext);
}
