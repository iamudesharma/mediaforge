package com.flutter_rust_bridge.rust_image

import android.graphics.Bitmap
import android.view.Surface
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Flutter [Texture] preview for GPU beauty readback (Sprint 22 Phase 4).
 * Mirrors macOS [RustImageTexturePlugin.swift] — RGBA upload via MethodChannel.
 */
object RustImageTexturePlugin {
    private const val CHANNEL = "rust_image/texture"

    private data class Entry(
        val surfaceProducer: TextureRegistry.SurfaceProducer,
        var bitmap: Bitmap?,
    )

    private val textures = mutableMapOf<Long, Entry>()
    private var textureRegistry: TextureRegistry? = null

    fun register(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val channel = MethodChannel(messenger, CHANNEL)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "createTexture" -> createTexture(call, result)
                "updateTexture" -> updateTexture(call, result)
                "notifyFrameAvailable" -> notifyFrameAvailable(call, result)
                "disposeTexture" -> disposeTexture(call, result)
                else -> result.notImplemented()
            }
        }
    }

    fun attachRegistry(registry: TextureRegistry) {
        textureRegistry = registry
    }

    private fun handleFromArgs(args: Map<*, *>?): Long? {
        if (args == null) return null
        val raw = args["handle"] ?: return null
        return when (raw) {
            is Int -> raw.toLong()
            is Long -> raw
            is Number -> raw.toLong()
            else -> null
        }
    }

    private fun createTexture(call: MethodCall, result: MethodChannel.Result) {
        val registry = textureRegistry
        if (registry == null) {
            result.error("no_registry", "TextureRegistry not attached", null)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        val width = (args?.get("width") as? Number)?.toInt() ?: 0
        val height = (args?.get("height") as? Number)?.toInt() ?: 0
        val handle = handleFromArgs(args)
        if (width <= 0 || height <= 0 || handle == null) {
            result.error("bad_args", "width/height/handle required", null)
            return
        }
        val producer = registry.createSurfaceProducer()
        producer.setSize(width, height)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        textures[handle] = Entry(producer, bitmap)
        result.success(producer.id())
    }

    private fun updateTexture(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        val handle = handleFromArgs(args)
        val pixels = args?.get("pixels") as? ByteArray
        val entry = handle?.let { textures[it] }
        if (handle == null || pixels == null || entry == null) {
            result.error("bad_args", "handle/pixels required", null)
            return
        }
        val bitmap = entry.bitmap
        if (bitmap == null) {
            result.error("no_bitmap", "texture not created", null)
            return
        }
        val w = bitmap.width
        val h = bitmap.height
        val expected = w * h * 4
        if (pixels.size < expected) {
            result.error("size_mismatch", "pixel buffer too small", null)
            return
        }
        val pixelsCopy = IntArray(w * h)
        var si = 0
        for (i in pixelsCopy.indices) {
            val r = pixels[si].toInt() and 0xff
            val g = pixels[si + 1].toInt() and 0xff
            val b = pixels[si + 2].toInt() and 0xff
            val a = pixels[si + 3].toInt() and 0xff
            pixelsCopy[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
            si += 4
        }
        bitmap.setPixels(pixelsCopy, 0, w, 0, 0, w, h)
        val surface = entry.surfaceProducer.surface
        try {
            val canvas = surface.lockCanvas(null)
            if (canvas != null) {
                canvas.drawBitmap(bitmap, 0f, 0f, null)
                surface.unlockCanvasAndPost(canvas)
            }
        } catch (_: Exception) {
            // Surface may not be ready on first frame.
        }
        entry.surfaceProducer.scheduleFrame()
        result.success(null)
    }

    private fun notifyFrameAvailable(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        val handle = handleFromArgs(args)
        val entry = handle?.let { textures[it] }
        entry?.surfaceProducer?.scheduleFrame()
        result.success(null)
    }

    private fun disposeTexture(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        val handle = handleFromArgs(args)
        if (handle != null) {
            val entry = textures.remove(handle)
            entry?.bitmap?.recycle()
            entry?.surfaceProducer?.release()
        }
        result.success(null)
    }
}
