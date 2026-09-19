package com.personalos.app.backup

import android.app.AlertDialog
import android.os.Build
import android.os.Looper
import android.text.InputFilter
import android.text.InputType
import android.text.TextUtils
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.widget.EditText
import android.widget.LinearLayout
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.atomic.AtomicBoolean

internal interface NativeBackupPassphrasePrompt {
    fun requestForExport(callback: (CharArray?) -> Unit)
    fun requestForImport(callback: (CharArray?) -> Unit)
    fun dispose()
}

/** Native-only passphrase entry. No passphrase value crosses Flutter. */
internal class AndroidNativeBackupPassphrasePrompt(
    private val activity: FragmentActivity,
) : NativeBackupPassphrasePrompt {
    private var activeDialog: AlertDialog? = null
    private var activeInputs: List<EditText> = emptyList()

    override fun requestForExport(callback: (CharArray?) -> Unit) {
        request(
            title = "设置备份口令",
            message = "至少 12 个字符。恢复此备份时必须输入相同口令。",
            confirm = true,
            callback = callback,
        )
    }

    override fun requestForImport(callback: (CharArray?) -> Unit) {
        request(
            title = "输入备份口令",
            message = "口令仅用于本次原生解密，不会发送给 Flutter 或写入磁盘。",
            confirm = false,
            callback = callback,
        )
    }

    private fun request(
        title: String,
        message: String,
        confirm: Boolean,
        callback: (CharArray?) -> Unit,
    ) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (activity.isFinishing || activity.isDestroyed) {
            callback(null)
            return
        }
        dispose()
        val first = secureInput("备份口令")
        val second = if (confirm) secureInput("再次输入") else null
        val inputs = listOfNotNull(first, second)
        val container = LinearLayout(activity).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, 0, padding, 0)
            inputs.forEach(::addView)
        }
        val completed = AtomicBoolean(false)
        lateinit var dialog: AlertDialog

        fun complete(ownedPassphrase: CharArray?) {
            if (!completed.compareAndSet(false, true)) {
                ownedPassphrase?.fill('\u0000')
                return
            }
            inputs.forEach(::clearInput)
            if (activeDialog === dialog) {
                activeDialog = null
                activeInputs = emptyList()
            }
            callback(ownedPassphrase)
        }

        dialog = AlertDialog.Builder(activity)
            .setTitle(title)
            .setMessage(message)
            .setView(container)
            .setPositiveButton(if (confirm) "加密并选择位置" else "解密") { _, _ -> }
            .setNegativeButton("取消") { _, _ -> complete(null) }
            .setOnCancelListener { complete(null) }
            .create()
        dialog.setOnShowListener {
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val passphrase = extractAndClear(first)
                val confirmation = second?.let(::extractAndClear)
                val validLength =
                    passphrase.size in PortableEventBackupCodec.MIN_PASSPHRASE_LENGTH..
                        PortableEventBackupCodec.MAX_PASSPHRASE_LENGTH
                val matches = confirmation == null ||
                    constantTimeEquals(passphrase, confirmation)
                confirmation?.fill('\u0000')
                if (!validLength || passphrase.none { !it.isWhitespace() }) {
                    passphrase.fill('\u0000')
                    first.error = "口令至少需要 12 个字符"
                    return@setOnClickListener
                }
                if (!matches) {
                    passphrase.fill('\u0000')
                    second?.error = "两次输入不一致"
                    return@setOnClickListener
                }
                complete(passphrase)
                dialog.dismiss()
            }
        }
        dialog.setOnDismissListener { complete(null) }
        activeDialog = dialog
        activeInputs = inputs
        dialog.show()
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun dispose() {
        val inputs = activeInputs
        activeInputs = emptyList()
        inputs.forEach(::clearInput)
        val dialog = activeDialog
        activeDialog = null
        dialog?.dismiss()
    }

    private fun secureInput(label: String): EditText = EditText(activity).apply {
        hint = label
        inputType = InputType.TYPE_CLASS_TEXT or
            InputType.TYPE_TEXT_VARIATION_PASSWORD
        imeOptions = EditorInfo.IME_ACTION_DONE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        filters = arrayOf(
            InputFilter.LengthFilter(
                PortableEventBackupCodec.MAX_PASSPHRASE_LENGTH,
            ),
        )
        filterTouchesWhenObscured = true
        isSingleLine = true
    }

    private fun extractAndClear(input: EditText): CharArray {
        val editable = input.text
        val owned = CharArray(editable.length)
        TextUtils.getChars(editable, 0, editable.length, owned, 0)
        editable.clear()
        return owned
    }

    private fun clearInput(input: EditText) {
        input.text?.clear()
    }

    private fun constantTimeEquals(left: CharArray, right: CharArray): Boolean {
        var difference = left.size xor right.size
        val length = maxOf(left.size, right.size)
        for (index in 0 until length) {
            val leftValue = if (index < left.size) left[index].code else 0
            val rightValue = if (index < right.size) right[index].code else 0
            difference = difference or (leftValue xor rightValue)
        }
        return difference == 0
    }
}
