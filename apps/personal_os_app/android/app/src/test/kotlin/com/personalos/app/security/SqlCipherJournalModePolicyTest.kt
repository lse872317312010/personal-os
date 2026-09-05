package com.personalos.app.security

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SqlCipherJournalModePolicyTest {
    @Test
    fun `rollback journal is accepted when WAL is unavailable`() {
        assertTrue(isAcceptedJournalMode(walEnabled = false, journalMode = "delete"))
        assertTrue(isAcceptedJournalMode(walEnabled = false, journalMode = null))
    }

    @Test
    fun `claimed WAL must be observable`() {
        assertTrue(isAcceptedJournalMode(walEnabled = true, journalMode = "wal"))
        assertTrue(isAcceptedJournalMode(walEnabled = true, journalMode = "WAL"))
        assertFalse(isAcceptedJournalMode(walEnabled = true, journalMode = "delete"))
        assertFalse(isAcceptedJournalMode(walEnabled = true, journalMode = null))
    }
}
