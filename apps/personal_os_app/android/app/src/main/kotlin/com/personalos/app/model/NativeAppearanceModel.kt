package com.personalos.app.model

import com.personalos.app.security.NativeModelMediaAccess
import com.personalos.app.security.NativeVaultFailure
import java.io.InputStream

internal enum class NativeAppearanceModelFailureCode(val wireValue: String) {
    INVALID_REQUEST("model.invalid_request"),
    VAULT_UNAVAILABLE("model.vault_unavailable"),
    ADAPTER_UNAVAILABLE("model.adapter_unavailable"),
    INVALID_RESPONSE("model.invalid_response"),
    MEDIA_TOO_LARGE("model.media_too_large"),
    MEDIA_TRANSCODE_UNAVAILABLE("model.media_transcode_unavailable"),
}

internal class NativeAppearanceModelFailure(
    val failureCode: NativeAppearanceModelFailureCode,
) : Exception()

internal enum class NativeModelProcessingBoundary(val wireValue: String) {
    ON_DEVICE("onDevice"),
    EXTERNAL_PROCESSOR("externalProcessor"),
}

internal data class NativeAppearanceModelRequest(
    val blobRef: String,
    val observationContext: String,
    val locale: String,
    val promptVersion: String,
    val processingBoundary: NativeModelProcessingBoundary,
) {
    init {
        require(blobRef.matches(Regex("blob://[A-Za-z0-9-]{16,128}")))
        requireBounded(observationContext, 2_048)
        require(locale.matches(Regex("[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?")))
        require(promptVersion.matches(Regex("[a-z][a-z0-9._-]{0,63}")))
    }
}

internal data class NativeAppearanceFinding(
    val dimension: String,
    val statement: String,
    val confidence: Double,
    val kind: String,
) {
    init {
        requireStableCode(dimension)
        requireBounded(statement, 2_048)
        require(confidence in 0.0..1.0)
        require(kind == "observableFact" || kind == "uncertainInference")
    }
}

internal data class NativeAppearanceAction(
    val title: String,
    val rationale: String,
    val dayOffset: Int,
    val requiresHumanConfirmation: Boolean,
) {
    init {
        requireBounded(title, 256)
        requireBounded(rationale, 2_048)
        require(dayOffset in 0..6)
    }
}

internal data class NativeAppearanceModelResult(
    val findings: List<NativeAppearanceFinding>,
    val actions: List<NativeAppearanceAction>,
    val modelTraceRef: String,
    val modelId: String,
    val promptVersion: String,
    val inputSummaryRef: String,
    val risks: List<NativeAppearanceRisk>,
    val humanConfirmations: List<NativeAppearanceHumanConfirmation>,
) {
    init {
        require(findings.isNotEmpty())
        require(findings.size <= 32)
        require(actions.isNotEmpty())
        require(actions.size <= 14)
        require(risks.size <= 32)
        require(humanConfirmations.size <= 32)
        requireBounded(modelTraceRef, 256)
        requireBounded(modelId, 128)
        require(promptVersion.matches(Regex("[a-z][a-z0-9._-]{0,63}")))
        requireBounded(inputSummaryRef, 256)
        require(risks.map { it.code }.distinct().size == risks.size)
        require(humanConfirmations.map { it.code }.distinct().size == humanConfirmations.size)
    }
}

internal data class NativeAppearanceRisk(
    val code: String,
    val statement: String,
) {
    init {
        requireStableCode(code)
        requireBounded(statement, 2_048)
    }
}

internal data class NativeAppearanceHumanConfirmation(
    val code: String,
    val prompt: String,
) {
    init {
        requireStableCode(code)
        requireBounded(prompt, 2_048)
    }
}

internal fun interface NativeAppearanceModelTransport {
    fun analyze(
        request: NativeAppearanceModelRequest,
        media: InputStream,
    ): NativeAppearanceModelResult
}

internal interface NativeAppearanceModelAdapter : NativeAppearanceModelTransport {
    val processingBoundary: NativeModelProcessingBoundary
    val runtimeCredentialReady: Boolean

    fun validateRequest(request: NativeAppearanceModelRequest) = Unit

    fun dispose() = Unit
}

internal interface RuntimeCredentialNativeAppearanceModelAdapter :
    NativeAppearanceModelAdapter {
    fun installRuntimeCredential(ownedCredential: CharArray)
    fun clearRuntimeCredential()
}

internal class NativeAppearanceModelCoordinator(
    private val mediaAccess: NativeModelMediaAccess,
    private val transport: NativeAppearanceModelTransport,
    private val transportBoundary: NativeModelProcessingBoundary =
        NativeModelProcessingBoundary.ON_DEVICE,
) {
    fun analyze(request: NativeAppearanceModelRequest): NativeAppearanceModelResult {
        if (request.processingBoundary != transportBoundary) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.INVALID_REQUEST,
            )
        }
        if (transport is NativeAppearanceModelAdapter &&
            transport.processingBoundary ==
                NativeModelProcessingBoundary.EXTERNAL_PROCESSOR &&
            !transport.runtimeCredentialReady
        ) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
        if (transport is NativeAppearanceModelAdapter) {
            try {
                transport.validateRequest(request)
            } catch (failure: NativeAppearanceModelFailure) {
                throw failure
            } catch (_: Throwable) {
                throw NativeAppearanceModelFailure(
                    NativeAppearanceModelFailureCode.INVALID_REQUEST,
                )
            }
        }
        return try {
            val result = mediaAccess.useBlobForModel(request.blobRef) { media ->
                try {
                    transport.analyze(request, media)
                } catch (failure: NativeAppearanceModelFailure) {
                    throw failure
                } catch (_: IllegalArgumentException) {
                    throw NativeAppearanceModelFailure(
                        NativeAppearanceModelFailureCode.INVALID_RESPONSE,
                    )
                } catch (_: Throwable) {
                    throw NativeAppearanceModelFailure(
                        NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
                    )
                }
            }
            if (result.promptVersion != request.promptVersion) {
                throw NativeAppearanceModelFailure(
                    NativeAppearanceModelFailureCode.INVALID_RESPONSE,
                )
            }
            result
        } catch (failure: NativeAppearanceModelFailure) {
            throw failure
        } catch (_: NativeVaultFailure) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.VAULT_UNAVAILABLE,
            )
        } catch (_: Throwable) {
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
    }
}

private fun requireStableCode(value: String) {
    require(value.matches(Regex("[a-z][a-z0-9_]{0,63}")))
}

private fun requireBounded(value: String, maximumLength: Int) {
    require(value.isNotBlank())
    require(value == value.trim())
    require(value.length <= maximumLength)
}
