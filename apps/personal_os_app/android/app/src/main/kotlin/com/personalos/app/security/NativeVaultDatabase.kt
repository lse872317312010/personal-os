package com.personalos.app.security

import android.content.Context
import android.database.Cursor
import net.zetetic.database.sqlcipher.SQLiteDatabase
import org.json.JSONObject

/** The only database API exposed to the native channel facade. */
internal interface NativeVaultDatabase : AutoCloseable {
    fun appendEvents(events: List<NativeEventRecord>)

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
        private const val SCHEMA_VERSION = 2

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
        if (!database.enableWriteAheadLogging()) {
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
        if (readPragmaText("journal_mode") != "wal") {
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
                    validateEventJson(event.eventJson)

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

    private fun validateEventJson(eventJson: String) {
        if (eventJson.isBlank() || eventJson.length > MAX_EVENT_JSON_LENGTH) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_EVENT_INVALID)
        }
        try {
            // Parse at the boundary so malformed JSON can never become an
            // idempotent retry or be persisted for a later comparison.
            JSONObject(eventJson)
        } catch (_: Throwable) {
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
            existing.similar(incoming)
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
            database.execSQL("PRAGMA user_version = $SCHEMA_VERSION")
            return
        }

        // The previous bridge schema split the envelope into columns and cannot
        // losslessly produce a strict EventEnvelope JSON. No implicit migration
        // or data guessing is permitted.
        if (version != SCHEMA_VERSION || !hasCurrentEventColumns() ||
            !hasCurrentSubjectTable() || !indexExists("vault_event_subject_lookup_idx")) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        }
        if (!indexExists("vault_events_profile_order_idx")) {
            throw NativeVaultFailure(NativeVaultFailureCode.SCHEMA_INVALID)
        }
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
