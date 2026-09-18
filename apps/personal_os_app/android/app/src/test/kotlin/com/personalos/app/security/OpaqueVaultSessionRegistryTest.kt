package com.personalos.app.security

import java.io.InputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OpaqueVaultSessionRegistryTest {
    @Test
    fun expiredSessionClosesDatabaseAndRejectsAccess() {
        var now = 1_000L
        val database = FakeDatabase()
        val registry = OpaqueVaultSessionRegistry(clockMillis = { now })
        try {
            registry.register("session-1", 2_000L, database)
            assertTrue(registry.isActive("session-1"))

            now = 2_001L
            try {
                registry.withActive("session-1") { error("expired session was used") }
                error("expected expiration failure")
            } catch (failure: NativeVaultFailure) {
                assertEquals(
                    NativeVaultFailureCode.AUTHENTICATION_EXPIRED,
                    failure.failureCode,
                )
            }
            assertTrue(database.closed)
            assertFalse(registry.isActive("session-1"))
        } finally {
            registry.closeAll()
        }
    }

    @Test
    fun closeAllClosesEveryDatabaseAndInvalidatesSessions() {
        val first = FakeDatabase()
        val second = FakeDatabase()
        val registry = OpaqueVaultSessionRegistry(clockMillis = { 1_000L })
        registry.register("first", 2_000L, first)
        registry.register("second", 2_000L, second)

        registry.closeAll()

        assertTrue(first.closed)
        assertTrue(second.closed)
        assertFalse(registry.isActive("first"))
        assertFalse(registry.isActive("second"))
    }

    private class FakeDatabase : NativeVaultDatabase {
        var closed = false

        override fun appendEvents(events: List<NativeEventRecord>) = Unit

        override fun writeBlob(source: NativeBlobSource): String = "blob://test"

        override fun deleteBlob(blobRef: String) = Unit

        override fun <T> useBlob(
            blobRef: String,
            consumer: (InputStream) -> T,
        ): T = throw UnsupportedOperationException()

        override fun readEventsByProfile(
            profileId: String,
            limit: Int,
        ): List<Map<String, Any?>> = emptyList()


        override fun readEventsByProfilePage(
            profileId: String,
            afterSequence: Long,
            limit: Int,
        ): List<Map<String, Any?>> = emptyList()

        override fun readEventsBySubject(
            subjectType: String,
            subjectId: String,
            limit: Int,
        ): List<Map<String, Any?>> = emptyList()

        override fun readEventById(eventId: String): Map<String, Any?>? = null

        override fun close() {
            closed = true
        }
    }
}
