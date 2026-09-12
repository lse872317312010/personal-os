package com.personalos.app.model

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.URL
import java.net.URLConnection
import java.net.URLStreamHandler
import java.security.cert.Certificate
import javax.net.ssl.HttpsURLConnection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class OpenAiResponsesAppearanceModelClientTest {
    @Test
    fun executesPinnedHttpsRequestAndParsesCompletedStructuredResponse() {
        lateinit var connection: FakeHttpsURLConnection
        val endpoint = fakeEndpoint { url ->
            FakeHttpsURLConnection(
                url = url,
                responseCodeValue = 200,
                responseBody = completedResponseJson().toByteArray(Charsets.UTF_8),
                contentTypeValue = "application/json; charset=utf-8",
            ).also { connection = it }
        }
        val client = OpenAiResponsesAppearanceModelClient(
            model = "gpt-5.4-mini",
            endpoint = endpoint,
        )

        val result = client.execute(
            request(),
            ByteArrayInputStream("abc".toByteArray(Charsets.US_ASCII)),
            "sk-test-only".toCharArray(),
        )

        assertEquals("resp_test_123", result["modelTraceRef"])
        assertEquals("gpt-5.4-mini", result["modelId"])
        assertEquals("appearance-v1", result["promptVersion"])
        assertEquals(
            "openai://response/resp_test_123/input",
            result["inputSummaryRef"],
        )
        assertEquals("Bearer sk-test-only", connection.headers["Authorization"])
        assertEquals("application/json", connection.headers["Accept"])
        assertEquals("identity", connection.headers["Accept-Encoding"])
        assertEquals("application/json", connection.headers["Content-Type"])
        assertFalse(connection.instanceFollowRedirects)
        assertFalse(connection.useCaches)
        assertEquals("POST", connection.requestMethod)
        assertEquals(12_345, connection.connectTimeout)
        assertEquals(12_345, connection.readTimeout)
        assertTrue(connection.disconnected)

        val body = connection.requestBody.toString(Charsets.UTF_8.name())
        assertTrue(body.contains("\"model\":\"gpt-5.4-mini\""))
        assertTrue(body.contains("\"store\":false"))
        assertTrue(body.contains("\"strict\":true"))
        assertTrue(body.contains("\"image_url\":\"data:image/jpeg;base64,YWJj\""))
        assertTrue(body.contains("\"detail\":\"high\""))
        assertTrue(body.contains("Observation context: test context"))
    }

    @Test
    fun mapsNonSuccessHttpStatusToRedactedAdapterFailure() {
        lateinit var connection: FakeHttpsURLConnection
        val endpoint = fakeEndpoint { url ->
            FakeHttpsURLConnection(
                url = url,
                responseCodeValue = 401,
                responseBody = "{\"error\":\"provider detail must not escape\"}"
                    .toByteArray(Charsets.UTF_8),
                contentTypeValue = "application/json",
            ).also { connection = it }
        }
        val client = OpenAiResponsesAppearanceModelClient(
            model = "gpt-5.4-mini",
            endpoint = endpoint,
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            client.execute(
                request(),
                ByteArrayInputStream(byteArrayOf(1, 2, 3)),
                "sk-test-only".toCharArray(),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            failure.failureCode,
        )
        assertTrue(connection.errorStreamRequested)
        assertTrue(connection.disconnected)
    }

    @Test
    fun rejectsNonJsonSuccessResponseAsInvalidResponse() {
        lateinit var connection: FakeHttpsURLConnection
        val endpoint = fakeEndpoint { url ->
            FakeHttpsURLConnection(
                url = url,
                responseCodeValue = 200,
                responseBody = "not-json".toByteArray(Charsets.UTF_8),
                contentTypeValue = "text/plain",
            ).also { connection = it }
        }
        val client = OpenAiResponsesAppearanceModelClient(
            model = "gpt-5.4-mini",
            endpoint = endpoint,
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            client.execute(
                request(),
                ByteArrayInputStream(byteArrayOf(1, 2, 3)),
                "sk-test-only".toCharArray(),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_RESPONSE,
            failure.failureCode,
        )
        assertTrue(connection.disconnected)
    }

    @Test
    fun rejectsUnsupportedProviderMediaBeforeOpeningNetworkConnection() {
        var opened = false
        val endpoint = fakeEndpoint { url ->
            opened = true
            FakeHttpsURLConnection(
                url = url,
                responseCodeValue = 200,
                responseBody = completedResponseJson().toByteArray(Charsets.UTF_8),
                contentTypeValue = "application/json",
            )
        }
        val client = OpenAiResponsesAppearanceModelClient(
            model = "gpt-5.4-mini",
            endpoint = endpoint,
        )

        val failure = assertThrows(NativeAppearanceModelFailure::class.java) {
            client.execute(
                request(mediaType = "image/heif"),
                ByteArrayInputStream(byteArrayOf(1, 2, 3)),
                "sk-test-only".toCharArray(),
            )
        }

        assertEquals(
            NativeAppearanceModelFailureCode.INVALID_REQUEST,
            failure.failureCode,
        )
        assertFalse(opened)
    }

    @Test
    fun cancellationDoesNotPoisonLaterCalls() {
        lateinit var connection: FakeHttpsURLConnection
        val endpoint = fakeEndpoint { url ->
            FakeHttpsURLConnection(
                url = url,
                responseCodeValue = 200,
                responseBody = completedResponseJson().toByteArray(Charsets.UTF_8),
                contentTypeValue = "application/json",
            ).also { connection = it }
        }
        val client = OpenAiResponsesAppearanceModelClient(
            model = "gpt-5.4-mini",
            endpoint = endpoint,
        )

        client.cancelInFlight()
        val result = client.execute(
            request(),
            ByteArrayInputStream(byteArrayOf(1, 2, 3)),
            "sk-test-only".toCharArray(),
        )

        assertEquals("resp_test_123", result["modelTraceRef"])
        assertTrue(connection.disconnected)
    }
}

private fun request(mediaType: String = "image/jpeg") = ExternalAppearanceModelRequest(
    observationContext = "test context",
    locale = "zh-CN",
    promptVersion = "appearance-v1",
    mediaType = mediaType,
    promptContract = ExternalAppearancePromptContract(
        version = "appearance-v1",
        responseSchemaVersion = "appearance-result-v1",
        systemInstructions = "Return only the requested structured response schema.",
        maximumFindings = 32,
        maximumActions = 14,
        maximumRisks = 32,
        maximumHumanConfirmations = 32,
    ),
    timeoutMillis = 12_345,
)

private fun completedResponseJson(): String = """
    {
      "id":"resp_test_123",
      "model":"gpt-5.4-mini",
      "status":"completed",
      "output":[
        {
          "type":"message",
          "role":"assistant",
          "content":[
            {
              "type":"output_text",
              "text":"{\"findings\":[],\"actions\":[],\"risks\":[],\"humanConfirmations\":[]}"
            }
          ]
        }
      ]
    }
""".trimIndent()

private fun fakeEndpoint(
    connectionFactory: (URL) -> HttpsURLConnection,
): URL = URL(
    null,
    "https://api.openai.com/v1/responses",
    object : URLStreamHandler() {
        override fun openConnection(url: URL): URLConnection = connectionFactory(url)
    },
)

private class FakeHttpsURLConnection(
    url: URL,
    private val responseCodeValue: Int,
    private val responseBody: ByteArray,
    private val contentTypeValue: String,
) : HttpsURLConnection(url) {
    val requestBody = ByteArrayOutputStream()
    val headers = linkedMapOf<String, String>()
    var disconnected = false
        private set
    var errorStreamRequested = false
        private set

    override fun setRequestProperty(key: String, value: String) {
        headers[key] = value
        super.setRequestProperty(key, value)
    }

    override fun getOutputStream(): OutputStream = requestBody

    override fun getInputStream(): InputStream = ByteArrayInputStream(responseBody)

    override fun getErrorStream(): InputStream? {
        errorStreamRequested = true
        return if (responseCodeValue >= 400) ByteArrayInputStream(responseBody) else null
    }

    override fun getResponseCode(): Int = responseCodeValue

    override fun getContentType(): String = contentTypeValue

    override fun getContentEncoding(): String? = null

    override fun getContentLengthLong(): Long = responseBody.size.toLong()

    override fun disconnect() {
        disconnected = true
    }

    override fun usingProxy(): Boolean = false

    override fun connect() = Unit

    override fun getCipherSuite(): String = "TLS_FAKE"

    override fun getLocalCertificates(): Array<Certificate>? = null

    override fun getServerCertificates(): Array<Certificate> = emptyArray()
}
