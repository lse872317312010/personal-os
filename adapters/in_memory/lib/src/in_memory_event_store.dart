import 'dart:collection';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Why an append transaction was rejected.
enum AppendFailure {
  revisionConflict,
  eventConflict,
  invalidEvent,
  transactionFailed,
}

abstract final class InMemoryRejectionReason {
  static const d4PersistenceForbidden = 'd4_persistence_forbidden';
}

/// A durable-order event returned by the candidate store.
final class StoredEvent {
  const StoredEvent({required this.sequence, required this.event});

  final int sequence;
  final EventEnvelope event;
}

/// A relay delivery item. Acknowledgement is separate from event persistence.
final class OutboxEntry {
  const OutboxEntry({
    required this.sequence,
    required this.eventId,
    required this.event,
    required this.acknowledged,
  });

  final int sequence;
  final String eventId;
  final EventEnvelope event;
  final bool acknowledged;

  OutboxEntry acknowledge() => OutboxEntry(
        sequence: sequence,
        eventId: eventId,
        event: event,
        acknowledged: true,
      );
}

final class AppendResult {
  const AppendResult._({
    required this.committed,
    required this.appendedEventIds,
    required this.duplicateEventIds,
    this.failure,
    this.failedEventId,
    this.reasonCode,
  });

  factory AppendResult.committed({
    required List<String> appendedEventIds,
    required List<String> duplicateEventIds,
  }) =>
      AppendResult._(
        committed: true,
        appendedEventIds: List.unmodifiable(appendedEventIds),
        duplicateEventIds: List.unmodifiable(duplicateEventIds),
      );

  factory AppendResult.rejected({
    required AppendFailure failure,
    required String failedEventId,
    required String reasonCode,
  }) =>
      AppendResult._(
        committed: false,
        appendedEventIds: const [],
        duplicateEventIds: const [],
        failure: failure,
        failedEventId: failedEventId,
        reasonCode: reasonCode,
      );

  final bool committed;
  final List<String> appendedEventIds;
  final List<String> duplicateEventIds;
  final AppendFailure? failure;
  final String? failedEventId;
  final String? reasonCode;
}

/// Single-isolate candidate EventStore + Projection + Outbox adapter.
///
/// The whole batch is reduced against private staging collections. State is
/// swapped only after every non-duplicate event applies, so a failure cannot
/// leave an event, projection, seen ID, sequence, or outbox item behind.
final class InMemoryEventStore implements EventStore {
  List<StoredEvent> _events = [];
  Map<String, ObjectProjection> _projections = {};
  Set<String> _seenEventIds = {};
  List<OutboxEntry> _outbox = [];
  int _nextEventSequence = 1;
  int _nextOutboxSequence = 1;

  AppendResult append(EventEnvelope event) => appendTransaction([event]);

  /// Synchronous test/spike API exposing detailed transaction diagnostics.
  AppendResult appendTransaction(Iterable<EventEnvelope> events) {
    try {
      final batch = List<EventEnvelope>.of(events);
      for (final event in batch) {
        if (event.sensitivity == Sensitivity.d4) {
          return AppendResult.rejected(
            failure: AppendFailure.invalidEvent,
            failedEventId: event.eventId,
            reasonCode: InMemoryRejectionReason.d4PersistenceForbidden,
          );
        }
      }

      final stagedEvents = List<StoredEvent>.of(_events);
      var stagedProjections = Map<String, ObjectProjection>.of(_projections);
      var stagedSeenIds = Set<String>.of(_seenEventIds);
      final stagedOutbox = List<OutboxEntry>.of(_outbox);
      var stagedEventSequence = _nextEventSequence;
      var stagedOutboxSequence = _nextOutboxSequence;
      final appendedIds = <String>[];
      final duplicateIds = <String>[];

      for (final event in batch) {
        if (stagedSeenIds.contains(event.eventId)) {
          final prior = stagedEvents
              .firstWhere((stored) => stored.event.eventId == event.eventId)
              .event;
          if (!_sameEventContent(prior, event)) {
            return AppendResult.rejected(
              failure: AppendFailure.eventConflict,
              failedEventId: event.eventId,
              reasonCode: PersistenceErrorCode.eventConflict,
            );
          }
          duplicateIds.add(event.eventId);
          continue;
        }

        final reduction = reduceCore(
          projections: stagedProjections,
          seenEventIds: stagedSeenIds,
          event: event,
        );
        if (reduction.disposition != ReductionDisposition.applied) {
          final reason =
              reduction.reasonCode ?? PersistenceErrorCode.eventConflict;
          return AppendResult.rejected(
            failure: reason == ReductionReason.revisionConflict
                ? AppendFailure.revisionConflict
                : AppendFailure.invalidEvent,
            failedEventId: event.eventId,
            reasonCode: reason,
          );
        }

        stagedEvents.add(
          StoredEvent(sequence: stagedEventSequence++, event: event),
        );
        stagedOutbox.add(
          OutboxEntry(
            sequence: stagedOutboxSequence++,
            eventId: event.eventId,
            event: event,
            acknowledged: false,
          ),
        );
        stagedProjections = Map<String, ObjectProjection>.of(
          reduction.projections,
        );
        stagedSeenIds = Set<String>.of(reduction.seenEventIds);
        appendedIds.add(event.eventId);
      }

      _events = stagedEvents;
      _projections = stagedProjections;
      _seenEventIds = stagedSeenIds;
      _outbox = stagedOutbox;
      _nextEventSequence = stagedEventSequence;
      _nextOutboxSequence = stagedOutboxSequence;
      return AppendResult.committed(
        appendedEventIds: appendedIds,
        duplicateEventIds: duplicateIds,
      );
    } on EventCodecException {
      return AppendResult.rejected(
        failure: AppendFailure.invalidEvent,
        failedEventId: '',
        reasonCode: PersistenceErrorCode.invalidEvent,
      );
    } on Object {
      return AppendResult.rejected(
        failure: AppendFailure.transactionFailed,
        failedEventId: '',
        reasonCode: PersistenceErrorCode.transactionFailed,
      );
    }
  }

  /// Formal application-layer port. Reducer rejections cross the boundary as
  /// stable append conflicts; policy-sensitive D4 rejection remains distinct.
  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    final result = appendTransaction(events);
    if (result.committed) return;
    if (result.failure == AppendFailure.revisionConflict) {
      throw EventAppendConflict(ReductionReason.revisionConflict);
    }
    if (result.failure == AppendFailure.eventConflict) {
      throw EventAppendConflict(
        result.reasonCode ?? PersistenceErrorCode.eventConflict,
      );
    }
    if (result.reasonCode == InMemoryRejectionReason.d4PersistenceForbidden) {
      throw const PersistenceException.d4PersistenceForbidden();
    }
    if (result.failure == AppendFailure.transactionFailed) {
      throw const PersistenceException.transactionFailed();
    }
    if (_isReducerConflict(result.reasonCode)) {
      throw EventAppendConflict(result.reasonCode!);
    }
    throw const PersistenceException.invalidEvent();
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    try {
      for (final stored in _events) {
        if (stored.event.eventId == eventId) return stored.event;
      }
      return null;
    } on Object {
      throw const PersistenceException.readFailed();
    }
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    try {
      if (limit != null && limit < 0) {
        throw const PersistenceException.readFailed();
      }
      final matches = _events
          .where(
            (stored) => stored.event.subjectRefs.any(
              (candidate) =>
                  candidate.type == subject.type && candidate.id == subject.id,
            ),
          )
          .map((stored) => stored.event);
      return List<EventEnvelope>.unmodifiable(
        limit == null ? matches : matches.take(limit),
      );
    } on PersistenceException {
      rethrow;
    } on Object {
      throw const PersistenceException.readFailed();
    }
  }

  /// Stable audit order, independent of wall-clock ties or clock skew.
  List<StoredEvent> readEvents({int afterSequence = 0}) => List.unmodifiable(
        _events.where((stored) => stored.sequence > afterSequence),
      );

  ObjectProjection? readProjection(String objectType, String objectId) =>
      _projections['$objectType:$objectId'];

  Map<String, ObjectProjection> readAllProjections() =>
      UnmodifiableMapView(Map<String, ObjectProjection>.of(_projections));

  /// Stable creation order. Acknowledged entries remain queryable for tests.
  List<OutboxEntry> readOutbox({
    int afterSequence = 0,
    bool includeAcknowledged = false,
  }) =>
      List.unmodifiable(
        _outbox.where(
          (entry) =>
              entry.sequence > afterSequence &&
              (includeAcknowledged || !entry.acknowledged),
        ),
      );

  bool acknowledgeOutbox(int sequence) {
    final index = _outbox.indexWhere((entry) => entry.sequence == sequence);
    if (index < 0) return false;
    if (_outbox[index].acknowledged) return true;
    final next = List<OutboxEntry>.of(_outbox);
    next[index] = next[index].acknowledge();
    _outbox = next;
    return true;
  }
}

bool _sameEventContent(EventEnvelope left, EventEnvelope right) =>
    EventEnvelopeJsonCodec.encodeString(left) ==
    EventEnvelopeJsonCodec.encodeString(right);

bool _isReducerConflict(String? reason) => switch (reason) {
      ReductionReason.illegalStateTransition ||
      ReductionReason.unsupportedEventType ||
      ReductionReason.unsupportedEventVersion ||
      ReductionReason.missingSubject ||
      ReductionReason.missingExecutionRecord ||
      ReductionReason.invalidDeletionTombstone =>
        true,
      _ => false,
    };
