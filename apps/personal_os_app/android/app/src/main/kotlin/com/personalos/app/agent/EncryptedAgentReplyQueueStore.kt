package com.personalos.app.agent

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction
import java.security.GeneralSecurityException
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class AgentReplyQueueSnapshot(
    val replies: List<String> = emptyList(),
    val droppedReplyCount: Int = 0,
)

internal interface AgentReplyQueueStore {
    @Throws(Exception::class)
    fun read(): AgentReplyQueueSnapshot

    @Throws(Exception::class)
    fun write(snapshot: AgentReplyQueueSnapshot)
}

/** Stores transient inbound replies as authenticated ciphertext outside Android backup. */
internal class EncryptedAgentReplyQueueStore(context: Context) : AgentReplyQueueStore {
    private val atomicFile = AtomicFile(
        File(context.applicationContext.noBackupFilesDir, FILE_NAME),
    )

    @Synchronized
    override fun read(): AgentReplyQueueSnapshot {
        val input = try {
            // openRead also restores AtomicFile's last-good backup after an
            // interrupted write; checking baseFile first would skip that path.
            atomicFile.openRead()
        } catch (_: FileNotFoundException) {
            if (hasQueueFiles()) {
                throw IOException("Unable to read the encrypted reply queue.")
            }
            return AgentReplyQueueSnapshot()
        }
        val encryptedFile = input.use { source ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8 * 1024)
            var totalBytes = 0
            while (true) {
                val read = source.read(buffer)
                if (read < 0) break
                totalBytes += read
                if (totalBytes > MAX_FILE_BYTES) {
                    throw IOException("Invalid encrypted reply queue size.")
                }
                output.write(buffer, 0, read)
            }
            output.toByteArray()
        }
        if (encryptedFile.size !in MIN_FILE_BYTES..MAX_FILE_BYTES) {
            throw IOException("Invalid encrypted reply queue size.")
        }
        if (!encryptedFile.copyOfRange(0, MAGIC.size).contentEquals(MAGIC) ||
            encryptedFile[MAGIC.size] != FORMAT_VERSION
        ) {
            throw IOException("Invalid encrypted reply queue header.")
        }

        val key = existingKey()
            ?: throw GeneralSecurityException("Reply queue key is unavailable.")
        val nonceStart = MAGIC.size + VERSION_BYTES
        val nonce = encryptedFile.copyOfRange(nonceStart, nonceStart + NONCE_BYTES)
        val ciphertextStart = nonceStart + NONCE_BYTES
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, nonce))
        cipher.updateAAD(AAD)
        val plaintext = cipher.doFinal(
            encryptedFile,
            ciphertextStart,
            encryptedFile.size - ciphertextStart,
        )
        return try {
            decodeSnapshot(plaintext)
        } finally {
            plaintext.fill(0)
        }
    }

    @Synchronized
    override fun write(snapshot: AgentReplyQueueSnapshot) {
        require(snapshot.droppedReplyCount >= 0) { "Invalid dropped reply count." }
        if (snapshot.replies.isEmpty() && snapshot.droppedReplyCount == 0) {
            deleteQueueFile()
            return
        }

        val plaintext = encodeSnapshot(snapshot)
        val encryptedFile = try {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, keyForWrite())
            cipher.updateAAD(AAD)
            val ciphertext = cipher.doFinal(plaintext)
            ByteArrayOutputStream(MAGIC.size + VERSION_BYTES + NONCE_BYTES + ciphertext.size)
                .apply {
                    write(MAGIC)
                    write(FORMAT_VERSION.toInt())
                    write(cipher.iv)
                    write(ciphertext)
                }
                .toByteArray()
        } finally {
            plaintext.fill(0)
        }

        val output = atomicFile.startWrite()
        try {
            output.write(encryptedFile)
            output.fd.sync()
            atomicFile.finishWrite(output)
        } catch (error: Exception) {
            atomicFile.failWrite(output)
            throw IOException("Unable to persist encrypted reply queue.", error)
        }
    }

    private fun existingKey(): SecretKey? {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        return keyStore.getKey(KEY_ALIAS, null) as? SecretKey
    }

    private fun deleteQueueFile() {
        atomicFile.delete()
        if (hasQueueFiles()) {
            throw IOException("Unable to remove the acknowledged reply queue.")
        }
    }

    private fun hasQueueFiles(): Boolean {
        val baseFile = atomicFile.baseFile
        return baseFile.exists() || File("${baseFile.path}.bak").exists() ||
            File("${baseFile.path}.new").exists()
    }

    private fun keyForWrite(): SecretKey = existingKey() ?: run {
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KEY_BITS)
                .setRandomizedEncryptionRequired(true)
                .build(),
        )
        generator.generateKey()
    }

    private fun encodeSnapshot(snapshot: AgentReplyQueueSnapshot): ByteArray {
        require(snapshot.droppedReplyCount >= 0) { "Invalid dropped reply count." }
        require(snapshot.replies.size <= AgentReplyReceiveChannel.MAX_PENDING_REPLIES) {
            "Too many persisted replies."
        }

        val encodedReplies = ArrayList<ByteArray>(snapshot.replies.size)
        try {
            snapshot.replies.forEach { reply ->
                require(reply.isNotBlank()) { "Blank replies cannot be persisted." }
                val bytes = reply.toByteArray(Charsets.UTF_8)
                if (bytes.size > AgentReplyReceiveChannel.MAX_TEXT_BYTES) {
                    bytes.fill(0)
                    throw IllegalArgumentException("Persisted reply exceeds the size limit.")
                }
                encodedReplies.add(bytes)
            }
            val totalBytes = encodedReplies.sumOf { it.size }
            require(totalBytes <= AgentReplyReceiveChannel.MAX_PENDING_BYTES) {
                "Persisted replies exceed the aggregate size limit."
            }

            val output = ByteBuffer.allocate(
                SNAPSHOT_HEADER_BYTES + encodedReplies.size * REPLY_LENGTH_BYTES + totalBytes,
            ).order(ByteOrder.BIG_ENDIAN)
            output.putInt(snapshot.droppedReplyCount)
            output.putInt(encodedReplies.size)
            encodedReplies.forEach { reply ->
                output.putInt(reply.size)
                output.put(reply)
            }
            return output.array()
        } finally {
            encodedReplies.forEach { it.fill(0) }
        }
    }

    private fun decodeSnapshot(plaintext: ByteArray): AgentReplyQueueSnapshot {
        if (plaintext.size < SNAPSHOT_HEADER_BYTES || plaintext.size > MAX_PLAINTEXT_BYTES) {
            throw IOException("Invalid encrypted reply queue payload size.")
        }

        val input = ByteBuffer.wrap(plaintext).order(ByteOrder.BIG_ENDIAN)
        val droppedCount = input.int
        val replyCount = input.int
        if (droppedCount < 0 || replyCount !in 0..AgentReplyReceiveChannel.MAX_PENDING_REPLIES) {
            throw IOException("Invalid encrypted reply queue metadata.")
        }

        val replies = ArrayList<String>(replyCount)
        var totalBytes = 0
        repeat(replyCount) {
            if (input.remaining() < REPLY_LENGTH_BYTES) {
                throw IOException("Truncated encrypted reply queue entry.")
            }
            val length = input.int
            if (length !in 1..AgentReplyReceiveChannel.MAX_TEXT_BYTES ||
                length > input.remaining()
            ) {
                throw IOException("Invalid encrypted reply queue entry size.")
            }
            totalBytes += length
            if (totalBytes > AgentReplyReceiveChannel.MAX_PENDING_BYTES) {
                throw IOException("Encrypted reply queue exceeds its size limit.")
            }

            val bytes = ByteArray(length)
            input.get(bytes)
            val reply = try {
                Charsets.UTF_8.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString()
            } catch (error: Exception) {
                throw IOException("Invalid UTF-8 in encrypted reply queue.", error)
            } finally {
                bytes.fill(0)
            }
            if (reply.isBlank()) throw IOException("Blank reply in encrypted reply queue.")
            replies.add(reply)
        }
        if (input.hasRemaining()) throw IOException("Unexpected encrypted reply queue data.")
        return AgentReplyQueueSnapshot(replies, droppedCount)
    }

    companion object {
        const val FILE_NAME = "agent-reply-queue.enc"
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "personal_os_agent_reply_queue_v1"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val KEY_BITS = 256
        private const val TAG_BITS = 128
        private const val TAG_BYTES = TAG_BITS / 8
        private const val NONCE_BYTES = 12
        private const val VERSION_BYTES = 1
        private const val SNAPSHOT_HEADER_BYTES = 8
        private const val REPLY_LENGTH_BYTES = 4
        private const val MAX_PLAINTEXT_BYTES =
            SNAPSHOT_HEADER_BYTES + AgentReplyReceiveChannel.MAX_PENDING_BYTES +
                AgentReplyReceiveChannel.MAX_PENDING_REPLIES * REPLY_LENGTH_BYTES
        private const val MIN_FILE_BYTES =
            MAGIC_SIZE + VERSION_BYTES + NONCE_BYTES + TAG_BYTES + SNAPSHOT_HEADER_BYTES
        private const val MAX_FILE_BYTES =
            MAGIC_SIZE + VERSION_BYTES + NONCE_BYTES + TAG_BYTES + MAX_PLAINTEXT_BYTES
        private const val MAGIC_SIZE = 4
        private val MAGIC = byteArrayOf(0x50, 0x4f, 0x41, 0x52)
        private val FORMAT_VERSION = 1.toByte()
        private val AAD = MAGIC + FORMAT_VERSION
    }
}
