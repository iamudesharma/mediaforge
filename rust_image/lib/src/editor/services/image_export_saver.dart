import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import '../../rust_image_editor.dart';

/// Saves edited images to the system photo library (mobile) or Downloads (desktop).
abstract final class ImageExportSaver {
  static String extensionFor(OutputFormat format) => switch (format) {
        OutputFormat.jpeg => 'jpg',
        OutputFormat.png => 'png',
        OutputFormat.webP => 'webp',
        OutputFormat.avif => 'avif',
      };

  static String defaultFileName(OutputFormat format) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return 'rust_image_$stamp.${extensionFor(format)}';
  }

  /// Returns a short user-facing status message.
  static Future<String> save({
    required Uint8List bytes,
    required OutputFormat format,
    String? fileName,
  }) async {
    final name = fileName ?? defaultFileName(format);

    if (Platform.isIOS || Platform.isAndroid) {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        await Gal.requestAccess();
      }
      await Gal.putImageBytes(bytes, name: name);
      return Platform.isIOS ? 'Saved to Photos' : 'Saved to gallery';
    }

    final dir = await _desktopSaveDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return 'Saved to ${file.path}';
  }

  static Future<Directory> _desktopSaveDirectory() async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) return downloads;
    }
    return await getApplicationDocumentsDirectory();
  }
}
