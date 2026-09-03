package com.personalos.app.model

import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import com.personalos.app.security.NativeModelMediaAccess
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

internal class NativeAppearanceModelChannel(
    activity: FragmentActivity,
    mediaAccess: NativeModelMediaAccess,
    private val adapter: NativeAppearanceModelAdapter? = null,
    private val credentialPrompt: NativeModelCredentialPrompt? = null,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "personal_os/internal/appearance_model"
        private const val METHOD_ANALYZE = "analyzeAppearance"
        private const val METHOD_CAPABILITIES = "inspectCapabilities"
        private const val METHOD_CONFIGURE_CREDENTIAL = "configureRuntimeCredential"
        private const val METHOD_CLEAR_CREDENTIAL = "clearRuntimeCredential"
    }

    private val mainExecutor: Executor = ContextCompat.getMainExecutor(activity)
    private val modelExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val coordinator = adapter?.let {
        NativeAppearanceModelCoordinator(mediaAccess, it, it.processingBoundary)
    }
    private val disposed = AtomicBoolean(false)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed.get()) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        if (call.method == METHOD_CAPABILITIES) {
            result.success(nativeModelCapabilities(adapter))
            return
        }
        if (call.method == METHOD_CONFIGURE_CREDENTIAL) {
            configureCredential(result)
            return
        }
        if (call.method == METHOD_CLEAR_CREDENTIAL) {
            clearCredential(result)
            return
        }
        val activeCoordinator = coordinator
        val activeAdapter = adapter
        if (disposed.get() ||
            call.method != METHOD_ANALYZE ||
            activeCoordinator == null ||
            activeAdapter == null ||
            (activeAdapter.processingBoundary ==
                NativeModelProcessingBoundary.EXTERNAL_PROCESSOR &&
                !activeAdapter.runtimeCredentialReady)
        ) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        val request = try {
            parseRequest(call.arguments)
        } catch (_: Throwable) {
            fail(result, NativeAppearanceModelFailureCode.INVALID_REQUEST)
            return
        }
        try {
            modelExecutor.execute {
                try {
                    val value = activeCoordinator.analyze(request)
                    deliver(result) { result.success(value.toWireValue()) }
                } catch (failure: NativeAppearanceModelFailure) {
                    deliver(result) { fail(result, failure.failureCode) }
                } catch (_: Throwable) {
                    deliver(result) {
                        fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
                    }
                }
            }
        } catch (_: Throwable) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
        }
    }

    fun dispose() {
        if (disposed.compareAndSet(false, true)) {
            credentialPrompt?.dispose()
            modelExecutor.shutdownNow()
            adapter?.dispose()
        }
    }

    fun revokeRuntimeCredential() {
        credentialPrompt?.dispose()
        try {
            (adapter as? RuntimeCredentialNativeAppearanceModelAdapter)
                ?.clearRuntimeCredential()
        } catch (_: Throwable) {
            // Native session invalidation is fail-closed and has no caller.
        }
    }

    private fun configureCredential(result: MethodChannel.Result) {
        val configurable = adapter as? RuntimeCredentialNativeAppearanceModelAdapter
        val prompt = credentialPrompt
        if (configurable == null ||
            prompt == null ||
            configurable.processingBoundary !=
                NativeModelProcessingBoundary.EXTERNAL_PROCESSOR
        ) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        try {
            prompt.requestCredential credentialCallback@ { ownedCredential ->
                if (disposed.get()) {
                    ownedCredential?.fill('\u0000')
                    return@credentialCallback
                }
                if (ownedCredential == null) {
                    result.success(false)
                    return@credentialCallback
                }
                try {
                    configurable.installRuntimeCredential(ownedCredential)
                } catch (failure: NativeAppearanceModelFailure) {
                    ownedCredential.fill('\u0000')
                    fail(result, failure.failureCode)
                    return@credentialCallback
                } catch (_: IllegalArgumentException) {
                    ownedCredential.fill('\u0000')
                    fail(result, NativeAppearanceModelFailureCode.INVALID_REQUEST)
                    return@credentialCallback
                } catch (_: Throwable) {
                    ownedCredential.fill('\u0000')
                    fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
                    return@credentialCallback
                }
                try {
                    result.success(true)
                } catch (_: Throwable) {
                    // Flutter teardown raced delivery. Revoke the credential
                    // whose successful installation could not be acknowledged.
                    try {
                        configurable.clearRuntimeCredential()
                    } catch (_: Throwable) {
                        // The channel is gone; no details can be reported.
                    }
                }
            }
        } catch (_: Throwable) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
        }
    }

    private fun clearCredential(result: MethodChannel.Result) {
        val configurable = adapter as? RuntimeCredentialNativeAppearanceModelAdapter
        if (configurable == null) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        try {
            credentialPrompt?.dispose()
            configurable.clearRuntimeCredential()
            result.success(null)
        } catch (_: Throwable) {
            fail(result, NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE)
        }
    }

    private fun deliver(result: MethodChannel.Result, callback: () -> Unit) {
        if (disposed.get()) {
            return
        }
        try {
            mainExecutor.execute {
                if (!disposed.get()) callback()
            }
        } catch (_: Throwable) {
            // Flutter teardown may race delivery. No adapter details are logged.
        }
    }

    private fun fail(
        result: MethodChannel.Result,
        code: NativeAppearanceModelFailureCode,
    ) {
        result.error(code.wireValue, null, null)
    }
}

internal fun nativeModelCapabilities(
    adapter: NativeAppearanceModelAdapter?,
): Map<String, Any> = mapOf(
    "configured" to (adapter != null),
    "supportedBoundaries" to if (adapter == null) {
        emptyList<String>()
    } else {
        listOf(adapter.processingBoundary.wireValue)
    },
    "runtimeCredentialReady" to (adapter?.runtimeCredentialReady ?: false),
)

private fun parseRequest(arguments: Any?): NativeAppearanceModelRequest {
    val values = arguments as? Map<*, *> ?: throw IllegalArgumentException()
    return NativeAppearanceModelRequest(
        blobRef = values.requiredString("imageRef"),
        observationContext = values.requiredString("observationContext"),
        locale = values.requiredString("locale"),
        promptVersion = values.requiredString("promptVersion"),
        processingBoundary = when (values.requiredString("processingBoundary")) {
            NativeModelProcessingBoundary.ON_DEVICE.wireValue ->
                NativeModelProcessingBoundary.ON_DEVICE
            NativeModelProcessingBoundary.EXTERNAL_PROCESSOR.wireValue ->
                NativeModelProcessingBoundary.EXTERNAL_PROCESSOR
            else -> throw IllegalArgumentException()
        },
    )
}

private fun Map<*, *>.requiredString(key: String): String =
    this[key] as? String ?: throw IllegalArgumentException()

private fun NativeAppearanceModelResult.toWireValue(): Map<String, Any> = mapOf(
    "findings" to findings.map { finding ->
        mapOf(
            "dimension" to finding.dimension,
            "statement" to finding.statement,
            "confidence" to finding.confidence,
            "kind" to finding.kind,
        )
    },
    "actions" to actions.map { action ->
        mapOf(
            "title" to action.title,
            "rationale" to action.rationale,
            "dayOffset" to action.dayOffset,
            "requiresHumanConfirmation" to action.requiresHumanConfirmation,
        )
    },
    "modelTraceRef" to modelTraceRef,
    "modelId" to modelId,
    "promptVersion" to promptVersion,
    "inputSummaryRef" to inputSummaryRef,
    "risks" to risks.map { risk ->
        mapOf("code" to risk.code, "statement" to risk.statement)
    },
    "humanConfirmations" to humanConfirmations.map { confirmation ->
        mapOf("code" to confirmation.code, "prompt" to confirmation.prompt)
    },
)
