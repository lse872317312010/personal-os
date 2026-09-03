package com.personalos.app.model

import com.personalos.app.security.NativeModelMediaAccess
import java.io.ByteArrayInputStream
import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NativeAppearanceModelTest {
    @Test
    fun keepsMediaInsideNativeConsumerAndClosesTheStream() {
        val media = TrackingMediaAccess(byteArrayOf(1, 2, 3))
        val coordinator = NativeAppearanceModelCoordinator(
            mediaAccess = media,
            transport = NativeAppearanceModelTransport { request, stream ->
                assertEquals("appearance-v1", request.promptVersion)
                assertArrayEquals(byteArrayOf(1, 2, 3), stream.readBytes())
                completeResult()
            },
        )

        val result = coordinator.analyze(validRequest())

        assertEquals("native-fixture-v1", result.modelId)
        assertTrue(media.consumerInvoked)
        assertTrue(media.streamClosed)
    }

    @Test
    fun rejectsPromptVersionMismatch() {
        val coordinator = NativeAppearanceModelCoordinator(
            mediaAccess = TrackingMediaAccess(byteArrayOf(1)),
            transport = NativeAppearanceModelTransport { _, _ ->
                completeResult(promptVersion = "appearance-v2")
            },
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            coordinator.analyze(validRequest())
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_RESPONSE,
            failure.failureCode,
        )
    }

    @Test
    fun redactsRawAdapterFailure() {
        val coordinator = NativeAppearanceModelCoordinator(
            mediaAccess = TrackingMediaAccess(byteArrayOf(1)),
            transport = NativeAppearanceModelTransport { _, _ ->
                error("api-key=secret provider detail")
            },
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            coordinator.analyze(validRequest())
        }

        assertEquals(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            failure.failureCode,
        )
        assertFalse(failure.toString().contains("secret"))
    }

    @Test
    fun rejectsPathOrUrlInsteadOfOpaqueBlobReference() {
        assertThrows(IllegalArgumentException::class.java) {
            validRequest(blobRef = "https://example.test/photo.jpg")
        }
        assertThrows(IllegalArgumentException::class.java) {
            validRequest(blobRef = "/data/user/0/photo.jpg")
        }
    }

    @Test
    fun rejectsTransportBoundaryMismatchBeforeMediaAccess() {
        val media = TrackingMediaAccess(byteArrayOf(1, 2, 3))
        val coordinator = NativeAppearanceModelCoordinator(
            media,
            NativeAppearanceModelTransport { _, _ -> completeResult() },
            NativeModelProcessingBoundary.ON_DEVICE,
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            coordinator.analyze(
                validRequest(
                    processingBoundary = NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
                ),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_REQUEST,
            failure.failureCode,
        )
        assertFalse(media.consumerInvoked)
    }

    @Test
    fun rejectsConsumedExternalCredentialBeforeMediaAccess() {
        val media = TrackingMediaAccess(byteArrayOf(1, 2, 3))
        val adapter = object : NativeAppearanceModelAdapter {
            override val processingBoundary =
                NativeModelProcessingBoundary.EXTERNAL_PROCESSOR
            override val runtimeCredentialReady = false

            override fun analyze(
                request: NativeAppearanceModelRequest,
                media: InputStream,
            ): NativeAppearanceModelResult = error("must not be called")
        }
        val coordinator = NativeAppearanceModelCoordinator(
            media,
            adapter,
            NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            coordinator.analyze(
                validRequest(
                    processingBoundary = NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
                ),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            failure.failureCode,
        )
        assertFalse(media.consumerInvoked)
    }

    @Test
    fun rejectsUnknownExternalPromptBeforeMediaAndCredentialAccess() {
        val media = TrackingMediaAccess(byteArrayOf(1, 2, 3))
        val credentials = EphemeralNativeModelCredentialProvider().also {
            it.install("one-call".toCharArray())
        }
        var clientCalled = false
        val adapter = StructuredExternalAppearanceModelTransport(
            credentials = credentials,
            client = ExternalAppearanceModelClient { _, _, _ ->
                clientCalled = true
                error("must not be called")
            },
        )
        val coordinator = NativeAppearanceModelCoordinator(
            media,
            adapter,
            NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            coordinator.analyze(
                NativeAppearanceModelRequest(
                    blobRef = "blob://1234567890abcdef",
                    observationContext = "front-facing natural light",
                    locale = "zh-CN",
                    promptVersion = "appearance-v2",
                    processingBoundary =
                        NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
                ),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_REQUEST,
            failure.failureCode,
        )
        assertFalse(media.consumerInvoked)
        assertFalse(clientCalled)
        assertTrue(adapter.runtimeCredentialReady)
    }

    private class TrackingMediaAccess(
        private val bytes: ByteArray,
    ) : NativeModelMediaAccess {
        var consumerInvoked = false
        var streamClosed = false

        override fun <T> useBlobForModel(
            blobRef: String,
            consumer: (InputStream) -> T,
        ): T {
            val stream = object : ByteArrayInputStream(bytes) {
                override fun close() {
                    streamClosed = true
                    super.close()
                }
            }
            return stream.use {
                consumerInvoked = true
                consumer(it)
            }
        }
    }
}

private fun validRequest(
    blobRef: String = "blob://1234567890abcdef",
    processingBoundary: NativeModelProcessingBoundary =
        NativeModelProcessingBoundary.ON_DEVICE,
): NativeAppearanceModelRequest = NativeAppearanceModelRequest(
    blobRef = blobRef,
    observationContext = "front-facing natural light",
    locale = "zh-CN",
    promptVersion = "appearance-v1",
    processingBoundary = processingBoundary,
)

private fun completeResult(
    promptVersion: String = "appearance-v1",
): NativeAppearanceModelResult = NativeAppearanceModelResult(
    findings = listOf(
        NativeAppearanceFinding(
            dimension = "hair_shape",
            statement = "Visible outline can be reviewed.",
            confidence = 0.8,
            kind = "observableFact",
        ),
    ),
    actions = listOf(
        NativeAppearanceAction(
            title = "Record a comparison",
            rationale = "Build a reviewable baseline.",
            dayOffset = 1,
            requiresHumanConfirmation = true,
        ),
    ),
    modelTraceRef = "trace://native/1",
    modelId = "native-fixture-v1",
    promptVersion = promptVersion,
    inputSummaryRef = "audit://input/1",
    risks = listOf(
        NativeAppearanceRisk(code = "low_light", statement = "Image may be too dark."),
    ),
    humanConfirmations = listOf(
        NativeAppearanceHumanConfirmation(
            code = "confirm_hair_shape",
            prompt = "Does the visible outline match what you see?",
        ),
    ),
)
