package com.personalos.app.source

import android.net.Uri

/**
 * Native-only handoff boundary for selected media.
 *
 * Implementations must read [uri] through a native ContentResolver held by the
 * sink and write directly to the encrypted vault. URI and media bytes must
 * never cross the Flutter channel or be persisted in a plaintext temp file.
 */
internal interface SourceBlobSink {
    fun ingest(uri: Uri, opaqueToken: String): BlobSinkResult
}

internal sealed interface BlobSinkResult {
    data class Stored(val blobRef: String) : BlobSinkResult
    object ReadFailed : BlobSinkResult
    object WriteFailed : BlobSinkResult
    object Unavailable : BlobSinkResult
}

/**
 * Safe default until the real encrypted-vault blob adapter is composed.
 * It deliberately refuses the handoff instead of buffering plaintext.
 */
internal object UnavailableSourceBlobSink : SourceBlobSink {
    override fun ingest(uri: Uri, opaqueToken: String): BlobSinkResult = BlobSinkResult.Unavailable
}
