import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final actor = ActorRef(
    actorId: 'user-1',
    actorType: ActorType.user,
    authoritySource: 'local-session',
  );

  test('request creates opaque tombstone and profile-linked barrier', () async {
    final store = _Store();
    final result = await _useCase(store).request(
      RequestDeletionCommand(
        profileId: EntityId('profile-1'),
        deletionId: EntityId('delete-1'),
        actor: actor,
        correlationId: 'corr-request',
      ),
    );

    expect(result.tombstoneRef, 'opaque-1');
    expect(store.batches.single.single.eventType, EventTypes.deletionRequested);
    final event = store.batches.single.single;
    expect(event.subjectRefs.map((ref) => ref.type), <String>[
      'deletion',
      'profile',
    ]);
    expect(event.subjectRefs.first.id, EntityId('delete-1'));
    expect(event.payload['expected_revision'], 0);
    expect(event.payload['contains_content_hash'], isFalse);
    expect(event.payload['tombstone_id'], result.tombstoneRef);
  });

  test('completion is a separate atomic batch with safe logical refs', () async {
    final store = _Store();
    final result = await _useCase(store).complete(
      CompleteDeletionCommand(
        profileId: EntityId('profile-1'),
        deletionId: EntityId('delete-1'),
        tombstoneRef: 'opaque-1',
        erasedRefs: const <String>['source:source-1', 'blob:blob-1'],
        actor: actor,
        correlationId: 'corr-complete',
        expectedDeletionRevision: 1,
      ),
    );

    expect(result.revision, 2);
    expect(store.batches.single.single.eventType, EventTypes.deletionCompleted);
    final event = store.batches.single.single;
    expect(event.subjectRefs.map((ref) => ref.type), <String>[
      'deletion',
      'profile',
      'tombstone',
    ]);
    expect(event.subjectRefs.last.id.value, event.payload['tombstone_id']);
    expect(event.payload['erased_refs'], <String>[
      'source:source-1',
      'blob:blob-1',
    ]);
  });

  test('rejects non-user actors and unsafe refs without writing', () async {
    final store = _Store();
    final useCase = _useCase(store);
    final agent = ActorRef(
      actorId: 'agent-1',
      actorType: ActorType.agent,
      authoritySource: 'system',
      onBehalfOf: 'user-1',
    );

    await expectLater(
      useCase.request(
        RequestDeletionCommand(
          profileId: EntityId('profile-1'),
          deletionId: EntityId('delete-1'),
          actor: agent,
          correlationId: 'corr',
        ),
      ),
      throwsA(isA<DeletionUseCaseFailure>().having(
        (error) => error.code,
        'code',
        DeletionFailureCode.userActorRequired,
      )),
    );
    await expectLater(
      useCase.complete(
        CompleteDeletionCommand(
          profileId: EntityId('profile-1'),
          deletionId: EntityId('delete-1'),
          tombstoneRef: 'opaque-1',
          erasedRefs: const <String>['/private/photo.jpg'],
          actor: actor,
          correlationId: 'corr',
          expectedDeletionRevision: 1,
        ),
      ),
      throwsA(isA<DeletionUseCaseFailure>().having(
        (error) => error.code,
        'code',
        DeletionFailureCode.invalidErasedRefs,
      )),
    );
    expect(store.batches, isEmpty);
  });

  test('rejects hash, path, and content-shaped logical refs', () async {
    final store = _Store();
    for (final ref in const <String>[
      'hash:abc123',
      'path:photo-1',
      'content:photo-1',
    ]) {
      await expectLater(
        _useCase(store).complete(
          CompleteDeletionCommand(
            profileId: EntityId('profile-1'),
            deletionId: EntityId('delete-1'),
            tombstoneRef: 'opaque-1',
            erasedRefs: <String>[ref],
            actor: actor,
            correlationId: 'corr',
            expectedDeletionRevision: 1,
          ),
        ),
        throwsA(isA<DeletionUseCaseFailure>().having(
          (error) => error.code,
          'code',
          DeletionFailureCode.invalidErasedRefs,
        )),
      );
    }
    expect(store.batches, isEmpty);
  });

  test('does not append a partial batch when store rejects it', () async {
    final store = _Store()..rejectWrites = true;
    await expectLater(
      _useCase(store).request(
        RequestDeletionCommand(
          profileId: EntityId('profile-1'),
          deletionId: EntityId('delete-1'),
          actor: actor,
          correlationId: 'corr',
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect(store.batches, isEmpty);
  });
}

DeletionUseCase _useCase(_Store store) => DeletionUseCase(
      eventStore: store,
      ids: _Ids(),
      clock: _Clock(),
    );

final class _Store implements EventStore {
  final batches = <List<EventEnvelope>>[];
  bool rejectWrites = false;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    if (rejectWrites) throw StateError('transaction rejected');
    batches.add(List<EventEnvelope>.unmodifiable(events));
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject, {int? limit}) async =>
      const <EventEnvelope>[];
}

final class _Ids implements IdGenerator {
  int value = 0;

  @override
  String nextId(String namespace) => '$namespace-${++value}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 8, 24, 10);
}
