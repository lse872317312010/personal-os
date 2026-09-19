import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

abstract final class StrategySessionRestoreFailureCode {
  static const ambiguousOpenSessions =
      'strategy.restore_ambiguous_open_sessions';
  static const malformedState = 'strategy.restore_malformed_state';
}

final class StrategySessionRestoreFailure implements Exception {
  const StrategySessionRestoreFailure(this.code);

  final String code;

  @override
  String toString() => 'StrategySessionRestoreFailure($code)';
}

/// Durable state needed to resume the Android strategy workflow.
final class StrategySessionView {
  const StrategySessionView({
    required this.sessionId,
    required this.sessionRevision,
    required this.agentId,
    this.strategyId,
    this.strategyRevision = 0,
    this.strategyState,
    this.proposalTitle,
    this.proposalRationale,
    this.parentStrategyRef,
    this.proposalEvidenceRefs = const <String>[],
    this.executionId,
    this.outcomeId,
    this.reviewId,
    this.reviewState,
    this.reviewSummary,
    this.reviewConclusion,
    this.reviewEvidenceRefs = const <String>[],
  });

  final EntityId sessionId;
  final int sessionRevision;
  final String agentId;
  final EntityId? strategyId;
  final int strategyRevision;
  final String? strategyState;
  final String? proposalTitle;
  final String? proposalRationale;
  final String? parentStrategyRef;
  final List<String> proposalEvidenceRefs;
  final EntityId? executionId;
  final EntityId? outcomeId;
  final EntityId? reviewId;
  final String? reviewState;
  final String? reviewSummary;
  final String? reviewConclusion;
  final List<String> reviewEvidenceRefs;
}

/// Replays the complete encrypted profile history and returns the only open
/// Agent session. Closed and failed sessions never reappear in controller state.
final class StrategySessionQueryHandler {
  const StrategySessionQueryHandler(this._eventStore);

  final EventStore _eventStore;

  Future<StrategySessionView?> execute(EntityId profileId) async {
    final events = _eventStore is CompleteProfileHistoryReader
        ? await (_eventStore as CompleteProfileHistoryReader)
            .readCompleteProfileHistory(profileId)
        : await _eventStore.readBySubject(
            ObjectRef(type: 'profile', id: profileId),
          );
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    final order = <String, int>{};
    for (var index = 0; index < events.length; index += 1) {
      final event = events[index];
      order[event.eventId] = index;
      final reduction = reduceCore(
        projections: projections,
        seenEventIds: seen,
        event: event,
      );
      if (reduction.disposition != ReductionDisposition.applied) continue;
      projections = Map<String, ObjectProjection>.of(reduction.projections);
      seen = Set<String>.of(reduction.seenEventIds);
    }

    final openSessions = projections.values
        .where((projection) =>
            projection.objectType == 'agent_session' &&
            (projection.state == 'opened' ||
                projection.state == 'proposalSubmitted'))
        .toList(growable: false);
    if (openSessions.isEmpty) return null;
    if (openSessions.length != 1) {
      throw const StrategySessionRestoreFailure(
        StrategySessionRestoreFailureCode.ambiguousOpenSessions,
      );
    }
    final session = openSessions.single;
    final agentId = _string(session.attributes['agent_id']);
    if (agentId == null || agentId.trim().isEmpty) {
      throw const StrategySessionRestoreFailure(
        StrategySessionRestoreFailureCode.malformedState,
      );
    }

    final strategy = _latest(
      projections.values.where((projection) =>
          projection.objectType == 'strategy' &&
          projection.attributes['created_by_session'] == session.id.value),
      order,
    );
    final strategyId = strategy?.id;
    final execution = strategyId == null
        ? null
        : _latest(
            projections.values.where((projection) =>
                projection.objectType == 'execution' &&
                _refId(projection.attributes['strategy_ref']) ==
                    strategyId.value),
            order,
          );
    final outcome = execution == null
        ? null
        : _latest(
            projections.values.where((projection) =>
                projection.objectType == 'outcome' &&
                _refId(projection.attributes['execution_ref']) ==
                    execution.id.value),
            order,
          );
    final review = _latest(
      projections.values.where((projection) =>
          projection.objectType == 'review' &&
          projection.attributes['reviewed_by_session'] == session.id.value),
      order,
    );

    return StrategySessionView(
      sessionId: session.id,
      sessionRevision: session.revision.value,
      agentId: agentId,
      strategyId: strategy?.id,
      strategyRevision: strategy?.revision.value ?? 0,
      strategyState: strategy?.state,
      proposalTitle: _string(strategy?.attributes['title']),
      proposalRationale: _string(strategy?.attributes['rationale']),
      parentStrategyRef: _formatRef(strategy?.attributes['parent_strategy']),
      proposalEvidenceRefs: _formatRefs(<Object?>[
        ..._list(strategy?.attributes['goal_refs']),
        ..._list(strategy?.attributes['asset_refs']),
      ]),
      executionId: execution?.id,
      outcomeId: outcome?.id,
      reviewId: review?.id,
      reviewState: review?.state,
      reviewSummary: _string(review?.attributes['summary']),
      reviewConclusion: _string(review?.attributes['conclusion']),
      reviewEvidenceRefs: _formatRefs(<Object?>[
        if (review?.attributes['strategy_ref'] != null)
          review!.attributes['strategy_ref'],
        ..._list(review?.attributes['execution_refs']),
        ..._list(review?.attributes['outcome_refs']),
        ..._list(review?.attributes['feedback_refs']),
      ]),
    );
  }
}

ObjectProjection? _latest(
  Iterable<ObjectProjection> values,
  Map<String, int> order,
) {
  ObjectProjection? latest;
  var latestOrder = -1;
  for (final value in values) {
    final valueOrder = order[value.lastEventId] ?? -1;
    if (valueOrder > latestOrder) {
      latest = value;
      latestOrder = valueOrder;
    }
  }
  return latest;
}

List<Object?> _list(Object? value) =>
    value is List ? List<Object?>.of(value) : const <Object?>[];

String? _string(Object? value) => value is String ? value : null;

String? _refId(Object? value) {
  if (value is! Map) return null;
  final id = value['id'];
  return id is String ? id : null;
}

String? _formatRef(Object? value) {
  if (value is! Map) return null;
  final type = value['type'];
  final id = value['id'];
  final revision = value['revision'];
  if (type is! String || id is! String || revision is! int) return null;
  return '$type:$id@$revision';
}

List<String> _formatRefs(Iterable<Object?> values) =>
    List<String>.unmodifiable(values.map(_formatRef).whereType<String>());
