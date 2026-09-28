package com.personalos.app.agent

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Keeps a single bounded ACTION_SEND text payload in volatile Activity memory.
class AgentReplyReceiveChannel : MethodChannel.MethodCallHandler {
    private var pendingText: String? = null

    @Synchronized
    fun capture(intent: Intent?): Boolean {
        if (intent?.action != Intent.ACTION_SEND) return false
        val mimeType = intent.type
            ?.substringBefore(';')
            ?.trim()
            ?: return false
        if (!mimeType.equals("text/plain", ignoreCase = true)) return false

        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: return false
        if (text.isBlank() || text.length > MAX_TEXT_BYTES) return false
        if (text.toByteArray(Charsets.UTF_8).size > MAX_TEXT_BYTES) return false

        pendingText = text
        return true
    }

    @Synchronized
    fun clear() {
        pendingText = null
    }

    @Synchronized
    private fun takePendingText(): String? {
        val text = pendingText
        pendingText = null
        return text
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != TAKE_PENDING_REPLY_METHOD) {
            result.notImplemented()
            return
        }
        result.success(takePendingText())
    }

    companion object {
        const val CHANNEL_NAME = "personal_os/agent_text_receive"
        const val TAKE_PENDING_REPLY_METHOD = "takePendingReply"
        const val REPLY_AVAILABLE_METHOD = "replyAvailable"
        const val MAX_TEXT_BYTES = 512 * 1024
    }
}
