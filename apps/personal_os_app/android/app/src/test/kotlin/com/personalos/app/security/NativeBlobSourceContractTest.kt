package com.personalos.app.security

import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeBlobSourceContractTest {
    @Test
    fun sourceExposesOnlyOpaqueTokenAndNativeStream() {
        var closed = false
        val source = object : NativeBlobSource {
            override val opaqueToken: String = "picker_token_01"

            override fun openStream(): InputStream =
                ByteArrayInputStream(byteArrayOf(1, 2, 3))

            override fun close() {
                closed = true
            }
        }

        assertEquals("picker_token_01", source.opaqueToken)
        source.openStream().use { stream ->
            assertArrayEquals(byteArrayOf(1, 2, 3), stream.readBytes())
        }
        source.close()
        assertTrue(closed)
    }

    @Test
    fun blobReferenceMustBeOpaqueBlobScheme() {
        assertEquals("blob://opaque-id", NativeBlobReference("blob://opaque-id").value)
        assertThrows(IllegalArgumentException::class.java) {
            NativeBlobReference("/provider/photo.jpg")
        }
    }

    @Test
    fun modelMediaBufferIsZeroedAfterSuccess() {
        val owned = byteArrayOf(7, 8, 9)

        val result = consumeOwnedBlobBytes(owned) { stream -> stream.readBytes().sum() }

        assertEquals(24, result)
        assertArrayEquals(byteArrayOf(0, 0, 0), owned)
    }

    @Test
    fun modelMediaBufferIsZeroedAfterConsumerFailure() {
        val owned = byteArrayOf(7, 8, 9)

        assertThrows(IllegalStateException::class.java) {
            consumeOwnedBlobBytes(owned) { error("adapter failed") }
        }

        assertArrayEquals(byteArrayOf(0, 0, 0), owned)
    }
}
