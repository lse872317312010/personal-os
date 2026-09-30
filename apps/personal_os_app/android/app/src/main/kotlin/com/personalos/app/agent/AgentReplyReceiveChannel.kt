package com.personalos.app.agent

import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

/// Keeps a bounded FIFO of ACTION_SEND text replies until they are acknowledged.
internal class AgentReplyReceiveChannel(
    private val queueStore: AgentReplyQueueStore? = null,
) : MethodChannel.MethodCallHandler {
    private val pendingReplies = ArrayDeque<String>()
    private var pendingBytes = 0
    private var droppedReplyCount = 0
    private var storageLoadFailed = false
    private var storageWriteFailed = false

    init {
        if (queueStore != null) {
            try {
                restore(queueStore.read())
            } catch (_: Exception) {
                // Keep the ciphertext untouched and report the unreadable store
                // to Dart instead of replacing it with an empty queue.
                pendingReplies.clear()
                pendingBytes = 0
                droppedReplyCount = 0
                storageLoadFailed = true
            }
        }
    }

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
        if (storageLoadFailed) {
            droppedReplyCount = incrementDroppedCount(droppedReplyCount)
            return CaptureOutcome.PERSISTENCE_FAILURE
        }

        if (pendingReplies.size >= MAX_PENDING_REPLIES ||
            pendingBytes + byteCount > MAX_PENDING_BYTES
        ) {
            val nextDroppedCount = incrementDroppedCount(droppedReplyCount)
            if (!persist(pendingReplies.toList(), nextDroppedCount)) {
                droppedReplyCount = nextDroppedCount
                return CaptureOutcome.PERSISTENCE_FAILURE
            }
            droppedReplyCount = nextDroppedCount
            return CaptureOutcome.OVERFLOW
        }

        val nextReplies = pendingReplies.toList() + text
        if (!persist(nextReplies, droppedReplyCount)) {
            droppedReplyCount = incrementDroppedCount(droppedReplyCount)
            return CaptureOutcome.PERSISTENCE_FAILURE
        }
        pendingReplies.addLast(text)
        pendingBytes += byteCount
        return CaptureOutcome.CAPTURED
    }

    @Synchronized
    private fun peekPendingText(): String? = pendingReplies.peekFirst()

    @Synchronized
    private fun acknowledgePendingText(): Boolean {
        val first = pendingReplies.peekFirst() ?: return true
        if (storageLoadFailed) return false
        val nextReplies = pendingReplies.drop(1)
        if (!persist(nextReplies, droppedReplyCount)) return false
        val text = pendingReplies.removeFirst()
        pendingBytes -= first.toByteArray(Charsets.UTF_8).size
        return true
    }

    @Synchronized
    private fun pendingReplyCount(): Int = pendingReplies.size

    @Synchronized
    private fun takeDroppedReplyCount(): Int {
        val count = droppedReplyCount
        if (count == 0) return 0
        if (storageLoadFailed) {
            droppedReplyCount = 0
            return count
        }
        if (!persist(pendingReplies.toList(), 0)) {
            // Deliver the warning once in this process; the storage status
            // below also tells the UI that the count could not be checkpointed.
            droppedReplyCount = 0
            return count
        }
        droppedReplyCount = 0
        return count
    }

    @Synchronized
    private fun replyQueueStorageReady(): Boolean =
        !storageLoadFailed && !storageWriteFailed

    private fun restore(snapshot: AgentReplyQueueSnapshot) {
        require(snapshot.droppedReplyCount >= 0)
        require(snapshot.replies.size <= MAX_PENDING_REPLIES)
        snapshot.replies.forEach { text ->
            require(text.isNotBlank())
            val byteCount = text.toByteArray(Charsets.UTF_8).size
            require(byteCount <= MAX_TEXT_BYTES)
            require(pendingBytes + byteCount <= MAX_PENDING_BYTES)
            pendingReplies.addLast(text)
            pendingBytes += byteCount
        }
        droppedReplyCount = snapshot.droppedReplyCount
    }

    @Synchronized
    private fun persist(
        replies: List<String>,
        droppedCount: Int,
    ): Boolean {
        val store = queueStore ?: return true
        if (storageLoadFailed) return false
        return try {
            store.write(AgentReplyQueueSnapshot(replies, droppedCount))
            storageWriteFailed = false
            true
        } catch (_: Exception) {
            storageWriteFailed = true
            false
        }
    }

    private fun incrementDroppedCount(value: Int): Int =
        if (value == Int.MAX_VALUE) value else value + 1

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
                result.success(acknowledgePendingText())
            }
            PENDING_REPLY_COUNT_METHOD -> result.success(pendingReplyCount())
            TAKE_DROPPED_REPLY_COUNT_METHOD -> result.success(takeDroppedReplyCount())
            REPLY_QUEUE_STORAGE_READY_METHOD -> result.success(replyQueueStorageReady())
            else -> result.notImplemented()
        }
    }

    private enum class CaptureOutcome {
        INVALID,
        CAPTURED,
        OVERFLOW,
        PERSISTENCE_FAILURE,
    }

    companion object {
        const val CHANNEL_NAME = "personal_os/agent_text_receive"
        const val PEEK_PENDING_REPLY_METHOD = "peekPendingReply"
        const val ACKNOWLEDGE_PENDING_REPLY_METHOD = "acknowledgePendingReply"
        const val PENDING_REPLY_COUNT_METHOD = "pendingReplyCount"
        const val TAKE_DROPPED_REPLY_COUNT_METHOD = "takeDroppedReplyCount"
        const val REPLY_QUEUE_STORAGE_READY_METHOD = "replyQueueStorageReady"
        const val REPLY_AVAILABLE_METHOD = "replyAvailable"
        const val MAX_TEXT_BYTES = 512 * 1024
        const val MAX_PENDING_REPLIES = 8
        const val MAX_PENDING_BYTES = 1024 * 1024
    }
}
