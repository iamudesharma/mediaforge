package com.flutter_rust_bridge.image_forge

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/** Registers platform channels for rust_image on Android (Nexus D). */
class RustImageCorePlugin : FlutterPlugin {
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RustImageAppContext.init(binding.applicationContext)
        RustImageFacePlugin.register(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Channels are tied to messenger lifetime.
    }
}
