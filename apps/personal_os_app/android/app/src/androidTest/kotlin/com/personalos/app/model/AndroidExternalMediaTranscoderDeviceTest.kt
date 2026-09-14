package com.personalos.app.model

import android.graphics.BitmapFactory
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import java.io.ByteArrayInputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Device/emulator codec regression for the real Android AVIF decoder.
 *
 * The fixture is generated in-house from an 8x6 asymmetric PNG pattern with:
 *
 * ffmpeg -i source.png -frames:v 1 -c:v libaom-av1 -still-picture 1 \
 *   -pix_fmt yuv420p pattern.avif
 *
 * It is embedded as Base64 so the repository does not need an opaque binary
 * test asset. This test is deliberately separate from Robolectric because host
 * graphics shadows are not evidence of the device codec implementation.
 */
@RunWith(AndroidJUnit4::class)
class AndroidExternalMediaTranscoderDeviceTest {
    @Test
    @SdkSuppress(minSdkVersion = 31)
    fun realAvifFixtureDecodesAndReachesDelegateAsJpeg() {
        val avif = Base64.decode(AVIF_FIXTURE_BASE64, Base64.NO_WRAP)
        val credential = "sk-test".toCharArray()
        var observedJpeg: ByteArray? = null
        val delegate = ExternalAppearanceModelClient { request, media, observedCredential ->
            assertEquals("image/jpeg", request.mediaType)
            assertTrue(observedCredential === credential)
            observedJpeg = media.readBytes()
            mapOf("ok" to true)
        }
        val wrapper = TranscodingExternalAppearanceModelClient(
            delegate = delegate,
            maximumDecodedPixels = 48,
            maximumEdgePixels = 8,
        )

        try {
            assertTrue(avif.size > 12)
            assertEquals("ftyp", String(avif, 4, 4, Charsets.US_ASCII))
            assertEquals("avif", String(avif, 8, 4, Charsets.US_ASCII))

            val result = wrapper.execute(
                request("image/avif"),
                ByteArrayInputStream(avif),
                credential,
            )

            assertEquals(true, result["ok"])
            val jpeg = requireNotNull(observedJpeg)
            try {
                assertTrue(jpeg.size >= 3)
                assertEquals(0xff, jpeg[0].toInt() and 0xff)
                assertEquals(0xd8, jpeg[1].toInt() and 0xff)
                assertEquals(0xff, jpeg[2].toInt() and 0xff)
                val decoded = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
                assertNotNull(decoded)
                requireNotNull(decoded)
                try {
                    assertEquals(8, decoded.width)
                    assertEquals(6, decoded.height)
                } finally {
                    decoded.recycle()
                }
            } finally {
                jpeg.fill(0)
            }
        } finally {
            credential.fill('\u0000')
            avif.fill(0)
            observedJpeg?.fill(0)
        }
    }

    private fun request(mediaType: String) = ExternalAppearanceModelRequest(
        observationContext = "device-codec-test",
        locale = "en-US",
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

    companion object {
        private const val AVIF_FIXTURE_BASE64 =
            "AAAAIGZ0eXBhdmlmAAAAAGF2aWZtaWYxbWlhZk1BMUIAAAD5bWV0YQAAAAAAAAAvaGRscgAAAAAAAAAAcGljdAAAAAAAAAAAAAAAAFBpY3R1cmVIYW5kbGVyAAAAAA5waXRtAAAAAAABAAAAHmlsb2MAAAAARAAAAQABAAAAAQAAASEAAAAwAAAAKGlpbmYAAAAAAAEAAAAaaW5mZQIAAAAAAQAAYXYwMUNvbG9yAAAAAGppcHJwAAAAS2lwY28AAAAUaXNwZQAAAAAAAAAIAAAABgAAABBwaXhpAAAAAAMICAgAAAAMYXYxQ4EADAAAAAATY29scm5jbHgAAQACAAIAAAAAF2lwbWEAAAAAAAAAAQABBAECgwQAAAA4bWRhdAoIGAi9bICBAQIyJBgAAABRuUBAj/WC3c/Dp0VeS2LU5gA96RNk1ScoE/3bdYbhIA=="
    }
}
