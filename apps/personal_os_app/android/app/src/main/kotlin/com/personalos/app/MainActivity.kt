package com.personalos.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.personalos.app.security.NativeVaultChannel

class MainActivity : FlutterFragmentActivity() {
    private var vaultChannel: MethodChannel? = null
    private var vaultHandler: NativeVaultChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val handler = NativeVaultChannel(this)
        vaultHandler = handler
        vaultChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NativeVaultChannel.CHANNEL_NAME,
        ).also { it.setMethodCallHandler(handler) }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        vaultChannel?.setMethodCallHandler(null)
        vaultChannel = null
        vaultHandler?.dispose()
        vaultHandler = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        vaultHandler?.dispose()
        vaultHandler = null
        super.onDestroy()
    }
}
