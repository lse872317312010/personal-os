package com.personalos.app.model

import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection
import org.json.JSONArray
import org.json.JSONObject

/**
 * Text-only OpenAI Responses API adapter. It sends no image or binary media,
 * sets store=false, and accepts exactly one completed JSON response.
 */
internal class OpenAiResponsesAgentClient(
    private val model: String,
    private val endpoint: URL = URL(OPENAI_RESPONSES_ENDPOINT),
) {
    companion object {
        private const val OPENAI_RESPONSES_ENDPOINT = "https://api.openai.com/v1/responses"
        private const val MAXIMUM_PROMPT_BYTES = 256 * 1024
        private const val MAXIMUM_RESPONSE_BYTES = 256 * 1024
        private const val MAXIMUM_REPLY_LENGTH = 65_536
        private const val CONNECT_TIMEOUT_MILLIS = 15_000
        private const val READ_TIMEOUT_MILLIS = 45_000
    }

    private val cancellationEpoch = AtomicLong(0)
    private val activeConnection = AtomicReference<HttpsURLConnection?>(null)

    init {
        require(model.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")))
        require(
            endpoint.protocol == "https" &&
                endpoint.host == "api.openai.com" &&
                endpoint.port in listOf(-1, 443) &&
                endpoint.userInfo == null,
        )
    }

    fun currentEpoch(): Long = cancellationEpoch.get()

    fun complete(prompt: String, credential: CharArray, expectedEpoch: Long): String {
        if (prompt.isBlank() ||
            prompt.length > AgentCompletionMaximums.MAXIMUM_PROMPT_LENGTH ||
            credential.isEmpty() ||
            credential.size > 512 ||
            credential.any { character -> character.code !in 0x21..0x7E }
        ) {
            throw AgentCompletionFailure(AgentCompletionFailureCode.INVALID_REQUEST)
        }
        val requestBody = openAiAgentRequestBody(model, prompt).toByteArray(Charsets.UTF_8)
        if (requestBody.size > MAXIMUM_PROMPT_BYTES) {
            throw AgentCompletionFailure(AgentCompletionFailureCode.INVALID_REQUEST)
        }
        if (cancellationEpoch.get() != expectedEpoch) {
            throw AgentCompletionFailure(AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
        }

        val connection = try {
            endpoint.openConnection() as? HttpsURLConnection
                ?: throw AgentCompletionFailure(AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
        } catch (failure: AgentCompletionFailure) {
            throw failure
        } catch (_: Throwable) {
            throw AgentCompletionFailure(AgentCompletionFailureCode.REQUEST_FAILED)
        }
        if (!activeConnection.compareAndSet(null, connection)) {
            connection.disconnect()
            throw AgentCompletionFailure(AgentCompletionFailureCode.REQUEST_FAILED)
        }

        try {
            configure(connection, credential, requestBody.size)
            if (cancellationEpoch.get() != expectedEpoch) {
                throw AgentCompletionFailure(AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
            }
            connection.outputStream.use { output -> output.write(requestBody) }
            if (cancellationEpoch.get() != expectedEpoch) {
                throw AgentCompletionFailure(AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                connection.errorStream?.use { it.drainBounded() }
                throw AgentCompletionFailure(AgentCompletionFailureCode.REQUEST_FAILED)
            }
            requireJsonResponse(connection)
            val raw = connection.inputStream.use { it.readBounded() }
            val rawResponse = try {
                Charsets.UTF_8.newDecoder().decode(java.nio.ByteBuffer.wrap(raw)).toString()
            } finally {
                raw.fill(0)
            }
            return try {
                extractOpenAiCompletedResponse(rawResponse, MAXIMUM_REPLY_LENGTH).structuredText
            } catch (_: Throwable) {
                throw AgentCompletionFailure(AgentCompletionFailureCode.INVALID_RESPONSE)
            }
        } catch (failure: AgentCompletionFailure) {
            throw failure
        } catch (_: Throwable) {
            if (cancellationEpoch.get() != expectedEpoch) {
                throw AgentCompletionFailure(AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
            }
            throw AgentCompletionFailure(AgentCompletionFailureCode.REQUEST_FAILED)
        } finally {
            activeConnection.compareAndSet(connection, null)
            connection.disconnect()
            requestBody.fill(0)
        }
    }

    fun cancelInFlight() {
        cancellationEpoch.incrementAndGet()
        activeConnection.getAndSet(null)?.disconnect()
    }

    private fun configure(
        connection: HttpsURLConnection,
        credential: CharArray,
        requestBodyLength: Int,
    ) {
        connection.instanceFollowRedirects = false
        connection.useCaches = false
        connection.connectTimeout = CONNECT_TIMEOUT_MILLIS
        connection.readTimeout = READ_TIMEOUT_MILLIS
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.setFixedLengthStreamingMode(requestBodyLength)
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("Accept-Encoding", "identity")
        connection.setRequestProperty("Cache-Control", "no-store")
        connection.setRequestProperty("Content-Type", "application/json")
        // HttpsURLConnection needs a short-lived immutable header String;
        // owned CharArray copies are still zeroized and this value is not logged.
        connection.setRequestProperty("Authorization", "Bearer ${String(credential)}")
    }

    private fun requireJsonResponse(connection: HttpsURLConnection) {
        if (connection.contentType?.substringBefore(';')?.trim() != "application/json") {
            throw AgentCompletionFailure(AgentCompletionFailureCode.INVALID_RESPONSE)
        }
        val encoding = connection.contentEncoding
        if (encoding != null && !encoding.equals("identity", ignoreCase = true)) {
            throw AgentCompletionFailure(AgentCompletionFailureCode.INVALID_RESPONSE)
        }
    }

    private fun InputStream.readBounded(): ByteArray {
        val output = ByteArrayOutputStream()
        val buffer = ByteArray(8 * 1024)
        try {
            while (true) {
                val count = read(buffer)
                if (count < 0) break
                if (output.size() + count > MAXIMUM_RESPONSE_BYTES) {
                    throw AgentCompletionFailure(AgentCompletionFailureCode.INVALID_RESPONSE)
                }
                output.write(buffer, 0, count)
                buffer.fill(0)
            }
            return output.toByteArray()
        } catch (failure: AgentCompletionFailure) {
            throw failure
        } finally {
            buffer.fill(0)
        }
    }

    private fun InputStream.drainBounded() {
        val buffer = ByteArray(4 * 1024)
        var consumed = 0
        try {
            while (consumed <= MAXIMUM_RESPONSE_BYTES) {
                val count = read(buffer)
                if (count < 0) return
                consumed += count
            }
        } finally {
            buffer.fill(0)
        }
    }
}

internal object AgentCompletionMaximums {
    const val MAXIMUM_PROMPT_LENGTH = 120_000
}

internal fun openAiAgentRequestBody(model: String, prompt: String): String =
    JSONObject()
        .put("model", model)
        .put("store", false)
        .put("max_output_tokens", 4096)
        .put(
            "input",
            JSONArray().put(
                JSONObject()
                    .put("role", "user")
                    .put(
                        "content",
                        JSONArray().put(
                            JSONObject()
                                .put("type", "input_text")
                                .put("text", prompt),
                        ),
                    ),
            ),
        )
        .put(
            "text",
            JSONObject().put(
                "format",
                JSONObject().put("type", "json_object"),
            ),
        )
        .toString()
