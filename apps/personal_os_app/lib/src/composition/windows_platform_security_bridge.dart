import 'package:flutter/services.dart';

import 'method_channel_platform_security_bridge.dart';

/// Windows binding for the shared platform-security MethodChannel codec.
///
/// This fixes the Dart/native ABI name without making Windows production-ready.
/// Production composition must remain fail-closed until a reviewed native
/// implementation provides this channel and the encrypted-vault adapters.
final class WindowsPlatformSecurityBridge
    extends MethodChannelPlatformSecurityBridge {
  WindowsPlatformSecurityBridge({MethodChannel? channel})
      : super(
          channel: channel ??
              const MethodChannel('personal_os/internal/windows_vault'),
        );
}
