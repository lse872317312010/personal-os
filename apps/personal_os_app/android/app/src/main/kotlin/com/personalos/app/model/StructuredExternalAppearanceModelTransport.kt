package com.personalos.app.model

import com.personalos.app.security.NativeExactLengthMediaStream
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream

/**
 * Provider-specific network boundary.
 *
 * Implementations must synchronously consume [media], must not retain the
 * stream or [credential], and must normalize the provider response to the
 * bounded schema consumed below. Raw HTTP bodies and provider errors remain
 * inside the implementation.
 */
internal fun interface ExternalAppearanceModelClient {
    fun execute(
        request: ExternalAppearanceModelRequest,
        media: InputStream,
        credential: CharArray,
    ): Map<String, Any?>

    /** Best-effort synchronous cancellation; must not make future calls unusable. */
    fun cancelInFlight() = Unit
}

internal data class ExternalAppearanceModelRequest(
    val observationContext: String,
    val locale: String,
    val promptVersion: String,
    val mediaType: String,
    val promptContract: ExternalAppearancePromptContract,
    val timeoutMillis: Int,
) {
    init {
        require(promptVersion == promptContract.version)
        require(mediaType in SUPPORTED_EXTERNAL_MEDIA_TYPES)
        require(timeoutMillis in 1..120_000)
    }
}

internal data class ExternalAppearancePromptContract(
    val version: String,
    val responseSchemaVersion: String,
    val systemInstructions: String,
    val maximumFindings: Int,
    val maximumActions: Int,
    val maximumRisks: Int,
    val maximumHumanConfirmations: Int,
) {
    init {
        require(version.matches(Regex("[a-z][a-z0-9._-]{0,63}")))
        require(responseSchemaVersion.matches(Regex("[a-z][a-z0-9._-]{0,63}")))
        require(systemInstructions.isNotBlank())
        require(systemInstructions == systemInstructions.trim())
        require(systemInstructions.length <= 4_096)
        require(maximumFindings in 1..32)
        require(maximumActions in 1..14)
        require(maximumRisks in 0..32)
        require(maximumHumanConfirmations in 0..32)
    }
}

private val SUPPORTED_EXTERNAL_MEDIA_TYPES = setOf(
    "image/jpeg",
    "image/png",
    "image/webp",
    "image/heif",
    "image/avif",
)

private val APPEARANCE_V1_PROMPT = ExternalAppearancePromptContract(
    version = "appearance-v1",
    responseSchemaVersion = "appearance-result-v1",
    systemInstructions = """
        Analyze only visible presentation details in the supplied image.
        Separate observable facts from uncertain inferences.
        Do not infer identity, protected traits, health diagnoses, or intent.
        Return bounded seven-day actions with dayOffset from 0 through 6.
        Flag uncertainty, risks, and items requiring human confirmation.
        Return only the requested structured response schema.
    """.trimIndent(),
    maximumFindings = 32,
    maximumActions = 14,
    maximumRisks = 32,
    maximumHumanConfirmations = 32,
)

/** Provider-neutral external transport with strict request and response bounds. */
internal class StructuredExternalAppearanceModelTransport(
    credentials: NativeModelCredentialProvider,
    private val client: ExternalAppearanceModelClient,
    private val maximumMediaBytes: Long = DEFAULT_MAXIMUM_MEDIA_BYTES,
) : CredentialedNativeAppearanceModelTransport(credentials) {
    companion object {
        const val DEFAULT_MAXIMUM_MEDIA_BYTES: Long = 15L * 1024L * 1024L
        const val PROVIDER_TIMEOUT_MILLIS: Int = 45_000
    }

    init {
        require(maximumMediaBytes in 1..DEFAULT_MAXIMUM_MEDIA_BYTES)
    }

    override fun validateRequest(request: NativeAppearanceModelRequest) {
        if (request.processingBoundary != NativeModelProcessingBoundary.EXTERNAL_PROCESSOR ||
            request.promptVersion != APPEARANCE_V1_PROMPT.version
        ) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.INVALID_REQUEST,
            )
        }
    }

    override fun analyzeWithCredential(
        request: NativeAppearanceModelRequest,
        media: InputStream,
        credential: CharArray,
    ): NativeAppearanceModelResult {
        validateRequest(request)
        val exactLength = (media as? NativeExactLengthMediaStream)?.exactLengthBytes
        if (exactLength != null && exactLength > maximumMediaBytes) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE,
            )
        }
        val boundedMedia = CompleteBoundedInputStream(media, maximumMediaBytes)
        val prefix = boundedMedia.readPrefix(16)
        try {
            val mediaType = supportedImageMediaType(prefix)
                ?: throw NativeAppearanceModelFailure(
                    NativeAppearanceModelFailureCode.INVALID_REQUEST,
                )
            val replay = PrefixReplayInputStream(prefix, boundedMedia)
            val response = client.execute(
                ExternalAppearanceModelRequest(
                    observationContext = request.observationContext,
                    locale = request.locale,
                    promptVersion = request.promptVersion,
                    mediaType = mediaType,
                    promptContract = APPEARANCE_V1_PROMPT,
                    timeoutMillis = PROVIDER_TIMEOUT_MILLIS,
                ),
                replay,
                credential,
            )
            replay.requirePrefixConsumed()
            boundedMedia.requireCompletelyConsumed()
            return parseExternalAppearanceModelResult(
                response,
                APPEARANCE_V1_PROMPT,
            )
        } finally {
            prefix.fill(0)
        }
    }

    override fun cancelTransportWork() {
        client.cancelInFlight()
    }
}

private fun InputStream.readPrefix(maximumLength: Int): ByteArray {
    val scratch = ByteArray(maximumLength)
    try {
        var length = 0
        while (length < scratch.size) {
            val count = read(scratch, length, scratch.size - length)
            if (count == -1) break
            length += count
        }
        return scratch.copyOf(length)
    } finally {
        scratch.fill(0)
    }
}

private fun supportedImageMediaType(prefix: ByteArray): String? = when {
    prefix.startsWith(0xFF, 0xD8, 0xFF) -> "image/jpeg"
    prefix.startsWith(0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) ->
        "image/png"
    prefix.matchesAscii(0, "RIFF") && prefix.matchesAscii(8, "WEBP") ->
        "image/webp"
    prefix.matchesAscii(4, "ftyp") &&
        (prefix.matchesAscii(8, "avif") || prefix.matchesAscii(8, "avis")) ->
        "image/avif"
    prefix.matchesAscii(4, "ftyp") && listOf(
        "heic",
        "heix",
        "hevc",
        "hevx",
        "mif1",
        "msf1",
    ).any { brand -> prefix.matchesAscii(8, brand) } -> "image/heif"
    else -> null
}

private fun ByteArray.startsWith(vararg expected: Int): Boolean =
    size >= expected.size && expected.indices.all { index ->
        this[index].toInt() and 0xFF == expected[index]
    }

private fun ByteArray.matchesAscii(offset: Int, value: String): Boolean =
    offset >= 0 && size - offset >= value.length && value.indices.all { index ->
        this[offset + index].toInt() == value[index].code
    }

private class PrefixReplayInputStream(
    private val prefix: ByteArray,
    source: InputStream,
) : FilterInputStream(source) {
    private var prefixOffset = 0

    override fun read(): Int {
        if (prefixOffset < prefix.size) {
            return prefix[prefixOffset++].toInt() and 0xFF
        }
        return super.read()
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        require(offset >= 0 && length >= 0 && length <= buffer.size - offset)
        if (length == 0) return 0
        if (prefixOffset >= prefix.size) return super.read(buffer, offset, length)
        val count = minOf(length, prefix.size - prefixOffset)
        prefix.copyInto(buffer, offset, prefixOffset, prefixOffset + count)
        prefixOffset += count
        return count
    }

    override fun skip(byteCount: Long): Long {
        if (byteCount == 0L) return 0
        throw NativeAppearanceModelFailure(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
        )
    }

    override fun markSupported(): Boolean = false

    override fun mark(readLimit: Int) = Unit

    @Throws(IOException::class)
    override fun reset() {
        throw IOException()
    }

    fun requirePrefixConsumed() {
        if (prefixOffset != prefix.size) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
    }
}

private class CompleteBoundedInputStream(
    source: InputStream,
    private val maximumBytes: Long,
) : FilterInputStream(source) {
    private var consumed = 0L
    private var exhausted = false

    override fun read(): Int {
        if (exhausted) return -1
        if (consumed == maximumBytes) {
            val probe = super.read()
            if (probe == -1) {
                exhausted = true
                return -1
            }
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.MEDIA_TOO_LARGE,
            )
        }
        val value = super.read()
        if (value == -1) {
            exhausted = true
        } else {
            consumed++
        }
        return value
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        require(offset >= 0 && length >= 0 && length <= buffer.size - offset)
        if (length == 0) return 0
        if (exhausted) return -1
        val remaining = maximumBytes - consumed
        if (remaining == 0L) return read()
        val boundedLength = minOf(length.toLong(), remaining).toInt()
        val count = super.read(buffer, offset, boundedLength)
        if (count == -1) {
            exhausted = true
        } else {
            consumed += count
        }
        return count
    }

    override fun skip(byteCount: Long): Long {
        if (byteCount == 0L) return 0
        throw NativeAppearanceModelFailure(
            NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
        )
    }

    override fun markSupported(): Boolean = false

    override fun mark(readLimit: Int) = Unit

    @Throws(IOException::class)
    override fun reset() {
        throw IOException()
    }

    fun requireCompletelyConsumed() {
        if (!exhausted && read() != -1) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
        if (consumed == 0L) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.INVALID_REQUEST,
            )
        }
    }
}

internal fun parseExternalAppearanceModelResult(
    value: Map<String, Any?>,
    promptContract: ExternalAppearancePromptContract = APPEARANCE_V1_PROMPT,
): NativeAppearanceModelResult {
    value.requireExactKeys(
        "findings",
        "actions",
        "modelTraceRef",
        "modelId",
        "promptVersion",
        "inputSummaryRef",
        "risks",
        "humanConfirmations",
    )
    return NativeAppearanceModelResult(
        findings = value.requiredList(
            "findings",
            promptContract.maximumFindings,
        ).map { item ->
            val finding = item.requiredMap()
            finding.requireExactKeys("dimension", "statement", "confidence", "kind")
            NativeAppearanceFinding(
                dimension = finding.requiredString("dimension"),
                statement = finding.requiredString("statement"),
                confidence = finding.requiredDouble("confidence"),
                kind = finding.requiredString("kind"),
            )
        },
        actions = value.requiredList(
            "actions",
            promptContract.maximumActions,
        ).map { item ->
            val action = item.requiredMap()
            action.requireExactKeys(
                "title",
                "rationale",
                "dayOffset",
                "requiresHumanConfirmation",
            )
            NativeAppearanceAction(
                title = action.requiredString("title"),
                rationale = action.requiredString("rationale"),
                dayOffset = action.requiredInt("dayOffset"),
                requiresHumanConfirmation =
                    action.requiredBoolean("requiresHumanConfirmation"),
            )
        },
        modelTraceRef = value.requiredString("modelTraceRef"),
        modelId = value.requiredString("modelId"),
        promptVersion = value.requiredString("promptVersion"),
        inputSummaryRef = value.requiredString("inputSummaryRef"),
        risks = value.requiredList(
            "risks",
            promptContract.maximumRisks,
        ).map { item ->
            val risk = item.requiredMap()
            risk.requireExactKeys("code", "statement")
            NativeAppearanceRisk(
                code = risk.requiredString("code"),
                statement = risk.requiredString("statement"),
            )
        },
        humanConfirmations = value.requiredList(
            "humanConfirmations",
            promptContract.maximumHumanConfirmations,
        ).map { item ->
            val confirmation = item.requiredMap()
            confirmation.requireExactKeys("code", "prompt")
            NativeAppearanceHumanConfirmation(
                code = confirmation.requiredString("code"),
                prompt = confirmation.requiredString("prompt"),
            )
        },
    )
}

private fun Map<String, Any?>.requireExactKeys(vararg expected: String) {
    require(keys == expected.toSet())
}

private fun Map<String, Any?>.requiredString(key: String): String =
    this[key] as? String ?: throw IllegalArgumentException()

private fun Map<String, Any?>.requiredBoolean(key: String): Boolean =
    this[key] as? Boolean ?: throw IllegalArgumentException()

private fun Map<String, Any?>.requiredInt(key: String): Int =
    this[key] as? Int ?: throw IllegalArgumentException()

private fun Map<String, Any?>.requiredDouble(key: String): Double =
    (this[key] as? Number)?.toDouble() ?: throw IllegalArgumentException()

private fun Map<String, Any?>.requiredList(key: String, maximumSize: Int): List<*> {
    val list = this[key] as? List<*> ?: throw IllegalArgumentException()
    require(list.size <= maximumSize)
    return list
}

private fun Any?.requiredMap(): Map<String, Any?> {
    val map = this as? Map<*, *> ?: throw IllegalArgumentException()
    require(map.keys.all { it is String })
    @Suppress("UNCHECKED_CAST")
    return map as Map<String, Any?>
}
