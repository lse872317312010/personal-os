package com.personalos.app.backup

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Test

class PortableEventBackupCodecTest {
    private val codec = PortableEventBackupCodec()

    @Test
    fun roundTripEncryptsAndAuthenticatesArchiveBytes() {
        val plaintext = """{"format":"personal-os.events","schema_version":1}"""
            .toByteArray()
        val passphrase = "portable-code-2026".toCharArray()

        val encrypted = codec.encrypt(plaintext, passphrase)
        val restored = codec.decrypt(
            encrypted,
            "portable-code-2026".toCharArray(),
        )

        assertArrayEquals(plaintext, restored)
        assertFalse(encrypted.toList().containsAll(plaintext.toList()))
        restored.fill(0)
        encrypted.fill(0)
        passphrase.fill('\u0000')
    }

    @Test
    fun wrongPassphraseFailsAuthenticationWithoutPlaintext() {
        val encrypted = codec.encrypt(
            """{"format":"personal-os.events"}""".toByteArray(),
            "portable-code-2026".toCharArray(),
        )

        val failure = assertThrows(PortableEventBackupException::class.java) {
            codec.decrypt(encrypted, "different-code-2026".toCharArray())
        }

        assertEquals(
            PortableEventBackupFailureCode.AUTHENTICATION_FAILED,
            failure.failureCode,
        )
        encrypted.fill(0)
    }

    @Test
    fun tamperedCiphertextFailsAuthentication() {
        val encrypted = codec.encrypt(
            """{"format":"personal-os.events"}""".toByteArray(),
            "portable-code-2026".toCharArray(),
        )
        encrypted[encrypted.lastIndex] =
            (encrypted.last().toInt() xor 0x01).toByte()

        val failure = assertThrows(PortableEventBackupException::class.java) {
            codec.decrypt(encrypted, "portable-code-2026".toCharArray())
        }

        assertEquals(
            PortableEventBackupFailureCode.AUTHENTICATION_FAILED,
            failure.failureCode,
        )
        encrypted.fill(0)
    }

    @Test
    fun unsupportedHeaderFailsBeforeDecryption() {
        val invalid = ByteArray(64)

        val failure = assertThrows(PortableEventBackupException::class.java) {
            codec.decrypt(invalid, "portable-code-2026".toCharArray())
        }

        assertEquals(
            PortableEventBackupFailureCode.UNSUPPORTED_FORMAT,
            failure.failureCode,
        )
    }
}
