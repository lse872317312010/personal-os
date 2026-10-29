import 'dart:convert';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'automatic_agent_gateway.dart';

/// Reuses the core reducer before persisting an append-only snapshot. The local
/// service serializes writes with a revision check, including across tabs.
final class LocalAgentEventStore implements EventStore {
  LocalAgentEventStore(this.gateway);
  final AutomaticAgentGateway gateway;
  InMemoryEventStore _memory = InMemoryEventStore();
  List<EventEnvelope> _events = <EventEnvelope>[];
  List<Object?> _encodedEvents = <Object?>[];
  int _revision = 0;
  Future<void> _tail = Future<void>.value();
  Future<void> load() async {
    final value = await gateway.get('/api/history');
    // Retain original JSON field order and optional null fields. Re-encoding
    // decoded envelopes may normalize them, violating the server's immutable
    // prefix check after an otherwise valid history restore.
    final encodedEvents = jsonDecode(jsonEncode(value['events'])) as List;
    final events = encodedEvents
        .map((e) =>
            EventEnvelopeJsonCodec.decode(Map<String, Object?>.from(e as Map)))
        .toList();
    final memory = InMemoryEventStore();
    await memory.appendAll(events);
    _memory = memory;
    _events = events;
    _encodedEvents = List<Object?>.from(encodedEvents);
    _revision = value['revision'] as int;
  }

  @override
  Future<void> appendAll(List<EventEnvelope> events) {
    final result = _tail.then((_) async {
      final memory = InMemoryEventStore();
      await memory.appendAll(_events);
      await memory.appendAll(events);
      final ids = _events.map((e) => e.eventId).toSet();
      final additions = events.where((e) => ids.add(e.eventId)).toList();
      final next = <EventEnvelope>[..._events, ...additions];
      final encodedEvents = <Object?>[
        ..._encodedEvents,
        ...additions.map(EventEnvelopeJsonCodec.encode)
      ];
      try {
        final value = await gateway.post('/api/history',
            <String, Object?>{'revision': _revision, 'events': encodedEvents});
        _revision = value['revision'] as int;
        _events = next;
        _encodedEvents = encodedEvents;
        _memory = memory;
      } on Object {
        throw const PersistenceException.writeFailed();
      }
    });
    _tail = result.catchError((Object _) {});
    return result;
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    await _tail;
    return _memory.readById(eventId);
  }

  @override
  Future<List<EventEnvelope>> readBySubject(ObjectRef subject,
      {int? limit}) async {
    await _tail;
    return _memory.readBySubject(subject, limit: limit);
  }
}
