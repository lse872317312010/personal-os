import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';

/// Append-only persistence boundary. Implementations must append [events]
/// atomically and in list order or fail without a partial write.
abstract interface class EventStore {
  Future<void> appendAll(List<EventEnvelope> events);

  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  });

  Future<EventEnvelope?> readById(String eventId);
}

/// Optional capability for stores that can stream an entire profile history.\n///\n/// Read models use this instead of a bounded [EventStore.readBySubject] call\n/// when correctness depends on replaying every durable event.\nabstract interface class CompleteProfileHistoryReader {\n  Future<List<EventEnvelope>> readCompleteProfileHistory(\n    EntityId profileId, {\n    int pageSize = 500,\n  });\n}\n\n/// Stable, adapter-neutral persistence error codes.
///
/// Adapter implementations may keep detailed diagnostics in private logs, but
/// these values are the only error identity that may cross the application
/// boundary. They intentionally do not contain event IDs, paths, SQL, keys, or
/// native exception text.
abstract final class PersistenceErrorCode {
  static const eventConflict = 'persistence.event_conflict';
  static const revisionConflict = 'persistence.revision_conflict';
  static const d4PersistenceForbidden = 'persistence.d4_forbidden';
  static const invalidEvent = 'persistence.invalid_event';
  static const schemaViolation = 'persistence.schema_violation';
  static const transactionFailed = 'persistence.transaction_failed';
  static const readFailed = 'persistence.read_failed';
  static const writeFailed = 'persistence.write_failed';
  static const vaultLocked = 'persistence.vault_locked';
  static const authenticationRequired = 'persistence.authentication_required';
  static const authenticationFailed = 'persistence.authentication_failed';
  static const keyUnavailable = 'persistence.key_unavailable';
  static const keyRevoked = 'persistence.key_revoked';
  static const corrupted = 'persistence.corrupted';
  static const unsupported = 'persistence.unsupported';
  static const notFound = 'persistence.not_found';
  static const unavailable = 'persistence.unavailable';
}

/// Public persistence failure with a fixed safe message.
///
/// This is deliberately an adapter-neutral exception rather than a platform
/// error. The public [message] is a stable reason token, not exception detail;
/// callers that need user-facing text must use [safeMessage].
class PersistenceException implements Exception {
  const PersistenceException._(this.code, String stableReason)
      : message = stableReason;

  const PersistenceException.d4PersistenceForbidden()
      : this._(
          PersistenceErrorCode.d4PersistenceForbidden,
          'event_append_rejected:d4_persistence_forbidden',
        );

  const PersistenceException.invalidEvent()
      : this._(PersistenceErrorCode.invalidEvent, 'invalid_event');

  const PersistenceException.schemaViolation()
      : this._(PersistenceErrorCode.schemaViolation, 'schema_violation');

  const PersistenceException.transactionFailed()
      : this._(PersistenceErrorCode.transactionFailed, 'transaction_failed');

  const PersistenceException.readFailed()
      : this._(PersistenceErrorCode.readFailed, 'read_failed');

  const PersistenceException.writeFailed()
      : this._(PersistenceErrorCode.writeFailed, 'write_failed');

  final String code;
  final String message;

  String get safeMessage => _safeMessages[code]!;

  @override
  String toString() => 'PersistenceException($code)';
}

final class EventAppendConflict extends PersistenceException {
  EventAppendConflict(String reason)
      : super._(
          reason == ReductionReason.revisionConflict
              ? PersistenceErrorCode.revisionConflict
              : PersistenceErrorCode.eventConflict,
          _stableReason(reason),
        );
}

String _stableReason(String reason) => switch (reason) {
      ReductionReason.revisionConflict => ReductionReason.revisionConflict,
      ReductionReason.illegalStateTransition =>
        ReductionReason.illegalStateTransition,
      ReductionReason.unsupportedEventType =>
        ReductionReason.unsupportedEventType,
      ReductionReason.missingSubject => ReductionReason.missingSubject,
      _ => 'event_conflict',
    };

const _safeMessages = <String, String>{
  PersistenceErrorCode.eventConflict:
      'The event conflicts with existing local state.',
  PersistenceErrorCode.revisionConflict:
      'The local state changed; retry from the latest state.',
  PersistenceErrorCode.d4PersistenceForbidden:
      'This data cannot be persisted by policy.',
  PersistenceErrorCode.invalidEvent: 'The event was rejected.',
  PersistenceErrorCode.schemaViolation:
      'The local storage schema rejected the operation.',
  PersistenceErrorCode.transactionFailed:
      'The local storage operation was rolled back.',
  PersistenceErrorCode.readFailed: 'The local state could not be read safely.',
  PersistenceErrorCode.writeFailed:
      'The local state could not be written safely.',
  PersistenceErrorCode.vaultLocked: 'The local vault is locked.',
  PersistenceErrorCode.authenticationRequired: 'Authentication is required.',
  PersistenceErrorCode.authenticationFailed: 'Authentication failed.',
  PersistenceErrorCode.keyUnavailable: 'The local security key is unavailable.',
  PersistenceErrorCode.keyRevoked: 'The local security key is revoked.',
  PersistenceErrorCode.corrupted: 'The local state could not be trusted.',
  PersistenceErrorCode.unsupported:
      'This local storage operation is unsupported.',
  PersistenceErrorCode.notFound: 'The requested local state was not found.',
  PersistenceErrorCode.unavailable: 'Local storage is temporarily unavailable.',
};
