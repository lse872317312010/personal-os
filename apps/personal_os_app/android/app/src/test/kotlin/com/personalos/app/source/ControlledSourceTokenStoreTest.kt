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
        val token = store.issue(uri)

        assertTrue(ControlledSourceMethodChannelContract.isOpaqueToken(token))
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Ready,
            store.consume(token) {
                reads += 1
                it == uri
            },
        )
        assertEquals(1, reads)
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token) { true },
        )
    }

    @Test
    fun expiredTokenIsRemovedBeforeRead() {
        val store = ControlledSourceTokenStore(
            nowMillis = { 500L },
            ttlMillis = 100L,
            tokenFactory = { "opaque_token_123456" },
        )
        val token = store.issue(Uri.parse("content://private/provider/2"))

        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Expired,
            store.consume(token) { error("must not read expired source") },
        )
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token) { true },
        )
    }

    @Test
    fun readFailureIsStableAndTokenCannotBeRetried() {
        val store = ControlledSourceTokenStore(
            nowMillis = { 10L },
            tokenFactory = { "opaque_token_123456" },
        )
        val token = store.issue(Uri.parse("content://private/provider/3"))

        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.ReadFailed,
            store.consume(token) { false },
        )
        assertEquals(
            ControlledSourceTokenStore.ConsumeResult.Consumed,
            store.consume(token) { true },
        )
    }
}
