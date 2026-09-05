package com.personalos.app.security

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class KeystoreTicketCodecTest {
    @Test
    fun `ticket tag is deterministic without mutating the database key`() {
        val databaseKey = ByteArray(32) { index -> (index + 1).toByte() }
        val original = databaseKey.copyOf()

        val first = KeystoreTicketCodec.deriveTicketTag(databaseKey, "ticket-body")
        val second = KeystoreTicketCodec.deriveTicketTag(databaseKey, "ticket-body")
        val different = KeystoreTicketCodec.deriveTicketTag(databaseKey, "other-body")

        assertArrayEquals(first, second)
        assertFalse(first.contentEquals(different))
        assertArrayEquals(original, databaseKey)
    }
}
