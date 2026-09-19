package com.personalos.app.backup

import android.content.ContentResolver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultLauncher
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

internal class PortableEventBackupChannel(
    private val activity: FragmentActivity,
    private val contentResolver: ContentResolver,
    private val createDocument: ActivityResultLauncher<String>,
    private val openDocument: ActivityResultLauncher<Array<String>>,
    private val isVaultActive: () -> Boolean,
    private val prompt: NativeBackupPassphrasePrompt =
        AndroidNativeBackupPassphrasePrompt(activity),
    private val codec: PortableEventBackupCodec = PortableEventBackupCodec(),
    private val executor: ExecutorService = Executors.newSingleThreadExecutor(),
) : MethodChannel.MethodCallHandler {
    private enum class State {
        EXPORT_PASSPHRASE,
        EXPORT_DOCUMENT,
        EXPORT_WRITE,
        IMPORT_DOCUMENT,
        IMPORT_PASSPHRASE,
        IMPORT_READ,
    }

    private val main = Handler(Looper.getMainLooper())
    private var state: State? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingEncrypted: ByteArray? = null
    private var pendingImportUri: Uri? = null
    private var generation = 0
    private var disposed = false

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            fail(result, BackupFailure.UNAVAILABLE)
            return
        }
        when (call.method) {
            METHOD_EXPORT -> beginExport(call, result)
            METHOD_IMPORT -> beginImport(result)
            else -> fail(result, BackupFailure.UNAVAILABLE)
        }
    }

    private fun beginExport(call: MethodCall, result: MethodChannel.Result) {
        if (!begin(result, State.EXPORT_PASSPHRASE)) return
        val arguments = call.arguments as? Map<*, *>
        val archive = arguments?.get(KEY_ARCHIVE_JSON) as? String
        val suggestedName = arguments?.get(KEY_SUGGESTED_NAME) as? String
        if (archive.isNullOrEmpty() || suggestedName == null) {
            finishFailure(BackupFailure.INVALID_REQUEST)
            return
        }
        val plaintext = archive.toByteArray(StandardCharsets.UTF_8)
        if (plaintext.size > PortableEventBackupCodec.MAX_PLAINTEXT_BYTES) {
            plaintext.fill(0)
            finishFailure(BackupFailure.TOO_LARGE)
            return
        }
        val safeName = safeFileName(suggestedName)
        val operation = generation
        prompt.requestForExport { passphrase ->
            if (!isCurrent(operation, State.EXPORT_PASSPHRASE)) {
                passphrase?.fill('\u0000')
                plaintext.fill(0)
                return@requestForExport
            }
            if (passphrase == null) {
                plaintext.fill(0)
                finishCancelled()
                return@requestForExport
            }
            try {
                executor.execute {
                    try {
                        val encrypted = codec.encrypt(plaintext, passphrase)
                        main.post {
                            if (!isCurrent(operation, State.EXPORT_PASSPHRASE)) {
                                encrypted.fill(0)
                                return@post
                            }
                            pendingEncrypted = encrypted
                            state = State.EXPORT_DOCUMENT
                            try {
                                createDocument.launch(safeName)
                            } catch (_: Throwable) {
                                finishFailure(BackupFailure.IO_FAILED)
                            }
                        }
                    } catch (failure: PortableEventBackupException) {
                        main.post {
                            if (isCurrent(operation, State.EXPORT_PASSPHRASE)) {
                                finishFailure(BackupFailure.from(failure))
                            }
                        }
                    } catch (_: Throwable) {
                        main.post {
                            if (isCurrent(operation, State.EXPORT_PASSPHRASE)) {
                                finishFailure(BackupFailure.CRYPTO_FAILED)
                            }
                        }
                    } finally {
                        plaintext.fill(0)
                        passphrase.fill('\u0000')
                    }
                }
            } catch (_: RejectedExecutionException) {
                plaintext.fill(0)
                passphrase.fill('\u0000')
                finishFailure(BackupFailure.UNAVAILABLE)
            }
        }
    }

    private fun beginImport(result: MethodChannel.Result) {
        if (!begin(result, State.IMPORT_DOCUMENT)) return
        try {
            openDocument.launch(arrayOf("*/*"))
        } catch (_: Throwable) {
            finishFailure(BackupFailure.IO_FAILED)
        }
    }

    fun onDocumentCreated(uri: Uri?) {
        if (state != State.EXPORT_DOCUMENT) return
        if (uri == null) {
            finishCancelled()
            return
        }
        val encrypted = pendingEncrypted
        pendingEncrypted = null
        if (encrypted == null) {
            finishFailure(BackupFailure.INVALID_REQUEST)
            return
        }
        state = State.EXPORT_WRITE
        val operation = generation
        try {
            executor.execute {
                try {
                    contentResolver.openOutputStream(uri, "w")?.use { output ->
                        output.write(encrypted)
                        output.flush()
                    } ?: throw IOException("output unavailable")
                    main.post {
                        if (isCurrent(operation, State.EXPORT_WRITE)) {
                            finishSuccess(mapOf(KEY_STATUS to STATUS_COMPLETED))
                        }
                    }
                } catch (_: Throwable) {
                    main.post {
                        if (isCurrent(operation, State.EXPORT_WRITE)) {
                            finishFailure(BackupFailure.IO_FAILED)
                        }
                    }
                } finally {
                    encrypted.fill(0)
                }
            }
        } catch (_: RejectedExecutionException) {
            encrypted.fill(0)
            finishFailure(BackupFailure.UNAVAILABLE)
        }
    }

    fun onDocumentOpened(uri: Uri?) {
        if (state != State.IMPORT_DOCUMENT) return
        if (uri == null) {
            finishCancelled()
            return
        }
        pendingImportUri = uri
        state = State.IMPORT_PASSPHRASE
        val operation = generation
        prompt.requestForImport { passphrase ->
            if (!isCurrent(operation, State.IMPORT_PASSPHRASE)) {
                passphrase?.fill('\u0000')
                return@requestForImport
            }
            if (passphrase == null) {
                finishCancelled()
                return@requestForImport
            }
            val selected = pendingImportUri
            pendingImportUri = null
            if (selected == null) {
                passphrase.fill('\u0000')
                finishFailure(BackupFailure.INVALID_REQUEST)
                return@requestForImport
            }
            state = State.IMPORT_READ
            try {
                executor.execute {
                    var encrypted: ByteArray? = null
                    var plaintext: ByteArray? = null
                    try {
                        encrypted = readBounded(selected)
                        plaintext = codec.decrypt(encrypted, passphrase)
                        val archive = String(plaintext, StandardCharsets.UTF_8)
                        main.post {
                            if (isCurrent(operation, State.IMPORT_READ)) {
                                finishSuccess(
                                    mapOf(
                                        KEY_STATUS to STATUS_COMPLETED,
                                        KEY_ARCHIVE_JSON to archive,
                                    ),
                                )
                            }
                        }
                    } catch (failure: PortableEventBackupException) {
                        main.post {
                            if (isCurrent(operation, State.IMPORT_READ)) {
                                finishFailure(BackupFailure.from(failure))
                            }
                        }
                    } catch (_: IOException) {
                        main.post {
                            if (isCurrent(operation, State.IMPORT_READ)) {
                                finishFailure(BackupFailure.IO_FAILED)
                            }
                        }
                    } catch (_: Throwable) {
                        main.post {
                            if (isCurrent(operation, State.IMPORT_READ)) {
                                finishFailure(BackupFailure.CRYPTO_FAILED)
                            }
                        }
                    } finally {
                        encrypted?.fill(0)
                        plaintext?.fill(0)
                        passphrase.fill('\u0000')
                    }
                }
            } catch (_: RejectedExecutionException) {
                passphrase.fill('\u0000')
                finishFailure(BackupFailure.UNAVAILABLE)
            }
        }
    }

    fun onVaultInvalidated() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            cancelActive()
        } else {
            main.post(::cancelActive)
        }
    }

    fun dispose() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            disposeOnMain()
        } else {
            main.post(::disposeOnMain)
        }
    }

    private fun begin(result: MethodChannel.Result, nextState: State): Boolean {
        if (pendingResult != null) {
            fail(result, BackupFailure.BUSY)
            return false
        }
        val active = try {
            isVaultActive()
        } catch (_: Throwable) {
            false
        }
        if (!active) {
            fail(result, BackupFailure.VAULT_LOCKED)
            return false
        }
        generation += 1
        pendingResult = result
        state = nextState
        return true
    }

    private fun isCurrent(operation: Int, expected: State): Boolean =
        !disposed && generation == operation && state == expected &&
            pendingResult != null

    private fun readBounded(uri: Uri): ByteArray {
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("input unavailable")
        input.use {
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(8192)
            try {
                while (true) {
                    val count = it.read(buffer)
                    if (count < 0) break
                    if (output.size() + count >
                        PortableEventBackupCodec.MAX_ENCRYPTED_BYTES
                    ) {
                        throw PortableEventBackupException(
                            PortableEventBackupFailureCode.TOO_LARGE,
                        )
                    }
                    output.write(buffer, 0, count)
                }
                return output.toByteArray()
            } finally {
                buffer.fill(0)
            }
        }
    }

    private fun safeFileName(value: String): String {
        val candidate = value
            .take(MAX_FILE_NAME_LENGTH)
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trim('.', '_')
        val base = candidate.ifEmpty { DEFAULT_FILE_NAME }
        return if (base.endsWith(FILE_EXTENSION)) base else "$base$FILE_EXTENSION"
    }

    private fun finishCancelled() {
        finishSuccess(mapOf(KEY_STATUS to STATUS_CANCELLED))
    }

    private fun finishSuccess(value: Map<String, Any?>) {
        val result = clearPending()
        result?.success(value)
    }

    private fun finishFailure(failure: BackupFailure) {
        val result = clearPending()
        if (result != null) fail(result, failure)
    }

    private fun clearPending(): MethodChannel.Result? {
        val result = pendingResult
        pendingResult = null
        state = null
        pendingImportUri = null
        pendingEncrypted?.fill(0)
        pendingEncrypted = null
        return result
    }

    private fun cancelActive() {
        prompt.dispose()
        val result = clearPending()
        generation += 1
        result?.success(mapOf(KEY_STATUS to STATUS_CANCELLED))
    }

    private fun disposeOnMain() {
        if (disposed) return
        disposed = true
        cancelActive()
        executor.shutdownNow()
    }

    private fun fail(result: MethodChannel.Result, failure: BackupFailure) {
        result.error(failure.code, failure.message, null)
    }

    private enum class BackupFailure(val code: String, val message: String) {
        BUSY("backup.busy", "Another backup operation is already running."),
        VAULT_LOCKED("backup.vault_locked", "The vault is locked."),
        INVALID_REQUEST("backup.invalid_request", "The backup request is invalid."),
        TOO_LARGE("backup.too_large", "The backup exceeds the supported size."),
        UNSUPPORTED_FORMAT("backup.unsupported_format", "The backup format is unsupported."),
        AUTHENTICATION_FAILED(
            "backup.authentication_failed",
            "The backup could not be authenticated.",
        ),
        CRYPTO_FAILED("backup.crypto_failed", "The backup cryptography failed."),
        IO_FAILED("backup.io_failed", "The backup file operation failed."),
        UNAVAILABLE("backup.unavailable", "Encrypted backup is unavailable.");

        companion object {
            fun from(failure: PortableEventBackupException): BackupFailure =
                when (failure.failureCode) {
                    PortableEventBackupFailureCode.INVALID_REQUEST -> INVALID_REQUEST
                    PortableEventBackupFailureCode.TOO_LARGE -> TOO_LARGE
                    PortableEventBackupFailureCode.UNSUPPORTED_FORMAT ->
                        UNSUPPORTED_FORMAT
                    PortableEventBackupFailureCode.AUTHENTICATION_FAILED ->
                        AUTHENTICATION_FAILED
                    PortableEventBackupFailureCode.CRYPTO_FAILED -> CRYPTO_FAILED
                }
        }
    }

    companion object {
        const val CHANNEL_NAME = "personal_os/internal/event_backup"
        private const val METHOD_EXPORT = "exportEncryptedArchive"
        private const val METHOD_IMPORT = "importEncryptedArchive"
        private const val KEY_ARCHIVE_JSON = "archiveJson"
        private const val KEY_SUGGESTED_NAME = "suggestedName"
        private const val KEY_STATUS = "status"
        private const val STATUS_COMPLETED = "completed"
        private const val STATUS_CANCELLED = "cancelled"
        private const val FILE_EXTENSION = ".posb"
        private const val DEFAULT_FILE_NAME = "personal-os-backup.posb"
        private const val MAX_FILE_NAME_LENGTH = 80
    }
}
