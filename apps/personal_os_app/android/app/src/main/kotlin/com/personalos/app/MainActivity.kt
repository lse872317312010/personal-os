package com.personalos.app

import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.personalos.app.security.NativeVaultChannel
import com.personalos.app.source.ControlledPhotoPicker
import com.personalos.app.source.ControlledSourceChannel
import com.personalos.app.source.ControlledSourceMethodChannelContract
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var vaultChannel: MethodChannel? = null
    private var vaultHandler: NativeVaultChannel? = null
    private var sourceChannel: MethodChannel? = null
    private var sourceHandler: ControlledSourceChannel? = null

    private val photoPickerLauncher: ActivityResultLauncher<PickVisualMediaRequest> by lazy {
        registerForActivityResult(
            ActivityResultContracts.PickVisualMedia(),
        ) { uri ->
            sourceHandler?.onPicked(uri)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val vault = NativeVaultChannel(this)
        vaultHandler = vault
        vaultChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeVaultChannel.CHANNEL_NAME,
        ).also { it.setMethodCallHandler(vault) }

        val source = ControlledPhotoPicker(
            resolver = contentResolver,
            blobSink = NativeVaultBlobSink(contentResolver, vault),
        )
        val handler = ControlledSourceChannel(source, photoPickerLauncher)
        sourceHandler = handler
        sourceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ControlledSourceMethodChannelContract.CHANNEL_NAME,
        ).also { it.setMethodCallHandler(handler) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        vaultChannel?.setMethodCallHandler(null)
        vaultChannel = null
        vaultHandler?.dispose()
        vaultHandler = null
        sourceChannel?.setMethodCallHandler(null)
        sourceChannel = null
        sourceHandler?.dispose()
        sourceHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        vaultHandler?.dispose()
        vaultHandler = null
        sourceHandler?.dispose()
        sourceHandler = null
        super.onDestroy()
    }
}
