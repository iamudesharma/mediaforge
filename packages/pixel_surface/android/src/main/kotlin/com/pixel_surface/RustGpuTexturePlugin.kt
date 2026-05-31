package com.pixel_surface

import android.graphics.Bitmap
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Flutter [Texture] bridge — RGBA upload and MediaCodec → Surface (Sprint P0.2 / V1.6).
 *
 * Uses [TextureRegistry.SurfaceProducer] + [TextureRegistry.SurfaceProducer.scheduleFrame]
 * (Flutter 3.27+); legacy [SurfaceTextureEntry.markTextureFrameAvailable] was removed.
 */
class RustGpuTexturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var textureRegistry: TextureRegistry? = null

    private data class Entry(
        val surfaceProducer: TextureRegistry.SurfaceProducer,
        var bitmap: Bitmap?,
    )

    private val textures = mutableMapOf<Long, Entry>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = binding.textureRegistry
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        textureRegistry = null
        textures.values.forEach { entry ->
            entry.bitmap?.recycle()
            entry.surfaceProducer.release()
        }
        textures.clear()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createTexture" -> createTexture(call, result)
            "updateTexture" -> updateTexture(call, result)
            "notifyFrameAvailable" -> notifyFrameAvailable(call, result)
            "decodePreviewToSurface" -> decodePreviewToSurface(call, result)
            "presentPixelBuffer" -> result.notImplemented()
            "disposeTexture" -> disposeTexture(call, result)
            else -> result.notImplemented()
        }
    }

    private fun handleFromArgs(args: Map<*, *>?): Long? {
        if (args == null) return null
        return when (val raw = args["handle"]) {
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

    private fun decodePreviewToSurface(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        val handle = handleFromArgs(args)
        val path = args?.get("path") as? String
        val positionMs = (args?.get("positionMs") as? Number)?.toLong()
        val maxEdge = (args?.get("maxEdge") as? Number)?.toInt() ?: 0
        val entry = handle?.let { textures[it] }
        if (handle == null || path.isNullOrBlank() || positionMs == null || entry == null) {
            result.error("bad_args", "handle/path/positionMs required", null)
            return
        }
        val surface = entry.surfaceProducer.surface
        try {
            val frame =
                AndroidPreviewDecoder.decodeFrameToSurface(
                    path = path,
                    positionMs = positionMs,
                    surface = surface,
                    maxEdge = maxEdge,
                )
            entry.surfaceProducer.scheduleFrame()
            result.success(
                mapOf(
                    "ptsMs" to frame.ptsMs,
                    "width" to frame.width,
                    "height" to frame.height,
                ),
            )
        } catch (e: AndroidPreviewDecoder.DecodeException) {
            result.error("decode_failed", e.message, null)
        } catch (e: Exception) {
            result.error("decode_failed", e.message ?: e.toString(), null)
        }
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

    companion object {
        private const val CHANNEL = "pixel_surface/texture"
    }
}
