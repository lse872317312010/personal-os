package com.personalos.app.source

import android.Manifest
import android.content.Context
import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Native-only camera capture and cache-file lifecycle. */
internal class ControlledCameraCapture(
    private val context: Context,
    private val tokenStore: ControlledSourceTokenStore,
    private val permissionLauncher: ActivityResultLauncher<String>,
    private val cameraLauncher: ActivityResultLauncher<Uri>,
    private val currentSessionId: () -> String?,
) {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingFile: File? = null

    fun capture(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error(ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE, null, null)
            return
        }
        pendingResult = result
        try {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        } catch (_: Throwable) {
            finish(ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE)
        }
    }

    fun onPermissionResult(granted: Boolean) {
        if (!granted) {
            val result = pendingResult ?: return
            pendingResult = null
            result.error(ControlledSourceMethodChannelContract.ERROR_DENIED, null, null)
            return
        }
        try {
            val directory = File(context.cacheDir, "camera_capture")
            if (!directory.exists() && !directory.mkdirs()) {
                finish(ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE)
                return
            }
            val file = File.createTempFile("capture-", ".jpg", directory)
            pendingFile = file
            cameraLauncher.launch(FileProvider.getUriForFile(
                context,
                context.packageName + ".fileprovider",
                file,
            ))
        } catch (_: Throwable) {
            finish(ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE)
        }
    }

    fun onCaptured(success: Boolean) {
        val result = pendingResult ?: return
        val file = pendingFile
        pendingResult = null
        pendingFile = null
        if (!success || file == null) {
            if (!cleanup(file)) result.error(ControlledSourceMethodChannelContract.ERROR_DELETE_FAILED, null, null)
            else result.error(ControlledSourceMethodChannelContract.ERROR_CANCELLED, null, null)
            return
        }
        val sessionId = currentSessionId()
        if (sessionId == null) {
            if (!cleanup(file)) result.error(ControlledSourceMethodChannelContract.ERROR_DELETE_FAILED, null, null)
            else result.error(ControlledSourceMethodChannelContract.ERROR_SESSION_INVALID, null, null)
            return
        }
        val uri = FileProvider.getUriForFile(
            context,
            context.packageName + ".fileprovider",
            file,
        )
        val token = tokenStore.issue(uri, sessionId) { cleanup(file) }
        result.success(ControlledSourceMethodChannelContract.safeTokenResult(token))
    }

    private fun finish(code: String) {
        val result = pendingResult ?: return
        pendingResult = null
        val file = pendingFile
        pendingFile = null
        if (!cleanup(file)) result.error(ControlledSourceMethodChannelContract.ERROR_DELETE_FAILED, null, null)
        else result.error(code, null, null)
    }

    private fun cleanup(file: File?): Boolean =
        file == null || !file.exists() || file.delete()

    fun dispose() {
        if (pendingResult != null) finish(ControlledSourceMethodChannelContract.ERROR_CANCELLED)
        pendingFile = null
    }
}
