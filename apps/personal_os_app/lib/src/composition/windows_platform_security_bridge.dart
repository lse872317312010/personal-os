import 'package:flutter/services.dart';

import 'method_channel_platform_security_bridge.dart';

/// Windows-specific channel selection for the shared native security protocol.
///
/// The Dart side does not infer that Windows Hello, TPM, DPAPI, or SQLCipher is
/// available. Native capability inspection remains the only source of truth.
final class WindowsPlatformSecurityBridge
    extends MethodChannelPlatformSecurityBridge {
  WindowsPlatformSecurityBridge({MethodChannel? channel})
      : super(
          channel ?? const MethodChannel('personal_os/internal/windows_vault'),
        );
}
