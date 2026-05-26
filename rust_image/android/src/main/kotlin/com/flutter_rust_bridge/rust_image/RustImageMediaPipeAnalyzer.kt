package com.flutter_rust_bridge.rust_image

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult
import java.io.File
import java.nio.ByteBuffer

/**
 * MediaPipe 468-point face mesh when models are downloaded (Nexus A).
 */
internal object RustImageMediaPipeAnalyzer {
    private const val MIN_LANDMARKS = 468
    private const val FACE_OVAL_COUNT = 36

    fun modelsReady(modelDir: String?): Boolean {
        if (modelDir.isNullOrBlank()) return false
        val base = File(modelDir)
        return File(base, "face_landmarker.task").exists() &&
            File(base, "selfie_segmenter.tflite").exists()
    }

    fun analyze(
        imageBytes: ByteArray,
        pixelFormat: String,
        targetWidth: Int,
        targetHeight: Int,
        modelDir: String,
    ): Map<String, Any> {
        val bitmap = decodeBitmap(imageBytes, pixelFormat, targetWidth, targetHeight)
            ?: throw IllegalArgumentException("Could not decode image")
        val scaled = Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)

        val facePath = File(modelDir, "face_landmarker.task").absolutePath
        val segPath = File(modelDir, "selfie_segmenter.tflite").absolutePath

        val landmarks = detectLandmarks(scaled, facePath, targetWidth, targetHeight)
        val mask = segmentSelfie(scaled, segPath, targetWidth, targetHeight)

        val confidence = if (landmarks.size >= MIN_LANDMARKS) 0.98f else 0f
        val landmarkMaps = landmarks.map {
            mapOf("x" to it.first.toDouble(), "y" to it.second.toDouble(), "z" to 0.0)
        }

        return mapOf(
            "landmarks" to landmarkMaps,
            "confidence" to confidence.toDouble(),
            "faceContourCount" to FACE_OVAL_COUNT,
            "regionCounts" to emptyList<Int>(),
            "mask" to mapOf(
                "width" to targetWidth,
                "height" to targetHeight,
                "bytes" to mask,
            ),
            "meshKind" to "mediapipe468",
        )
    }

    private fun decodeBitmap(
        bytes: ByteArray,
        pixelFormat: String,
        width: Int,
        height: Int,
    ): Bitmap? {
        if (pixelFormat == "rgba" && width > 0 && height > 0 && bytes.size >= width * height * 4) {
            return Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { bmp ->
                bmp.copyPixelsFromBuffer(ByteBuffer.wrap(bytes))
            }
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    }

    private fun detectLandmarks(
        bitmap: Bitmap,
        modelPath: String,
        width: Int,
        height: Int,
    ): List<Pair<Float, Float>> {
        val baseOptions = BaseOptions.builder().setModelAssetPath(modelPath).build()
        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(1)
            .build()
        val landmarker = FaceLandmarker.createFromOptions(RustImageAppContext.get(), options)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: FaceLandmarkerResult = landmarker.detect(mpImage)
        landmarker.close()

        val face = result.faceLandmarks().firstOrNull() ?: return emptyList()
        return face.map { lm ->
            Pair(lm.x(), lm.y())
        }
    }

    private fun segmentSelfie(
        bitmap: Bitmap,
        modelPath: String,
        width: Int,
        height: Int,
    ): ByteArray {
        val baseOptions = BaseOptions.builder().setModelAssetPath(modelPath).build()
        val options = ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.IMAGE)
            .setOutputCategoryMask(true)
            .build()
        val segmenter = ImageSegmenter.createFromOptions(RustImageAppContext.get(), options)
        val mpImage = BitmapImageBuilder(bitmap).build()
        val result: ImageSegmenterResult = segmenter.segment(mpImage)
        segmenter.close()

        val mask = result.categoryMask().get()
        val maskWidth = mask.width
        val maskHeight = mask.height
        val buffer = mask.buffer
        val out = ByteArray(width * height)

        for (y in 0 until height) {
            val sy = y * maskHeight / height
            for (x in 0 until width) {
                val sx = x * maskWidth / width
                val idx = sy * maskWidth + sx
                val confidence = buffer.get(idx).toInt() and 0xFF
                out[y * width + x] = if (confidence > 0) 255.toByte() else 0
            }
        }
        return out
    }
}
