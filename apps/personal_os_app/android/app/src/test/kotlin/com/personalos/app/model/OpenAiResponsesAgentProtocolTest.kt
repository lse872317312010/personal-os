package com.personalos.app.model

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class OpenAiResponsesAgentProtocolTest {
    @Test
    fun requestDisablesStorageAndRequiresOneJsonObject() {
        val prompt = "Use only the approved Personal OS context."
        val request = JSONObject(openAiAgentRequestBody("gpt-test", prompt))
        val firstInput = request.getJSONArray("input").getJSONObject(0)
        val inputText = firstInput.getJSONArray("content")
            .getJSONObject(0)
            .getString("text")

        assertFalse(request.getBoolean("store"))
        assertEquals("gpt-test", request.getString("model"))
        assertEquals(prompt, inputText)
        assertEquals(
            "json_object",
            request.getJSONObject("text")
                .getJSONObject("format")
                .getString("type"),
        )
    }

    @Test
    fun extractsOnlyACompletedAssistantJsonResponse() {
        val raw = responseEnvelope(status = "completed", text = "{\"strategy\":{}}")

        assertEquals(
            "{\"strategy\":{}}",
            extractOpenAiCompletedResponse(raw, 1_024).structuredText,
        )
    }

    @Test
    fun rejectsIncompleteAndRefusedResponses() {
        val incomplete = responseEnvelope(status = "incomplete", text = "{}")
        assertThrows(NativeAppearanceModelFailure::class.java) {
            extractOpenAiCompletedResponse(incomplete, 1_024)
        }

        val refused = JSONObject(responseEnvelope(status = "completed", text = "{}"))
            .put(
                "output",
                JSONArray().put(
                    JSONObject()
                        .put("type", "message")
                        .put("role", "assistant")
                        .put(
                            "content",
                            JSONArray().put(
                                JSONObject()
                                    .put("type", "refusal")
                                    .put("refusal", "redacted"),
                            ),
                        ),
                ),
            )
            .toString()
        assertThrows(NativeAppearanceModelFailure::class.java) {
            extractOpenAiCompletedResponse(refused, 1_024)
        }
    }

    private fun responseEnvelope(status: String, text: String): String =
        JSONObject()
            .put("id", "resp_test")
            .put("model", "gpt-test")
            .put("status", status)
            .put(
                "output",
                JSONArray().put(
                    JSONObject()
                        .put("type", "message")
                        .put("role", "assistant")
                        .put(
                            "content",
                            JSONArray().put(
                                JSONObject()
                                    .put("type", "output_text")
                                    .put("text", text),
                            ),
                        ),
                ),
            )
            .toString()
}
