package com.personalos.app.source

import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ControlledSourceTokenStoreTest {
    @Test
    fun tokenIsOneTimeAndDoesNotExposeUri() {
        val uri = Uri.parse("content://private/provider/1")
        var reads = 0
        val store = ControlledSourceTokenStore(
            nowMillis = { 10L },
            tokenFactory = { "opaque_token_123456" },
        )
        val token = store.issue(uri, "session-1")

        assertTrue(ControlledSourceMethodChannelContract.isOpaqueToken(token))
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Stored("blob://12345678-1234-1234-123456789012"),
            store.consume(token, "session-1", sink(uri) {
                reads += 1
                BlobSinkResult.Stored("blob://12345678-1234-1234-123456789012")
            }),
        )
        assertEquals(1, reads)
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token, "session-1", sink(uri) {
                BlobSinkResult.Stored("blob://12345678-1234-1234-123456789012")
            }),
        )
    }

    @Test
    fun tokenCannotMoveAcrossVaultSessions() {
        val store = ControlledSourceTokenStore(
            nowMillis = { 10L },
            tokenFactory = { "opaque_token_123456" },
        )
        val token = store.issue(Uri.parse("content://private/provider/2"), "session-1")

        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.SessionMismatch,
            store.consume(token, "session-2", sink(Uri.parse("content://private/provider/2")) {
                error("must not read a token from another session")
            }),
        )
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token, "session-1", sink(Uri.parse("content://private/provider/2")) {
                error("session-mismatched token must be retired")
            }),
        )
    }

    @Test
    fun expiredTokenIsRemovedBeforeRead() {
        val store = ControlledSourceTokenStore(
            nowMillis = { 500L },
            ttlMillis = 100L,
            tokenFactory = { "opaque_token_123456" },
        )
        val token = store.issue(Uri.parse("content://private/provider/3"), "session-1")

        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Expired,
            store.consume(token, "session-1", sink(Uri.parse("content://private/provider/3")) {
                error("must not read expired source")
            }),
        )
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token, "session-1", sink(Uri.parse("content://private/provider/3")) {
                error("expired token must be retired")
            }),
        )
    }

    @Test
    fun writeFailureIsStableAndTokenCannotBeRetried() {
        val store = ControlledSourceTokenStore(
            nowMillis = { 10L },
            tokenFactory = { "opaque_token_123456" },
        )
        val token = store.issue(Uri.parse("content://private/provider/4"), "session-1")

        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.WriteFailed,
            store.consume(token, "session-1", sink(Uri.parse("content://private/provider/4")) {
                BlobSinkResult.WriteFailed
            }),
        )
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token, "session-1", sink(Uri.parse("content://private/provider/4")) {
                error("failed write must not replay the source")
            }),
        )
    }

    private fun sink(uri: Uri, ingest: (Uri) -> BlobSinkResult): SourceBlobSink =
        object : SourceBlobSink {
            override fun ingest(value: Uri, opaqueToken: String): BlobSinkResult {
                assertEquals(uri, value)
                assertTrue(ControlledSourceMethodChannelContract.isOpaqueToken(opaqueToken))
                return ingest(value)
            }

            override fun deleteBlob(blobRef: String): BlobDeleteResult =
                BlobDeleteResult.Deleted
        }
}
