package com.personalos.app.security

import android.content.Context
import android.database.Cursor
import java.io.ByteArrayOutputStream
import java.io.InputStream
import java.util.UUID
import net.zetetic.database.sqlcipher.SQLiteDatabase
import org.json.JSONObject

/** The only database API exposed to the native channel facade. */
internal interface NativeVaultDatabase : AutoCloseable {
    fun appendEvents(events: List<NativeEventRecord>)

    /** Writes from a native-owned stream and returns only an opaque blob reference. */
    fun writeBlob(source: NativeBlobSource): String

    /** Deletes an opaque blob reference; missing references are an idempotent success. */
    fun deleteBlob(blobRef: String)

    /**
     * Gives a native-only consumer temporary stream access to one blob.
     * The backing byte array is zeroed before this call returns.
     */
    fun <T> useBlob(blobRef: String, consumer: (InputStream) -> T): T

    fun readEventsByProfile(profileId: String, limit: Int): List<Map<String, Any?>>

    fun readEventsBySubject(subjectType: String, subjectId: String, limit: Int): List<Map<String, Any?>>

    fun readEventById(eventId: String): Map<String, Any?>?

    override fun close()
}

internal data class NativeEventRecord(
    val profileId: String,
    val eventId: String,
    val eventJson: String,
    val subjects: List<NativeSubjectRecord>,
)

internal data class NativeSubjectRecord(
    val type: String,
    val id: String,
    val revision: Long?,
    val ordinal: Int,
)

/**
 * SQLCipher-backed app-private event store.
 *
 * The password is only materialized for the duration of the native open call;
 * it is never returned, logged, persisted, or placed in a channel result.
 */
internal class SqlCipherVaultDatabase private constructor(
    private val database: SQLiteDatabase,
) : NativeVaultDatabase {
    companion object {
        private const val DATABASE_FILE_NAME = "personal_os_vault.db"
        private const val MAX_ID_LENGTH = 512
        private const val MAX_EVENT_JSON_LENGTH = 1_048_576
        private const val DEFAULT_READ_LIMIT = 100
        private const val MAX_READ_LIMIT = 1_000
        private const val SCHEMA_VERSION = 3
        private const val PREVIOUS_SCHEMA_VERSION = 2
        private const val MAX_BLOB_TOKEN_LENGTH = 512
        private const val MAX_BLOB_REF_LENGTH = 136
        private const val MAX_BLOB_BYTES = 50 * 1024 * 1024
        private const val BLOB_READ_BUFFER_SIZE = 32 * 1024

        fun open(context: Context, databaseKey: ByteArray): NativeVaultDatabase {
            var database: SQLiteDatabase? = null
            try {
                // Deliberately fail closed if the native SQLCipher library cannot load.
                System.loadLibrary("sqlcipher")
                val databaseFile = context.getDatabasePath(DATABASE_FILE_NAME)
                val parent = databaseFile.parentFile
                    ?: throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
                if (!parent.exists() && !parent.mkdirs() && !parent.isDirectory) {
                    throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
                }

                // The current SQLCipher Android API accepts a String password. This
                // transient value remains native-only and is never placed in a result.
                val password = android.util.Base64.encodeToString(
                    databaseKey,
                    android.util.Base64.NO_WRAP or android.util.Base64.NO_PADDING,
                )
                database = SQLiteDatabase.openOrCreateDatabase(
                    databaseFile,
                    password,
                    null,
                    null,
                    null,
                )
                val opened = SqlCipherVaultDatabase(
                    database ?: throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE),
                )
                try {
                    opened.initialize()
                    database = null
                    return opened
                } catch (failure: Throwable) {
                    opened.close()
                    throw failure
                }
            } catch (failure: NativeVaultFailure) {
                database?.close()
                throw failure
            } catch (_: Throwable) {
                database?.close()
                throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
            } finally {
                databaseKey.fill(0)
            }
        }

        fun defaultReadLimit(): Int = DEFAULT_READ_LIMIT

        fun boundedReadLimit(value: Int): Int {
            if (value <= 0 || value > MAX_READ_LIMIT) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
            return value
        }
    }

    private val lock = Any()
    private var closed = false

    private fun initialize() = synchronized(lock) {
        ensureOpen()
        verifySqlCipher()
        database.execSQL("PRAGMA foreign_keys = ON")
        if (readPragmaInt("foreign_keys") != 1) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
        database.execSQL("PRAGMA busy_timeout = 5000")
        // WAL is an optional concurrency optimization, not an encryption or
        // durability prerequisite. SQLCipher follows Android's contract and
        // may decline WAL on a supported device/filesystem. Keep the encrypted
        // database usable with its rollback journal in that case. If the
        // provider claims WAL was enabled, verify that claim fail-closed.
        val walEnabled = try {
            database.enableWriteAheadLogging()
        } catch (_: Throwable) {
            false
        }
        if (walEnabled && !isAcceptedJournalMode(walEnabled, readPragmaText("journal_mode"))) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
        initializeSchema()
    }

    override fun appendEvents(events: List<NativeEventRecord>) = synchronized(lock) {
        ensureOpen()
        if (events.isEmpty() || events.size > MAX_READ_LIMIT) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        try {
            database.beginTransaction()
            try {
                events.forEach { event ->
                    validateText(event.profileId, MAX_ID_LENGTH)
                    validateText(event.eventId, MAX_ID_LENGTH)
                    validateEventIdentity(
                        event.eventJson,
                        event.eventId,
                        event.profileId,
                    )

                    val existingEventJson = existingEventJson(event.eventId)
                    if (existingEventJson != null) {
                        if (!sameEventContentForIdempotency(existingEventJson, event.eventJson)) {
                            throw NativeVaultFailure(
                                NativeVaultFailureCode.VAULT_EVENT_CONFLICT,
                            )
                        }
                        // Retrying an already committed event is an idempotent no-op.
                        return@forEach
                    }

                    if (event.subjects.none { subject ->
                            subject.type == "profile" && subject.id == event.profileId
                        }) {
                        throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
                    }

                    database.insertOrThrow(
                        "vault_events",
                        null,
                        android.content.ContentValues().apply {
                            put("profile_id", event.profileId)
                            put("event_id", event.eventId)
                            put("event_json", event.eventJson)
                        },
                    )
                    event.subjects.forEach { subject ->
                        database.insertOrThrow(
                            "vault_event_subjects",
                            null,
                            android.content.ContentValues().apply {
                                put("event_id", event.eventId)
                                put("subject_type", subject.type)
                                put("subject_id", subject.id)
                                if (subject.revision == null) {
                                    putNull("subject_revision")
                                } else {
                                    put("subject_revision", subject.revision)
                                }
                                put("subject_ordinal", subject.ordinal)
                            },
                        )
                    }
                }
                database.setTransactionSuccessful()
            } finally {
                database.endTransaction()
            }
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.TRANSACTION_FAILED)
        }
    }

    override fun writeBlob(source: NativeBlobSource): String = synchronized(lock) {
        ensureOpen()
        val token = source.opaqueToken
        validateBlobToken(token)
        var transactionOpen = false
        var ownedBytes: ByteArray? = null
        try {
            database.beginTransaction()
            transactionOpen = true

            // Check before opening the stream: retrying the same source token is
            // a no-op and cannot cause a second encrypted row to be written.
            existingBlobReference(token)?.let { existing ->
                database.setTransactionSuccessful()
                return@synchronized existing
            }

            val bytes = source.openStream().use { stream ->
                readBlobBytes(stream)
            }
            ownedBytes = bytes
            if (bytes.isEmpty()) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
            val blobReference = "blob://" + UUID.randomUUID()
            database.insertOrThrow(
                "vault_blobs",
                null,
                android.content.ContentValues().apply {
                    put("blob_ref", blobReference)
                    put("source_token", token)
                    put("content", bytes)
                    put("created_at", System.currentTimeMillis())
                },
            )
            // Closing the source before commit makes release failure fail closed.
            source.close()
            database.setTransactionSuccessful()
            return@synchronized blobReference
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.TRANSACTION_FAILED)
        } finally {
            if (transactionOpen) {
                try {
                    database.endTransaction()
                } catch (_: Throwable) {
                    // The outer failure mapping remains stable and does not expose
                    // provider details.
                }
            }
            try {
                source.close()
            } catch (_: Throwable) {
                // The transaction has already rolled back or committed. No details
                // cross the native boundary.
            }
            ownedBytes?.fill(0)
        }
    }

    override fun deleteBlob(blobRef: String) = synchronized(lock) {
        ensureOpen()
        validateBlobReference(blobRef)
        try {
            // DELETE is intentionally idempotent: an already discarded blob is
            // a successful retry, while the active session remains mandatory.
            database.delete(
                "vault_blobs",
                "blob_ref = ?",
                arrayOf(blobRef),
            )
            Unit
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.TRANSACTION_FAILED)
        }
    }

    override fun <T> useBlob(
        blobRef: String,
        consumer: (InputStream) -> T,
    ): T = synchronized(lock) {
        ensureOpen()
        validateBlobReference(blobRef)
        var cursor: Cursor? = null
        val ownedBytes = try {
            cursor = database.query(
                "vault_blobs",
                arrayOf("content"),
                "blob_ref = ?",
                arrayOf(blobRef),
                null,
                null,
                null,
                "1",
            )
            if (!cursor.moveToFirst()) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
            val value = cursor.getBlob(cursor.getColumnIndexOrThrow("content"))
            if (value.isEmpty() || value.size > MAX_BLOB_BYTES) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
            value
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.TRANSACTION_FAILED)
        } finally {
            try {
                cursor?.close()
            } catch (_: Throwable) {
                // The owned result is still consumed and zeroed below.
            }
        }
        // Consumer failures belong to the model boundary and must not be
        // mislabeled as SQLCipher transaction failures.
        consumeOwnedBlobBytes(ownedBytes, consumer)
    }

    private fun readBlobBytes(stream: InputStream): ByteArray {
        val output = ZeroingByteArrayOutputStream()
        val buffer = ByteArray(BLOB_READ_BUFFER_SIZE)
        try {
            var total = 0
            while (true) {
                val count = stream.read(buffer)
                if (count == -1) break
                if (count <= 0) {
                    throw NativeVaultFailure(NativeVaultFailureCode.TRANSACTION_FAILED)
                }
                total += count
                if (total > MAX_BLOB_BYTES) {
                    throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
                }
                output.write(buffer, 0, count)
            }
            return output.toByteArray()
        } finally {
            buffer.fill(0)
            output.zeroize()
        }
    }

    private fun validateBlobToken(token: String) {
        if (token.isBlank() ||
            token.length > MAX_BLOB_TOKEN_LENGTH ||
            token != token.trim() ||
            !token.matches(Regex("[A-Za-z0-9._-]+"))
        ) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
    }

    private fun validateBlobReference(blobRef: String) {
        if (blobRef.isBlank() ||
            blobRef.length > MAX_BLOB_REF_LENGTH ||
            blobRef != blobRef.trim() ||
            !blobRef.matches(Regex("blob://[A-Za-z0-9-]{16,128}"))
        ) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
    }

    private fun existingBlobReference(token: String): String? {
        var cursor: Cursor? = null
        return try {
            cursor = database.query(
                "vault_blobs",
                arrayOf("blob_ref"),
                "source_token = ?",
                arrayOf(token),
                null,
                null,
                null,
                "1",
            )
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } finally {
            cursor?.close()
        }
    }

    override fun readEventsBySubject(
        subjectType: String,
        subjectId: String,
        limit: Int,
    ): List<Map<String, Any?>> = synchronized(lock) {
        ensureOpen()
        validateText(subjectType, MAX_ID_LENGTH)
        validateText(subjectId, MAX_ID_LENGTH)
        val boundedLimit = boundedReadLimit(limit)
        val rows = ArrayList<Map<String, Any?>>()
        var cursor: Cursor? = null
        try {
            cursor = database.rawQuery(
                "SELECT e.sequence_no, e.profile_id, e.event_id, e.event_json " +
                    "FROM vault_events e JOIN vault_event_subjects s " +
                    "ON s.event_id = e.event_id " +
                    "WHERE s.subject_type = ? AND s.subject_id = ? " +
                    "ORDER BY e.sequence_no ASC LIMIT ?",
                arrayOf(subjectType, subjectId, boundedLimit.toString()),
            )
            while (cursor.moveToNext()) {
                rows += mapOf(
                    "sequenceNo" to cursor.getLong(cursor.getColumnIndexOrThrow("sequence_no")),
                    "profileId" to cursor.getString(cursor.getColumnIndexOrThrow("profile_id")),
                    "eventId" to cursor.getString(cursor.getColumnIndexOrThrow("event_id")),
                    "eventJson" to cursor.getString(cursor.getColumnIndexOrThrow("event_json")),
                )
            }
            rows
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        } finally {
            cursor?.close()
        }
    }

    override fun readEventsByProfile(
        profileId: String,
        limit: Int,
    ): List<Map<String, Any?>> = synchronized(lock) {
        ensureOpen()
        validateText(profileId, MAX_ID_LENGTH)
        val boundedLimit = boundedReadLimit(limit)
        val rows = ArrayList<Map<String, Any?>>()
        var cursor: Cursor? = null
        try {
            cursor = database.query(
                "vault_events",
                arrayOf(
                    "sequence_no",
                    "profile_id",
                    "event_id",
                    "event_json",
                ),
                "profile_id = ?",
                arrayOf(profileId),
                null,
                null,
                "sequence_no ASC",
                boundedLimit.toString(),
            )
            val sequenceIndex = cursor.getColumnIndexOrThrow("sequence_no")
            val profileIndex = cursor.getColumnIndexOrThrow("profile_id")
            val eventIdIndex = cursor.getColumnIndexOrThrow("event_id")
            val eventJsonIndex = cursor.getColumnIndexOrThrow("event_json")
            while (cursor.moveToNext()) {
                rows += mapOf(
                    "sequenceNo" to cursor.getLong(sequenceIndex),
                    "profileId" to cursor.getString(profileIndex),
                    "eventId" to cursor.getString(eventIdIndex),
                    "eventJson" to cursor.getString(eventJsonIndex),
                )
            }
            return rows
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        } finally {
            cursor?.close()
        }
    }

    override fun readEventById(eventId: String): Map<String, Any?>? = synchronized(lock) {
        ensureOpen()
        validateText(eventId, MAX_ID_LENGTH)
        var cursor: Cursor? = null
        try {
            cursor = database.query(
                "vault_events",
                arrayOf("sequence_no", "profile_id", "event_id", "event_json"),
                "event_id = ?",
                arrayOf(eventId),
                null,
                null,
                null,
                "1",
            )
            if (!cursor.moveToFirst()) return null
            mapOf(
                "sequenceNo" to cursor.getLong(cursor.getColumnIndexOrThrow("sequence_no")),
                "profileId" to cursor.getString(cursor.getColumnIndexOrThrow("profile_id")),
                "eventId" to cursor.getString(cursor.getColumnIndexOrThrow("event_id")),
                "eventJson" to cursor.getString(cursor.getColumnIndexOrThrow("event_json")),
            )
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        } finally {
            cursor?.close()
        }
    }

    override fun close() = synchronized(lock) {
        if (closed) return
        closed = true
        try {
            database.close()
        } catch (_: Throwable) {
            // The handle is considered closed even if the provider reports a close error.
        }
    }

    private fun verifySqlCipher() {
        var cursor: Cursor? = null
        try {
            cursor = database.rawQuery("PRAGMA cipher_version", null)
            if (!cursor.moveToFirst() || cursor.getString(0).isNullOrBlank()) {
                throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
            }
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        } finally {
            cursor?.close()
        }
    }

    private fun readPragmaInt(name: String): Int {
        return readPragmaText(name)?.toIntOrNull()
            ?: throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
    }

    private fun readPragmaText(name: String): String? {
        var cursor: Cursor? = null
        return try {
            cursor = database.rawQuery("PRAGMA $name", null)
            if (!cursor.moveToFirst() || cursor.isNull(0)) null else cursor.getString(0)
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        } finally {
            cursor?.close()
        }
    }

    private fun ensureOpen() {
        if (closed) throw NativeVaultFailure(NativeVaultFailureCode.VAULT_LOCKED)
    }

    private fun validateText(value: String, maxLength: Int) {
        if (value.isBlank() || value.length > maxLength || value != value.trim()) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
    }

    private fun validateEventIdentity(
        eventJson: String,
        expectedEventId: String,
        expectedProfileId: String,
    ) {
        if (eventJson.isBlank() || eventJson.length > MAX_EVENT_JSON_LENGTH) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        try {
            // Parse and cross-check the untrusted channel payload before any
            // index row or event body can be persisted.
            val event = JSONObject(eventJson)
            if (event.optString("event_id", null) != expectedEventId) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
            val subjects = event.optJSONArray("subject_refs")
                ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            var matchingProfile = false
            for (index in 0 until subjects.length()) {
                val subject = subjects.optJSONObject(index)
                    ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
                if (subject.optString("type", null) == "profile" &&
                    subject.optString("id", null) == expectedProfileId
                ) {
                    matchingProfile = true
                }
            }
            if (!matchingProfile) {
                throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
            }
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            // Never expose JSON parser details across the native boundary.
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
    }

    /**
     * The expected projection revision is a retry-time concurrency guard, not
     * part of the event identity. All other JSON content remains conflict
     * sensitive. Parsing failures deliberately return false (fail closed).
     */
    private fun sameEventContentForIdempotency(
        existingEventJson: String,
        incomingEventJson: String,
    ): Boolean {
        return try {
            val existing = JSONObject(existingEventJson)
            val incoming = JSONObject(incomingEventJson)
            existing.optJSONObject("payload")?.remove("expected_revision")
            incoming.optJSONObject("payload")?.remove("expected_revision")
            // EventEnvelopeJsonCodec emits canonical JSON, so equivalent
            // persisted envelopes have the same normalized representation.
            existing.toString() == incoming.toString()
        } catch (_: Throwable) {
            false
        }
    }

    private fun existingEventJson(eventId: String): String? {
        var cursor: Cursor? = null
        return try {
            cursor = database.query(
                "vault_events",
                arrayOf("event_json"),
                "event_id = ?",
                arrayOf(eventId),
                null,
                null,
                null,
                "1",
            )
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } finally {
            cursor?.close()
        }
    }

    private fun initializeSchema() {
        val version = readUserVersion()
        val tableExists = tableExists("vault_events")
        if (!tableExists && version == 0) {
            database.execSQL(
                """
                CREATE TABLE vault_events (
                  sequence_no INTEGER PRIMARY KEY AUTOINCREMENT,
                  event_id TEXT NOT NULL UNIQUE,
                  profile_id TEXT NOT NULL,
                  event_json TEXT NOT NULL
                )
                """.trimIndent(),
            )
            database.execSQL(
                """
                CREATE TABLE vault_event_subjects (
                  event_id TEXT NOT NULL,
                  subject_type TEXT NOT NULL,
                  subject_id TEXT NOT NULL,
                  subject_revision INTEGER,
                  subject_ordinal INTEGER NOT NULL,
                  PRIMARY KEY (event_id, subject_ordinal),
                  FOREIGN KEY (event_id) REFERENCES vault_events(event_id)
                )
                """.trimIndent(),
            )
            database.execSQL(
                "CREATE INDEX vault_events_profile_order_idx " +
                    "ON vault_events(profile_id, sequence_no)",
            )
            database.execSQL(
                "CREATE INDEX vault_event_subject_lookup_idx " +
                    "ON vault_event_subjects(subject_type, subject_id, event_id)",
            )
            createBlobSchema()
            database.execSQL("PRAGMA user_version = $SCHEMA_VERSION")
            return
        }

        if (version == PREVIOUS_SCHEMA_VERSION && hasCurrentEventColumns() &&
            hasCurrentSubjectTable() && indexExists("vault_events_profile_order_idx") &&
            indexExists("vault_event_subject_lookup_idx")
        ) {
            createBlobSchema()
            database.execSQL("PRAGMA user_version = $SCHEMA_VERSION")
            return
        }

        // The previous bridge schema split the envelope into columns and cannot
        // losslessly produce a strict EventEnvelope JSON. No implicit migration
        // or data guessing is permitted.
        if (version != SCHEMA_VERSION || !hasCurrentEventColumns() ||
            !hasCurrentSubjectTable() || !hasCurrentBlobTable() ||
            !indexExists("vault_event_subject_lookup_idx") ||
            !indexExists("vault_blobs_source_token_idx")) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        }
        if (!indexExists("vault_events_profile_order_idx")) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        }
    }

    private fun createBlobSchema() {
        database.execSQL(
            """
            CREATE TABLE IF NOT EXISTS vault_blobs (
              blob_ref TEXT NOT NULL UNIQUE,
              source_token TEXT NOT NULL UNIQUE,
              content BLOB NOT NULL CHECK(length(content) > 0),
              created_at INTEGER NOT NULL
            )
            """.trimIndent(),
        )
        database.execSQL(
            "CREATE UNIQUE INDEX IF NOT EXISTS vault_blobs_source_token_idx " +
                "ON vault_blobs(source_token)",
        )
    }

    private fun readUserVersion(): Int {
        var cursor: Cursor? = null
        return try {
            cursor = database.rawQuery("PRAGMA user_version", null)
            if (!cursor.moveToFirst()) {
                throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
            }
            cursor.getInt(0)
        } catch (failure: NativeVaultFailure) {
            throw failure
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        } finally {
            cursor?.close()
        }
    }

    private fun tableExists(name: String): Boolean = objectExists("table", name)

    private fun indexExists(name: String): Boolean = objectExists("index", name)

    private fun hasCurrentBlobTable(): Boolean {
        val columns = LinkedHashSet<String>()
        var cursor: Cursor? = null
        try {
            cursor = database.rawQuery("PRAGMA table_info(vault_blobs)", null)
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            while (cursor.moveToNext()) columns += cursor.getString(nameIndex)
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        } finally {
            cursor?.close()
        }
        return columns == setOf("blob_ref", "source_token", "content", "created_at")
    }

    private fun objectExists(type: String, name: String): Boolean {
        var cursor: Cursor? = null
        return try {
            cursor = database.query(
                "sqlite_master",
                arrayOf("name"),
                "type = ? AND name = ?",
                arrayOf(type, name),
                null,
                null,
                null,
                "1",
            )
            cursor.moveToFirst()
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        } finally {
            cursor?.close()
        }
    }

    private fun hasCurrentEventColumns(): Boolean {
        val columns = LinkedHashSet<String>()
        var cursor: Cursor? = null
        try {
            cursor = database.rawQuery("PRAGMA table_info(vault_events)", null)
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            while (cursor.moveToNext()) columns += cursor.getString(nameIndex)
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        } finally {
            cursor?.close()
        }
        return columns == setOf("sequence_no", "event_id", "profile_id", "event_json")
    }

    private fun hasCurrentSubjectTable(): Boolean {
        val columns = LinkedHashSet<String>()
        var cursor: Cursor? = null
        try {
            cursor = database.rawQuery("PRAGMA table_info(vault_event_subjects)", null)
            val nameIndex = cursor.getColumnIndexOrThrow("name")
            while (cursor.moveToNext()) columns += cursor.getString(nameIndex)
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        } finally {
            cursor?.close()
        }
        return columns == setOf(
            "event_id",
            "subject_type",
            "subject_id",
            "subject_revision",
            "subject_ordinal",
        )
    }
}

internal fun isAcceptedJournalMode(walEnabled: Boolean, journalMode: String?): Boolean =
    !walEnabled || journalMode.equals("wal", ignoreCase = true)

private class ZeroingByteArrayOutputStream : ByteArrayOutputStream() {
    fun zeroize() {
        buf.fill(0)
        reset()
    }
}
