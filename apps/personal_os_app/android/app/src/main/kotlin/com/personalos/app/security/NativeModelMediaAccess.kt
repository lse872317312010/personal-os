package com.personalos.app.security

import java.io.ByteArrayInputStream
import java.io.InputStream

/**
 * Native-only media handoff for model adapters.
 *
 * Implementations must require an active authenticated vault session. The
 * consumer must not retain the stream or bytes after [useBlobForModel] returns.
 * No provider URI, path, SQLCipher handle, or byte array crosses Flutter.
 */
internal interface NativeModelMediaAccess {
    fun <T> useBlobForModel(
        blobRef: String,
        consumer: (InputStream) -> T,
    ): T
}

/**
 * Exact plaintext length known by the native Vault before model processing.
 *
 * Consumers may use this metadata for fail-before-network size checks. The
 * length itself is not exposed through Flutter or persisted as model output.
 */
internal interface NativeExactLengthMediaStream {
    val exactLengthBytes: Long
}

private class OwnedBlobInputStream(
    ownedBytes: ByteArray,
) : ByteArrayInputStream(ownedBytes), NativeExactLengthMediaStream {
    override val exactLengthBytes: Long = ownedBytes.size.toLong()
}

/** Consumes an owned plaintext buffer exactly once and always zeroes it. */
internal fun <T> consumeOwnedBlobBytes(
    ownedBytes: ByteArray,
    consumer: (InputStream) -> T,
): T {
    try {
        return OwnedBlobInputStream(ownedBytes).use { stream -> consumer(stream) }
    } finally {
        ownedBytes.fill(0)
    }
}
