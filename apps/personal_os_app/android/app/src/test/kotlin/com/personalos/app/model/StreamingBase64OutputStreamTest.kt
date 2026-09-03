package com.personalos.app.model

import java.io.ByteArrayOutputStream
import java.io.OutputStream
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StreamingBase64OutputStreamTest {
    @Test
    fun matchesStandardBase64AcrossChunkAndPaddingBoundaries() {
        val lengths = listOf(0, 1, 2, 3, 4, 5, 8_191, 8_192, 12_289, 32_769)
        for (length in lengths) {
            val input = ByteArray(length) { index ->
                ((index * 37 + 11) and 0xFF).toByte()
            }
            val output = ByteArrayOutputStream()
            StreamingBase64OutputStream(output).use { encoder ->
                var offset = 0
                var chunkIndex = 0
                val chunks = intArrayOf(1, 2, 7, 4_093, 8_192)
                while (offset < input.size) {
                    val count = minOf(chunks[chunkIndex % chunks.size], input.size - offset)
                    encoder.write(input, offset, count)
                    offset += count
                    chunkIndex++
                }
            }

            assertArrayEquals(
                "length=$length",
                Base64.getEncoder().encode(input),
                output.toByteArray(),
            )
            input.fill(0)
        }
    }

    @Test
    fun singleByteWritesMatchStandardBase64() {
        val input = byteArrayOf(0, 1, 2, 0x7F, 0x80.toByte(), 0xFF.toByte())
        val output = ByteArrayOutputStream()

        StreamingBase64OutputStream(output).use { encoder ->
            input.forEach { value -> encoder.write(value.toInt()) }
        }

        assertArrayEquals(Base64.getEncoder().encode(input), output.toByteArray())
        input.fill(0)
    }

    @Test
    fun closingEncoderFlushesButDoesNotCloseDelegate() {
        val delegate = TrackingOutputStream()
        val encoder = StreamingBase64OutputStream(delegate)

        encoder.write(byteArrayOf(1, 2))
        encoder.close()
        encoder.close()

        assertTrue(delegate.flushed)
        assertFalse(delegate.closed)
        assertArrayEquals(
            Base64.getEncoder().encode(byteArrayOf(1, 2)),
            delegate.bytes.toByteArray(),
        )
    }

    private class TrackingOutputStream : OutputStream() {
        val bytes = ByteArrayOutputStream()
        var flushed = false
        var closed = false

        override fun write(value: Int) {
            bytes.write(value)
        }

        override fun write(buffer: ByteArray, offset: Int, length: Int) {
            bytes.write(buffer, offset, length)
        }

        override fun flush() {
            flushed = true
        }

        override fun close() {
            closed = true
        }
    }
}
