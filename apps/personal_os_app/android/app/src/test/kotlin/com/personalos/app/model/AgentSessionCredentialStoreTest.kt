package com.personalos.app.model

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AgentSessionCredentialStoreTest {
    @Test
    fun credentialIsAvailableForMultipleRequestsAndClearedWithSession() {
        val store = AgentSessionCredentialStore()
        val owned = "session-secret".toCharArray()
        store.install(owned)

        repeat(2) {
            val observed = store.useCredential { copy ->
                String(copy)
            }
            assertEquals("session-secret", observed)
            assertTrue(store.isReady)
        }

        store.clear()

        assertArrayEquals(CharArray(owned.size), owned)
        assertFalse(store.isReady)
    }

    @Test
    fun replacementAndBlankCredentialsAreZeroized() {
        val store = AgentSessionCredentialStore()
        val first = "first-secret".toCharArray()
        val second = "second-secret".toCharArray()
        store.install(first)
        store.install(second)

        assertArrayEquals(CharArray(first.size), first)
        store.clear()
        assertArrayEquals(CharArray(second.size), second)
        assertFalse(store.isReady)

        val blank = charArrayOf(' ', '\t')
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            store.install(blank)
        }
        assertArrayEquals(CharArray(blank.size), blank)
    }

    @Test
    fun eachRequestUsesAndZeroizesATemporaryCopy() {
        val store = AgentSessionCredentialStore()
        val owned = "original-secret".toCharArray()
        var temporary: CharArray? = null
        store.install(owned)

        store.useCredential { copy ->
            temporary = copy
            assertEquals("original-secret", String(copy))
        }

        assertArrayEquals(CharArray(temporary!!.size), temporary)
        assertTrue(store.isReady)
        store.clear()
        assertArrayEquals(CharArray(owned.size), owned)
    }
}
