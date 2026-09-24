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
    required bool Function() vaultUnlocked,
  })  : _handleRequest = handleRequest,
        _revokeAll = revokeAll,
        _vaultUnlocked = vaultUnlocked;

  final AgentRequestHandler _handleRequest;
  final VoidCallback _revokeAll;
  final bool Function() _vaultUnlocked;
  int _epoch = 0;

  bool _active = false;
  bool get active => _active;

  /// Starts a volatile access window after an explicit user action.
  ///
  /// The current authoritative Vault state is checked at the boundary.
  bool start() {
    if (!_vaultUnlocked() || _active) return false;
    _revokeAll();
    _active = true;
    notifyListeners();
    return true;
  }

  Future<Map<String, Object?>?> handle(
    Map<String, Object?> request,
  ) async {
    if (!_active || !_vaultUnlocked()) {
      if (!request.containsKey('id')) {
        return null;
      }
      return <String, Object?>{
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
      };
    }
    final epoch = _epoch;
    final response = await _handleRequest(request);
    if (!_active || !_vaultUnlocked() || epoch != _epoch) {
      return null;
    }
    return response;
  }

  /// Stops access synchronously and revokes every volatile Agent binding.
  void stop() {
    final wasActive = _active;
    _epoch++;
    _active = false;
    _revokeAll();
    if (wasActive) notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
