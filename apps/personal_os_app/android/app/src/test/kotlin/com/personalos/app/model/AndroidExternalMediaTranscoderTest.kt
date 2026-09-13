package com.personalos.app.model

import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AndroidExternalMediaTranscoderTest {
    @Test
    fun preservesAlreadySupportedStreamingMediaWithoutBuffering() {
        val observed = mutableListOf<Any?>()
        val delegate = ExternalAppearanceModelClient { request, media, credential ->
            observed += request.mediaType
            observed += media
            observed += credential
            mapOf("ok" to true)
        }
        val wrapper = TranscodingExternalAppearanceModelClient(delegate)
        val media = ByteArrayInputStream(byteArrayOf(1, 2, 3))
        val credential = "sk-test".toCharArray()

        val result = wrapper.execute(request("image/jpeg"), media, credential)

        assertEquals(true, result["ok"])
        assertEquals("image/jpeg", observed[0])
        assertSame(media, observed[1])
        assertSame(credential, observed[2])
    }

    @Test
    fun rejectsOversizeEncodedMediaBeforeDelegateOrCodec() {
        var delegateCalled = false
        val delegate = ExternalAppearanceModelClient { _, _, _ ->
            delegateCalled = true
            mapOf("ok" to true)
        }
        val wrapper = TranscodingExternalAppearanceModelClient(
            delegate = delegate,
            maximumEncodedInputBytes = 2,
        )

        try {
            wrapper.execute(
                request("image/heif"),
                ByteArrayInputStream(byteArrayOf(1, 2, 3)),
                "sk-test".toCharArray(),
            )
            fail("expected NativeAppearanceModelFailure")
        } catch (failure: NativeAppearanceModelFailure) {
            assertEquals(
                NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE,
                failure.failureCode,
            )
        }
        assertFalse(delegateCalled)
    }

    @Test
    fun boundsLargeLandscapeByEdgeAndPixelBudget() {
        val target = boundedDimensions(
            width = 12_000,
            height = 9_000,
            maximumPixels = 12_000_000,
            maximumEdge = 4_096,
        )

        assertTrue(target.first <= 4_096)
        assertTrue(target.second <= 4_096)
        assertTrue(target.first.toLong() * target.second.toLong() <= 12_000_000L)
    }

    @Test
    fun leavesSmallImagesAtNativeDimensions() {
        assertEquals(
            1_920 to 1_080,
            boundedDimensions(
                width = 1_920,
                height = 1_080,
                maximumPixels = 12_000_000,
                maximumEdge = 4_096,
            ),
        )
    }

    @Test
    fun legacyDecoderUsesPowerOfTwoSampleLargeEnoughForBudget() {
        val sample = boundedSampleSize(
            width = 8_000,
            height = 6_000,
            maximumPixels = 12_000_000,
            maximumEdge = 4_096,
        )

        assertEquals(2, sample)
        assertTrue((8_000L / sample) * (6_000L / sample) <= 12_000_000L)
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
