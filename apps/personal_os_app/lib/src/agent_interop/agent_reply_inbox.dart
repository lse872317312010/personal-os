import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef AgentReplyAvailableHandler = Future<void> Function();

abstract interface class AgentReplyInboxPort {
  Future<String?> peekPendingReply();

  Future<void> acknowledgePendingReply();

  Future<int> pendingReplyCount();

  Future<int> takeDroppedReplyCount();

  void setReplyAvailableHandler(AgentReplyAvailableHandler? handler);
}

/// Reads text replies supplied to Android's generic ACTION_SEND target.
final class MethodChannelAgentReplyInboxPort implements AgentReplyInboxPort {
  const MethodChannelAgentReplyInboxPort({
    MethodChannel channel = const MethodChannel(channelName),
  }) : _channel = channel;

  static const String channelName = 'personal_os/agent_text_receive';
  static const String peekPendingReplyMethodName = 'peekPendingReply';
  static const String acknowledgePendingReplyMethodName =
      'acknowledgePendingReply';
  static const String pendingReplyCountMethodName = 'pendingReplyCount';
  static const String takeDroppedReplyCountMethodName = 'takeDroppedReplyCount';
  static const String replyAvailableMethodName = 'replyAvailable';

  final MethodChannel _channel;

  @override
  Future<String?> peekPendingReply() =>
      _channel.invokeMethod<String>(peekPendingReplyMethodName);

  @override
  Future<void> acknowledgePendingReply() async {
    await _channel.invokeMethod<void>(acknowledgePendingReplyMethodName);
  }

  @override
  Future<int> pendingReplyCount() async =>
      await _channel.invokeMethod<int>(pendingReplyCountMethodName) ?? 0;

  @override
  Future<int> takeDroppedReplyCount() async =>
      await _channel.invokeMethod<int>(takeDroppedReplyCountMethodName) ?? 0;

  @override
  void setReplyAvailableHandler(AgentReplyAvailableHandler? handler) {
    if (handler == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != replyAvailableMethodName) {
        throw MissingPluginException(
          'No handler for ${call.method} on $channelName',
        );
      }
      if (call.arguments != null) {
        throw PlatformException(
          code: 'unexpected_reply_payload',
          message: 'Reply availability notifications must not include text.',
        );
      }
      await handler();
      return null;
    });
  }
}

/// Explicit no-op used by synthetic previews and unsupported platforms.
final class NoopAgentReplyInboxPort implements AgentReplyInboxPort {
  const NoopAgentReplyInboxPort();

  @override
  Future<String?> peekPendingReply() async => null;

  @override
  Future<void> acknowledgePendingReply() async {}

  @override
  Future<int> pendingReplyCount() async => 0;

  @override
  Future<int> takeDroppedReplyCount() async => 0;

  @override
  void setReplyAvailableHandler(AgentReplyAvailableHandler? handler) {}
}

/// Holds incoming replies in memory only while the Vault is unlocked.
final class AgentReplyInboxController extends ChangeNotifier {
  AgentReplyInboxController({
    required AgentReplyInboxPort port,
    required bool Function() isVaultUnlocked,
  })  : _port = port,
        _isVaultUnlocked = isVaultUnlocked {
    _port.setReplyAvailableHandler(receivePendingReply);
  }

  static const int maxReplyBytes = 512 * 1024;

  final AgentReplyInboxPort _port;
  final bool Function() _isVaultUnlocked;
  String? _pendingReply;
  int _queuedReplyCount = 0;
  int _droppedReplyCount = 0;
  int _vaultGeneration = 0;
  bool _loading = false;
  bool _refreshRequested = false;
  bool _vaultOpen = false;
  bool _disposed = false;

  String? get pendingReply => _pendingReply;
  bool get hasPendingReply => _pendingReply != null;
  int get queuedReplyCount => _queuedReplyCount;
  int get droppedReplyCount => _droppedReplyCount;
  bool get vaultOpen => _vaultOpen;

  Future<void> receivePendingReply() async {
    if (_disposed || !_isVaultUnlocked()) return;
    _vaultOpen = true;
    if (_loading) {
      _refreshRequested = true;
      return;
    }

    final generation = _vaultGeneration;
    _loading = true;
    try {
      do {
        _refreshRequested = false;
        if (_pendingReply == null) {
          final text = await _port.peekPendingReply();
          if (_disposed ||
              generation != _vaultGeneration ||
              !_isVaultUnlocked()) {
            return;
          }
          if (text != null &&
              text.trim().isNotEmpty &&
              utf8.encode(text).length <= maxReplyBytes) {
            _pendingReply = text;
            notifyListeners();
          } else if (text != null) {
            // Native capture validates too. Acknowledge corrupt/invalid heads
            // so they cannot block later replies in the FIFO.
            if (_disposed ||
                generation != _vaultGeneration ||
                !_isVaultUnlocked()) {
              return;
            }
            await _port.acknowledgePendingReply();
            _refreshRequested = true;
          }
        }

        if (_disposed ||
            generation != _vaultGeneration ||
            !_isVaultUnlocked()) {
          return;
        }
        final queuedCount = await _port.pendingReplyCount();
        final droppedCount = await _port.takeDroppedReplyCount();
        if (_disposed ||
            generation != _vaultGeneration ||
            !_isVaultUnlocked()) {
          return;
        }

        final safeQueuedCount = queuedCount < 0 ? 0 : queuedCount;
        final activeReplyCount = _pendingReply == null ? 0 : 1;
        final waitingReplyCount = safeQueuedCount > activeReplyCount
            ? safeQueuedCount - activeReplyCount
            : 0;
        final safeDroppedCount = droppedCount < 0 ? 0 : droppedCount;
        final totalDroppedCount = _droppedReplyCount + safeDroppedCount;
        if (_queuedReplyCount != waitingReplyCount ||
            _droppedReplyCount != totalDroppedCount) {
          _queuedReplyCount = waitingReplyCount;
          _droppedReplyCount = totalDroppedCount;
          notifyListeners();
        }
        if (_pendingReply == null && safeQueuedCount > 0) {
          _refreshRequested = true;
        }
      } while (_refreshRequested &&
          !_disposed &&
          generation == _vaultGeneration &&
          _isVaultUnlocked());
    } on PlatformException {
      // The native buffer remains available until a later successful read.
    } on MissingPluginException {
      // Synthetic and non-Android shells do not expose the Android receiver.
    } finally {
      _loading = false;
      if (_refreshRequested &&
          !_disposed &&
          generation == _vaultGeneration &&
          _isVaultUnlocked()) {
        _refreshRequested = false;
        unawaited(receivePendingReply());
      }
    }
  }

  Future<void> clearPendingReply() async {
    final pendingReply = _pendingReply;
    if (pendingReply == null) return;
    final generation = _vaultGeneration;
    try {
      await _port.acknowledgePendingReply();
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
    if (_disposed ||
        generation != _vaultGeneration ||
        _pendingReply != pendingReply) {
      return;
    }
    _pendingReply = null;
    notifyListeners();
    if (_vaultOpen) await receivePendingReply();
  }

  void clearDroppedReplyNotice() {
    if (_droppedReplyCount == 0) return;
    _droppedReplyCount = 0;
    notifyListeners();
  }

  /// Called synchronously with the Vault lock so reply text does not outlive
  /// the user's unlocked session in Flutter memory.
  void clearForVaultLock() {
    _vaultGeneration++;
    _vaultOpen = false;
    _pendingReply = null;
    _queuedReplyCount = 0;
    _refreshRequested = false;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingReply = null;
    _queuedReplyCount = 0;
    _port.setReplyAvailableHandler(null);
    super.dispose();
  }
}
