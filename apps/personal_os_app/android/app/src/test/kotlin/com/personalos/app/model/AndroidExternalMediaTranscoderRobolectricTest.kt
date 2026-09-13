package com.personalos.app.model

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AndroidExternalMediaTranscoderRobolectricTest {
    @Test
    fun executesDecodeScaleEncodePipelineBeforeDelegate() {
        val source = Bitmap.createBitmap(128, 96, Bitmap.Config.ARGB_8888)
        val encoded = ByteArrayOutputStream().use { output ->
            assertTrue(source.compress(Bitmap.CompressFormat.PNG, 100, output))
            output.toByteArray()
        }
        source.recycle()

        var observedMediaType: String? = null
        var observedJpeg: ByteArray? = null
        val delegate = ExternalAppearanceModelClient { request, media, _ ->
            observedMediaType = request.mediaType
            observedJpeg = media.readBytes()
            mapOf("ok" to true)
        }
        val wrapper = TranscodingExternalAppearanceModelClient(
            delegate = delegate,
            maximumDecodedPixels = 4_096,
            maximumEdgePixels = 64,
        )

        val result = wrapper.execute(
            request("image/heif"),
            ByteArrayInputStream(encoded),
            "sk-test".toCharArray(),
        )

        assertEquals(true, result["ok"])
        assertEquals("image/jpeg", observedMediaType)
        val jpeg = requireNotNull(observedJpeg)
        assertTrue(jpeg.size >= 3)
        assertEquals(0xff, jpeg[0].toInt() and 0xff)
        assertEquals(0xd8, jpeg[1].toInt() and 0xff)
        assertEquals(0xff, jpeg[2].toInt() and 0xff)
        val decoded = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
        assertNotNull(decoded)
        requireNotNull(decoded)
        assertTrue(decoded.width <= 64)
        assertTrue(decoded.height <= 64)
        assertTrue(decoded.width.toLong() * decoded.height.toLong() <= 4_096L)
        decoded.recycle()
        jpeg.fill(0)
        encoded.fill(0)
    }

    private fun request(mediaType: String) = ExternalAppearanceModelRequest(
        observationContext = "test",
        locale = "zh-CN",
        promptVersion = "appearance-v1",
        mediaType = mediaType,
        promptContract = ExternalAppearancePromptContract(
            version = "appearance-v1",
            responseSchemaVersion = "appearance-result-v1",
            systemInstructions = "Return structured output.",
            maximumFindings = 32,
            maximumActions = 14,
            maximumRisks = 32,
            maximumHumanConfirmations = 32,
        ),
        timeoutMillis = 1_000,
    )
}
