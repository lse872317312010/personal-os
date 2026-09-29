package com.personalos.app.agent

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

/// Keeps a bounded FIFO of ACTION_SEND text replies in volatile Activity memory.
class AgentReplyReceiveChannel : MethodChannel.MethodCallHandler {
    private val pendingReplies = ArrayDeque<String>()
    private var pendingBytes = 0
    private var droppedReplyCount = 0

    @Synchronized
    fun capture(intent: Intent?): Boolean =
        captureReply(intent) == CaptureOutcome.CAPTURED

    fun captureAndNotify(
        intent: Intent?,
        onReplyAvailable: () -> Unit,
    ): Boolean {
        val outcome = synchronized(this) { captureReply(intent) }
        if (outcome == CaptureOutcome.INVALID) return false
        // Also notify on overflow so the unlocked UI can explain that a new
        // reply was not retained. The signal never carries reply text.
        onReplyAvailable()
        return outcome == CaptureOutcome.CAPTURED
    }

    private fun captureReply(intent: Intent?): CaptureOutcome {
        if (intent?.action != Intent.ACTION_SEND) return CaptureOutcome.INVALID
        val mimeType = intent.type
            ?.substringBefore(';')
            ?.trim()
            ?: return CaptureOutcome.INVALID
        if (!mimeType.equals("text/plain", ignoreCase = true)) {
            return CaptureOutcome.INVALID
        }

        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
            ?: return CaptureOutcome.INVALID
        if (text.isBlank() || text.length > MAX_TEXT_BYTES) {
            return CaptureOutcome.INVALID
        }
        val byteCount = text.toByteArray(Charsets.UTF_8).size
        if (byteCount > MAX_TEXT_BYTES) return CaptureOutcome.INVALID

        if (pendingReplies.size >= MAX_PENDING_REPLIES ||
            pendingBytes + byteCount > MAX_PENDING_BYTES
        ) {
            if (droppedReplyCount < Int.MAX_VALUE) droppedReplyCount++
            return CaptureOutcome.OVERFLOW
        }

        pendingReplies.addLast(text)
        pendingBytes += byteCount
        return CaptureOutcome.CAPTURED
    }

    @Synchronized
    fun clear() {
        pendingReplies.clear()
        pendingBytes = 0
        droppedReplyCount = 0
    }

    @Synchronized
    private fun peekPendingText(): String? = pendingReplies.peekFirst()

    @Synchronized
    private fun acknowledgePendingText() {
        if (pendingReplies.isEmpty()) return
        val text = pendingReplies.removeFirst()
        pendingBytes -= text.toByteArray(Charsets.UTF_8).size
    }

    @Synchronized
    private fun pendingReplyCount(): Int = pendingReplies.size

    @Synchronized
    private fun takeDroppedReplyCount(): Int {
        val count = droppedReplyCount
        droppedReplyCount = 0
        return count
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.arguments != null) {
            result.error(
                "unexpected_arguments",
                "Reply inbox methods do not accept arguments.",
                null,
            )
            return
        }
        when (call.method) {
            PEEK_PENDING_REPLY_METHOD -> result.success(peekPendingText())
            ACKNOWLEDGE_PENDING_REPLY_METHOD -> {
                acknowledgePendingText()
                result.success(null)
            }
            PENDING_REPLY_COUNT_METHOD -> result.success(pendingReplyCount())
            TAKE_DROPPED_REPLY_COUNT_METHOD -> result.success(takeDroppedReplyCount())
            else -> result.notImplemented()
        }
    }

    private enum class CaptureOutcome {
        INVALID,
        CAPTURED,
        OVERFLOW,
    }

    companion object {
        const val CHANNEL_NAME = "personal_os/agent_text_receive"
        const val PEEK_PENDING_REPLY_METHOD = "peekPendingReply"
        const val ACKNOWLEDGE_PENDING_REPLY_METHOD = "acknowledgePendingReply"
        const val PENDING_REPLY_COUNT_METHOD = "pendingReplyCount"
        const val TAKE_DROPPED_REPLY_COUNT_METHOD = "takeDroppedReplyCount"
        const val REPLY_AVAILABLE_METHOD = "replyAvailable"
        const val MAX_TEXT_BYTES = 512 * 1024
        const val MAX_PENDING_REPLIES = 8
        const val MAX_PENDING_BYTES = 1024 * 1024
    }
}
