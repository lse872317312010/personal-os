package com.personalos.app.security

import android.content.Context
import java.io.File
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class SqlCipherVaultDatabasePersistenceTest {
    private lateinit var context: Context

    @Before
    fun clearExistingVault() {
        context = RuntimeEnvironment.getApplication()
        context.deleteDatabase(DATABASE_FILE_NAME)
    }

    @After
    fun removeTestVault() {
        context.deleteDatabase(DATABASE_FILE_NAME)
    }

    @Test
    fun `committed events survive closing and reopening the encrypted database`() {
        val event = eventRecord()
        val firstKey = databaseKey()
        val firstDatabase = SqlCipherVaultDatabase.open(context, firstKey)
        try {
            assertTrue(firstKey.all { byte -> byte == 0.toByte() })
            firstDatabase.appendEvents(listOf(event))
        } finally {
            firstDatabase.close()
        }

        val databaseFile = context.getDatabasePath(DATABASE_FILE_NAME)
        assertTrue("expected SQLCipher database file", databaseFile.isFile)
        val databaseArtifacts = databaseFile.parentFile
            ?.listFiles()
            ?.filter { file -> file.name.startsWith(DATABASE_FILE_NAME) }
            .orEmpty()
        assertTrue("expected database or WAL artifacts", databaseArtifacts.isNotEmpty())
        assertFalse(
            "event identifiers must not appear in encrypted database files",
            databaseArtifacts.any { file -> file.containsPlaintext(event.eventId) },
        )

        val reopened = SqlCipherVaultDatabase.open(context, databaseKey())
        try {
            val events = reopened.readEventsByProfile(PROFILE_ID, 10)
            assertEquals(1, events.size)
            assertEquals(event.eventJson, events.single()["eventJson"])
            assertEquals(event.eventId, reopened.readEventById(event.eventId)?.get("eventId"))
            assertEquals(
                event.eventId,
                reopened.readEventsBySubject("profile", PROFILE_ID, 10).single()["eventId"],
            )
        } finally {
            reopened.close()
        }
    }

    private fun eventRecord() = NativeEventRecord(
        profileId = PROFILE_ID,
        eventId = EVENT_ID,
        eventJson = EVENT_JSON,
        subjects = listOf(
            NativeSubjectRecord(
                type = "profile",
                id = PROFILE_ID,
                revision = 1,
                ordinal = 0,
            ),
        ),
    )

    private fun databaseKey() = ByteArray(32) { index -> (index + 1).toByte() }

    private fun File.containsPlaintext(value: String): Boolean =
        String(readBytes(), Charsets.ISO_8859_1).contains(value)

    private companion object {
        const val DATABASE_FILE_NAME = "personal_os_vault.db"
        const val PROFILE_ID = "profile-persist-1"
        const val EVENT_ID = "evt-reopen-1"
        const val EVENT_JSON =
            """{"event_id":"evt-reopen-1","subject_refs":[{"type":"profile","id":"profile-persist-1","revision":1}],"payload":{"kind":"strategy.started"}}"""
    }
}
