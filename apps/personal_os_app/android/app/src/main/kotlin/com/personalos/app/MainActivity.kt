package com.personalos.app

import android.net.Uri
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.personalos.app.security.NativeVaultChannel
import com.personalos.app.source.ControlledCameraCapture
import com.personalos.app.source.ControlledPhotoPicker
import com.personalos.app.source.ControlledSourceTokenStore
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
    private var cameraCapture: ControlledCameraCapture? = null

    private val cameraPermissionLauncher: ActivityResultLauncher<String> by lazy {
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            cameraCapture?.onPermissionResult(granted)
        }
    }

    private val cameraLauncher: ActivityResultLauncher<Uri> by lazy {
        registerForActivityResult(ActivityResultContracts.TakePicture()) { success ->
            cameraCapture?.onCaptured(success)
        }
    }

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

        val tokenStore = ControlledSourceTokenStore()
        val blobSink = NativeVaultBlobSink(contentResolver, vault)
        val source = ControlledPhotoPicker(
            resolver = contentResolver,
            tokenStore = tokenStore,
            blobSink = blobSink,
            currentSessionId = vault::currentSessionId,
        )
        val camera = ControlledCameraCapture(
            context = this,
            tokenStore = tokenStore,
            permissionLauncher = cameraPermissionLauncher,
            cameraLauncher = cameraLauncher,
            currentSessionId = vault::currentSessionId,
        )
        cameraCapture = camera
        val handler = ControlledSourceChannel(source, camera)
        sourceHandler = handler
        vault.onSessionInvalidated = handler::retireTokens
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
        cameraCapture = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        vaultHandler?.dispose()
        vaultHandler = null
        sourceHandler?.dispose()
        sourceHandler = null
        cameraCapture = null
        super.onDestroy()
    }
}
