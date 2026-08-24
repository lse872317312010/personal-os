package com.personalos.app.source

/**
 * B2-02 protocol contract for a future MethodChannel registration.
 *
 * This file deliberately contains no Activity, URI, path, or provider object.
 * A later composition change may register the channel without changing the
 * Dart-visible protocol. Native source ownership remains outside Dart.
 */
object ControlledSourceMethodChannelContract {
    const val CHANNEL_NAME = "personal_os/internal/controlled_source"

    const val METHOD_CAPABILITIES = "capabilities"
    const val METHOD_PICK_PHOTO = "pickPhoto"
    const val METHOD_CAPTURE_PHOTO = "capturePhoto"
    const val METHOD_RELEASE = "release"

    const val KEY_PHOTO_PICKER = "photoPicker"
    const val KEY_CAMERA = "camera"
    const val KEY_TOKEN = "token"
    const val KEY_ERROR_CODE = "errorCode"

    const val ERROR_CANCELLED = "source.cancelled"
    const val ERROR_UNAVAILABLE = "source.unavailable"
    const val ERROR_DENIED = "source.denied"
    const val ERROR_INVALID_RESPONSE = "source.invalid_response"
    const val ERROR_EXPIRED = "source.expired"
    const val ERROR_CONSUMED = "source.consumed"

    fun isOpaqueToken(value: Any?): Boolean =
        value is String && Regex("^[A-Za-z0-9_-]{16,128}$").matches(value)

    fun safeTokenResult(token: String): Map<String, Any> =
        if (isOpaqueToken(token)) {
            mapOf(KEY_TOKEN to token)
        } else {
            mapOf(KEY_ERROR_CODE to ERROR_INVALID_RESPONSE)
        }

    fun safeFailure(code: String): Map<String, String> =
        mapOf(KEY_ERROR_CODE to when (code) {
            ERROR_CANCELLED,
            ERROR_UNAVAILABLE,
            ERROR_DENIED,
            ERROR_INVALID_RESPONSE,
            ERROR_EXPIRED,
            ERROR_CONSUMED -> code
            else -> ERROR_UNAVAILABLE
        })
}
