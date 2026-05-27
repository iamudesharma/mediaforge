package com.flutter_rust_bridge.rust_image_core

import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import com.google.mlkit.vision.segmentation.Segmentation
import com.google.mlkit.vision.segmentation.SegmentationMask
import com.google.mlkit.vision.segmentation.selfie.SelfieSegmenterOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import java.nio.ByteBuffer

/**
 * Nexus D — ML Kit face landmarks + selfie mask (same FRB payload as Apple Vision).
 */
object RustImageFacePlugin {
    private const val CHANNEL = "rust_image/face"
    private const val MIN_LANDMARKS = 68

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(true)
                "isMediaPipeReady" -> {
                    val args = call.arguments as? Map<*, *>
                    val modelDir = args?.get("modelDir") as? String
                    result.success(RustImageMediaPipeAnalyzer.modelsReady(modelDir))
                }
                "analyzeImage" -> {
                    val args = call.arguments as? Map<*, *>
                    val bytes = byteArrayFromArg(args?.get("bytes"))
                    val width = (args?.get("width") as? Number)?.toInt() ?: 0
                    val height = (args?.get("height") as? Number)?.toInt() ?: 0
                    val pixelFormat = args?.get("pixelFormat") as? String ?: "jpeg"
                    val modelDir = args?.get("modelDir") as? String
                    if (bytes == null || width <= 0 || height <= 0) {
                        result.error("bad_args", "bytes/width/height required", null)
                        return@setMethodCallHandler
                    }
                    CoroutineScope(Dispatchers.Default).launch {
                        try {
                            val payload = if (RustImageMediaPipeAnalyzer.modelsReady(modelDir)) {
                                RustImageMediaPipeAnalyzer.analyze(
                                    bytes,
                                    pixelFormat,
                                    width,
                                    height,
                                    modelDir!!,
                                )
                            } else {
                                analyzeMlKit(bytes, pixelFormat, width, height)
                            }
                            CoroutineScope(Dispatchers.Main).launch { result.success(payload) }
                        } catch (e: Exception) {
                            CoroutineScope(Dispatchers.Main).launch {
                                result.error("analyze_failed", e.message, null)
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun byteArrayFromArg(value: Any?): ByteArray? = when (value) {
        is ByteArray -> value
        is ByteBuffer -> {
            val buf = value.duplicate()
            ByteArray(buf.remaining()).also { buf.get(it) }
        }
        else -> null
    }

    private suspend fun analyzeMlKit(
        jpegOrPng: ByteArray,
        pixelFormat: String,
        targetWidth: Int,
        targetHeight: Int,
    ): Map<String, Any> {
        val decoded = if (pixelFormat == "rgba" && targetWidth > 0 && targetHeight > 0 &&
            jpegOrPng.size >= targetWidth * targetHeight * 4
        ) {
            android.graphics.Bitmap.createBitmap(
                targetWidth,
                targetHeight,
                android.graphics.Bitmap.Config.ARGB_8888,
            ).also { bmp ->
                bmp.copyPixelsFromBuffer(java.nio.ByteBuffer.wrap(jpegOrPng))
            }
        } else {
            android.graphics.BitmapFactory.decodeByteArray(jpegOrPng, 0, jpegOrPng.size)
                ?: throw IllegalArgumentException("Could not decode image")
        }
        val scaled = android.graphics.Bitmap.createScaledBitmap(decoded, targetWidth, targetHeight, true)
        val image = InputImage.fromBitmap(scaled, 0)

        val (landmarkPairs, contourCount, regionCounts) =
            detectLandmarks(image, targetWidth, targetHeight)
        val mask = segmentSelfie(image, targetWidth, targetHeight)

        val confidence = if (landmarkPairs.size >= MIN_LANDMARKS) 0.95f else 0f
        val landmarkMaps = landmarkPairs.map {
            mapOf("x" to it.first.toDouble(), "y" to it.second.toDouble(), "z" to 0.0)
        }

        return mapOf(
            "landmarks" to landmarkMaps,
            "confidence" to confidence.toDouble(),
            "faceContourCount" to contourCount,
            "regionCounts" to regionCounts,
            "mask" to mapOf(
                "width" to targetWidth,
                "height" to targetHeight,
                "bytes" to mask,
            ),
        )
    }

    private suspend fun detectLandmarks(
        image: InputImage,
        width: Int,
        height: Int,
    ): Triple<List<Pair<Float, Float>>, Int, List<Int>> {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
            .build()
        val detector = FaceDetection.getClient(options)

        val faces = suspendCancellableCoroutine { cont ->
            detector.process(image)
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

        if (faces.isEmpty()) {
            detector.close()
            return Triple(emptyList(), 0, emptyList())
        }

        val face = faces[0]
        val points = mutableListOf<Pair<Float, Float>>()
        val regionCounts = mutableListOf<Int>()

        fun norm(x: Float, y: Float) = Pair(x / width.toFloat(), y / height.toFloat())

        fun addContour(type: Int) {
            val before = points.size
            face.getContour(type)?.points?.forEach { pt ->
                points.add(norm(pt.x, pt.y))
            }
            regionCounts.add(points.size - before)
        }

        fun addLandmark(type: Int) {
            val before = points.size
            face.getLandmark(type)?.position?.let { pt ->
                points.add(norm(pt.x, pt.y))
            }
            regionCounts.add(points.size - before)
        }

        fun addContours(vararg types: Int) {
            val before = points.size
            for (type in types) {
                face.getContour(type)?.points?.forEach { pt ->
                    points.add(norm(pt.x, pt.y))
                }
            }
            regionCounts.add(points.size - before)
        }

        val beforeContour = points.size
        addContour(FaceContour.FACE)
        val contourCount = points.size - beforeContour
        if (regionCounts.isNotEmpty()) regionCounts.removeAt(0)

        // Vision-compatible region order (11 feature regions).
        addContour(FaceContour.LEFT_EYE)
        addContour(FaceContour.RIGHT_EYE)
        addContour(FaceContour.LEFT_EYEBROW_TOP)
        addContour(FaceContour.RIGHT_EYEBROW_TOP)
        addContour(FaceContour.NOSE_BRIDGE)
        addContour(FaceContour.NOSE_BOTTOM)
        addContour(FaceContour.NOSE_BRIDGE)
        addContours(
            FaceContour.UPPER_LIP_TOP,
            FaceContour.UPPER_LIP_BOTTOM,
            FaceContour.LOWER_LIP_TOP,
            FaceContour.LOWER_LIP_BOTTOM,
        )
        addContours(
            FaceContour.UPPER_LIP_BOTTOM,
            FaceContour.LOWER_LIP_TOP,
        )
        addLandmark(FaceLandmark.LEFT_EYE)
        addLandmark(FaceLandmark.RIGHT_EYE)

        detector.close()
        return Triple(points.toList(), contourCount, regionCounts)
    }

    private suspend fun segmentSelfie(
        image: InputImage,
        width: Int,
        height: Int,
    ): ByteArray {
        val options = SelfieSegmenterOptions.Builder()
            .setDetectorMode(SelfieSegmenterOptions.SINGLE_IMAGE_MODE)
            .build()
        val segmenter = Segmentation.getClient(options)

        val mask: SegmentationMask = suspendCancellableCoroutine { cont ->
            segmenter.process(image)
                .addOnSuccessListener { cont.resume(it) }
                .addOnFailureListener { cont.resumeWithException(it) }
        }

        val buffer = mask.buffer
        val maskWidth = mask.width
        val maskHeight = mask.height
        val out = ByteArray(width * height)

        for (y in 0 until height) {
            val sy = y * maskHeight / height
            for (x in 0 until width) {
                val sx = x * maskWidth / width
                val idx = sy * maskWidth + sx
                val confidence = buffer.get(idx).toInt() and 0xFF
                out[y * width + x] = confidence.toByte()
            }
        }

        segmenter.close()
        return out
    }
}
