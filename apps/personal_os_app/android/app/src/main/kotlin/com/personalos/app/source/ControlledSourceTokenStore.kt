package com.personalos.app.source

import android.net.Uri
import android.util.Base64
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap

/**
 * Native-only ownership of selected media. No URI or resolver result crosses the
 * Dart channel. A token can be consumed once, released, or expires.
 */
internal class ControlledSourceTokenStore(
    private val nowMillis: () -> Long = { System.currentTimeMillis() },
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val tokenFactory: () -> String = ::newOpaqueToken,
) {
    private data class Entry(
        val uri: Uri,
        val expiresAtMillis: Long,
        val sessionId: String,
        val cleanup: (() -> Boolean)? = null,
    )

    private val entries = ConcurrentHashMap<String, Entry>()

    fun issue(uri: Uri, sessionId: String, cleanup: (() -> Boolean)? = null): String {
        var token: String
        do {
            token = tokenFactory()
        } while (entries.putIfAbsent(token, Entry(uri, nowMillis() + ttlMillis, sessionId, cleanup)) != null)
        return token
    }

    fun consume(
        token: String,
        sessionId: String,
        sink: SourceBlobSink,
    ): ConsumeResult {
        if (!ControlledSourceMethodChannelContract.isOpaqueToken(token)) {
            return ConsumeResult.Invalid
        }
        val entry = entries.remove(token) ?: return ConsumeResult.Consumed
        if (nowMillis() >= entry.expiresAtMillis) {
            cleanup(entry)
            return ConsumeResult.Expired
        }
        if (entry.sessionId != sessionId) {
            cleanup(entry)
            return ConsumeResult.SessionMismatch
        }
        return try {
            val outcome = sink.ingest(entry.uri, token)
            if (!cleanup(entry)) {
                ConsumeResult.CleanupFailed
            } else {
                when (outcome) {
                    is BlobSinkResult.Stored -> {
                        if (!ControlledSourceMethodChannelContract.isOpaqueBlobRef(outcome.blobRef)) ConsumeResult.WriteFailed
                        else ConsumeResult.Stored(outcome.blobRef)
                    }
                    BlobSinkResult.ReadFailed -> ConsumeResult.ReadFailed
                    BlobSinkResult.WriteFailed -> ConsumeResult.WriteFailed
                    BlobSinkResult.Unavailable -> ConsumeResult.Unavailable
                }
            }
        } catch (_: Throwable) {
            cleanup(entry)
            ConsumeResult.WriteFailed
        }
    }

    fun release(token: String): Boolean {
        if (!ControlledSourceMethodChannelContract.isOpaqueToken(token)) return false
        val entry = entries.remove(token) ?: return false
        return cleanup(entry)
    }

    fun clear() {
        entries.values.forEach { cleanup(it) }
        entries.clear()
    }

    private fun cleanup(entry: Entry): Boolean = try {
        entry.cleanup?.invoke() ?: true
    } catch (_: Throwable) {
        false
    }

    sealed interface ConsumeResult {
        data class Stored(val blobRef: String) : ConsumeResult
        object Invalid : ConsumeResult
        object Expired : ConsumeResult
        object Consumed : ConsumeResult
        object SessionMismatch : ConsumeResult
        object ReadFailed : ConsumeResult
        object WriteFailed : ConsumeResult
        object Unavailable : ConsumeResult
        object CleanupFailed : ConsumeResult
    }

    companion object {
        const val DEFAULT_TTL_MILLIS = 5 * 60 * 1000L

        private fun newOpaqueToken(): String {
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
        }
    }
}
