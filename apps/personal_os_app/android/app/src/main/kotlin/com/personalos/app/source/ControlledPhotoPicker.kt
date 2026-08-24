package com.personalos.app.source

import android.content.ContentResolver
import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.plugin.common.MethodChannel

/**
 * Android Photo Picker bridge. The resolver and URI stay native; Dart receives
 * only an opaque token and stable failure codes.
 */
internal class ControlledPhotoPicker(
    private val resolver: ContentResolver,
    private val tokenStore: ControlledSourceTokenStore = ControlledSourceTokenStore(),
    private val blobSink: SourceBlobSink = UnavailableSourceBlobSink,
) {
    private var pendingPick: MethodChannel.Result? = null

    fun pick(
        launcher: ActivityResultLauncher<PickVisualMediaRequest>,
        result: MethodChannel.Result,
    ) {
        if (pendingPick != null) {
            result.error(
                ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE,
                null,
                null,
            )
            return
        }
        pendingPick = result
        try {
            launcher.launch(
                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
            )
        } catch (_: Throwable) {
            pendingPick = null
            result.error(
                ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE,
                null,
                null,
            )
        }
    }

    fun onPicked(uri: Uri?) {
        val result = pendingPick ?: return
        pendingPick = null
        if (uri == null) {
            result.error(
                ControlledSourceMethodChannelContract.ERROR_CANCELLED,
                null,
                null,
            )
            return
        }
        val token = tokenStore.issue(uri)
        result.success(ControlledSourceMethodChannelContract.safeTokenResult(token))
    }

    fun consume(
        token: String,
        result: MethodChannel.Result,
    ) {
        when (val outcome = tokenStore.consume(token, blobSink)) {
            is ControlledSourceTokenStore.ConsumeResult.Stored ->
                result.success(
                    ControlledSourceMethodChannelContract.safeBlobRefResult(outcome.blobRef),
                )
            ControlledSourceTokenStore.ConsumeResult.Invalid ->
                result.error(
                    ControlledSourceMethodChannelContract.ERROR_INVALID_RESPONSE,
                    null,
                    null,
                )
            ControlledSourceTokenStore.ConsumeResult.Expired ->
                result.error(
                    ControlledSourceMethodChannelContract.ERROR_EXPIRED,
                    null,
                    null,
                )
            ControlledSourceTokenStore.ConsumeResult.Consumed ->
                result.error(
                    ControlledSourceMethodChannelContract.ERROR_CONSUMED,
                    null,
                    null,
                )
            ControlledSourceTokenStore.ConsumeResult.ReadFailed ->
                result.error(
                    ControlledSourceMethodChannelContract.ERROR_READ_FAILED,
                    null,
                    null,
                )
            ControlledSourceTokenStore.ConsumeResult.WriteFailed ->
                result.error(
                    ControlledSourceMethodChannelContract.ERROR_WRITE_FAILED,
                    null,
                    null,
                )
            ControlledSourceTokenStore.ConsumeResult.Unavailable ->
                result.error(
                    ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE,
                    null,
                    null,
                )
        }
    }

    fun release(token: String, result: MethodChannel.Result) {
        tokenStore.release(token)
        result.success(null)
    }

    fun dispose() {
        pendingPick?.error(
            ControlledSourceMethodChannelContract.ERROR_CANCELLED,
            null,
            null,
        )
        pendingPick = null
        tokenStore.clear()
    }
}
