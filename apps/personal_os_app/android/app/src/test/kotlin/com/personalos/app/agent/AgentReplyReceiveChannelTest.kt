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
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "one assistant reply")

        assertTrue(channel.capture(intent))
        assertEquals("one assistant reply", channel.takeForTest())
        assertNull(channel.takeForTest())
    }

    @Test
    fun notifiesOnlyAfterCapturingValidPlainText() {
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

        val accepted = channel.captureAndNotify(
            Intent(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "reply body"),
        ) {
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

        assertFalse(
            channel.capture(
                Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(Intent.EXTRA_TEXT, "   "),
            ),
        )
        assertFalse(
            channel.capture(
                Intent(Intent.ACTION_SEND)
                    .setType("text/plain")
                    .putExtra(
                        Intent.EXTRA_TEXT,
                        "x".repeat(AgentReplyReceiveChannel.MAX_TEXT_BYTES + 1),
                    ),
            ),
        )
        assertNull(channel.takeForTest())
    }

    @Test
    fun clearDropsVolatileReply() {
        val channel = AgentReplyReceiveChannel()
        channel.capture(
            Intent(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, "discarded"),
        )

        channel.clear()

        assertNull(channel.takeForTest())
    }
}

private fun AgentReplyReceiveChannel.takeForTest(): String? {
    val result = RecordingMethodResult()
    onMethodCall(
        io.flutter.plugin.common.MethodCall(
            AgentReplyReceiveChannel.TAKE_PENDING_REPLY_METHOD,
            null,
        ),
        result,
    )
    return result.successValue as? String
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
