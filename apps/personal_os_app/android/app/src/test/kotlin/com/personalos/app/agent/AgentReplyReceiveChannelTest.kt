package com.personalos.app.agent

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class AgentReplyReceiveChannelTest {
    @Test
    fun capturesOnlyPlainTextSendAndConsumesItOnce() {
        val channel = AgentReplyReceiveChannel()
        val intent = plainText("one assistant reply")

        assertTrue(channel.capture(intent))
        assertEquals("one assistant reply", channel.takeForTest())
        assertNull(channel.takeForTest())
    }

    @Test
    fun notifiesAfterCaptureAndOnOverflowButNotForInvalidText() {
        val channel = AgentReplyReceiveChannel()
        var notifications = 0

        val rejected = channel.captureAndNotify(
            Intent(Intent.ACTION_SEND)
                .setType("text/html")
                .putExtra(Intent.EXTRA_TEXT, "ignored"),
        ) {
            notifications++
        }

        assertFalse(rejected)
        assertEquals(0, notifications)

        val accepted = channel.captureAndNotify(plainText("reply body")) {
            notifications++
        }

        assertTrue(accepted)
        assertEquals(1, notifications)
        assertEquals("reply body", channel.takeForTest())
    }

    @Test
    fun rejectsOtherActionsTypesAndMissingText() {
        val channel = AgentReplyReceiveChannel()

        assertFalse(
            channel.capture(
                Intent(Intent.ACTION_SEND_MULTIPLE)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, "ignored"),
            ),
        )
        assertFalse(
            channel.capture(
                Intent(Intent.ACTION_SEND)
                    .setType("text/html")
                    .putExtra(Intent.EXTRA_TEXT, "ignored"),
            ),
        )
        assertFalse(
            channel.capture(
                Intent(Intent.ACTION_SEND).setType("text/plain"),
            ),
        )
        assertNull(channel.takeForTest())
    }

    @Test
    fun rejectsBlankAndOversizedReplies() {
        val channel = AgentReplyReceiveChannel()

        assertFalse(channel.capture(plainText("   ")))
        assertFalse(
            channel.capture(
                plainText("x".repeat(AgentReplyReceiveChannel.MAX_TEXT_BYTES + 1)),
            ),
        )
        assertEquals(0, channel.pendingReplyCountForTest())
    }

    @Test
    fun peekingRetainsReplyUntilExplicitlyAcknowledged() {
        val channel = AgentReplyReceiveChannel()

        assertTrue(channel.capture(plainText("review this later")))
        assertEquals("review this later", channel.peekForTest())
        assertEquals(1, channel.pendingReplyCountForTest())
        channel.acknowledgeForTest()
        assertNull(channel.peekForTest())
        assertEquals(0, channel.pendingReplyCountForTest())
    }

    @Test
    fun capturesRepliesInFifoOrder() {
        val channel = AgentReplyReceiveChannel()

        assertTrue(channel.capture(plainText("first")))
        assertTrue(channel.capture(plainText("second")))
        assertTrue(channel.capture(plainText("third")))

        assertEquals(3, channel.pendingReplyCountForTest())
        assertEquals("first", channel.takeForTest())
        assertEquals("second", channel.takeForTest())
        assertEquals("third", channel.takeForTest())
        assertEquals(0, channel.pendingReplyCountForTest())
    }

    @Test
    fun boundedQueuePreservesExistingRepliesAndReportsOverflow() {
        val channel = AgentReplyReceiveChannel()
        repeat(AgentReplyReceiveChannel.MAX_PENDING_REPLIES) { index ->
            assertTrue(channel.capture(plainText("reply-$index")))
        }
        var notifications = 0

        val captured = channel.captureAndNotify(plainText("overflow reply")) {
            notifications++
        }

        assertFalse(captured)
        assertEquals(1, notifications)
        assertEquals(
            AgentReplyReceiveChannel.MAX_PENDING_REPLIES,
            channel.pendingReplyCountForTest(),
        )
        assertEquals(1, channel.takeDroppedReplyCountForTest())
        assertEquals(0, channel.takeDroppedReplyCountForTest())
        assertEquals("reply-0", channel.takeForTest())
    }

    @Test
    fun boundedAggregateBytesCanAcceptRepliesAfterAnEarlierReplyIsTaken() {
        val channel = AgentReplyReceiveChannel()
        val largeReply = "x".repeat(AgentReplyReceiveChannel.MAX_TEXT_BYTES)

        assertTrue(channel.capture(plainText(largeReply)))
        assertTrue(channel.capture(plainText(largeReply)))
        assertFalse(channel.capture(plainText("over byte limit")))
        assertEquals(1, channel.takeDroppedReplyCountForTest())

        assertEquals(largeReply, channel.takeForTest())
        assertTrue(channel.capture(plainText("fits after one reply is read")))
        assertEquals(2, channel.pendingReplyCountForTest())
    }

    @Test
    fun clearDropsVolatileRepliesAndOverflowCount() {
        val channel = AgentReplyReceiveChannel()
        channel.capture(plainText("discarded"))
        repeat(AgentReplyReceiveChannel.MAX_PENDING_REPLIES) {
            channel.capture(plainText("reply-$it"))
        }
        channel.capture(plainText("overflow"))

        channel.clear()

        assertEquals(0, channel.pendingReplyCountForTest())
        assertEquals(0, channel.takeDroppedReplyCountForTest())
    }
}

private fun plainText(text: String): Intent =
    Intent(Intent.ACTION_SEND)
        .setType("text/plain")
        .putExtra(Intent.EXTRA_TEXT, text)

private fun AgentReplyReceiveChannel.peekForTest(): String? =
    invokeForTest(AgentReplyReceiveChannel.PEEK_PENDING_REPLY_METHOD) as? String

private fun AgentReplyReceiveChannel.acknowledgeForTest() {
    invokeForTest(AgentReplyReceiveChannel.ACKNOWLEDGE_PENDING_REPLY_METHOD)
}

private fun AgentReplyReceiveChannel.takeForTest(): String? {
    val text = peekForTest()
    acknowledgeForTest()
    return text
}

private fun AgentReplyReceiveChannel.pendingReplyCountForTest(): Int =
    invokeForTest(AgentReplyReceiveChannel.PENDING_REPLY_COUNT_METHOD) as Int

private fun AgentReplyReceiveChannel.takeDroppedReplyCountForTest(): Int =
    invokeForTest(AgentReplyReceiveChannel.TAKE_DROPPED_REPLY_COUNT_METHOD) as Int

private fun AgentReplyReceiveChannel.invokeForTest(method: String): Any? {
    val result = RecordingMethodResult()
    onMethodCall(
        io.flutter.plugin.common.MethodCall(method, null),
        result,
    )
    return result.successValue
}

private class RecordingMethodResult : io.flutter.plugin.common.MethodChannel.Result {
    var successValue: Any? = null

    override fun success(result: Any?) {
        successValue = result
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        throw AssertionError("Unexpected method error: $errorCode")
    }

    override fun notImplemented() {
        throw AssertionError("Method was not implemented")
    }
}
