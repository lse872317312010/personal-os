package com.personalos.app.security

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

/** Consumes an owned plaintext buffer exactly once and always zeroes it. */
internal fun <T> consumeOwnedBlobBytes(
    ownedBytes: ByteArray,
    consumer: (InputStream) -> T,
): T {
    try {
        return ownedBytes.inputStream().use { stream -> consumer(stream) }
    } finally {
        ownedBytes.fill(0)
    }
}
