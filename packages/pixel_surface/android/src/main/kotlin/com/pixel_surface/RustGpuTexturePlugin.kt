package com.pixel_surface

import android.app.Application
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.Build
import android.view.Surface
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * Flutter [Texture] bridge — RGBA upload and MediaCodec → Surface (Sprint P0.2 / V1.6).
 *
 * Uses [TextureRegistry.SurfaceProducer] + [TextureRegistry.SurfaceProducer.scheduleFrame]
 * (Flutter 3.27+); legacy [SurfaceTextureEntry.markTextureFrameAvailable] was removed.
 *
 * Upload performance (pixel_surface 1.1.0):
 * - API 26+ (Android 8.0+): the texture backing is `RGBA_8888` and pixels are
 *   pushed via `Bitmap.copyPixelsFromBuffer` — a single native `memcpy` for
 *   RGBA uploads. BGRA uploads run a 32-bit word swap (a few microseconds for
 *   typical preview sizes) and then the same memcpy.
 * - API 21–25: fall back to the legacy `IntArray` + `setPixels` path used
 *   before 1.1.0, since `RGBA_8888` and `copyPixelsFromBuffer` require
 *   Android 8.0.
 *
 * Memory pressure (pixel_surface 1.1.0):
 * - The plugin registers a [ComponentCallbacks2] on the application context
 *   and reacts to `onTrimMemory` events by:
 *   - `TRIM_MEMORY_RUNNING_LOW` / `TRIM_MEMORY_RUNNING_CRITICAL`: mark every
 *     unreferenced backing bitmap for recycling on next detach.
 *   - `TRIM_MEMORY_BACKGROUND` / `TRIM_MEMORY_UI_HIDDEN`: recycle every
 *     backing bitmap immediately. They are lazily re-created on the next
 *     `updateTexture` call.
 *   The Flutter-side texture handle is preserved across trims; only the GPU
 *   memory is released, matching the iOS/macOS `flushPools` semantics.
 */
class RustGpuTexturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ComponentCallbacks2 {
    private var channel: MethodChannel? = null
    private var textureRegistry: TextureRegistry? = null
    private var application: Application? = null

    private enum class Layout {
        Rgba8888,
        Bgra8888,
    }

    private data class Entry(
        val surfaceProducer: TextureRegistry.SurfaceProducer,
        var bitmap: Bitmap?,
        val width: Int,
        val height: Int,
    )

    private val textures = mutableMapOf<Long, Entry>()

    /// Aggregated stats for [debugStats]. Cheap to read; the map is only
    /// touched on the platform channel thread, so no extra lock is needed.
    private var trimEventCount: Int = 0
    private var recycledBitmapCount: Int = 0
    private var lastTrimLevel: Int = -1
    private var lastTrimMs: Double = 0.0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        textureRegistry = binding.textureRegistry
        application = binding.applicationContext as? Application
        application?.registerComponentCallbacks(this)
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        application?.unregisterComponentCallbacks(this)
        application = null
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
            "resizeTexture" -> resizeTexture(call, result)
            "debugStats" -> debugStats(result)
            "flushPools" -> flushPools(result)
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

    private fun layoutFromArgs(value: Any?): Layout =
        when (value) {
            "bgra8888" -> Layout.Bgra8888
            else -> Layout.Rgba8888
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
        val bitmap = createBackingBitmap(width, height)
        textures[handle] = Entry(producer, bitmap, width, height)
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
        var bitmap = entry.bitmap
        if (bitmap == null) {
            // The bitmap may have been recycled by an `onTrimMemory`
            // callback. Re-create it lazily so the next frame works.
            bitmap = createBackingBitmap(entry.width, entry.height)
            entry.bitmap = bitmap
        }
        val w = bitmap.width
        val h = bitmap.height
        val expected = w * h * 4
        if (pixels.size < expected) {
            result.error("size_mismatch", "pixel buffer too small", null)
            return
        }
        val layout = layoutFromArgs(args["layout"])
        try {
            uploadPixels(bitmap, pixels, w, h, layout)
            presentToSurface(entry, bitmap)
        } catch (e: Exception) {
            result.error("upload_failed", e.message ?: e.toString(), null)
            return
        }
        result.success(null)
    }

    /**
     * Resize an existing texture handle to a new (width, height). The Flutter
     * `SurfaceProducer.setSize` is the canonical Android resize primitive —
     * it triggers a re-alloc of the underlying `SurfaceTexture` on the next
     * `scheduleFrame` call. The backing bitmap is recycled and re-created
     * lazily in `updateTexture` to match the new dimensions.
     */
    private fun resizeTexture(call: MethodCall, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = call.arguments as? Map<String, Any>
        val handle = handleFromArgs(args)
        val width = (args?.get("width") as? Number)?.toInt() ?: 0
        val height = (args?.get("height") as? Number)?.toInt() ?: 0
        val entry = handle?.let { textures[it] }
        if (handle == null || width <= 0 || height <= 0 || entry == null) {
            result.error("bad_args", "handle/width/height required", null)
            return
        }
        entry.surfaceProducer.setSize(width, height)
        entry.bitmap?.recycle()
        entry.bitmap = null
        textures[handle] = entry.copy(width = width, height = height)
        entry.surfaceProducer.scheduleFrame()
        result.success(null)
    }

    private fun debugStats(result: MethodChannel.Result) {
        result.success(
            mapOf(
                "handleCount" to textures.size,
                "trimEventCount" to trimEventCount,
                "recycledBitmapCount" to recycledBitmapCount,
                "lastTrimLevel" to lastTrimLevel,
                "lastTrimMs" to lastTrimMs,
            ),
        )
    }

    /// Operator-driven flush; matches the iOS/macOS `flushPools` method.
    private fun flushPools(result: MethodChannel.Result) {
        recycleAllBitmaps()
        result.success(null)
    }

    /**
     * Push [pixels] into [bitmap] using the fast path available on the device.
     * - RGBA8888 / API 26+:  direct `copyPixelsFromBuffer` (native memcpy).
     * - BGRA8888 / API 26+:  32-bit word swap, then `copyPixelsFromBuffer`.
     * - API 21–25:  legacy `IntArray` + `setPixels` path (one full-frame rebuild).
     */
    private fun uploadPixels(
        bitmap: Bitmap,
        pixels: ByteArray,
        w: Int,
        h: Int,
        layout: Layout,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            uploadFastPath(bitmap, pixels, layout)
        } else {
            uploadLegacy(bitmap, pixels, w, h, layout)
        }
    }

    private fun uploadFastPath(bitmap: Bitmap, pixels: ByteArray, layout: Layout) {
        // Wrap the inbound bytes in a direct, native-order ByteBuffer. We
        // never call `Bitmap.allocateDirect` ourselves; `copyPixelsFromBuffer`
        // is happy with any direct ByteBuffer as long as it contains at
        // least w*h*4 bytes.
        val buf = ByteBuffer.allocateDirect(pixels.size).order(ByteOrder.nativeOrder())
        buf.put(pixels)
        buf.position(0)
        if (layout == Layout.Bgra8888) {
            // Bitmap is RGBA_8888, so the on-GPU layout is (R, G, B, A) per
            // pixel. The inbound bytes are (B, G, R, A). Reorder the buffer
            // 32 bits at a time: keep the middle two bytes, swap the outer.
            val intCount = pixels.size / 4
            val view = buf.order(ByteOrder.LITTLE_ENDIAN).asIntBuffer()
            val tmp = IntArray(intCount)
            view.get(tmp)
            for (i in 0 until intCount) {
                val v = tmp[i]
                tmp[i] = (v and 0xff00ff00.toInt()) or
                    ((v and 0xff) shl 16) or
                    ((v and 0xff0000) ushr 16)
            }
            view.position(0)
            view.put(tmp)
        }
        buf.position(0)
        bitmap.copyPixelsFromBuffer(buf)
    }

    /**
     * API 21–25 fallback. Always ARGB_8888 (only config available pre-O);
     * rebuilds a packed `IntArray` of ARGB words from RGBA or BGRA bytes.
     */
    private fun uploadLegacy(
        bitmap: Bitmap,
        pixels: ByteArray,
        w: Int,
        h: Int,
        layout: Layout,
    ) {
        val count = w * h
        val argb = IntArray(count)
        var si = 0
        when (layout) {
            Layout.Rgba8888 -> {
                for (i in 0 until count) {
                    val r = pixels[si].toInt() and 0xff
                    val g = pixels[si + 1].toInt() and 0xff
                    val b = pixels[si + 2].toInt() and 0xff
                    val a = pixels[si + 3].toInt() and 0xff
                    argb[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
                    si += 4
                }
            }
            Layout.Bgra8888 -> {
                for (i in 0 until count) {
                    val b = pixels[si].toInt() and 0xff
                    val g = pixels[si + 1].toInt() and 0xff
                    val r = pixels[si + 2].toInt() and 0xff
                    val a = pixels[si + 3].toInt() and 0xff
                    argb[i] = (a shl 24) or (r shl 16) or (g shl 8) or b
                    si += 4
                }
            }
        }
        bitmap.setPixels(argb, 0, w, 0, 0, w, h)
    }

    private fun presentToSurface(entry: Entry, bitmap: Bitmap) {
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

    /**
     * Allocate the backing bitmap. API 26+ uses `RGBA_8888` so callers can
     * push pixels via `copyPixelsFromBuffer` directly. API 21–25 uses
     * `ARGB_8888` (the only four-channel config available before O) and
     * relies on the legacy `IntArray` swizzle path.
     */
    private fun createBackingBitmap(width: Int, height: Int): Bitmap {
        val config = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Bitmap.Config.RGBA_8888
        } else {
            Bitmap.Config.ARGB_8888
        }
        return Bitmap.createBitmap(width, height, config)
    }

    // ----- Memory pressure handling -------------------------------------------

    private fun recycleAllBitmaps() {
        var count = 0
        for (entry in textures.values) {
            val bm = entry.bitmap
            if (bm != null && !bm.isRecycled) {
                bm.recycle()
                count += 1
            }
            entry.bitmap = null
        }
        recycledBitmapCount += count
    }

    // ComponentCallbacks2

    override fun onConfigurationChanged(newConfig: Configuration) {
        // No-op: surface producer handles config changes itself.
    }

    override fun onLowMemory() {
        // Legacy equivalent of `onTrimMemory(TRIM_MEMORY_COMPLETE)`.
        trimEventCount += 1
        lastTrimLevel = ComponentCallbacks2.TRIM_MEMORY_COMPLETE
        lastTrimMs = System.currentTimeMillis().toDouble()
        recycleAllBitmaps()
    }

    override fun onTrimMemory(level: Int) {
        trimEventCount += 1
        lastTrimLevel = level
        lastTrimMs = System.currentTimeMillis().toDouble()
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL,
            -> {
                // App is still in the foreground but the OS is asking us to
                // drop some weight. Recycle everything; the next frame will
                // re-allocate on demand.
                recycleAllBitmaps()
            }
            ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN,
            ComponentCallbacks2.TRIM_MEMORY_BACKGROUND,
            ComponentCallbacks2.TRIM_MEMORY_MODERATE,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            -> {
                recycleAllBitmaps()
            }
            else -> {
                // Unknown level; be conservative and flush.
                recycleAllBitmaps()
            }
        }
    }

    companion object {
        private const val CHANNEL = "pixel_surface/texture"
    }
}
