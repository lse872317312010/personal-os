package com.personalos.app.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class OpenAiResponsesProtocolTest {
    @Test
    fun extractsCompletedStructuredTextAndInjectsTrustedMetadata() {
        val completed = extractOpenAiCompletedResponse(
            completedEnvelope("{\"findings\":[]}"),
            maximumStructuredTextLength = 1_024,
        )

        val result = completeOpenAiAppearanceResult(
            semanticResult(),
            completed,
            promptVersion = "appearance-v1",
        )

        assertEquals("resp_123", result["modelTraceRef"])
        assertEquals("gpt-test", result["modelId"])
        assertEquals("appearance-v1", result["promptVersion"])
        assertEquals(
            "openai://response/resp_123/input",
            result["inputSummaryRef"],
        )
    }

    @Test
    fun rejectsIncompleteAndRefusalEnvelopes() {
        val incomplete = completedEnvelope("{}").toMutableMap().apply {
            put("status", "incomplete")
        }
        assertInvalidResponse {
            extractOpenAiCompletedResponse(incomplete, 1_024)
        }

        val refusal = completedEnvelope("{}").toMutableMap().apply {
            put(
                "output",
                listOf(
                    mapOf(
                        "type" to "message",
                        "role" to "assistant",
                        "content" to listOf(
                            mapOf("type" to "refusal", "refusal" to "redacted"),
                        ),
                    ),
                ),
            )
        }
        assertInvalidResponse {
            extractOpenAiCompletedResponse(refusal, 1_024)
        }
    }

    @Test
    fun rejectsDuplicateOutputText() {
        val duplicate = completedEnvelope("{}").toMutableMap().apply {
            put(
                "output",
                listOf(
                    mapOf(
                        "type" to "message",
                        "role" to "assistant",
                        "content" to listOf(
                            mapOf("type" to "output_text", "text" to "{}"),
                            mapOf("type" to "output_text", "text" to "{}"),
                        ),
                    ),
                ),
            )
        }

        assertInvalidResponse {
            extractOpenAiCompletedResponse(duplicate, 1_024)
        }
    }

    @Test
    fun rejectsProviderAttemptToSupplyReservedAuditMetadata() {
        val injected = semanticResult().toMutableMap().apply {
            put("modelId", "provider-controlled")
        }

        assertInvalidResponse {
            completeOpenAiAppearanceResult(
                injected,
                OpenAiCompletedResponse("resp_123", "gpt-test", "{}"),
                "appearance-v1",
            )
        }
    }

    private fun assertInvalidResponse(block: () -> Unit) {
        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            block()
        }
        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_RESPONSE,
            failure.failureCode,
        )
    }
}

private fun completedEnvelope(structuredText: String): Map<String, Any?> = mapOf(
    "id" to "resp_123",
    "model" to "gpt-test",
    "status" to "completed",
    "output" to listOf(
        mapOf("type" to "reasoning"),
        mapOf(
            "type" to "message",
            "role" to "assistant",
            "content" to listOf(
                mapOf("type" to "output_text", "text" to structuredText),
            ),
        ),
    ),
)

private fun semanticResult(): Map<String, Any?> = linkedMapOf(
    "findings" to emptyList<Any>(),
    "actions" to emptyList<Any>(),
    "risks" to emptyList<Any>(),
    "humanConfirmations" to emptyList<Any>(),
)
