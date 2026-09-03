package com.personalos.app.model

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
import androidx.fragment.app.FragmentActivity
import java.util.concurrent.atomic.AtomicBoolean

internal interface NativeModelCredentialPrompt {
    fun requestCredential(callback: (CharArray?) -> Unit)
    fun dispose()
}

/**
 * Native-only one-call credential entry. No credential value crosses Flutter.
 */
internal class AndroidNativeModelCredentialPrompt(
    private val activity: FragmentActivity,
) : NativeModelCredentialPrompt {
    private var activeDialog: AlertDialog? = null
    private var activeInput: EditText? = null

    override fun requestCredential(callback: (CharArray?) -> Unit) {
        check(Looper.myLooper() == Looper.getMainLooper())
        if (activity.isFinishing || activity.isDestroyed) {
            callback(null)
            return
        }
        dispose()
        val input = EditText(activity).apply {
            inputType = InputType.TYPE_CLASS_TEXT or
                InputType.TYPE_TEXT_VARIATION_PASSWORD
            imeOptions = EditorInfo.IME_ACTION_DONE
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                imeOptions = imeOptions or EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING
                importantForAutofill =
                    View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
            }
            filters = arrayOf(InputFilter.LengthFilter(MAXIMUM_CREDENTIAL_LENGTH))
            filterTouchesWhenObscured = true
            isSingleLine = true
        }
        val completed = AtomicBoolean(false)
        lateinit var dialog: AlertDialog

        fun complete(ownedCredential: CharArray?) {
            if (!completed.compareAndSet(false, true)) {
                ownedCredential?.fill('\u0000')
                return
            }
            clearInput(input)
            if (activeDialog === dialog) {
                activeDialog = null
                activeInput = null
            }
            callback(ownedCredential)
        }

        dialog = AlertDialog.Builder(activity)
            .setTitle("配置一次性模型凭据")
            .setMessage("凭据仅保留在本次 native 内存会话中，使用后立即清除。")
            .setView(input)
            .setPositiveButton("使用一次") { _, _ ->
                complete(extractAndClear(input))
            }
            .setNegativeButton("取消") { _, _ -> complete(null) }
            .setOnCancelListener { complete(null) }
            .create()
        dialog.setOnDismissListener { complete(null) }
        activeDialog = dialog
        activeInput = input
        dialog.show()
        dialog.window?.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }

    override fun dispose() {
        val input = activeInput
        activeInput = null
        input?.let(::clearInput)
        val dialog = activeDialog
        activeDialog = null
        dialog?.dismiss()
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

    companion object {
        private const val MAXIMUM_CREDENTIAL_LENGTH = 512
    }
}
