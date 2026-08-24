package com.personalos.app.source

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal class ControlledSourceChannel(
    private val picker: ControlledPhotoPicker,
    private val camera: ControlledCameraCapture,
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                ControlledSourceMethodChannelContract.METHOD_CAPABILITIES ->
                    result.success(
                        mapOf(
                            ControlledSourceMethodChannelContract.KEY_PHOTO_PICKER to true,
                            ControlledSourceMethodChannelContract.KEY_CAMERA to true,
                        ),
                    )

                ControlledSourceMethodChannelContract.METHOD_PICK_PHOTO ->
                    picker.pick(launcher, result)

                ControlledSourceMethodChannelContract.METHOD_CONSUME -> {
                    val token = (call.arguments as? Map<*, *>)?.get(
                        ControlledSourceMethodChannelContract.KEY_TOKEN,
                    ) as? String
                    if (token == null) {
                        result.error(
                            ControlledSourceMethodChannelContract.ERROR_INVALID_RESPONSE,
                            null,
                            null,
                        )
                    } else {
                        picker.consume(token, result)
                    }
                }

                ControlledSourceMethodChannelContract.METHOD_DELETE_BLOB -> {
                    val blobRef = (call.arguments as? Map<*, *>)?.get(
                        ControlledSourceMethodChannelContract.KEY_BLOB_REF,
                    ) as? String
                    if (blobRef == null) {
                        result.error(
                            ControlledSourceMethodChannelContract.ERROR_INVALID_RESPONSE,
                            null,
                            null,
                        )
                    } else {
                        picker.deleteBlob(blobRef, result)
                    }
                }

                ControlledSourceMethodChannelContract.METHOD_RELEASE -> {
                    val token = (call.arguments as? Map<*, *>)?.get(
                        ControlledSourceMethodChannelContract.KEY_TOKEN,
                    ) as? String
                    if (token == null) {
                        result.error(
                            ControlledSourceMethodChannelContract.ERROR_INVALID_RESPONSE,
                            null,
                            null,
                        )
                    } else {
                        picker.release(token, result)
                    }
                }

                ControlledSourceMethodChannelContract.METHOD_CAPTURE_PHOTO -> camera.capture(result)

                else ->
                    result.error(
                        ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE,
                        null,
                        null,
                    )
            }
        } catch (_: Throwable) {
            result.error(
                ControlledSourceMethodChannelContract.ERROR_UNAVAILABLE,
                null,
                null,
            )
        }
    }

    fun onPicked(uri: android.net.Uri?) {
        picker.onPicked(uri)
    }

    fun onPermissionResult(granted: Boolean) {
        camera.onPermissionResult(granted)
    }

    fun onCaptured(success: Boolean) {
        camera.onCaptured(success)
    }
    fun retireTokens() {
        picker.retireTokens()
    }

    fun dispose() {
        picker.dispose()
        camera.dispose()
    }
}
