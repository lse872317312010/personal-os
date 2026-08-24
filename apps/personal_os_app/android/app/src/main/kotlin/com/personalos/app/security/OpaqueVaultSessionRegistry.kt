package com.personalos.app.security

import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/** In-process opaque session lifecycle; it never stores database keys or paths. */
internal class OpaqueVaultSessionRegistry(
    private val clockMillis: () -> Long = { System.currentTimeMillis() },
) {
    private data class Session(
        val expiresAt: Long,
        val database: NativeVaultDatabase,
        @Volatile var expiryTask: ScheduledFuture<*>? = null,
    )

    private val sessions = ConcurrentHashMap<String, Session>()
    private val expiryExecutor = Executors.newSingleThreadScheduledExecutor()

    fun register(id: String, ticketExpiresAt: Long, database: NativeVaultDatabase) {
        if (id.isBlank()) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        }
        if (ticketExpiresAt <= clockMillis()) {
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        }
        val session = Session(ticketExpiresAt, database)
        if (sessions.putIfAbsent(id, session) != null) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        }
        try {
            val delay = (ticketExpiresAt - clockMillis()).coerceAtLeast(1L)
            session.expiryTask = expiryExecutor.schedule(
                { expire(id, session) },
                delay,
                TimeUnit.MILLISECONDS,
            )
        } catch (_: Throwable) {
            if (sessions.remove(id, session)) {
                database.close()
            }
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
    }

    fun <T> withActive(id: String, operation: (NativeVaultDatabase) -> T): T {
        val session = sessions[id]
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        if (session.expiresAt <= clockMillis()) {
            expire(id, session)
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        }
        return operation(session.database)
    }

    fun close(id: String) {
        val session = sessions[id]
            ?: throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        if (session.expiresAt <= clockMillis()) {
            expire(id, session)
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        }
        if (!sessions.remove(id, session)) {
            throw NativeVaultFailure(NativeVaultFailureCode.VAULT_SESSION_INVALID)
        }
        session.expiryTask?.cancel(false)
        session.database.close()
    }

    fun closeAll() {
        expiryExecutor.shutdownNow()
        sessions.values.forEach { session ->
            session.expiryTask?.cancel(false)
            session.database.close()
        }
        sessions.clear()
    }

    private fun expire(id: String, expected: Session) {
        if (sessions.remove(id, expected)) {
            expected.expiryTask?.cancel(false)
            expected.database.close()
        }
    }
}
