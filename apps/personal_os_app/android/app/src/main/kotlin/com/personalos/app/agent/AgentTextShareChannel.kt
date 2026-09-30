package com.personalos.app.agent

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AgentTextShareChannel(
    private val activity: Activity,
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        if (call.method != "shareText") {
            result.notImplemented()
            return
        }

        val text = call.argument<String>("text")
        if (text.isNullOrBlank()) {
            result.error("invalid_request", "Text is required", null)
            return
        }
        if (text.toByteArray(Charsets.UTF_8).size > MAX_TEXT_BYTES) {
            result.error("payload_too_large", "Text is too large to share", null)
            return
        }

        val sendIntent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        try {
            activity.startActivity(
                Intent.createChooser(sendIntent, "选择 AI 助手或 Harness"),
            )
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("share_unavailable", "Unable to open the share menu", null)
        } catch (_: RuntimeException) {
            result.error("share_unavailable", "Unable to open the share menu", null)
        }
    }

    companion object {
        const val CHANNEL_NAME = "personal_os/agent_text_share"
        private const val MAX_TEXT_BYTES = 512 * 1024
    }
}
