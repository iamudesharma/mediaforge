import 'frb_generated/api.dart' as frb;
import 'frb_generated/frb_generated.dart';
import 'native_library_loader.dart';

/// Single entry point for loading the native library and initializing FRB.
abstract final class NativeBindings {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;
    final externalLibrary = await NativeLibraryLoader.load();
    await RustLib.init(externalLibrary: externalLibrary);
    await frb.initialize();
    _initialized = true;
  }
}
