package com.personalos.app.agent

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EncryptedAgentReplyQueueStoreTest {
    private val context
        get() = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext

    @Test
    fun encryptedQueueSurvivesStoreRecreationAndDeletesAfterFinalAcknowledge() {
        val file = queueFile()
        val first = EncryptedAgentReplyQueueStore(context)
        val expected = AgentReplyQueueSnapshot(
            replies = listOf("private reply marker 7b3e1d", "second reply"),
            droppedReplyCount = 3,
        )

        first.write(expected)

        val ciphertext = file.readBytes()
        assertFalse(String(ciphertext, Charsets.ISO_8859_1).contains("private reply marker"))
        assertEquals(expected, EncryptedAgentReplyQueueStore(context).read())

        val afterFirstAcknowledge = AgentReplyQueueSnapshot(
            replies = listOf("second reply"),
            droppedReplyCount = 0,
        )
        EncryptedAgentReplyQueueStore(context).write(afterFirstAcknowledge)
        assertEquals(afterFirstAcknowledge, EncryptedAgentReplyQueueStore(context).read())

        EncryptedAgentReplyQueueStore(context).write(AgentReplyQueueSnapshot())
        assertFalse(file.exists())
        assertEquals(AgentReplyQueueSnapshot(), EncryptedAgentReplyQueueStore(context).read())
    }

    @Test
    fun modifiedCiphertextIsRejectedAndLeftForRecovery() {
        val file = queueFile()
        val store = EncryptedAgentReplyQueueStore(context)
        store.write(AgentReplyQueueSnapshot(listOf("tamper check reply")))
        val ciphertext = file.readBytes()
        ciphertext[ciphertext.lastIndex] = (ciphertext.last().toInt() xor 0x01).toByte()
        file.writeBytes(ciphertext)

        var rejected = false
        try {
            EncryptedAgentReplyQueueStore(context).read()
        } catch (_: Exception) {
            rejected = true
        }
        assertTrue(rejected)
        assertTrue(file.exists())

        store.write(AgentReplyQueueSnapshot())
    }

    private fun queueFile(): File =
        File(context.noBackupFilesDir, EncryptedAgentReplyQueueStore.FILE_NAME)
            .also { it.delete() }
}
