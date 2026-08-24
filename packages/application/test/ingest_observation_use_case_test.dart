import 'dart:async';

import 'package:personal_os_application/application.dart';
import 'package:personal_os_blob_engine/blob_engine.dart';
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
  final consent = ObjectRef(type: 'consent', id: EntityId('consent-1'));
  final access = BlobAccessContext(
    actorRef: 'user:owner',
    purpose: 'appearance-analysis',
    consentRef: 'consent:appearance-v1',
  );

  IngestObservationUseCase _useCase(_Ingestion ingestion, _Store store) =>
      IngestObservationUseCase(
        ingestion: ingestion,
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: _Ids(),
          clock: _Clock(),
        ),
      );

  IngestObservationCommand _command(
    Stream<List<int>> bytes, {
    Sensitivity sensitivity = Sensitivity.d3,
  }) =>
      IngestObservationCommand(
        bytes: bytes,
        mediaType: 'image/jpeg',
        sensitivity: sensitivity,
        access: access,
        profileId: EntityId('profile-1'),
        observationContext: 'profile appearance capture',
        consentRef: consent,
        actor: actor,
        correlationId: 'corr-observation',
      );

  test('ingests first and records only the returned opaque ref', () async {
    final ingestion = _Ingestion();
    final store = _Store();
    final result = await _useCase(ingestion, store).execute(
      _command(Stream<List<int>>.value(<int>[1, 2, 3])),
    );

    expect(ingestion.calls, 1);
    expect(store.events.single.payload, <String, Object?>{
      'observation_id': 'observation-1',
      'blob_ref': 'blob://opaque-1',
      'media_type': 'image/jpeg',
      'observation_context': 'profile appearance capture',
    });
    expect(result.eventId, 'event-1');
    expect(
        store.events.single.payload.keys,
        everyElement(isNot(anyOf(
          'path',
          'uri',
          'raw_bytes',
          'bytes',
          'content',
          'plaintext',
        ))));
  });

  test('fails closed when ingestion rejects input and does not append',
      () async {
    final store = _Store();
    final ingestion = _Ingestion()..failure = const _SafeIngestionFailure();
    await expectLater(
      _useCase(ingestion, store).execute(_command(_listeningStream())),
      throwsA(isA<_SafeIngestionFailure>()),
    );
    expect(ingestion.calls, 1);
    expect(store.events, isEmpty);
  });

  test('rejects a legacy ingestion adapter before consuming input', () async {
    var listened = false;
    final store = _Store();
    await expectLater(
      IngestObservationUseCase(
        ingestion: _LegacyIngestion(),
        recordObservation: RecordObservationUseCase(
          eventStore: store,
          ids: _Ids(),
          clock: _Clock(),
        ),
      ).execute(_command(Stream<List<int>>.multi((controller) {
        listened = true;
        controller.close();
      }))),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.rollbackUnavailable,
      )),
    );
    expect(listened, isFalse);
    expect(store.events, isEmpty);
  });

  test('D4 is rejected by the ingestion boundary before listening', () async {
    final store = _Store();
    final ingestion = _Ingestion()..failure = const _SafeIngestionFailure();
    var listened = false;
    final command = _command(
      Stream<List<int>>.multi((controller) {
        listened = true;
        controller.add(<int>[1]);
        controller.close();
      }),
      sensitivity: Sensitivity.d4,
    );
    await expectLater(
      _useCase(ingestion, store).execute(command),
      throwsA(isA<_SafeIngestionFailure>()),
    );
    expect(listened, isFalse);
    expect(store.events, isEmpty);
  });

  test('does not append when recording rejects the opaque ref', () async {
    final ingestion = _Ingestion()..ref = BlobRef('/tmp/leaked-path');
    final store = _Store();
    await expectLater(
      _useCase(ingestion, store).execute(_command(Stream<List<int>>.empty())),
      throwsA(isA<ObservationUseCaseFailure>()),
    );
    expect(ingestion.calls, 1);
    expect(store.events, isEmpty);
  });

  test('discards the blob when recording append fails', () async {
    final ingestion = _Ingestion();
    final store = _Store()..failure = StateError('adapter details');
    await expectLater(
      _useCase(ingestion, store).execute(_command(Stream<List<int>>.empty())),
      throwsA(isA<ObservationUseCaseFailure>().having(
        (error) => error.code,
        'code',
        ObservationFailureCode.appendFailed,
      )),
    );
    expect(ingestion.discarded, <BlobRef>[BlobRef('blob://opaque-1')]);
    expect(store.events, isEmpty);
  });

  test('keeps the append failure stable when discard also fails', () async {
    final ingestion = _Ingestion()..discardFailure = StateError('sql path');
    final store = _Store()..failure = StateError('raw append details');
    await expectLater(
      _useCase(ingestion, store).execute(_command(Stream<List<int>>.empty())),
      throwsA(isA<ObservationUseCaseFailure>()
          .having((error) => error.code, 'code',
              ObservationFailureCode.appendFailed)
          .having(
              (error) => error.toString(), 'safe', isNot(contains('sql path')))
          .having((error) => error.toString(), 'safe',
              isNot(contains('raw append details')))),
    );
    expect(ingestion.discardCalls, 1);
    expect(store.events, isEmpty);
  });

}

Stream<List<int>> _listeningStream() => Stream<List<int>>.multi((controller) {
      controller.add(<int>[1]);
      controller.close();
    });

final class _Ingestion implements BlobIngestionContract, BlobIngestionRollback {
  int calls = 0;
  int discardCalls = 0;
  BlobRef ref = BlobRef('blob://opaque-1');
  Object? failure;
  Object? discardFailure;

  @override
  Future<BlobRef> ingest({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    await bytes.drain<void>();
    return ref;
  }

  final List<BlobRef> discarded = <BlobRef>[];

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) async {
    discardCalls++;
    if (discardFailure != null) throw discardFailure!;
    discarded.add(ref);
  }
}

final class _LegacyIngestion implements BlobIngestionContract {
  @override
  Future<BlobRef> ingest({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async =>
      BlobRef('blob://legacy');
}

final class _SafeIngestionFailure implements Exception {
  const _SafeIngestionFailure();
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
  final List<EventEnvelope> events = <EventEnvelope>[];
  Object? failure;

  @override
  Future<void> appendAll(List<EventEnvelope> incoming) async {
    if (failure != null) throw failure!;
    events.addAll(incoming);
  }

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject,
          {int? limit}) async =>
      const <EventEnvelope>[];

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;
}
