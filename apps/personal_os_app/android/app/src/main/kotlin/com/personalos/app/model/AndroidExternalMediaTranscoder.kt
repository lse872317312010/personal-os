package com.personalos.app.model

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.os.Build
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import kotlin.math.ceil
import kotlin.math.sqrt

/**
 * Android-only compatibility layer for provider image formats.
 *
 * JPEG/PNG/WebP stay streaming and untouched. HEIF/AVIF are decoded only when
 * the platform codec is available, down-scaled before pixel allocation, and
 * re-encoded to bounded JPEG in memory. No plaintext temporary file is used.
 */
internal class TranscodingExternalAppearanceModelClient(
    private val delegate: ExternalAppearanceModelClient,
    private val maximumEncodedInputBytes: Int = MAXIMUM_ENCODED_INPUT_BYTES,
    private val maximumOutputBytes: Int = MAXIMUM_OUTPUT_BYTES,
    private val maximumDecodedPixels: Long = MAXIMUM_DECODED_PIXELS,
    private val maximumEdgePixels: Int = MAXIMUM_EDGE_PIXELS,
) : ExternalAppearanceModelClient {
    init {
        require(maximumEncodedInputBytes in 1..MAXIMUM_ENCODED_INPUT_BYTES)
        require(maximumOutputBytes in 1..MAXIMUM_OUTPUT_BYTES)
        require(maximumDecodedPixels in 1..MAXIMUM_DECODED_PIXELS)
        require(maximumEdgePixels in 1..MAXIMUM_EDGE_PIXELS)
    }

    override fun execute(
        request: ExternalAppearanceModelRequest,
        media: InputStream,
        credential: CharArray,
    ): Map<String, Any?> {
        if (request.mediaType !in TRANSCODED_MEDIA_TYPES) {
            return delegate.execute(request, media, credential)
        }
        val encoded = media.readBoundedSensitive(maximumEncodedInputBytes)
        try {
            val bitmap = decodeBoundedBitmap(
                encoded = encoded,
                maximumDecodedPixels = maximumDecodedPixels,
                maximumEdgePixels = maximumEdgePixels,
            )
            try {
                val output = SensitiveBoundedByteArrayOutputStream(maximumOutputBytes)
                val compressed = try {
                    bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)
                } catch (_: IOException) {
                    false
                }
                if (!compressed || output.size() == 0) invalidTranscode()
                val jpeg = output.copySensitiveBytes()
                try {
                    return delegate.execute(
                        request.copy(mediaType = "image/jpeg"),
                        ByteArrayInputStream(jpeg),
                        credential,
                    )
                } finally {
                    jpeg.fill(0)
                    output.zeroize()
                }
            } finally {
                bitmap.recycle()
            }
        } finally {
            encoded.fill(0)
        }
    }

    override fun cancelInFlight() {
        delegate.cancelInFlight()
    }

    companion object {
        private const val MAXIMUM_ENCODED_INPUT_BYTES = 15 * 1024 * 1024
        private const val MAXIMUM_OUTPUT_BYTES = 15 * 1024 * 1024
        private const val MAXIMUM_DECODED_PIXELS = 12_000_000L
        private const val MAXIMUM_EDGE_PIXELS = 4_096
        private const val JPEG_QUALITY = 92
        private val TRANSCODED_MEDIA_TYPES = setOf("image/heif", "image/avif")
    }
}

private fun decodeBoundedBitmap(
    encoded: ByteArray,
    maximumDecodedPixels: Long,
    maximumEdgePixels: Int,
): Bitmap {
    if (encoded.isEmpty()) invalidTranscode()
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        decodeWithImageDecoder(encoded, maximumDecodedPixels, maximumEdgePixels)
    } else {
        decodeWithBitmapFactory(encoded, maximumDecodedPixels, maximumEdgePixels)
    }
}

private fun decodeWithImageDecoder(
    encoded: ByteArray,
    maximumDecodedPixels: Long,
    maximumEdgePixels: Int,
): Bitmap {
    try {
        val source = ImageDecoder.createSource(ByteBuffer.wrap(encoded))
        return ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            val target = boundedDimensions(
                width = info.size.width,
                height = info.size.height,
                maximumPixels = maximumDecodedPixels,
                maximumEdge = maximumEdgePixels,
            )
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.memorySizePolicy = ImageDecoder.MEMORY_POLICY_LOW_RAM
            if (target.first != info.size.width || target.second != info.size.height) {
                decoder.setTargetSize(target.first, target.second)
            }
        }
    } catch (_: Throwable) {
        invalidTranscode()
    }
}

private fun decodeWithBitmapFactory(
    encoded: ByteArray,
    maximumDecodedPixels: Long,
    maximumEdgePixels: Int,
): Bitmap {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(encoded, 0, encoded.size, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) invalidTranscode()
    val sampleSize = boundedSampleSize(
        width = bounds.outWidth,
        height = bounds.outHeight,
        maximumPixels = maximumDecodedPixels,
        maximumEdge = maximumEdgePixels,
    )
    val options = BitmapFactory.Options().apply {
        inSampleSize = sampleSize
        inPreferredConfig = Bitmap.Config.ARGB_8888
    }
    return BitmapFactory.decodeByteArray(encoded, 0, encoded.size, options)
        ?: invalidTranscode()
}

internal fun boundedDimensions(
    width: Int,
    height: Int,
    maximumPixels: Long,
    maximumEdge: Int,
): Pair<Int, Int> {
    if (width <= 0 || height <= 0 || maximumPixels <= 0 || maximumEdge <= 0) {
        invalidTranscode()
    }
    val edgeScale = maximumEdge.toDouble() / maxOf(width, height).toDouble()
    val pixelScale = sqrt(maximumPixels.toDouble() / (width.toDouble() * height.toDouble()))
    val scale = minOf(1.0, edgeScale, pixelScale)
    return maxOf(1, (width * scale).toInt()) to maxOf(1, (height * scale).toInt())
}

internal fun boundedSampleSize(
    width: Int,
    height: Int,
    maximumPixels: Long,
    maximumEdge: Int,
): Int {
    val target = boundedDimensions(width, height, maximumPixels, maximumEdge)
    val required = maxOf(
        width.toDouble() / target.first.toDouble(),
        height.toDouble() / target.second.toDouble(),
    )
    var sample = 1
    val minimumPowerOfTwo = maxOf(1, ceil(required).toInt())
    while (sample < minimumPowerOfTwo && sample <= Int.MAX_VALUE / 2) {
        sample *= 2
    }
    return sample
}

private fun InputStream.readBoundedSensitive(maximumBytes: Int): ByteArray {
    val output = SensitiveBoundedByteArrayOutputStream(maximumBytes)
    val scratch = ByteArray(16 * 1024)
    try {
        while (true) {
            val count = read(scratch)
            if (count == -1) break
            output.write(scratch, 0, count)
        }
        return output.copySensitiveBytes()
    } catch (_: IOException) {
        invalidTranscode()
    } finally {
        scratch.fill(0)
        output.zeroize()
    }
}

/** ByteArrayOutputStream whose owned backing buffer can be explicitly cleared. */
private class SensitiveBoundedByteArrayOutputStream(
    private val maximumBytes: Int,
) : ByteArrayOutputStream(minOf(maximumBytes, 64 * 1024)) {
    override fun write(value: Int) {
        requireCapacity(1)
        super.write(value)
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
        require(offset >= 0 && length >= 0 && length <= buffer.size - offset)
        requireCapacity(length)
        super.write(buffer, offset, length)
    }

    fun copySensitiveBytes(): ByteArray = toByteArray()

    fun zeroize() {
        buf.fill(0)
        reset()
    }

    private fun requireCapacity(additional: Int) {
        if (additional > maximumBytes - count) throw IOException()
    }
}

private fun invalidTranscode(): Nothing = throw NativeAppearanceModelFailure(
    NativeAppearanceModelFailureCode.INVALID_REQUEST,
)
