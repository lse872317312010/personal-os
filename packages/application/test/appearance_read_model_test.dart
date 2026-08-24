import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('rebuilds the appearance session from profile-scoped events', () async {
    final store = _Store(_events());
    final view = await AppearanceSessionQueryHandler(store).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1')),
    );

    expect(view.hasAnalysis, isTrue);
    expect(view.claims, hasLength(2));
    expect(view.claims.first.statement, '顶部体积不足');
    expect(view.goal?.state, GoalState.draft.name);
    expect(view.plan?.goalRef, 'goal-1');
    expect(view.tasks.single.state, TaskState.planned.name);
    expect(view.events, hasLength(5));
  });

  test('replays state transitions without losing claim data', () async {
    final events = _events()
      ..add(_event(
        id: 'claim-confirmed',
        type: EventTypes.claimConfirmed,
        subject: ObjectRef(type: 'claim', id: EntityId('claim-1')),
        payload: const <String, Object?>{'expected_revision': 1},
      ));
    final view = await AppearanceSessionQueryHandler(_Store(events)).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1')),
    );

    expect(view.claims.first.state, ClaimState.confirmed.name);
    expect(view.claims.first.statement, '顶部体积不足');
  });

  test('projects only safe metadata from valid profile observations', () async {
    final view = await AppearanceSessionQueryHandler(_Store(<EventEnvelope>[
      _observationEvent(
        id: 'observation-event-1',
        observationId: 'observation-1',
        payload: const <String, Object?>{
          'observation_id': 'observation-1',
          'blob_ref': 'blob://vault/photo-1',
          'media_type': 'image/jpeg',
          'observation_context': 'profile appearance capture',
          'raw_bytes': 'must not be projected',
        },
      ),
    ])).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1')),
    );

    expect(view.observations, hasLength(1));
    expect(view.observations.single.id, 'observation-1');
    expect(view.observations.single.blobRef, 'blob://vault/photo-1');
    expect(view.observations.single.mediaType, 'image/jpeg');
    expect(view.observations.single.context, 'profile appearance capture');
    expect(view.observations.single.eventId, 'observation-event-1');
  });

  test('ignores D4, malformed, mismatched, and out-of-profile observations',
      () async {
    final events = <EventEnvelope>[
      _observationEvent(
        id: 'd4-event',
        observationId: 'observation-d4',
        sensitivity: Sensitivity.d4,
      ),
      _observationEvent(
        id: 'bad-ref-event',
        observationId: 'observation-bad-ref',
        payload: const <String, Object?>{
          'observation_id': 'observation-bad-ref',
          'blob_ref': '/tmp/photo.jpg',
          'media_type': 'image/jpeg',
          'observation_context': 'context',
        },
      ),
      _observationEvent(
        id: 'mismatch-event',
        observationId: 'observation-subject',
        payload: const <String, Object?>{
          'observation_id': 'observation-payload',
          'blob_ref': 'blob://vault/photo-2',
          'media_type': 'image/jpeg',
          'observation_context': 'context',
        },
      ),
      _observationEvent(
        id: 'other-profile-event',
        observationId: 'observation-other',
        profileId: 'profile-2',
      ),
    ];
    final view = await AppearanceSessionQueryHandler(_Store(events)).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1')),
    );

    expect(view.observations, isEmpty);
  });

  test('keeps observation list backward-compatible by default', () {
    final view = AppearanceSessionView(
      profileId: EntityId('profile-1'),
      events: <EventEnvelope>[],
      claims: <AppearanceClaimView>[],
      goal: null,
      plan: null,
      tasks: <AppearanceTaskView>[],
      review: null,
      consent: null,
    );

    expect(view.observations, isEmpty);
  });

  test('keeps reconstruction bounded to the requested history limit', () async {
    final store = _Store(_events());
    final view = await AppearanceSessionQueryHandler(store).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1'), limit: 2),
    );

    expect(view.events, hasLength(2));
    expect(view.claims, hasLength(2));
    expect(view.goal, isNull);
  });

  test('reconstructs revoked consent instead of inferring a UI checkbox',
      () async {
    final view = await AppearanceSessionQueryHandler(_Store(<EventEnvelope>[
      _event(
        id: 'consent-requested',
        type: EventTypes.consentRequested,
        subject: ObjectRef(type: 'consent', id: EntityId('consent-1')),
        payload: const <String, Object?>{
          'expected_revision': 0,
          'consent_revision': 1,
        },
      ),
      _event(
        id: 'consent-granted',
        type: EventTypes.consentGranted,
        subject: ObjectRef(type: 'consent', id: EntityId('consent-1')),
        payload: const <String, Object?>{
          'expected_revision': 1,
          'consent_revision': 1,
        },
      ),
      _event(
        id: 'consent-revoked',
        type: EventTypes.consentRevoked,
        subject: ObjectRef(type: 'consent', id: EntityId('consent-1')),
        payload: const <String, Object?>{
          'expected_revision': 2,
          'consent_revision': 1,
        },
      ),
    ])).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1')),
    );

    expect(view.consent?.state, ConsentState.revoked.name);
    expect(view.consent?.stateRevision, 3);
    expect(view.consent?.consentRevision, 1);
  });

  test('reconstructs feedback completion, skip, and review lifecycle',
      () async {
    final task = ObjectRef(type: 'task', id: EntityId('task-1'));
    final review = ObjectRef(type: 'review', id: EntityId('review-1'));
    final profile = ObjectRef(type: 'profile', id: EntityId('profile-1'));
    final events = <EventEnvelope>[
      _event(
        id: 'task-planned',
        type: EventTypes.taskPlanned,
        subject: task,
        payload: const <String, Object?>{
          'expected_revision': 0,
          'title': '尝试纹理短发',
        },
      ),
      _eventWithSubjects(
        id: 'task-completed',
        type: EventTypes.taskCompleted,
        subjects: <ObjectRef>[task, profile],
        payload: const <String, Object?>{'expected_revision': 1},
      ),
      _eventWithSubjects(
        id: 'task-skipped',
        type: EventTypes.taskSkipped,
        subjects: <ObjectRef>[task, profile],
        payload: const <String, Object?>{'expected_revision': 2},
      ),
      _eventWithSubjects(
        id: 'review-created',
        type: EventTypes.reviewCreated,
        subjects: <ObjectRef>[review, profile],
        payload: const <String, Object?>{'expected_revision': 0},
      ),
      _eventWithSubjects(
        id: 'review-user-reviewed',
        type: EventTypes.reviewUserReviewed,
        subjects: <ObjectRef>[review, profile],
        payload: const <String, Object?>{'expected_revision': 1},
      ),
      _eventWithSubjects(
        id: 'review-rejected',
        type: EventTypes.reviewRejected,
        subjects: <ObjectRef>[review, profile],
        payload: const <String, Object?>{'expected_revision': 2},
      ),
    ];

    final view = await AppearanceSessionQueryHandler(_Store(events)).execute(
      GetAppearanceHistoryQuery(profileId: EntityId('profile-1')),
    );

    expect(view.tasks.single.state, TaskState.skipped.name);
    expect(view.review?.id, 'review-1');
    expect(view.review?.state, ReviewState.rejected.name);
  });
}

List<EventEnvelope> _events() => <EventEnvelope>[
      _event(
        id: 'claim-1-event',
        type: EventTypes.claimProposed,
        subject: ObjectRef(type: 'claim', id: EntityId('claim-1')),
        payload: const <String, Object?>{
          'expected_revision': 0,
          'dimension': 'hair',
          'statement': '顶部体积不足',
          'confidence': .8,
          'evidence_blob_ref': 'blob://photo-1',
        },
      ),
      _event(
        id: 'claim-2-event',
        type: EventTypes.claimProposed,
        subject: ObjectRef(type: 'claim', id: EntityId('claim-2')),
        payload: const <String, Object?>{
          'expected_revision': 0,
          'dimension': 'skin',
          'statement': '肤色略不均',
          'confidence': .7,
        },
      ),
      _event(
        id: 'goal-event',
        type: EventTypes.goalCreated,
        subject: ObjectRef(type: 'goal', id: EntityId('goal-1')),
        payload: const <String, Object?>{
          'expected_revision': 0,
          'title': '改善外貌呈现',
          'claim_refs': <String>['claim-1', 'claim-2'],
        },
      ),
      _event(
        id: 'plan-event',
        type: EventTypes.planDrafted,
        subject: ObjectRef(type: 'plan', id: EntityId('plan-1')),
        payload: const <String, Object?>{
          'expected_revision': 0,
          'goal_ref': 'goal-1',
          'title': '外貌改善行动计划',
        },
      ),
      _event(
        id: 'task-event',
        type: EventTypes.taskPlanned,
        subject: ObjectRef(type: 'task', id: EntityId('task-1')),
        payload: const <String, Object?>{
          'expected_revision': 0,
          'plan_ref': 'plan-1',
          'title': '尝试纹理短发',
          'rationale': '增强顶部轮廓',
        },
      ),
    ];

EventEnvelope _event({
  required String id,
  required String type,
  required ObjectRef subject,
  required Map<String, Object?> payload,
}) {
  return _eventWithSubjects(
    id: id,
    type: type,
    subjects: <ObjectRef>[
      subject,
      ObjectRef(type: 'profile', id: EntityId('profile-1')),
    ],
    payload: payload,
  );
}

EventEnvelope _observationEvent({
  required String id,
  required String observationId,
  String profileId = 'profile-1',
  Sensitivity sensitivity = Sensitivity.d3,
  Map<String, Object?>? payload,
}) =>
    _eventWithSubjects(
      id: id,
      type: EventTypes.observationRecorded,
      subjects: <ObjectRef>[
        ObjectRef(type: 'observation', id: EntityId(observationId)),
        ObjectRef(type: 'profile', id: EntityId(profileId)),
      ],
      payload: payload ?? <String, Object?>{
        'observation_id': observationId,
        'blob_ref': 'blob://vault/photo-1',
        'media_type': 'image/jpeg',
        'observation_context': 'context',
      },
      sensitivity: sensitivity,
    );

EventEnvelope _eventWithSubjects({
  required String id,
  required String type,
  required List<ObjectRef> subjects,
  required Map<String, Object?> payload,
  Sensitivity sensitivity = Sensitivity.d3,
}) {
  final instant = DateTime.utc(2026, 8, 24);
  return EventEnvelope(
    eventId: id,
    eventType: type,
    eventVersion: 1,
    occurredAt: instant,
    recordedAt: instant,
    actor: ActorRef(
      actorId: 'user-1',
      actorType: ActorType.user,
      authoritySource: 'local-session',
    ),
    subjectRefs: subjects,
    correlationId: 'corr-1',
    sensitivity: sensitivity,
    payload: payload,
  );
}

final class _Store implements EventStore {
  _Store(this.events);

  final List<EventEnvelope> events;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {}

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async => events.take(limit ?? events.length).toList(growable: false);
}
