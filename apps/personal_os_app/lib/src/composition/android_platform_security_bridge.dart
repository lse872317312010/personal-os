import 'package:flutter/services.dart';

import 'method_channel_platform_security_bridge.dart';

/// Android-specific channel selection for the shared native security protocol.
final class AndroidPlatformSecurityBridge
    extends MethodChannelPlatformSecurityBridge {
  AndroidPlatformSecurityBridge({MethodChannel? channel})
      : super(
          channel ?? const MethodChannel('personal_os/internal/android_vault'),
        );
}
