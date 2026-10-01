package com.personalos.app.model

import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
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

    @Test
    fun lateCredentialCallbackFromInvalidatedSessionIsIgnored() {
        val activity = Robolectric.buildActivity(FragmentActivity::class.java)
            .setup()
            .get()
        var vaultActive = true
        val prompt = DeferredCredentialPrompt()
        val channel = AgentCompletionMethodChannel(
            activity = activity,
            client = OpenAiResponsesAgentClient(model = "test-model"),
            credentialPrompt = prompt,
            isVaultActive = { vaultActive },
        )
        val configure = RecordingResult()

        channel.onMethodCall(MethodCall("configureCredential", null), configure)
        vaultActive = false
        channel.clearRuntimeCredential()
        vaultActive = true
        val staleCredential = ("sk-" + "a".repeat(32)).toCharArray()
        prompt.deliver(staleCredential)

        assertEquals(false, configure.successValue)
        assertTrue(staleCredential.all { it == '\u0000' })
        channel.dispose()
    }

}

private class DeferredCredentialPrompt : NativeModelCredentialPrompt {
    private var callback: ((CharArray?) -> Unit)? = null

    override fun requestCredential(callback: (CharArray?) -> Unit) {
        this.callback = callback
    }

    override fun dispose() {
        // Keep the callback to model a result racing with Vault invalidation.
    }

    fun deliver(credential: CharArray) {
        val pending = callback ?: error("No credential request is pending")
        callback = null
        pending(credential)
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
