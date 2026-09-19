import 'package:flutter/services.dart';
import 'package:personal_os_device_security/device_security.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// App-private EventStore adapter for the native SQLCipher session.
///
/// This class accepts only complete, strictly codec-produced event JSON. The
/// native side treats that JSON as opaque text; decoding happens here again so
/// an invalid, old, or forward-incompatible row is never trusted.
final class NativeSqlCipherEventStore
    implements EventStore, CompleteProfileHistoryReader {
  NativeSqlCipherEventStore({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('personal_os/internal/android_vault');

  final MethodChannel _channel;
  PlatformVaultSession? _nativeSession;
  void Function(SecurityException error)? _sessionInvalidatedHandler;

  /// Installs the lifecycle callback owned by the session coordinator.
  ///
  /// Only stable security codes cross this boundary; native exception text,
  /// paths, aliases, and other details are never forwarded.
  void setSessionInvalidatedHandler(
    void Function(SecurityException error) handler,
  ) {
    _sessionInvalidatedHandler = handler;
  }

  /// Called only by [NativeSqlCipherSessionCoordinator].
  void attachNativeSession(PlatformVaultSession session) {
    if (_nativeSession != null) {
      throw const PersistenceException.transactionFailed();
    }
    _nativeSession = session;
  }

  /// Called before the coordinator closes the native session.
  void detachNativeSession(PlatformVaultSession session) {
    if (_nativeSession?.id != session.id) return;
    _nativeSession = null;
  }

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    if (events.isEmpty) return;
    final records = <Map<String, Object?>>[];
    try {
      for (final event in events) {
        final profile = _profileSubject(event);
        records.add(<String, Object?>{
          'profileId': profile.id.value,
          'eventId': event.eventId,
          'eventJson': EventEnvelopeJsonCodec.encodeString(event),
          'subjectRefs': event.subjectRefs
              .map((ref) => ref.toJson())
              .toList(growable: false),
        });
      }
    } on EventCodecException catch (error) {
      throw _codecPersistenceException(error);
    } on PersistenceException {
      rethrow;
    } on Object {
      throw const PersistenceException.invalidEvent();
    }

    try {
      await _invoke(
        'appendEvents',
        <String, Object?>{
          'sessionId': _requireSession(forWrite: true).id,
          'events': records,
        },
        failure: const PersistenceException.writeFailed(),
      );
    } on PersistenceException {
      rethrow;
    } on Object {
      throw const PersistenceException.writeFailed();
    }
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    if (limit != null && limit <= 0) return const <EventEnvelope>[];
    // Native filters by subject, while this adapter performs the final
    // envelope-reference check below. Ask native for the full bounded page so
    // an unrelated earlier row cannot consume the caller's post-filter limit.
    const nativeLimit = _maxNativeRead;
    final method = subject.type == 'profile'
        ? 'readEventsByProfile'
        : 'readEventsBySubject';
    final arguments = <String, Object?>{
      'sessionId': _requireSession().id,
      if (method == 'readEventsByProfile') 'profileId': subject.id.value,
      if (method == 'readEventsBySubject') ...<String, Object?>{
        'subjectType': subject.type,
        'subjectId': subject.id.value,
      },
      'limit': nativeLimit,
    };
    final rows = await _invokeList(
      method,
      arguments,
      failure: const PersistenceException.readFailed(),
    );
    final decoded = rows.map(_decodeRow).toList(growable: false);
    final filtered = decoded
        .where(
            (event) => event.subjectRefs.any((ref) => _sameRef(ref, subject)))
        .toList(growable: false);
    return limit == null || filtered.length <= limit
        ? filtered
        : filtered.take(limit).toList(growable: false);
  }


  /// Reads the complete profile history in stable native sequence order.
  ///
  /// This is the only supported source for lossless archive creation. Paging
  /// continues until native returns a short page; cursor regressions,
  /// duplicate event IDs, and malformed sequence values fail closed.
  Future<List<EventEnvelope>> readCompleteProfileHistory(
    EntityId profileId, {
    int pageSize = 500,
  }) async {
    if (pageSize <= 0 || pageSize > _maxNativeRead) {
      throw const PersistenceException.readFailed();
    }
    var afterSequence = 0;
    final events = <EventEnvelope>[];
    final eventIds = <String>{};
    while (true) {
      final rows = await _invokeList(
        'readEventsByProfilePage',
        <String, Object?>{
          'sessionId': _requireSession().id,
          'profileId': profileId.value,
          'afterSequence': afterSequence,
          'limit': pageSize,
        },
        failure: const PersistenceException.readFailed(),
      );
      for (final row in rows) {
        final sequence = row['sequenceNo'];
        if (sequence is! int || sequence <= afterSequence) {
          throw const PersistenceException.schemaViolation();
        }
        final event = _decodeRow(row);
        if (!eventIds.add(event.eventId)) {
          throw const PersistenceException.schemaViolation();
        }
        afterSequence = sequence;
        events.add(event);
      }
      if (rows.length < pageSize) {
        return List<EventEnvelope>.unmodifiable(events);
      }
    }
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    if (eventId.trim().isEmpty || eventId != eventId.trim()) {
      throw const PersistenceException.invalidEvent();
    }
    final value = await _invoke(
      'readEventById',
      <String, Object?>{
        'sessionId': _requireSession().id,
        'eventId': eventId,
      },
      failure: const PersistenceException.readFailed(),
    );
    if (value == null) return null;
    return _decodeRow(_asStringObjectMap(value));
  }

  static const _maxNativeRead = 1000;

  PlatformVaultSession _requireSession({bool forWrite = false}) {
    final session = _nativeSession;
    if (session == null || session.id.trim().isEmpty) {
      throw forWrite
          ? const PersistenceException.writeFailed()
          : const PersistenceException.readFailed();
    }
    return session;
  }

  Future<Object?> _invoke(
    String method,
    Map<String, Object?> arguments, {
    required PersistenceException failure,
  }) async {
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on PlatformException catch (error) {
      final mapped = _mapNativeFailure(error.code, failure);
      final securityFailure = _sessionFailure(error.code);
      if (securityFailure != null) {
        _notifySessionInvalidated(securityFailure);
      }
      throw mapped;
    } on MissingPluginException {
      throw failure;
    } on Object {
      throw failure;
    }
  }

  void _notifySessionInvalidated(SecurityException error) {
    final handler = _sessionInvalidatedHandler;
    if (handler == null) return;
    try {
      handler(error);
    } on Object {
      // Invalidation remains fail-closed if the lifecycle observer fails.
    }
  }

  Future<List<Map<String, Object?>>> _invokeList(
    String method,
    Map<String, Object?> arguments, {
    required PersistenceException failure,
  }) async {
    final value = await _invoke(method, arguments, failure: failure);
    if (value is! List) throw const PersistenceException.schemaViolation();
    if (value.any((row) => row is! Map)) {
      throw const PersistenceException.schemaViolation();
    }
    try {
      return value
          .map<Map<String, Object?>>(_asStringObjectMap)
          .toList(growable: false);
    } on Object {
      throw const PersistenceException.schemaViolation();
    }
  }

  Map<String, Object?> _asStringObjectMap(Object? value) {
    if (value is! Map) throw const PersistenceException.schemaViolation();
    return <String, Object?>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }

  EventEnvelope _decodeRow(Map<String, Object?> row) {
    final json = row['eventJson'];
    final rowEventId = row['eventId'];
    if (json is! String || rowEventId is! String) {
      throw const PersistenceException.schemaViolation();
    }
    try {
      final event = EventEnvelopeJsonCodec.decodeString(json);
      if (event.eventId != rowEventId) {
        throw const PersistenceException.schemaViolation();
      }
      return event;
    } on EventCodecException catch (error) {
      throw _codecReadException(error);
    } on Object {
      throw const PersistenceException.schemaViolation();
    }
  }
}

ObjectRef _profileSubject(EventEnvelope event) {
  for (final subject in event.subjectRefs) {
    if (subject.type == 'profile') return subject;
  }
  throw EventAppendConflict(ReductionReason.missingSubject);
}

bool _sameRef(ObjectRef left, ObjectRef right) =>
    left.type == right.type && left.id.value == right.id.value;

PersistenceException _codecPersistenceException(EventCodecException error) =>
    error.reasonCode == EventCodecReason.d4PersistenceForbidden
        ? const PersistenceException.d4PersistenceForbidden()
        : const PersistenceException.invalidEvent();

PersistenceException _codecReadException(EventCodecException error) =>
    error.reasonCode == EventCodecReason.d4PersistenceForbidden
        ? const PersistenceException.d4PersistenceForbidden()
        : const PersistenceException.schemaViolation();

SecurityException? _sessionFailure(String code) => switch (code) {
      'security.vault_locked' =>
        const SecurityException(SecurityErrorCode.vaultLocked),
      'security.unlock_expired' =>
        const SecurityException(SecurityErrorCode.unlockExpired),
      _ => null,
    };


PersistenceException _mapNativeFailure(
  String code,
  PersistenceException operationFailure,
) {
  switch (code) {
    case 'security.vault_event_conflict':
      return EventAppendConflict(PersistenceErrorCode.eventConflict);
    case 'security.vault_event_invalid':
      return const PersistenceException.invalidEvent();
    case 'security.vault_schema_invalid':
      return const PersistenceException.schemaViolation();
    case 'security.vault_transaction_failed':
      return const PersistenceException.transactionFailed();
    default:
      return operationFailure;
  }
}
