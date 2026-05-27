import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Runtime camera permission for live beauty preview (Android / iOS).
abstract final class CameraPermission {
  static Future<bool> ensureGranted() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }

    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    if (status.isDenied || status.isLimited) {
      status = await Permission.camera.request();
    }

    return status.isGranted;
  }

  static Future<bool> get isPermanentlyDenied async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return false;
    }
    return Permission.camera.isPermanentlyDenied;
  }
}
