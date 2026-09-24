import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'package:personal_os_app/src/composition/agent_access_event_store.dart';

void main() {
  test('locked Agent lease denies storage reads and writes', () async {
    final delegate = _PendingReadStore();
    final store = AgentAccessEventStore(
      inner: delegate,
      isAuthorized: () => false,
    );

    await expectLater(
      store.readBySubject(
        ObjectRef(type: 'profile', id: EntityId('primary-user')),
      ),
      throwsA(isA<PersistenceException>()),
    );
    await expectLater(
      store.appendAll(const <EventEnvelope>[]),
      throwsA(isA<PersistenceException>()),
    );
    expect(delegate.appendCalls, 0);
    expect(delegate.readCalls, 0);
  });

  test('a pending read cannot continue into a write after lease revocation',
      () async {
    var authorized = true;
    final delegate = _PendingReadStore();
    final store = AgentAccessEventStore(
      inner: delegate,
      isAuthorized: () => authorized,
    );

    final pendingRead = store.readBySubject(
      ObjectRef(type: 'agent_session', id: EntityId('session')),
    );
    expect(delegate.readCalls, 1);

    authorized = false;
    delegate.completeRead();
    await pendingRead;

    await expectLater(
      store.appendAll(const <EventEnvelope>[]),
      throwsA(isA<PersistenceException>()),
    );
    expect(delegate.appendCalls, 0);
  });
}

final class _PendingReadStore implements EventStore {
  final Completer<List<EventEnvelope>> _read = Completer<List<EventEnvelope>>();
  int readCalls = 0;
  int appendCalls = 0;

  void completeRead() => _read.complete(const <EventEnvelope>[]);

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    appendCalls++;
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) {
    readCalls++;
    return _read.future;
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;
}
