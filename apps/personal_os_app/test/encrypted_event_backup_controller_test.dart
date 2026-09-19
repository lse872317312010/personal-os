import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/controller/encrypted_event_backup_controller.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

void main() {
  test('export validates and passes a lossless complete archive', () async {
    final event = _event('event-1');
    final store = _HistoryStore(<EventEnvelope>[event]);
    final port = _RecordingBackupPort();
    final controller = EncryptedEventBackupController(
      eventStore: store,
      port: port,
      profileId: EntityId('primary-user'),
    );

    await controller.exportBackup();

    expect(controller.status, EncryptedBackupStatus.succeeded);
    expect(controller.lastEventCount, 1);
    expect(port.suggestedName, matches(RegExp(r'^personal-os-\d{8}\.posb$')));
    final decoded = EventArchiveCodec.decode(port.exportedArchive!);
    expect(decoded.events.single.eventId, event.eventId);
  });

  test('restore authenticates before one atomic append and requests relock',
      () async {
    final event = _event('event-1');
    final store = _HistoryStore(const <EventEnvelope>[]);
    final port = _RecordingBackupPort(
      importedArchive: EventArchiveCodec.encode(<EventEnvelope>[event]),
    );
    var relocked = false;
    final controller = EncryptedEventBackupController(
      eventStore: store,
      port: port,
      profileId: EntityId('primary-user'),
      onRestoreCompleted: () => relocked = true,
    );

    await controller.restoreBackup();

    expect(controller.status, EncryptedBackupStatus.succeeded);
    expect(controller.lastEventCount, 1);
    expect(store.appendCalls, 1);
    expect(store.events.single.eventId, event.eventId);
    expect(relocked, isTrue);
  });

  test('cancelled native restore does not write', () async {
    final store = _HistoryStore(const <EventEnvelope>[]);
    final controller = EncryptedEventBackupController(
      eventStore: store,
      port: _RecordingBackupPort(),
      profileId: EntityId('primary-user'),
    );

    await controller.restoreBackup();

    expect(controller.status, EncryptedBackupStatus.cancelled);
    expect(store.appendCalls, 0);
  });
}

final class _RecordingBackupPort implements EncryptedEventBackupPort {
  _RecordingBackupPort({this.importedArchive});

  final String? importedArchive;
  String? exportedArchive;
  String? suggestedName;

  @override
  bool get available => true;

  @override
  Future<bool> exportEncryptedArchive({
    required String archiveJson,
    required String suggestedName,
  }) async {
    exportedArchive = archiveJson;
    this.suggestedName = suggestedName;
    return true;
  }

  @override
  Future<String?> importEncryptedArchive() async => importedArchive;
}

final class _HistoryStore
    implements EventStore, CompleteProfileHistoryReader {
  _HistoryStore(Iterable<EventEnvelope> seed)
      : events = List<EventEnvelope>.of(seed);

  final List<EventEnvelope> events;
  int appendCalls = 0;

  @override
  Future<void> appendAll(List<EventEnvelope> next) async {
    appendCalls += 1;
    events.addAll(next);
  }

  @override
  Future<List<EventEnvelope>> readCompleteProfileHistory(
    EntityId profileId, {
    int pageSize = 500,
  }) async =>
      List<EventEnvelope>.unmodifiable(events);

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    for (final event in events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      events
          .where(
            (event) => event.subjectRefs.any(
              (ref) => ref.type == subject.type && ref.id == subject.id,
            ),
          )
          .take(limit ?? events.length)
          .toList(growable: false);
}

EventEnvelope _event(String id) => EventEnvelope(
      eventId: id,
      eventType: EventTypes.agentSessionOpened,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 9, 19, 12),
      recordedAt: DateTime.utc(2026, 9, 19, 12),
      actor: ActorRef(
        actorId: 'harness',
        actorType: ActorType.agent,
        authoritySource: 'offline_bundle',
        sessionOrRunId: 'session-1',
        onBehalfOf: 'primary-user',
      ),
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'agent_session', id: EntityId('session-1')),
        ObjectRef(type: 'profile', id: EntityId('primary-user')),
      ],
      correlationId: 'session-1',
      sensitivity: Sensitivity.d2,
      payload: const <String, Object?>{
        'expected_revision': 0,
        'agent_id': 'harness',
        'protocol_version': 'personal-os.mcp.v0',
        'purpose': 'backup test',
        'capabilities': <Object?>[],
      },
    );
