package com.personalos.app.backup

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.GeneralSecurityException
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec

internal class PortableEventBackupException(
    val failureCode: PortableEventBackupFailureCode,
) : Exception()

internal enum class PortableEventBackupFailureCode(
    val wireValue: String,
    val safeMessage: String,
) {
    INVALID_REQUEST("backup.invalid_request", "The backup request is invalid."),
    TOO_LARGE("backup.too_large", "The backup exceeds the supported size."),
    UNSUPPORTED_FORMAT("backup.unsupported_format", "The backup format is unsupported."),
    AUTHENTICATION_FAILED(
        "backup.authentication_failed",
        "The backup could not be authenticated.",
    ),
    CRYPTO_FAILED("backup.crypto_failed", "The backup cryptography failed."),
}

internal class PortableEventBackupCodec(
    private val random: SecureRandom = SecureRandom(),
) {
    fun encrypt(plaintext: ByteArray, passphrase: CharArray): ByteArray {
        validatePlaintext(plaintext)
        validatePassphrase(passphrase)
        val salt = ByteArray(SALT_BYTES).also(random::nextBytes)
        val nonce = ByteArray(NONCE_BYTES).also(random::nextBytes)
        val header = ByteBuffer.allocate(HEADER_BYTES)
            .order(ByteOrder.BIG_ENDIAN)
            .put(MAGIC)
            .put(VERSION)
            .putInt(PBKDF2_ITERATIONS)
            .put(salt)
            .put(nonce)
            .array()
        val key = deriveKey(passphrase, salt, PBKDF2_ITERATIONS)
        try {
            val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
            cipher.init(
                Cipher.ENCRYPT_MODE,
                SecretKeySpec(key, KEY_ALGORITHM),
                GCMParameterSpec(GCM_TAG_BITS, nonce),
            )
            cipher.updateAAD(header)
            val ciphertext = cipher.doFinal(plaintext)
            if (header.size + ciphertext.size > MAX_ENCRYPTED_BYTES) {
                ciphertext.fill(0)
                throw PortableEventBackupException(
                    PortableEventBackupFailureCode.TOO_LARGE,
                )
            }
            return header + ciphertext
        } catch (failure: PortableEventBackupException) {
            throw failure
        } catch (_: GeneralSecurityException) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.CRYPTO_FAILED,
            )
        } finally {
            key.fill(0)
        }
    }

    fun decrypt(encrypted: ByteArray, passphrase: CharArray): ByteArray {
        validatePassphrase(passphrase)
        if (encrypted.size !in MIN_ENCRYPTED_BYTES..MAX_ENCRYPTED_BYTES) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.UNSUPPORTED_FORMAT,
            )
        }
        val input = ByteBuffer.wrap(encrypted).order(ByteOrder.BIG_ENDIAN)
        val magic = ByteArray(MAGIC.size).also(input::get)
        if (!MessageDigest.isEqual(magic, MAGIC) || input.get() != VERSION) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.UNSUPPORTED_FORMAT,
            )
        }
        val iterations = input.int
        if (iterations != PBKDF2_ITERATIONS) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.UNSUPPORTED_FORMAT,
            )
        }
        val salt = ByteArray(SALT_BYTES).also(input::get)
        val nonce = ByteArray(NONCE_BYTES).also(input::get)
        val ciphertext = ByteArray(input.remaining()).also(input::get)
        val header = encrypted.copyOfRange(0, HEADER_BYTES)
        val key = deriveKey(passphrase, salt, iterations)
        try {
            val cipher = Cipher.getInstance(CIPHER_TRANSFORMATION)
            cipher.init(
                Cipher.DECRYPT_MODE,
                SecretKeySpec(key, KEY_ALGORITHM),
                GCMParameterSpec(GCM_TAG_BITS, nonce),
            )
            cipher.updateAAD(header)
            val plaintext = cipher.doFinal(ciphertext)
            if (plaintext.isEmpty() || plaintext.size > MAX_PLAINTEXT_BYTES) {
                plaintext.fill(0)
                throw PortableEventBackupException(
                    PortableEventBackupFailureCode.TOO_LARGE,
                )
            }
            return plaintext
        } catch (_: AEADBadTagException) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.AUTHENTICATION_FAILED,
            )
        } catch (failure: PortableEventBackupException) {
            throw failure
        } catch (_: GeneralSecurityException) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.CRYPTO_FAILED,
            )
        } finally {
            key.fill(0)
            ciphertext.fill(0)
            header.fill(0)
        }
    }

    private fun deriveKey(
        passphrase: CharArray,
        salt: ByteArray,
        iterations: Int,
    ): ByteArray {
        val spec = PBEKeySpec(passphrase, salt, iterations, KEY_BITS)
        return try {
            SecretKeyFactory.getInstance(KDF_ALGORITHM)
                .generateSecret(spec)
                .encoded
        } catch (_: GeneralSecurityException) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.CRYPTO_FAILED,
            )
        } finally {
            spec.clearPassword()
        }
    }

    private fun validatePlaintext(plaintext: ByteArray) {
        if (plaintext.isEmpty()) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.INVALID_REQUEST,
            )
        }
        if (plaintext.size > MAX_PLAINTEXT_BYTES) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.TOO_LARGE,
            )
        }
    }

    private fun validatePassphrase(passphrase: CharArray) {
        if (passphrase.size !in MIN_PASSPHRASE_LENGTH..MAX_PASSPHRASE_LENGTH ||
            passphrase.none { !it.isWhitespace() }
        ) {
            throw PortableEventBackupException(
                PortableEventBackupFailureCode.INVALID_REQUEST,
            )
        }
    }

    companion object {
        private val MAGIC = byteArrayOf(0x50, 0x4f, 0x53, 0x42)
        private const val VERSION: Byte = 1
        private const val PBKDF2_ITERATIONS = 210_000
        private const val SALT_BYTES = 16
        private const val NONCE_BYTES = 12
        private const val GCM_TAG_BITS = 128
        private const val GCM_TAG_BYTES = GCM_TAG_BITS / 8
        private const val KEY_BITS = 256
        private const val KEY_ALGORITHM = "AES"
        private const val KDF_ALGORITHM = "PBKDF2WithHmacSHA256"
        private const val CIPHER_TRANSFORMATION = "AES/GCM/NoPadding"
        private const val HEADER_BYTES = 4 + 1 + 4 + SALT_BYTES + NONCE_BYTES
        private const val MIN_ENCRYPTED_BYTES = HEADER_BYTES + GCM_TAG_BYTES + 1
        const val MAX_PLAINTEXT_BYTES = 16 * 1024 * 1024
        const val MAX_ENCRYPTED_BYTES =
            HEADER_BYTES + MAX_PLAINTEXT_BYTES + GCM_TAG_BYTES
        const val MIN_PASSPHRASE_LENGTH = 12
        const val MAX_PASSPHRASE_LENGTH = 128
    }
}
