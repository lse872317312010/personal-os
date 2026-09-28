import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract interface class AgentReplyInboxPort {
  Future<String?> takePendingReply();
}

/// Reads one text reply supplied to Android's generic ACTION_SEND target.
final class MethodChannelAgentReplyInboxPort implements AgentReplyInboxPort {
  const MethodChannelAgentReplyInboxPort({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'personal_os/agent_text_receive';

  final MethodChannel _channel;

  @override
  Future<String?> takePendingReply() =>
      _channel.invokeMethod<String>('takePendingReply');
}

/// Explicit no-op used by synthetic previews and unsupported platforms.
final class NoopAgentReplyInboxPort implements AgentReplyInboxPort {
  const NoopAgentReplyInboxPort();

  @override
  Future<String?> takePendingReply() async => null;
}

/// Holds an incoming reply in memory only while the Vault is unlocked.
final class AgentReplyInboxController extends ChangeNotifier {
  AgentReplyInboxController({
    required AgentReplyInboxPort port,
    required bool Function() isVaultUnlocked,
  })  : _port = port,
        _isVaultUnlocked = isVaultUnlocked;

  static const int maxReplyBytes = 512 * 1024;

  final AgentReplyInboxPort _port;
  final bool Function() _isVaultUnlocked;
  String? _pendingReply;
  bool _loading = false;
  bool _vaultOpen = false;
  bool _disposed = false;

  String? get pendingReply => _pendingReply;
  bool get hasPendingReply => _pendingReply != null;
  bool get vaultOpen => _vaultOpen;

  Future<void> receivePendingReply() async {
    if (_disposed || !_isVaultUnlocked()) return;
    _vaultOpen = true;
    if (_loading || _pendingReply != null) return;
    _loading = true;
    try {
      final text = await _port.takePendingReply();
      if (_disposed ||
          !_isVaultUnlocked() ||
          text == null ||
          text.trim().isEmpty ||
          utf8.encode(text).length > maxReplyBytes) {
        return;
      }
      _pendingReply = text;
      notifyListeners();
    } on PlatformException {
      // The native buffer remains available until a later successful read.
    } on MissingPluginException {
      // Synthetic and non-Android shells do not expose the Android receiver.
    } finally {
      _loading = false;
    }
  }

  void clearPendingReply() {
    if (_pendingReply == null) return;
    _pendingReply = null;
    notifyListeners();
  }

  /// Called synchronously with the Vault lock so reply text does not outlive
  /// the user's unlocked session in Flutter memory.
  void clearForVaultLock() {
    _vaultOpen = false;
    _pendingReply = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingReply = null;
    super.dispose();
  }
}
