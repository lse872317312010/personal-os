package com.personalos.app.source

import android.content.ContentResolver
import android.net.Uri
import com.personalos.app.security.NativeBlobSource
import com.personalos.app.security.NativeVaultChannel
import com.personalos.app.security.NativeVaultFailure
import com.personalos.app.security.NativeVaultFailureCode
import java.io.InputStream

/**
 * Native-only source sink. Resolver access and the stream remain inside the
 * Android adapter; Flutter receives only the resulting opaque BlobRef.
 */
internal class NativeVaultBlobSink(
    private val resolver: ContentResolver,
    private val vault: NativeVaultChannel,
) : SourceBlobSink {
    override fun ingest(uri: Uri, opaqueToken: String): BlobSinkResult {
        val source = ResolverNativeBlobSource(resolver, uri, opaqueToken)
        return try {
            BlobSinkResult.Stored(vault.writeBlobFromCurrentSession(source))
        } catch (failure: NativeVaultFailure) {
            when (failure.failureCode) {
                NativeVaultFailureCode.VAULT_LOCKED,
                NativeVaultFailureCode.VAULT_SESSION_INVALID,
                NativeVaultFailureCode.UNAVAILABLE,
                -> BlobSinkResult.Unavailable
                else -> BlobSinkResult.WriteFailed
            }
        } catch (_: Throwable) {
            BlobSinkResult.WriteFailed
        } finally {
            source.close()
        }
    }
}

private class ResolverNativeBlobSource(
    private val resolver: ContentResolver,
    private val uri: Uri,
    override val opaqueToken: String,
) : NativeBlobSource {
    private var stream: InputStream? = null

    override fun openStream(): InputStream {
        val opened = resolver.openInputStream(uri)
            ?: throw IllegalStateException("source unavailable")
        stream = opened
        return opened
    }

    override fun close() {
        try {
            stream?.close()
        } catch (_: Throwable) {
            // Native source cleanup is best effort; no details cross the channel.
        } finally {
            stream = null
        }
    }
}
