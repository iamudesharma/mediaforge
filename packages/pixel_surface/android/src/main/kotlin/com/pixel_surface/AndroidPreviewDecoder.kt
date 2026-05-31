package com.pixel_surface

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.view.Surface
import kotlin.math.max

/**
 * Single-frame preview decode to a [Surface] (Flutter SurfaceTexture backing).
 * Sprint V1.6 — avoids RGBA CPU upload on Android when stable.
 */
object AndroidPreviewDecoder {
    data class FrameResult(
        val ptsMs: Long,
        val width: Int,
        val height: Int,
    )

    class DecodeException(message: String) : Exception(message)

    fun decodeFrameToSurface(
        path: String,
        positionMs: Long,
        surface: Surface,
        maxEdge: Int,
    ): FrameResult {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(path)
            var trackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("video/")) {
                    trackIndex = i
                    break
                }
            }
            if (trackIndex < 0) {
                throw DecodeException("no video track")
            }
            extractor.selectTrack(trackIndex)
            val format = extractor.getTrackFormat(trackIndex)
            val mime =
                format.getString(MediaFormat.KEY_MIME)
                    ?: throw DecodeException("missing mime type")

            var srcW = format.getInteger(MediaFormat.KEY_WIDTH)
            var srcH = format.getInteger(MediaFormat.KEY_HEIGHT)
            if (format.containsKey(MediaFormat.KEY_ROTATION)) {
                val rotation = format.getInteger(MediaFormat.KEY_ROTATION)
                if (rotation == 90 || rotation == 270) {
                    val tmp = srcW
                    srcW = srcH
                    srcH = tmp
                }
            }

            if (maxEdge > 0 && max(srcW, srcH) > maxEdge) {
                throw DecodeException("video exceeds preview max edge; use RGBA fallback")
            }

            val codec = MediaCodec.createDecoderByType(mime)
            try {
                codec.configure(format, surface, null, 0)
                codec.start()

                val targetUs = positionMs.coerceAtLeast(0L) * 1000L
                extractor.seekTo(targetUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

                val bufferInfo = MediaCodec.BufferInfo()
                var rendered = false
                var outPtsMs = positionMs
                var inputDone = false
                var iterations = 0
                val maxIterations = 512

                while (!rendered && iterations < maxIterations) {
                    iterations++
                    if (!inputDone) {
                        val inputIndex = codec.dequeueInputBuffer(5_000)
                        if (inputIndex >= 0) {
                            val inputBuffer =
                                codec.getInputBuffer(inputIndex)
                                    ?: throw DecodeException("no input buffer")
                            val sampleSize = extractor.readSampleData(inputBuffer, 0)
                            if (sampleSize < 0) {
                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    0,
                                    0L,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM,
                                )
                                inputDone = true
                            } else {
                                val pts = extractor.sampleTime
                                codec.queueInputBuffer(
                                    inputIndex,
                                    0,
                                    sampleSize,
                                    pts,
                                    0,
                                )
                                extractor.advance()
                            }
                        }
                    }

                    val outputIndex = codec.dequeueOutputBuffer(bufferInfo, 5_000)
                    when {
                        outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> Unit
                        outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> Unit
                        outputIndex >= 0 -> {
                            val eos =
                                bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                            val ptsUs = bufferInfo.presentationTimeUs
                            val shouldRender =
                                !rendered &&
                                    (ptsUs >= targetUs || eos || inputDone)
                            if (shouldRender) {
                                codec.releaseOutputBuffer(outputIndex, true)
                                rendered = true
                                outPtsMs = (ptsUs / 1000L).coerceAtLeast(0L)
                            } else {
                                codec.releaseOutputBuffer(outputIndex, false)
                            }
                            if (eos) break
                        }
                    }
                }

                if (!rendered) {
                    throw DecodeException("MediaCodec did not produce a preview frame")
                }

                return FrameResult(
                    ptsMs = outPtsMs,
                    width = srcW,
                    height = srcH,
                )
            } finally {
                try {
                    codec.stop()
                } catch (_: Exception) {
                }
                codec.release()
            }
        } finally {
            extractor.release()
        }
    }
}
