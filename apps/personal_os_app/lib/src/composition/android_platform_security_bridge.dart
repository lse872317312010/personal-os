import 'package:flutter/services.dart';

import 'method_channel_platform_security_bridge.dart';

/// Android binding for the shared platform-security MethodChannel codec.
///
/// The channel name is part of the private Android/native ABI and must stay in
/// sync with `NativeVaultChannel.CHANNEL_NAME`.
final class AndroidPlatformSecurityBridge
    extends MethodChannelPlatformSecurityBridge {
  AndroidPlatformSecurityBridge({MethodChannel? channel})
      : super(
          channel: channel ??
              const MethodChannel('personal_os/internal/android_vault'),
        );
}
