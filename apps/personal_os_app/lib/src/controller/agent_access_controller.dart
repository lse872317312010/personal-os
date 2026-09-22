import 'package:flutter/foundation.dart';

typedef AgentRequestHandler = Future<Map<String, Object?>?> Function(
  Map<String, Object?> request,
);

/// Owns the volatile, foreground-only Agent access boundary.
///
/// This controller opens no network listener. A future Android loopback
/// transport may forward requests through [handle] only while [active] is true.
final class AgentAccessController extends ChangeNotifier {
  AgentAccessController({
    required AgentRequestHandler handleRequest,
    required VoidCallback revokeAll,
  })  : _handleRequest = handleRequest,
        _revokeAll = revokeAll;

  final AgentRequestHandler _handleRequest;
  final VoidCallback _revokeAll;

  bool _active = false;
  bool get active => _active;

  /// Starts a volatile access window after an explicit user action.
  ///
  /// The caller must pass the current authoritative Vault state. A locked
  /// Vault always fails closed.
  bool start({required bool vaultUnlocked}) {
    if (!vaultUnlocked || _active) return false;
    _revokeAll();
    _active = true;
    notifyListeners();
    return true;
  }

  Future<Map<String, Object?>?> handle(
    Map<String, Object?> request,
  ) {
    if (!_active) {
      if (!request.containsKey('id')) {
        return Future<Map<String, Object?>?>.value(null);
      }
      return Future<Map<String, Object?>?>.value(<String, Object?>{
        'jsonrpc': '2.0',
        'id': request['id'],
        'error': <String, Object?>{
          'code': -32001,
          'message': 'access_denied',
          'data': <String, Object?>{
            'code': 'access_denied',
            'retryable': false,
          },
        },
      });
    }
    return _handleRequest(request);
  }

  /// Stops access synchronously and revokes every volatile Agent binding.
  void stop() {
    _revokeAll();
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _revokeAll();
    super.dispose();
  }
}
