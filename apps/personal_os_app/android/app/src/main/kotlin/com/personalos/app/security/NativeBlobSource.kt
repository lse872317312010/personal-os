package com.personalos.app.security

import java.io.InputStream

/**
 * Native-owned media source. Implementations must keep the provider URI,
 * path, resolver and provider metadata on the native side.
 *
 * The vault never receives Dart bytes; it consumes this stream only while the
 * source token is valid and closes the source after the transaction completes.
 */
internal interface NativeBlobSource : AutoCloseable {
    val opaqueToken: String

    fun openStream(): InputStream

    override fun close()
}

internal data class NativeBlobReference(
    val value: String,
) {
    init {
        require(value.startsWith("blob://"))
    }
}
