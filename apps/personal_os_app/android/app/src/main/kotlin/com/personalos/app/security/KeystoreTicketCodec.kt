package com.personalos.app.security

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.util.Base64
import java.nio.charset.StandardCharsets
import java.security.KeyStore
import java.security.SecureRandom
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.SecretKeyFactory
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey

/**
 * Issues short-lived opaque tickets authenticated by an Android Keystore key.
 *
 * The returned ticket id contains only a version, random nonce, and HMAC tag.
 * The expiry is returned as a separate value for the Dart contract. It never
 * contains key material, a database path, a native alias, or exception text.
 * The Mac is initialized before a BiometricPrompt and is usable only after
 * that prompt authenticates the user.
 */
internal class KeystoreTicketCodec(
    private val clockMillis: () -> Long = { System.currentTimeMillis() },
    private val random: SecureRandom = SecureRandom(),
) {
    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        /** One auth-per-use key keeps the derived database key stable across auth modes. */
        private const val AUTH_KEY_ALIAS = "personalos.internal.ticket.auth.v2"
        private const val TICKET_LIFETIME_MILLIS = 5 * 60 * 1000L
        private const val MAC_ALGORITHM = "HmacSHA256"
        private const val TICKET_VERSION = "v1"
        private const val DATABASE_KEY_LABEL = "personalos/internal/sqlcipher-key/v1"
    }

    internal data class Challenge(
        val nonce: String,
        val expiresAt: Long,
    )

    internal data class IssuedTicket(
        val id: String,
        val expiresAt: Long,
    )

    private data class OpenableTicket(
        val expiresAt: Long,
        val databaseKey: ByteArray,
    )

    private val openableTickets = ConcurrentHashMap<String, OpenableTicket>()
    private val expiryExecutor = Executors.newSingleThreadScheduledExecutor()

    fun prepare(): Challenge {
        val expiresAt = clockMillis() + TICKET_LIFETIME_MILLIS
        val nonce = ByteArray(32).also(random::nextBytes)
        return Challenge(encode(nonce), expiresAt)
    }

    /** Returns an auth-gated Mac. The key itself never leaves this class. */
    fun newMac(_allowDeviceCredential: Boolean): Mac {
        return try {
            Mac.getInstance(MAC_ALGORITHM).apply {
                init(signingKey())
            }
        } catch (_: NativeVaultFailure) {
            throw NativeVaultFailure(NativeVaultFailureCode.KEY_NOT_FOUND)
        } catch (_: Throwable) {
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_UNAVAILABLE)
        }
    }

    fun issue(challenge: Challenge, authenticatedMac: Mac): IssuedTicket {
        if (challenge.expiresAt <= clockMillis()) {
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        }
        val body = body(challenge)
        val tag = authenticatedMac.doFinal(body.toByteArray(StandardCharsets.UTF_8))
        val databaseKey = try {
            authenticatedMac.doFinal(DATABASE_KEY_LABEL.toByteArray(StandardCharsets.UTF_8))
        } catch (_: Throwable) {
            tag.fill(0)
            throw NativeVaultFailure(NativeVaultFailureCode.KEY_NOT_FOUND)
        }
        val issued = IssuedTicket(
            id = "$TICKET_VERSION.${challenge.nonce}.${encode(tag)}",
            expiresAt = challenge.expiresAt,
        )
        tag.fill(0)
        openableTickets[issued.id]?.databaseKey?.fill(0)
        openableTickets[issued.id] = OpenableTicket(issued.expiresAt, databaseKey)
        try {
            expiryExecutor.schedule(
                {
                    openableTickets.remove(issued.id)?.databaseKey?.fill(0)
                },
                (issued.expiresAt - clockMillis()).coerceAtLeast(1L),
                TimeUnit.MILLISECONDS,
            )
        } catch (_: Throwable) {
            openableTickets.remove(issued.id)?.databaseKey?.fill(0)
            throw NativeVaultFailure(NativeVaultFailureCode.UNAVAILABLE)
        }
        return issued
    }

    /**
     * Consumes a ticket issued by this process after a successful auth prompt.
     * The database key never enters the MethodChannel and the ticket is single-use.
     */
    fun consumeForOpen(ticketId: String, expiresAt: Long): ByteArray {
        if (ticketId.isBlank()) {
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        }
        val ticket = openableTickets.remove(ticketId)
            ?: throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        if (ticket.expiresAt != expiresAt || ticket.expiresAt <= clockMillis()) {
            ticket.databaseKey.fill(0)
            throw NativeVaultFailure(NativeVaultFailureCode.AUTHENTICATION_EXPIRED)
        }
        return ticket.databaseKey
    }

    /** Wipes all not-yet-opened database keys during channel teardown. */
    fun clear() {
        expiryExecutor.shutdownNow()
        openableTickets.values.forEach { it.databaseKey.fill(0) }
        openableTickets.clear()
    }

    /**
     * Reports whether the authenticated Keystore key is currently available.
     *
     * This is deliberately false before first unlock and on any inspection
     * failure so capability discovery cannot be used as a readiness bypass.
     */
    fun hasNonExportableKey(): Boolean {
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val key = keyStore.getKey(AUTH_KEY_ALIAS, null) as? SecretKey ?: return false
            val keyInfo = SecretKeyFactory.getInstance(key.algorithm, KEYSTORE)
                .getKeySpec(key, KeyInfo::class.java)
            keyInfo.isUserAuthenticationRequired
        } catch (_: Throwable) {
            false
        }
    }

    /** Reports the Keystore backing of an already-created ticket key only. */
    fun protectionLevel(): String {
        return try {
            val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
            val key = keyStore.getKey(AUTH_KEY_ALIAS, null) as? SecretKey ?: return "unavailable"
            val keyInfo = SecretKeyFactory.getInstance(key.algorithm, KEYSTORE)
                .getKeySpec(key, KeyInfo::class.java)
            val insideSecureHardware = if (android.os.Build.VERSION.SDK_INT >=
                android.os.Build.VERSION_CODES.S
            ) {
                val securityLevel = KeyInfo::class.java
                    .getMethod("getSecurityLevel")
                    .invoke(keyInfo) as Int
                securityLevel == KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT ||
                    securityLevel == KeyProperties.SECURITY_LEVEL_STRONGBOX ||
                    securityLevel == KeyProperties.SECURITY_LEVEL_UNKNOWN_SECURE
            } else {
                @Suppress("DEPRECATION")
                KeyInfo::class.java
                    .getMethod("isInsideSecureHardware")
                    .invoke(keyInfo) as Boolean
            }
            if (insideSecureHardware) "trustedEnvironment" else "software"
        } catch (_: Throwable) {
            "unavailable"
        }
    }

    private fun body(challenge: Challenge): String =
        "$TICKET_VERSION.${challenge.expiresAt}.${challenge.nonce}"

    private fun signingKey(): SecretKey {
        val alias = AUTH_KEY_ALIAS
        val keyStore = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (keyStore.getKey(alias, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_HMAC_SHA256, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_SIGN,
            ).setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(true)
                .apply {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                        // The key is shared by both prompt modes so the database key is
                        // stable. The prompt still controls which authenticator is allowed
                        // for this individual authentication request.
                        val authenticators = KeyProperties.AUTH_BIOMETRIC_STRONG or
                            KeyProperties.AUTH_DEVICE_CREDENTIAL
                        setUserAuthenticationParameters(0, authenticators)
                    } else {
                        @Suppress("DEPRECATION")
                        setUserAuthenticationValidityDurationSeconds(-1)
                    }
                }
                .build(),
        )
        return generator.generateKey()
    }

    private fun encode(value: ByteArray): String =
        Base64.encodeToString(value, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)

}
