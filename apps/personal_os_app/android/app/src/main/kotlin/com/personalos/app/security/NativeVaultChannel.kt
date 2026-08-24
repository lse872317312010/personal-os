package com.personalos.app.security

import android.os.Build
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.UUID

/** Private channel facade. Database keys and handles never cross this class boundary. */
internal class NativeVaultChannel(
    private val activity: FragmentActivity,
    private val sessions: OpaqueVaultSessionRegistry = OpaqueVaultSessionRegistry(),
    private val tickets: KeystoreTicketCodec = KeystoreTicketCodec(),
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "personal_os/internal/android_vault"
        private const val DEFAULT_PROMPT_TITLE = "Unlock Personal OS"
        private const val DEFAULT_PROMPT_DESCRIPTION =
            "Authenticate to continue to the secure vault."
        private const val MAX_REASON_LENGTH = 256
        private const val MAX_APPEND_BATCH_SIZE = 1_000
    }

    private val mainExecutor: Executor = ContextCompat.getMainExecutor(activity)
    private val preparationExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val databaseExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val biometricManager: BiometricManager = BiometricManager.from(activity)
    private val disposed = AtomicBoolean(false)
    private val pendingDatabaseCalls = ConcurrentHashMap.newKeySet<PendingDatabaseCall>()
    private var activeAuthentication: ActiveAuthentication? = null
    @Volatile private var activeSessionId: String? = null

    private data class ActiveAuthentication(
        val result: MethodChannel.Result,
        val challenge: KeystoreTicketCodec.Challenge,
        var prompt: BiometricPrompt? = null,
    )

    private inner class PendingDatabaseCall(
        private val result: MethodChannel.Result,
    ) {
        private val completed = AtomicBoolean(false)

        fun success(value: Any?) = deliver { result.success(value) }

        fun failure(code: NativeVaultFailureCode) = deliver { sendFailure(result, code) }

        private fun deliver(callback: () -> Unit) {
            if (!completed.compareAndSet(false, true)) return
            pendingDatabaseCalls.remove(this)
            try {
                mainExecutor.execute(callback)
            } catch (_: Throwable) {
                // Flutter engine teardown may race delivery; the native state is already
                // closed and no platform details are exposed.
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed.get()) {
            sendFailure(result, NativeVaultFailureCode.UNAVAILABLE)
            return
        }
        try {
            when (call.method) {
                "inspectCapabilities" -> result.success(inspectCapabilities())
                "authenticate" -> authenticate(call, result)
                "openVault" -> openVault(call, result)
                "appendEvents" -> appendEvents(call, result)
                "readEventsByProfile" -> readEventsByProfile(call, result)
                "readEventsBySubject" -> readEventsBySubject(call, result)
                "readEventById" -> readEventById(call, result)
                "closeVault" -> closeVault(call, result)
                else -> throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
            }
        } catch (failure: NativeVaultFailure) {
            sendFailure(result, failure.failureCode)
        } catch (_: Throwable) {
            sendFailure(result, NativeVaultFailureCode.UNAVAILABLE)
        }
    }

    /** Cancels in-flight work and closes all session/database state. */
    fun dispose() {
        if (!disposed.compareAndSet(false, true)) return
        val pending = activeAuthentication
        if (pending != null) {
            activeAuthentication = null
            pending.prompt?.cancelAuthentication()
            sendFailure(pending.result, NativeVaultFailureCode.CANCELLED)
        }
        pendingDatabaseCalls.toList().forEach {
            it.failure(NativeVaultFailureCode.CANCELLED)
        }
        databaseExecutor.shutdownNow()
        preparationExecutor.shutdownNow()
        tickets.clear()
        activeSessionId = null
        sessions.closeAll()
    }

    private fun inspectCapabilities(): Map<String, Any> {
        val strongBiometricAvailable = canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)
        val deviceCredentialAvailable = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_STRONG or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        return mapOf(
            "protectionLevel" to tickets.protectionLevel(),
            "userAuthenticationAvailable" to strongBiometricAvailable,
            "deviceCredentialAvailable" to deviceCredentialAvailable,
            "nonExportableKeys" to true,
            "atomicDeviceRevocation" to false,
        )
    }

    private fun authenticate(call: MethodCall, result: MethodChannel.Result) {
        if (activeAuthentication != null) {
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        }

        val arguments = call.arguments as? Map<*, *>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        val allowDeviceCredential = arguments["allowDeviceCredential"] as? Boolean
            ?: throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        if (allowDeviceCredential && Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            // CryptoObject + DEVICE_CREDENTIAL is not supported before Android 11.
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        }

        val authenticators = if (allowDeviceCredential) {
            BiometricManager.Authenticators.BIOMETRIC_STRONG or
                BiometricManager.Authenticators.DEVICE_CREDENTIAL
        } else {
            BiometricManager.Authenticators.BIOMETRIC_STRONG
        }
        if (!canAuthenticate(authenticators)) {
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        }

        val reason = (arguments["reason"] as? String)
            ?.trim()
            ?.takeIf(String::isNotEmpty)
            ?.take(MAX_REASON_LENGTH)
            ?: DEFAULT_PROMPT_DESCRIPTION
        val challenge = tickets.prepare()
        val promptInfo = BiometricPrompt.PromptInfo.Builder()
            .setTitle(DEFAULT_PROMPT_TITLE)
            .setDescription(reason)
            .setAllowedAuthenticators(authenticators)
            .apply {
                if (!allowDeviceCredential) {
                    setNegativeButtonText("Cancel")
                }
            }
            .build()

        val pending = ActiveAuthentication(result, challenge)
        activeAuthentication = pending
        try {
            preparationExecutor.execute {
                try {
                    val mac = tickets.newMac(allowDeviceCredential)
                    mainExecutor.execute { startPrompt(pending, promptInfo, mac) }
                } catch (failure: NativeVaultFailure) {
                    mainExecutor.execute { finishFailure(pending, failure.failureCode) }
                } catch (_: Throwable) {
                    mainExecutor.execute {
                        finishFailure(
                            pending,
                            NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE,
                        )
                    }
                }
            }
        } catch (_: Throwable) {
            activeAuthentication = null
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        }
    }

    private fun startPrompt(
        pending: ActiveAuthentication,
        promptInfo: BiometricPrompt.PromptInfo,
        mac: javax.crypto.Mac,
    ) {
        if (activeAuthentication !== pending) return
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(
                authenticationResult: BiometricPrompt.AuthenticationResult,
            ) {
                if (activeAuthentication !== pending) return
                activeAuthentication = null
                try {
                    val authenticatedMac = authenticationResult.cryptoObject?.mac
                        ?: throw NativeVaultFailure(
                            NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE,
                        )
                    val issued = tickets.issue(pending.challenge, authenticatedMac)
                    pending.result.success(
                        mapOf(
                            "id" to issued.id,
                            "expiresAt" to issued.expiresAt,
                        ),
                    )
                } catch (failure: NativeVaultFailure) {
                    sendFailure(pending.result, failure.failureCode)
                } catch (_: Throwable) {
                    sendFailure(
                        pending.result,
                        NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE,
                    )
                }
            }

            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                finishFailure(pending, mapAuthenticationError(errorCode))
            }

            // A failed biometric attempt is non-terminal; the system prompt may allow
            // another attempt. The terminal error callback completes the channel.
            override fun onAuthenticationFailed() = Unit
        }

        val prompt = try {
            BiometricPrompt(activity, mainExecutor, callback)
        } catch (_: Throwable) {
            finishFailure(pending, NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
            return
        }
        pending.prompt = prompt
        try {
            prompt.authenticate(promptInfo, BiometricPrompt.CryptoObject(mac))
        } catch (_: Throwable) {
            finishFailure(pending, NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        }
    }

    private fun finishFailure(pending: ActiveAuthentication, code: NativeVaultFailureCode) {
        if (activeAuthentication !== pending) return
        activeAuthentication = null
        sendFailure(pending.result, code)
    }

    private fun canAuthenticate(authenticators: Int): Boolean = try {
        biometricManager.canAuthenticate(authenticators) == BiometricManager.BIOMETRIC_SUCCESS
    } catch (_: Throwable) {
        false
    }

    private fun mapAuthenticationError(errorCode: Int): NativeVaultFailureCode = when (errorCode) {
        BiometricPrompt.ERROR_CANCELED,
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        -> NativeVaultFailureCode.CANCELLED

        BiometricPrompt.ERROR_HW_UNAVAILABLE,
        BiometricPrompt.ERROR_NO_BIOMETRICS,
        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_NO_DEVICE_CREDENTIAL,
        BiometricPrompt.ERROR_SECURITY_UPDATE_REQUIRED,
        -> NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE

        else -> NativeVaultFailureCode.DENIED
    }

    private fun requiredStringArgument(call: MethodCall, name: String): String {
        val arguments = call.arguments as? Map<*, *>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        val value = arguments[name]
        if (value !is String || value.isBlank()) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        }
        return value
    }

    private fun requiredLongArgument(call: MethodCall, name: String): Long {
        val arguments = call.arguments as? Map<*, *>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        val value = arguments[name]
        if (value !is Number) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        }
        return integralLong(value)
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
    }

    private fun optionalLimitArgument(call: MethodCall): Int {
        val arguments = call.arguments as? Map<*, *>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        val value = arguments["limit"] ?: return SqlCipherVaultDatabase.defaultReadLimit()
        if (value !is Number || value.toLong() != value.toInt().toLong()) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        return SqlCipherVaultDatabase.boundedReadLimit(value.toInt())
    }

    private fun openVault(call: MethodCall, result: MethodChannel.Result) {
        val ticketId = requiredStringArgument(call, "authenticationTicketId")
        val ticketExpiresAt = requiredLongArgument(call, "ticketExpiresAt")
        enqueueDatabase(result) {
            val databaseKey = tickets.consumeForOpen(ticketId, ticketExpiresAt)
            var database: NativeVaultDatabase? = null
            try {
                database = SqlCipherVaultDatabase.open(
                    activity.applicationContext,
                    databaseKey,
                )
                val sessionId = UUID.randomUUID().toString()
                sessions.register(sessionId, ticketExpiresAt, database)
                activeSessionId = sessionId
                val opened = mapOf("id" to sessionId)
                database = null
                opened
            } finally {
                database?.close()
                databaseKey.fill(0)
            }
        }
    }

    /**
     * Native-only bridge for a source adapter. The source adapter resolves its
     * provider token and stream on the native side; this method is never
     * reachable through a MethodChannel call.
     */
    internal fun currentSessionId(): String? = activeSessionId?.takeIf(sessions::isActive)

    internal fun writeBlobFromNativeSource(
        sessionId: String,
        source: NativeBlobSource,
    ): String {
        if (disposed.get()) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
        return sessions.withActive(sessionId) { database ->
            database.writeBlob(source)
        }
    }

    /** Native-only source composition uses the currently authenticated vault. */
    internal fun writeBlobFromCurrentSession(source: NativeBlobSource): String {
        val sessionId = activeSessionId
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_LOCKED)
        return writeBlobFromNativeSource(sessionId, source)
    }

    /** Deletes only within the currently authenticated native vault session. */
    internal fun deleteBlobFromCurrentSession(blobRef: String) {
        if (disposed.get()) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
        val sessionId = activeSessionId
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_LOCKED)
        sessions.withActive(sessionId) { database ->
            database.deleteBlob(blobRef)
        }
    }

    private fun appendEvents(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = requiredStringArgument(call, "sessionId")
        val arguments = call.arguments as? Map<*, *>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        val rawEvents = arguments["events"] as? List<*>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        if (rawEvents.isEmpty() || rawEvents.size > MAX_APPEND_BATCH_SIZE) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        val events = rawEvents.map { raw ->
            val value = raw as? Map<*, *>
                ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            NativeEventRecord(
                profileId = requiredString(value, "profileId"),
                eventId = requiredString(value, "eventId"),
                eventJson = requiredString(value, "eventJson", trim = false),
                subjects = requiredSubjects(value["subjectRefs"]),
            )
        }
        enqueueDatabase(result) {
            sessions.withActive(sessionId) { database ->
                database.appendEvents(events)
                null
            }
        }
    }

    private fun readEventsByProfile(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = requiredStringArgument(call, "sessionId")
        val profileId = requiredStringArgument(call, "profileId")
        val limit = optionalLimitArgument(call)
        enqueueDatabase(result) {
            sessions.withActive(sessionId) { database ->
                database.readEventsByProfile(profileId, limit)
            }
        }
    }

    private fun readEventById(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = requiredStringArgument(call, "sessionId")
        val eventId = requiredStringArgument(call, "eventId")
        enqueueDatabase(result) {
            sessions.withActive(sessionId) { database ->
                database.readEventById(eventId)
            }
        }
    }

    private fun readEventsBySubject(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = requiredStringArgument(call, "sessionId")
        val subjectType = requiredStringArgument(call, "subjectType")
        val subjectId = requiredStringArgument(call, "subjectId")
        val limit = optionalLimitArgument(call)
        enqueueDatabase(result) {
            sessions.withActive(sessionId) { database ->
                database.readEventsBySubject(subjectType, subjectId, limit)
            }
        }
    }

    private fun closeVault(call: MethodCall, result: MethodChannel.Result) {
        val sessionId = requiredStringArgument(call, "sessionId")
        enqueueDatabase(result) {
            sessions.close(sessionId)
            if (activeSessionId == sessionId) {
                activeSessionId = null
            }
            null
        }
    }

    private fun enqueueDatabase(
        result: MethodChannel.Result,
        operation: () -> Any?,
    ) {
        val pending = PendingDatabaseCall(result)
        pendingDatabaseCalls += pending
        try {
            databaseExecutor.execute {
                try {
                    pending.success(operation())
                } catch (failure: NativeVaultFailure) {
                    pending.failure(failure.failureCode)
                } catch (_: Throwable) {
                    pending.failure(NativeVaultFailureCode.UNAVAILABLE)
                }
            }
        } catch (_: Throwable) {
            pending.failure(NativeVaultFailureCode.UNAVAILABLE)
        }
    }

    private fun sendFailure(result: MethodChannel.Result, code: NativeVaultFailureCode) {
        result.error(code.wireValue, code.safeMessage, null)
    }

    private fun requiredSubjects(value: Any?): List<NativeSubjectRecord> {
        val subjects = value as? List<*>
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        if (subjects.isEmpty()) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        return subjects.mapIndexed { ordinal, raw ->
            val subject = raw as? Map<*, *>
                ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            val revision = subject["revision"]
            val revisionLong = if (revision == null) {
                null
            } else if (revision !is Number) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            } else {
                integralLong(revision)?.takeIf { it >= 0 }
                    ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
            NativeSubjectRecord(
                type = requiredString(subject, "type"),
                id = requiredString(subject, "id"),
                revision = revisionLong,
                ordinal = ordinal,
            )
        }
    }

    private fun integralLong(value: Number): Long? = when (value) {
        is Byte, is Short, is Int, is Long -> value.toLong()
        is Float, is Double -> {
            val asDouble = value.toDouble()
            if (!asDouble.isFinite() ||
                asDouble < Long.MIN_VALUE.toDouble() ||
                asDouble >= Long.MAX_VALUE.toDouble()
            ) {
                null
            } else {
                val asLong = asDouble.toLong()
                if (asDouble == asLong.toDouble()) asLong else null
            }
        }
        else -> null
    }

    private fun requiredString(
        arguments: Map<*, *>,
        name: String,
        trim: Boolean = true,
    ): String {
        val value = arguments[name]
        if (value !is String || value.isBlank() || (trim && value != value.trim())) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        return value
    }
}
