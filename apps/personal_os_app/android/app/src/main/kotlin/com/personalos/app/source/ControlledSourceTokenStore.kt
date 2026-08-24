package com.personalos.app.source

import android.net.Uri
import java.security.SecureRandom
import android.util.Base64
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
    )

    private val entries = ConcurrentHashMap<String, Entry>()

    fun issue(uri: Uri): String {
        var token: String
        do {
            token = tokenFactory()
        } while (entries.putIfAbsent(token, Entry(uri, nowMillis() + ttlMillis)) != null)
        return token
    }

    fun consume(token: String, canRead: (Uri) -> Boolean): ConsumeResult {
        if (!ControlledSourceMethodChannelContract.isOpaqueToken(token)) {
            return ConsumeResult.Invalid
        }
        val entry = entries.remove(token) ?: return ConsumeResult.Consumed
        if (nowMillis() >= entry.expiresAtMillis) {
            return ConsumeResult.Expired
        }
        return if (runCatching { canRead(entry.uri) }.getOrDefault(false)) {
            ConsumeResult.Ready
        } else {
            ConsumeResult.ReadFailed
        }
    }

    fun release(token: String): Boolean {
        if (!ControlledSourceMethodChannelContract.isOpaqueToken(token)) return false
        return entries.remove(token) != null
    }

    fun clear() {
        entries.clear()
    }

    sealed interface ConsumeResult {
        object Ready : ConsumeResult
        object Invalid : ConsumeResult
        object Expired : ConsumeResult
        object Consumed : ConsumeResult
        object ReadFailed : ConsumeResult
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
