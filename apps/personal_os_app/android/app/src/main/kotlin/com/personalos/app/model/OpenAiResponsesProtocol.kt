package com.personalos.app.model

internal data class OpenAiCompletedResponse(
    val traceId: String,
    val modelId: String,
    val structuredText: String,
)

/** Pure Kotlin validation for the provider envelope returned by Responses. */
internal fun extractOpenAiCompletedResponse(
    response: Map<String, Any?>,
    maximumStructuredTextLength: Int,
): OpenAiCompletedResponse {
    if (response["status"] != "completed") invalidOpenAiResponse()
    val trace = response.requiredOpenAiString("id", 200)
    val model = response.requiredOpenAiString("model", 128)
    val output = response["output"] as? List<*> ?: invalidOpenAiResponse()
    var structuredText: String? = null
    for (rawItem in output) {
        val item = rawItem.openAiStringMap()
        when (item["type"]) {
            "reasoning" -> Unit
            "message" -> {
                if (item["role"] != "assistant") invalidOpenAiResponse()
                val content = item["content"] as? List<*> ?: invalidOpenAiResponse()
                for (rawPart in content) {
                    val part = rawPart.openAiStringMap()
                    when (part["type"]) {
                        "refusal" -> invalidOpenAiResponse()
                        "output_text" -> {
                            if (structuredText != null) invalidOpenAiResponse()
                            structuredText = part.requiredOpenAiString(
                                "text",
                                maximumStructuredTextLength,
                            )
                        }
                        else -> invalidOpenAiResponse()
                    }
                }
            }
            else -> invalidOpenAiResponse()
        }
    }
    return OpenAiCompletedResponse(
        traceId = trace,
        modelId = model,
        structuredText = structuredText ?: invalidOpenAiResponse(),
    )
}

/** Adds only locally trusted audit metadata after exact semantic-key validation. */
internal fun completeOpenAiAppearanceResult(
    semanticResult: Map<String, Any?>,
    completed: OpenAiCompletedResponse,
    promptVersion: String,
): Map<String, Any?> {
    if (semanticResult.keys != OPENAI_APPEARANCE_SEMANTIC_KEYS) {
        invalidOpenAiResponse()
    }
    return LinkedHashMap(semanticResult).apply {
        put("modelTraceRef", completed.traceId)
        put("modelId", completed.modelId)
        put("promptVersion", promptVersion)
        put("inputSummaryRef", "openai://response/${completed.traceId}/input")
    }
}

private val OPENAI_APPEARANCE_SEMANTIC_KEYS = setOf(
    "findings",
    "actions",
    "risks",
    "humanConfirmations",
)

private fun Map<String, Any?>.requiredOpenAiString(
    key: String,
    maximumLength: Int,
): String {
    val value = this[key] as? String ?: invalidOpenAiResponse()
    if (value.isBlank() || value.length > maximumLength) invalidOpenAiResponse()
    return value
}

private fun Any?.openAiStringMap(): Map<String, Any?> {
    val map = this as? Map<*, *> ?: invalidOpenAiResponse()
    if (map.keys.any { key -> key !is String }) invalidOpenAiResponse()
    @Suppress("UNCHECKED_CAST")
    return map as Map<String, Any?>
}

private fun invalidOpenAiResponse(): Nothing = throw NativeAppearanceModelFailure(
    NativeAppearanceModelFailureCode.INVALID_RESPONSE,
)
