import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Applies the foreground Agent access lease at the persistence boundary.
///
/// This prevents an operation that resumed after a lock/background transition
/// from starting a new read or write with an adapter binding it captured before
/// the transition. Storage calls already in progress remain governed by the
/// underlying vault transaction and session-close behavior.
final class AgentAccessEventStore implements EventStore {
  const AgentAccessEventStore({
    required EventStore inner,
    required bool Function() isAuthorized,
  })  : _inner = inner,
        _isAuthorized = isAuthorized;

  final EventStore _inner;
  final bool Function() _isAuthorized;

  void _requireAuthorized({required bool write}) {
    if (!_isAuthorized()) {
      throw write
          ? const PersistenceException.writeFailed()
          : const PersistenceException.readFailed();
    }
  }

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    _requireAuthorized(write: true);
    await _inner.appendAll(events);
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    _requireAuthorized(write: false);
    return _inner.readBySubject(subject, limit: limit);
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    _requireAuthorized(write: false);
    return _inner.readById(eventId);
  }
}
