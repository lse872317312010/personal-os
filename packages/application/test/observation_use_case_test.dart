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

  test('records one profile-scoped observation with safe payload', () async {
    final store = _Store();
    final result = await _useCase(store).execute(_command());

    expect(result.observationId, 'observation-1');
    expect(
        store.batches.single.single.eventType, EventTypes.observationRecorded);
    final event = store.batches.single.single;
    expect(event.sensitivity, Sensitivity.d3);
    expect(event.subjectRefs.map((ref) => ref.type), <String>[
      'observation',
      'profile',
    ]);
    expect(event.consentRefs.single, _consent);
    expect(event.payload, <String, Object?>{
      'observation_id': 'observation-1',
      'blob_ref': 'blob://vault/photo-1',
      'media_type': 'image/jpeg',
      'observation_context': 'profile appearance capture',
    });
    expect(
      event.payload.keys,
      everyElement(isNot(anyOf(
        'path',
        'uri',
        'raw_bytes',
        'bytes',
        'hash',
        'content',
      ))),
    );
  });

  test('rejects D4 before writing', () async {
    final store = _Store();
    await expectLater(
      _useCase(store).execute(_command(sensitivity: Sensitivity.d4)),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.d4Forbidden,
      )),
    );
    expect(store.batches, isEmpty);
  });

  test('requires a consent reference', () async {
    final store = _Store();
    await expectLater(
      _useCase(store).execute(_command(includeConsent: false)),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.consentRequired,
      )),
    );
    expect(store.batches, isEmpty);
  });

  test('rejects non-opaque references', () async {
    final store = _Store();
    await expectLater(
      _useCase(store).execute(_command(blobRef: BlobRef('/tmp/photo.jpg'))),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.invalidBlobRef,
      )),
    );
    expect(store.batches, isEmpty);
  });

  test('maps an atomic append failure to a stable error without leaking it',
      () async {
    final store = _Store()..failure = StateError('sql path leaked');
    await expectLater(
      _useCase(store).execute(_command()),
      throwsA(isA<ObservationUseCaseFailure>()
          .having((error) => error.code, 'code',
              ObservationFailureCode.appendFailed)
          .having((error) => error.toString(), 'safe error',
              contains('append_failed'))),
    );
    expect(store.batches, isEmpty);
  });

  RecordObservationUseCase _useCase(_Store store) => RecordObservationUseCase(
        eventStore: store,
        ids: _Ids(),
        clock: _Clock(),
      );

  final _consent = ObjectRef(type: 'consent', id: EntityId('consent-1'));

  RecordObservationCommand _command({
    BlobRef? blobRef,
    bool includeConsent = true,
    Sensitivity sensitivity = Sensitivity.d3,
  }) =>
      RecordObservationCommand(
        profileId: EntityId('profile-1'),
        blobRef: blobRef ?? BlobRef('blob://vault/photo-1'),
        mediaType: 'image/jpeg',
        observationContext: 'profile appearance capture',
        consentRef: includeConsent ? _consent : null,
        actor: actor,
        correlationId: 'corr-observation',
        sensitivity: sensitivity,
      );
}

final class _Ids implements IdGenerator {
  var _observation = 0;
  var _event = 0;

  @override
  String nextId(String namespace) => namespace == 'observation'
      ? 'observation-${++_observation}'
      : 'event-${++_event}';
}

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 8, 24, 1, 2, 3);
}

final class _Store implements EventStore {
  final List<List<EventEnvelope>> batches = <List<EventEnvelope>>[];
  Object? failure;

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    if (failure != null) throw failure!;
    batches.add(List<EventEnvelope>.unmodifiable(events));
  }

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject,
          {int? limit}) async =>
      const <EventEnvelope>[];

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;
}
