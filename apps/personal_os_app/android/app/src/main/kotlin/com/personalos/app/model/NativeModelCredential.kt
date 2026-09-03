package com.personalos.app.model

import java.io.InputStream

/** Runtime-only credential source. Implementations must never persist or log it. */
internal interface NativeModelCredentialProvider {
    val isReady: Boolean

    fun <T> useCredential(consumer: (CharArray) -> T): T

    fun clear()
}

internal interface InstallableNativeModelCredentialProvider :
    NativeModelCredentialProvider {
    fun install(ownedCredential: CharArray)
}

/**
 * Process-memory-only, single-use credential holder.
 *
 * [install] takes ownership of the supplied array. Replacement, explicit
 * clearing, adapter teardown, successful use, and failed use all zeroize the
 * owned value. No String copy is created.
 */
internal class EphemeralNativeModelCredentialProvider :
    InstallableNativeModelCredentialProvider {
    private val monitor = Any()
    private var credential: CharArray? = null

    override val isReady: Boolean
        get() = synchronized(monitor) { credential != null }

    override fun install(ownedCredential: CharArray) {
        if (ownedCredential.isEmpty() || ownedCredential.all { it.isWhitespace() }) {
            ownedCredential.fill('\u0000')
            throw IllegalArgumentException()
        }
        val previous = synchronized(monitor) {
            if (credential === ownedCredential) return
            val value = credential
            credential = ownedCredential
            value
        }
        previous?.fill('\u0000')
    }

    override fun <T> useCredential(consumer: (CharArray) -> T): T {
        val owned = synchronized(monitor) {
            val value = credential ?: throw IllegalStateException()
            credential = null
            value
        }
        return consumeOwnedCredential(owned, consumer)
    }

    override fun clear() {
        val owned = synchronized(monitor) {
            val value = credential
            credential = null
            value
        }
        owned?.fill('\u0000')
    }
}

/**
 * Base class for external transports that require a runtime credential.
 *
 * The credential never enters a request, result, MethodChannel value, event,
 * exception, or log. The provider owns zeroization after [analyzeWithCredential]
 * returns or throws.
 */
internal abstract class CredentialedNativeAppearanceModelTransport(
    private val credentials: NativeModelCredentialProvider,
) : RuntimeCredentialNativeAppearanceModelAdapter {
    final override val processingBoundary: NativeModelProcessingBoundary =
        NativeModelProcessingBoundary.EXTERNAL_PROCESSOR

    final override val runtimeCredentialReady: Boolean
        get() = credentials.isReady

    final override fun dispose() {
        try {
            cancelTransportWork()
        } finally {
            credentials.clear()
        }
    }

    final override fun installRuntimeCredential(ownedCredential: CharArray) {
        val installable = credentials as? InstallableNativeModelCredentialProvider
        if (installable == null) {
            ownedCredential.fill('\u0000')
            throw NativeAppearanceModelFailure(
                NativeAppearanceModelFailureCode.ADAPTER_UNAVAILABLE,
            )
        }
        installable.install(ownedCredential)
    }

    final override fun clearRuntimeCredential() {
        try {
            cancelTransportWork()
        } finally {
            credentials.clear()
        }
    }

    final override fun analyze(
        request: NativeAppearanceModelRequest,
        media: InputStream,
    ): NativeAppearanceModelResult = credentials.useCredential { credential ->
        analyzeWithCredential(request, media, credential)
    }

    protected abstract fun analyzeWithCredential(
        request: NativeAppearanceModelRequest,
        media: InputStream,
        credential: CharArray,
    ): NativeAppearanceModelResult

    protected open fun cancelTransportWork() = Unit
}

/** Takes ownership of [ownedCredential] and always clears it exactly once. */
internal fun <T> consumeOwnedCredential(
    ownedCredential: CharArray,
    consumer: (CharArray) -> T,
): T {
    try {
        return consumer(ownedCredential)
    } finally {
        ownedCredential.fill('\u0000')
    }
}
