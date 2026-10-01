package com.personalos.app.model

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class AgentCompletionMethodChannelTest {
    @Test
    fun configurationAndRequestsFailClosedWhenVaultIsLocked() {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java)
            .setup()
            .get()
        val channel = AgentCompletionMethodChannel(
            activity = activity,
            client = null,
            credentialPrompt = null,
            isVaultActive = { false },
        )
        val configure = RecordingResult()
        val complete = RecordingResult()

        channel.onMethodCall(MethodCall("configureCredential", null), configure)
        channel.onMethodCall(
            MethodCall("complete", mapOf("prompt" to "approved prompt")),
            complete,
        )

        assertEquals("agent.credential_required", configure.errorCode)
        assertEquals("agent.credential_required", complete.errorCode)
        channel.dispose()
    }
}

private class RecordingResult : MethodChannel.Result {
    var errorCode: String? = null
    var successValue: Any? = null
    var notImplemented = false

    override fun success(result: Any?) {
        successValue = result
    }

    override fun error(
        errorCode: String,
        errorMessage: String?,
        errorDetails: Any?,
    ) {
        this.errorCode = errorCode
    }

    override fun notImplemented() {
        notImplemented = true
    }
}
