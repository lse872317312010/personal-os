package com.personalos.app.model

import java.io.InputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class StructuredExternalAppearanceModelTransportTest {
    @Test
    fun parsesBoundedStructuredResultAndConsumesCredential() {
        val ownedCredential = "runtime-only".toCharArray()
        val credentials = EphemeralNativeModelCredentialProvider().also {
            it.install(ownedCredential)
        }
        var observedMedia = byteArrayOf()
        val transport = StructuredExternalAppearanceModelTransport(
            credentials = credentials,
            client = ExternalAppearanceModelClient { request, media, credential ->
                assertEquals("appearance-v1", request.promptVersion)
                assertEquals("image/jpeg", request.mediaType)
                assertEquals("appearance-v1", request.promptContract.version)
                assertEquals(
                    "appearance-result-v1",
                    request.promptContract.responseSchemaVersion,
                )
                assertEquals(45_000, request.timeoutMillis)
                assertEquals(12, credential.size)
                observedMedia = media.readBytes()
                completeExternalResponse()
            },
        )

        val result = transport.analyze(
            externalRequest(),
            jpegBytes().inputStream(),
        )

        assertEquals("provider-model-1", result.modelId)
        assertArrayEquals(jpegBytes(), observedMedia)
        assertArrayEquals(CharArray(ownedCredential.size), ownedCredential)
        assertFalse(transport.runtimeCredentialReady)
    }

    @Test
    fun rejectsMediaAboveConfiguredLimit() {
        val transport = transportWithClient(maximumMediaBytes = 3) { _, media, _ ->
            media.readBytes()
            completeExternalResponse()
        }

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            transport.analyze(
                externalRequest(),
                jpegBytes().inputStream(),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_REQUEST,
            failure.failureCode,
        )
    }

    @Test
    fun rejectsEmptyMedia() {
        val transport = transportWithClient { _, media, _ ->
            media.readBytes()
            completeExternalResponse()
        }

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            transport.analyze(externalRequest(), byteArrayOf().inputStream())
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_REQUEST,
            failure.failureCode,
        )
    }

    @Test
    fun rejectsUnsupportedMediaBeforeProviderCall() {
        var called = false
        val transport = transportWithClient { _, _, _ ->
            called = true
            completeExternalResponse()
        }

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            transport.analyze(
                externalRequest(),
                byteArrayOf(1, 2, 3, 4).inputStream(),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_REQUEST,
            failure.failureCode,
        )
        assertFalse(called)
    }

    @Test
    fun recognizesSupportedNativeImageFormats() {
        val formats = listOf(
            pngBytes() to "image/png",
            "RIFF0000WEBP".toByteArray() to "image/webp",
            isoBaseMediaBytes("heic") to "image/heif",
            isoBaseMediaBytes("avif") to "image/avif",
        )

        for ((bytes, expectedMediaType) in formats) {
            var observedMediaType: String? = null
            val transport = transportWithClient(maximumMediaBytes = 16) { request, media, _ ->
                observedMediaType = request.mediaType
                media.readBytes()
                completeExternalResponse()
            }

            transport.analyze(externalRequest(), bytes.inputStream())

            assertEquals(expectedMediaType, observedMediaType)
        }
    }

    @Test
    fun rejectsClientThatDoesNotConsumeTheCompleteMedia() {
        val transport = transportWithClient { _, media, _ ->
            media.read()
            completeExternalResponse()
        }

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            transport.analyze(
                externalRequest(),
                jpegBytes().inputStream(),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            failure.failureCode,
        )
    }

    @Test
    fun rejectsUnknownResponseFields() {
        val response = completeExternalResponse().toMutableMap()
        response["rawProviderBody"] = "must not cross boundary"

        assertThrows(IllegalArgumentException::class.java) {
            parseExternalAppearanceModelResult(response)
        }
    }

    @Test
    fun rejectsOversizedResponseCollections() {
        val response = completeExternalResponse().toMutableMap()
        response["findings"] = List(33) { completeFinding() }

        assertThrows(IllegalArgumentException::class.java) {
            parseExternalAppearanceModelResult(response)
        }
    }

    private fun transportWithClient(
        maximumMediaBytes: Long = 16,
        client: (
            ExternalAppearanceModelRequest,
            InputStream,
            CharArray,
        ) -> Map<String, Any?>,
    ): StructuredExternalAppearanceModelTransport {
        val credentials = EphemeralNativeModelCredentialProvider().also {
            it.install("one-call".toCharArray())
        }
        return StructuredExternalAppearanceModelTransport(
            credentials = credentials,
            client = ExternalAppearanceModelClient { request, media, credential ->
                client(request, media, credential)
            },
            maximumMediaBytes = maximumMediaBytes,
        )
    }
}

private fun externalRequest(): NativeAppearanceModelRequest =
    NativeAppearanceModelRequest(
        blobRef = "blob://1234567890abcdef",
        observationContext = "front-facing natural light",
        locale = "zh-CN",
        promptVersion = "appearance-v1",
        processingBoundary = NativeModelProcessingBoundary.EXTERNAL_PROCESSOR,
    )

private fun jpegBytes(): ByteArray = byteArrayOf(
    0xFF.toByte(),
    0xD8.toByte(),
    0xFF.toByte(),
    0x00,
)

private fun pngBytes(): ByteArray = byteArrayOf(
    0x89.toByte(),
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
)

private fun isoBaseMediaBytes(brand: String): ByteArray =
    byteArrayOf(0, 0, 0, 0) + "ftyp$brand".toByteArray()

private fun completeExternalResponse(): Map<String, Any?> = mapOf(
    "findings" to listOf(completeFinding()),
    "actions" to listOf(
        mapOf(
            "title" to "Record a comparison",
            "rationale" to "Build a reviewable baseline.",
            "dayOffset" to 1,
            "requiresHumanConfirmation" to true,
        ),
    ),
    "modelTraceRef" to "trace://provider/1",
    "modelId" to "provider-model-1",
    "promptVersion" to "appearance-v1",
    "inputSummaryRef" to "audit://input/1",
    "risks" to listOf(
        mapOf("code" to "low_light", "statement" to "Image may be too dark."),
    ),
    "humanConfirmations" to listOf(
        mapOf(
            "code" to "confirm_hair_shape",
            "prompt" to "Does the visible outline match what you see?",
        ),
    ),
)

private fun completeFinding(): Map<String, Any?> = mapOf(
    "dimension" to "hair_shape",
    "statement" to "Visible outline can be reviewed.",
    "confidence" to 0.8,
    "kind" to "observableFact",
)
