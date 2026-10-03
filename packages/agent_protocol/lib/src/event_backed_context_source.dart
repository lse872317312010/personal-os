import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'bundles.dart';
import 'service.dart';

/// Builds Agent-visible context from the profile's append-only event history.
///
/// The source never accepts a profile identifier from the caller. It is bound
/// to one profile at composition time and verifies that every querying session
/// belongs to that profile and is still open.
final class EventBackedAgentContextSource implements AgentContextSource {
  const EventBackedAgentContextSource({
    required EventStore eventStore,
    required EntityId profileId,
  })  : _eventStore = eventStore,
        _profileId = profileId;

  final EventStore _eventStore;
  final EntityId _profileId;

  @override
  Future<ContextPage> query({
    required EntityId sessionId,
    required String purpose,
    required Set<String> objectTypes,
    String? cursor,
    int limit = 100,
  }) async {
    await _requireOpenOwnedSession(sessionId);
    final offset = _decodeCursor(cursor);
    final current = await _profileRecords();
    final records = current
        .where((record) =>
            objectTypes.isEmpty || objectTypes.contains(record.ref.type))
        .where((record) => !_unavailableStates.contains(record.data['state']))
        .where((record) => record.ref.type != 'personal_asset' ||
            !const <String>{'archived', 'superseded'}.contains(record.data['state']))
        .toList(growable: false)
      ..sort((left, right) {
        final typeOrder = left.ref.type.compareTo(right.ref.type);
        return typeOrder != 0
            ? typeOrder
            : left.ref.id.value.compareTo(right.ref.id.value);
      });
    if (offset > records.length) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'context cursor is outside the result set',
      );
    }
    final requestedEnd = offset + limit;
    final end = requestedEnd < records.length ? requestedEnd : records.length;
    return ContextPage(
      records: records.sublist(offset, end),
      cursor: end < records.length ? end.toString() : null,
      hasMore: end < records.length,
    );
  }

  @override
  Future<ContextRecord?> get({
    required EntityId sessionId,
    required ObjectRef ref,
  }) async {
    await _requireOpenOwnedSession(sessionId);
    final requestedRevision = ref.revision;
    if (requestedRevision == null) {
      throw const AgentProtocolException(
        AgentProtocolError.unpinnedReference,
        'context object reads require a pinned reference',
      );
    }
    final events = await _eventStore.readBySubject(
      ObjectRef(type: ref.type, id: ref.id),
    );
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    final key = '${ref.type}:${ref.id.value}';
    ObjectRef? legacyGoal;
    for (final event in events) {
      if (event.eventType == EventTypes.personalAssetRecorded) {
        final goals = event.sourceRefs.where((source) => source.type == 'goal');
        if (goals.isNotEmpty) legacyGoal = goals.first;
      }
      final reduction = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: event,
      );
      if (reduction.disposition != ReductionDisposition.applied) continue;
      projections = Map<String, ObjectProjection>.of(reduction.projections);
      seen = Set<String>.of(reduction.seenEventIds);
      final projection = projections[key];
      if (projection?.revision == requestedRevision) {
        return _unavailableStates.contains(projection!.state)
            ? null
            : _record(projection, legacyGoal: legacyGoal);
      }
    }
    return null;
  }

  Future<List<ContextRecord>> _profileRecords() async {
    final events = await _eventStore.readBySubject(
      ObjectRef(type: 'profile', id: _profileId),
    );
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    final legacyGoals = <String, ObjectRef>{};
    for (final event in events) {
      final reduction = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: event,
      );
      if (reduction.disposition != ReductionDisposition.applied) continue;
      projections = Map<String, ObjectProjection>.of(reduction.projections);
      seen = Set<String>.of(reduction.seenEventIds);
      if (event.eventType == EventTypes.personalAssetRecorded) {
        final goals = event.sourceRefs.where((source) => source.type == 'goal');
        if (goals.isNotEmpty) {
          legacyGoals[event.subjectRefs.first.id.value] = goals.first;
        }
      }
    }
    return projections.values.map((projection) => _record(projection,
        legacyGoal: projection.objectType == 'personal_asset'
            ? legacyGoals[projection.id.value] : null)).toList();
  }

  Future<void> _requireOpenOwnedSession(EntityId sessionId) async {
    final events = await _eventStore.readBySubject(
      ObjectRef(type: 'agent_session', id: sessionId),
    );
    final ownsSession = events.any(
      (event) =>
          event.eventType == EventTypes.agentSessionOpened &&
          event.subjectRefs.any(
            (subject) => subject.type == 'profile' && subject.id == _profileId,
          ),
    );
    if (!ownsSession) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'Agent session does not belong to this profile',
      );
    }

    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    for (final event in events) {
      final reduction = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: event,
      );
      if (reduction.disposition != ReductionDisposition.applied) continue;
      projections = Map<String, ObjectProjection>.of(reduction.projections);
      seen = Set<String>.of(reduction.seenEventIds);
    }
    final state = projections['agent_session:${sessionId.value}']?.state;
    if (state != 'opened' && state != 'proposalSubmitted') {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'Agent session is not open',
      );
    }
  }
}

ContextRecord _record(ObjectProjection projection, {ObjectRef? legacyGoal}) => ContextRecord(
      ref: ObjectRef(
        type: projection.objectType,
        id: projection.id,
        revision: projection.revision,
      ),
      data: <String, Object?>{
        'state': projection.state,
        'last_event_id': projection.lastEventId,
        ...projection.attributes,
        if (!projection.attributes.containsKey('goal_ref') && legacyGoal != null)
          'goal_ref': legacyGoal.toJson(),
      },
    );

int _decodeCursor(String? cursor) {
  if (cursor == null) return 0;
  final value = int.tryParse(cursor);
  if (value == null || value < 0) {
    throw const AgentProtocolException(
      AgentProtocolError.invalidRequest,
      'context cursor is invalid',
    );
  }
  return value;
}

const _unavailableStates = <String>{
  'deleted',
  'unavailable_pending_deletion',
};
