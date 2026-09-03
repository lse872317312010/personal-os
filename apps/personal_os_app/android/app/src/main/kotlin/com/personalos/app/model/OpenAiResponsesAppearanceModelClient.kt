package com.personalos.app.model

import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import javax.net.ssl.HttpsURLConnection

/**
 * OpenAI Responses API implementation of the provider network boundary.
 *
 * Media is base64-encoded directly into the request stream and is never copied
 * into a complete plaintext byte array. The API key is supplied only for this
 * synchronous call. HttpsURLConnection requires an immutable String for the
 * Authorization header, so that final header copy cannot be zeroized; it is
 * never persisted or logged and the connection is disconnected in `finally`.
 */
internal class OpenAiResponsesAppearanceModelClient(
    private val model: String,
    private val endpoint: URL = URL(OPENAI_RESPONSES_ENDPOINT),
) : ExternalAppearanceModelClient {
    companion object {
        private const val OPENAI_RESPONSES_ENDPOINT =
            "https://api.openai.com/v1/responses"
        private const val OPENAI_HOST = "api.openai.com"
        private const val MAXIMUM_RESPONSE_BYTES = 256 * 1024
        private val SUPPORTED_OPENAI_MEDIA_TYPES = setOf(
            "image/jpeg",
            "image/png",
            "image/webp",
        )
    }

    init {
        require(model.matches(Regex("[A-Za-z0-9][A-Za-z0-9._-]{0,127}")))
        require(endpoint.protocol == "https")
        require(endpoint.host == OPENAI_HOST)
        require(endpoint.port == -1 || endpoint.port == 443)
        require(endpoint.path == "/v1/responses")
        require(endpoint.query == null && endpoint.ref == null && endpoint.userInfo == null)
    }

    private val activeConnection = AtomicReference<HttpsURLConnection?>(null)
    private val cancellationEpoch = AtomicLong(0)

    override fun execute(
        request: ExternalAppearanceModelRequest,
        media: InputStream,
        credential: CharArray,
    ): Map<String, Any?> {
        if (request.mediaType !in SUPPORTED_OPENAI_MEDIA_TYPES ||
            credential.isEmpty() ||
            credential.size > 512 ||
            credential.any { character -> character.code !in 0x21..0x7E }
        ) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.INVALID_REQUEST,
            )
        }
        val callEpoch = cancellationEpoch.get()
        val connection = endpoint.openConnection() as? HttpsURLConnection
            ?: throw IOException()
        if (!activeConnection.compareAndSet(null, connection)) {
            connection.disconnect()
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
        if (cancellationEpoch.get() != callEpoch) {
            activeConnection.compareAndSet(connection, null)
            connection.disconnect()
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
        try {
            configure(connection, request, credential)
            writeRequest(connection, request, media)
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                connection.errorStream?.use { it.drainBounded() }
                throw NativeAppearanceModelFailure(
                    NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
                )
            }
            requireJsonResponse(connection)
            val responseBytes = connection.inputStream.use { it.readBounded() }
            try {
                return parseResponse(
                    responseBytes.toString(Charsets.UTF_8),
                    request,
                )
            } finally {
                responseBytes.fill(0)
            }
        } finally {
            activeConnection.compareAndSet(connection, null)
            connection.disconnect()
        }
    }

    override fun cancelInFlight() {
        cancellationEpoch.incrementAndGet()
        activeConnection.getAndSet(null)?.disconnect()
    }

    private fun configure(
        connection: HttpsURLConnection,
        request: ExternalAppearanceModelRequest,
        credential: CharArray,
    ) {
        connection.instanceFollowRedirects = false
        connection.useCaches = false
        connection.requestMethod = "POST"
        connection.doOutput = true
        connection.connectTimeout = request.timeoutMillis
        connection.readTimeout = request.timeoutMillis
        connection.setChunkedStreamingMode(16 * 1024)
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("Accept-Encoding", "identity")
        connection.setRequestProperty("Content-Type", "application/json")
        connection.setRequestProperty("Authorization", "Bearer ${String(credential)}")
    }

    private fun writeRequest(
        connection: HttpsURLConnection,
        request: ExternalAppearanceModelRequest,
        media: InputStream,
    ) {
        connection.outputStream.use { output ->
            output.writeUtf8(requestPrefix(request))
            val base64 = StreamingBase64OutputStream(output)
            val buffer = ByteArray(16 * 1024)
            try {
                while (true) {
                    val count = media.read(buffer)
                    if (count == -1) break
                    base64.write(buffer, 0, count)
                }
            } finally {
                buffer.fill(0)
                base64.close()
            }
            output.writeUtf8(requestSuffix(request))
        }
    }

    private fun requestPrefix(request: ExternalAppearanceModelRequest): String = buildString {
        append("{\"model\":")
        append(JSONObject.quote(model))
        append(",\"store\":false,\"max_output_tokens\":4096")
        append(",\"instructions\":")
        append(JSONObject.quote(request.promptContract.systemInstructions))
        append(",\"input\":[{\"role\":\"user\",\"content\":[")
        append("{\"type\":\"input_text\",\"text\":")
        append(
            JSONObject.quote(
                "Locale: ${request.locale}\nObservation context: " +
                    request.observationContext,
            ),
        )
        append("},{\"type\":\"input_image\",\"image_url\":\"")
        append("data:")
        append(request.mediaType)
        append(";base64,")
    }

    private fun requestSuffix(request: ExternalAppearanceModelRequest): String = buildString {
        append("\",\"detail\":\"high\"}]}],\"text\":{\"format\":")
        append(responseFormat(request.promptContract).toString())
        append("}}")
    }

    private fun responseFormat(contract: ExternalAppearancePromptContract): JSONObject =
        JSONObject().apply {
            put("type", "json_schema")
            put("name", contract.responseSchemaVersion.replace('-', '_'))
            put("strict", true)
            put("schema", semanticResponseSchema())
        }

    private fun semanticResponseSchema(): JSONObject = objectSchema(
        linkedMapOf(
            "findings" to arraySchema(
                objectSchema(
                    linkedMapOf(
                        "dimension" to stringSchema(),
                        "statement" to stringSchema(),
                        "confidence" to JSONObject().put("type", "number"),
                        "kind" to JSONObject()
                            .put("type", "string")
                            .put(
                                "enum",
                                JSONArray(
                                    listOf("observableFact", "uncertainInference"),
                                ),
                            ),
                    ),
                ),
            ),
            "actions" to arraySchema(
                objectSchema(
                    linkedMapOf(
                        "title" to stringSchema(),
                        "rationale" to stringSchema(),
                        "dayOffset" to JSONObject().put("type", "integer"),
                        "requiresHumanConfirmation" to
                            JSONObject().put("type", "boolean"),
                    ),
                ),
            ),
            "risks" to arraySchema(
                objectSchema(
                    linkedMapOf(
                        "code" to stringSchema(),
                        "statement" to stringSchema(),
                    ),
                ),
            ),
            "humanConfirmations" to arraySchema(
                objectSchema(
                    linkedMapOf(
                        "code" to stringSchema(),
                        "prompt" to stringSchema(),
                    ),
                ),
            ),
        ),
    )

    private fun parseResponse(
        rawResponse: String,
        request: ExternalAppearanceModelRequest,
    ): Map<String, Any?> {
        try {
            val response = JSONObject(rawResponse).toStringKeyMap()
            val completed = extractOpenAiCompletedResponse(
                response,
                MAXIMUM_RESPONSE_BYTES,
            )
            val semantic = JSONObject(completed.structuredText).toStringKeyMap()
            return completeOpenAiAppearanceResult(
                semantic,
                completed,
                request.promptVersion,
            )
        } catch (failure: NativeAppearanceModelFailure) {
            throw failure
        } catch (_: Throwable) {
            invalidResponse()
        }
    }

    private fun requireJsonResponse(connection: HttpsURLConnection) {
        val contentType = connection.contentType?.substringBefore(';')?.trim()
        if (contentType != "application/json") invalidResponse()
        val encoding = connection.contentEncoding
        if (encoding != null && !encoding.equals("identity", ignoreCase = true)) {
            invalidResponse()
        }
        if (connection.contentLengthLong > MAXIMUM_RESPONSE_BYTES) invalidResponse()
    }

    private fun InputStream.readBounded(): ByteArray {
        val buffer = ByteArray(8 * 1024)
        val output = ByteArrayOutputStream()
        try {
            while (true) {
                val count = read(buffer)
                if (count == -1) return output.toByteArray()
                if (output.size() + count > MAXIMUM_RESPONSE_BYTES) invalidResponse()
                output.write(buffer, 0, count)
            }
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
                if (count == -1) return
                consumed += count
            }
        } finally {
            buffer.fill(0)
        }
    }
}

private fun objectSchema(properties: LinkedHashMap<String, JSONObject>): JSONObject =
    JSONObject().apply {
        put("type", "object")
        put(
            "properties",
            JSONObject().apply {
                properties.forEach { (name, schema) -> put(name, schema) }
            },
        )
        put("required", JSONArray(properties.keys.toList()))
        put("additionalProperties", false)
    }

private fun arraySchema(items: JSONObject): JSONObject =
    JSONObject().put("type", "array").put("items", items)

private fun stringSchema(): JSONObject = JSONObject().put("type", "string")

private fun JSONObject.toStringKeyMap(): MutableMap<String, Any?> {
    val result = linkedMapOf<String, Any?>()
    val keys = keys()
    while (keys.hasNext()) {
        val key = keys.next()
        result[key] = get(key).toKotlinJsonValue()
    }
    return result
}

private fun Any?.toKotlinJsonValue(): Any? = when (this) {
    JSONObject.NULL -> null
    is JSONObject -> toStringKeyMap()
    is JSONArray -> (0 until length()).map { index -> get(index).toKotlinJsonValue() }
    else -> this
}

private fun OutputStream.writeUtf8(value: String) {
    write(value.toByteArray(Charsets.UTF_8))
}

internal class StreamingBase64OutputStream(
    private val output: OutputStream,
) : OutputStream() {
    private val carry = ByteArray(3)
    private var carryLength = 0
    private val encoded = ByteArray(16 * 1024)
    private var closed = false

    override fun write(value: Int) {
        val single = byteArrayOf(value.toByte())
        try {
            write(single, 0, 1)
        } finally {
            single.fill(0)
        }
    }

    override fun write(buffer: ByteArray, offset: Int, length: Int) {
        check(!closed)
        require(offset >= 0 && length >= 0 && length <= buffer.size - offset)
        var sourceOffset = offset
        val sourceEnd = offset + length

        if (carryLength > 0) {
            while (carryLength < 3 && sourceOffset < sourceEnd) {
                carry[carryLength++] = buffer[sourceOffset++]
            }
            if (carryLength == 3) {
                encodeTriplet(carry, 0, encoded, 0)
                output.write(encoded, 0, 4)
                carry.fill(0)
                carryLength = 0
            }
        }

        while (sourceEnd - sourceOffset >= 3) {
            var encodedLength = 0
            while (sourceEnd - sourceOffset >= 3 && encodedLength <= encoded.size - 4) {
                encodeTriplet(buffer, sourceOffset, encoded, encodedLength)
                sourceOffset += 3
                encodedLength += 4
            }
            output.write(encoded, 0, encodedLength)
            encoded.fill(0, 0, encodedLength)
        }

        while (sourceOffset < sourceEnd) {
            carry[carryLength++] = buffer[sourceOffset++]
        }
    }

    override fun flush() {
        check(!closed)
        output.flush()
    }

    override fun close() {
        if (closed) return
        try {
            if (carryLength > 0) {
                val first = carry[0].toInt() and 0xFF
                val second = if (carryLength == 2) carry[1].toInt() and 0xFF else 0
                encoded[0] = BASE64_ALPHABET[first ushr 2]
                encoded[1] = BASE64_ALPHABET[((first and 0x03) shl 4) or (second ushr 4)]
                encoded[2] = if (carryLength == 2) {
                    BASE64_ALPHABET[(second and 0x0F) shl 2]
                } else {
                    '='.code.toByte()
                }
                encoded[3] = '='.code.toByte()
                output.write(encoded, 0, 4)
            }
            output.flush()
        } finally {
            carry.fill(0)
            encoded.fill(0)
            carryLength = 0
            closed = true
        }
    }

    private fun encodeTriplet(
        source: ByteArray,
        sourceOffset: Int,
        destination: ByteArray,
        destinationOffset: Int,
    ) {
        val first = source[sourceOffset].toInt() and 0xFF
        val second = source[sourceOffset + 1].toInt() and 0xFF
        val third = source[sourceOffset + 2].toInt() and 0xFF
        destination[destinationOffset] = BASE64_ALPHABET[first ushr 2]
        destination[destinationOffset + 1] =
            BASE64_ALPHABET[((first and 0x03) shl 4) or (second ushr 4)]
        destination[destinationOffset + 2] =
            BASE64_ALPHABET[((second and 0x0F) shl 2) or (third ushr 6)]
        destination[destinationOffset + 3] = BASE64_ALPHABET[third and 0x3F]
    }

    companion object {
        private val BASE64_ALPHABET =
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
                .toByteArray(Charsets.US_ASCII)
    }
}

private fun invalidResponse(): Nothing = throw NativeAppearanceModelFailure(
    NativeAppearanceModelFailureCode.INVALID_RESPONSE,
)
