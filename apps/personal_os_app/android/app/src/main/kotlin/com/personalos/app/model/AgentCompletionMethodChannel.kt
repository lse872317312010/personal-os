package com.personalos.app.model

import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Native-only credential and transport boundary for automatic strategy turns.
 * The key stays in this process and is cleared when the Vault session closes.
 */
internal class AgentCompletionMethodChannel(
    activity: FragmentActivity,
    private val client: OpenAiResponsesAgentClient?,
    private val credentialPrompt: NativeModelCredentialPrompt?,
    private val isVaultActive: () -> Boolean,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "personal_os/internal/agent_completion"
        private const val METHOD_CONFIGURE = "configureCredential"
        private const val METHOD_COMPLETE = "complete"
        private const val METHOD_CLEAR = "clearCredential"
    }

    private val mainExecutor: Executor = ContextCompat.getMainExecutor(activity)
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private val credentials = AgentSessionCredentialStore()
    private val disposed = AtomicBoolean(false)
    private val pending = AtomicReference<PendingRequest?>(null)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed.get()) {
            fail(result, AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        when (call.method) {
            METHOD_CONFIGURE -> configureCredential(result)
            METHOD_COMPLETE -> complete(call.arguments, result)
            METHOD_CLEAR -> {
                clearRuntimeCredential()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun clearRuntimeCredential() {
        client?.cancelInFlight()
        credentials.clear()
        val active = pending.getAndSet(null) ?: return
        if (!active.completed.compareAndSet(false, true)) return
        try {
            mainExecutor.execute {
                if (!disposed.get()) {
                    fail(active.result, AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
                }
            }
        } catch (_: Throwable) {
            // Vault invalidation must not depend on a Flutter callback.
        }
    }

    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        credentialPrompt?.dispose()
        client?.cancelInFlight()
        credentials.clear()
        pending.getAndSet(null)?.completed?.set(true)
        executor.shutdownNow()
    }

    private fun configureCredential(result: MethodChannel.Result) {
        if (!vaultIsActive()) {
            fail(result, AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
            return
        }
        val prompt = credentialPrompt
        if (client == null || prompt == null) {
            fail(result, AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        if (pending.get() != null) {
            fail(result, AgentCompletionFailureCode.REQUEST_FAILED)
            return
        }
        try {
            prompt.requestSessionCredential credentialCallback@ { ownedCredential ->
                if (disposed.get()) {
                    ownedCredential?.fill('\u0000')
                    return@credentialCallback
                }
                if (ownedCredential == null) {
                    result.success(false)
                    return@credentialCallback
                }
                try {
                    credentials.install(ownedCredential)
                    result.success(true)
                } catch (_: IllegalArgumentException) {
                    ownedCredential.fill('\u0000')
                    fail(result, AgentCompletionFailureCode.INVALID_REQUEST)
                } catch (_: Throwable) {
                    ownedCredential.fill('\u0000')
                    fail(result, AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
                }
            }
        } catch (_: Throwable) {
            fail(result, AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
        }
    }

    private fun complete(arguments: Any?, result: MethodChannel.Result) {
        if (!vaultIsActive()) {
            fail(result, AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
            return
        }
        val activeClient = client
        if (activeClient == null) {
            fail(result, AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
            return
        }
        if (!credentials.isReady) {
            fail(result, AgentCompletionFailureCode.CREDENTIAL_REQUIRED)
            return
        }
        val prompt = try {
            parsePrompt(arguments)
        } catch (_: Throwable) {
            fail(result, AgentCompletionFailureCode.INVALID_REQUEST)
            return
        }
        val request = PendingRequest(result)
        if (!pending.compareAndSet(null, request)) {
            fail(result, AgentCompletionFailureCode.REQUEST_FAILED)
            return
        }
        val expectedEpoch = activeClient.currentEpoch()
        try {
            executor.execute {
                try {
                    val output = credentials.useCredential { credential ->
                        activeClient.complete(prompt, credential, expectedEpoch)
                    }
                    deliver(request) { request.result.success(output) }
                } catch (failure: AgentCompletionFailure) {
                    deliver(request) { fail(request.result, failure.failureCode) }
                } catch (_: Throwable) {
                    deliver(request) {
                        fail(request.result, AgentCompletionFailureCode.REQUEST_FAILED)
                    }
                }
            }
        } catch (_: Throwable) {
            pending.compareAndSet(request, null)
            fail(result, AgentCompletionFailureCode.ADAPTER_UNAVAILABLE)
        }
    }

    private fun deliver(request: PendingRequest, callback: () -> Unit) {
        if (!pending.compareAndSet(request, null) ||
            !request.completed.compareAndSet(false, true) ||
            disposed.get()
        ) {
            return
        }
        try {
            mainExecutor.execute {
                if (!disposed.get()) callback()
            }
        } catch (_: Throwable) {
            // Flutter teardown may race delivery; do not log prompt or output.
        }
    }

    private fun fail(
        result: MethodChannel.Result,
        code: AgentCompletionFailureCode,
    ) {
        result.error(code.wireValue, null, null)
    }

    private fun vaultIsActive(): Boolean = try {
        isVaultActive()
    } catch (_: Throwable) {
        false
    }

    private class PendingRequest(val result: MethodChannel.Result) {
        val completed = AtomicBoolean(false)
    }
}

private fun parsePrompt(arguments: Any?): String {
    val values = arguments as? Map<*, *> ?: throw IllegalArgumentException()
    val prompt = values["prompt"] as? String ?: throw IllegalArgumentException()
    if (prompt.isBlank() ||
        prompt.length > AgentCompletionMaximums.MAXIMUM_PROMPT_LENGTH ||
        containsD4CredentialMaterial(prompt)
    ) {
        throw IllegalArgumentException()
    }
    return prompt
}

private fun containsD4CredentialMaterial(value: String): Boolean {
    val patterns = listOf(
        Regex("sk-[A-Za-z0-9_-]{16,}"),
        Regex("-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----"),
        Regex("(?i)\\bbearer\\s+[A-Za-z0-9._~-]{16,}"),
        Regex(
            "(?i)\\b(?:api[_ -]?key|password|passwd|secret|recovery[_ -]?code|otp|verification[_ -]?code|验证码|密码|私钥)\\s*[:=：]\\s*[^\\s,;]{4,}",
        ),
    )
    return patterns.any { pattern -> pattern.containsMatchIn(value) }
}
