import 'dart:convert';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:test/test.dart';

void main() {
  test('gateway export preserves text, references, order and source revision',
      () {
    final values = _events();
    final preview = WebHistoryCodec.preview(_file(values));
    expect(preview.sourceRevision, 42);
    expect(preview.exportedAt, DateTime.utc(2026, 10, 30));
    expect(preview.events.map(EventEnvelopeJsonCodec.encode).toList(), values);
    expect(preview.projections['strategy:plan']!.state, 'accepted');
    expect(preview.projections['strategy:plan']!.revision.value, 2);
    expect(preview.events.last.payload['goal_ref'],
        <String, Object?>{'type': 'goal', 'id': 'goal', 'revision': 1});
    expect(preview.events.clear, throwsUnsupportedError);
    expect(preview.projections.clear, throwsUnsupportedError);
    expect(() => preview.events.first.payload.clear(), throwsUnsupportedError);
  });

  test('empty export is valid; preview never creates history or a session', () {
    final preview = WebHistoryCodec.preview(_file(<Object?>[]));
    expect(preview.events, isEmpty);
    expect(preview.projections, isEmpty);
    expect(preview.sourceRevision, 42);
  });

  test('rejects broken JSON, unknown fields, unsupported format and metadata',
      () {
    expect(() => WebHistoryCodec.preview('{private text'),
        _fails('history.invalid_json'));
    final base = jsonDecode(_file(_events())) as Map<String, Object?>;
    for (final value in <Object?>[
      null,
      <Object?>[],
      {...base, 'connection': 'secret'},
      {...base}..remove('source_revision'),
      {...base, 'source_revision': -1},
      {...base, 'source_revision': 9007199254740992},
      {...base, 'source_revision': 1.5},
      {...base, 'events': null},
    ]) {
      expect(() => WebHistoryCodec.preview(jsonEncode(value)),
          _fails('history.invalid_shape'));
    }
    expect(() => WebHistoryCodec.preview(jsonEncode({...base, 'format': 'v2'})),
        _fails('history.unsupported_format'));
    for (final time in <String>[
      'not-time',
      '2026-02-30T00:00:00.000Z',
      '2026-10-30T00:00:00.000+00:00',
    ]) {
      expect(
          () => WebHistoryCodec.preview(
              jsonEncode({...base, 'exported_at': time})),
          _fails('history.invalid_timestamp'));
    }
  });

  test('rejects duplicate IDs even when their content is identical', () {
    final values = _events();
    expect(() => WebHistoryCodec.preview(_file([...values, values.last])),
        _fails('history.duplicate_event', index: 3));
  });

  test('strict codec rejects D4, malformed events and unsupported versions',
      () {
    final first = _events().first;
    for (final value in <Object?>[
      null,
      {...first, 'sensitivity': 'd4'},
      {...first, 'event_version': 2},
      {...first, 'schema_version': 2},
      {...first, 'api_key': 'secret'},
      {...first, 'actor': <String, Object?>{}},
    ]) {
      expect(() => WebHistoryCodec.preview(_file([value])),
          _fails('history.invalid_event', index: 0));
    }
  });

  test(
      'reducer rejects missing parents, changed revisions and reordered events',
      () {
    final values = _events();
    final accepted = values.last;
    expect(() => WebHistoryCodec.preview(_file([accepted])),
        _fails('history.invalid_chain', index: 0));
    final payload = accepted['payload']! as Map<String, Object?>;
    expect(
        () => WebHistoryCodec.preview(_file([
              ...values.take(2),
              {
                ...accepted,
                'payload': {...payload, 'expected_revision': 9}
              },
            ])),
        _fails('history.invalid_chain', index: 2));
    expect(
        () => WebHistoryCodec.preview(_file([values[0], values[2], values[1]])),
        _fails('history.invalid_chain', index: 1));
    expect(
        () => WebHistoryCodec.preview(_file([
              {...values.first, 'event_type': 'unknown.private-event'},
            ])),
        _fails('history.invalid_chain', index: 0));
  });

  test(
      'bounded input rejects oversized files, event arrays and compact payloads',
      () {
    expect(
        () =>
            WebHistoryCodec.preview(' ' * (WebHistoryCodec.maxSourceBytes + 1)),
        _fails('history.file_too_large'));
    expect(
        () => WebHistoryCodec.preview(
            '中' * (WebHistoryCodec.maxSourceBytes ~/ 3 + 1)),
        _fails('history.file_too_large'));
    expect(
        () => WebHistoryCodec.preview(_file(List<Object?>.filled(20001, null))),
        _fails('history.too_many_events'));
    expect(() => WebHistoryCodec.preview(_file(['x' * 8000000])),
        _fails('history.events_too_large'));
  });

  test('failures expose a stable reason and index without imported text', () {
    final original = _file([
      {'event_id': 'private-id', 'payload': 'private text'}
    ]);
    try {
      WebHistoryCodec.preview(original);
      fail('invalid event accepted');
    } on WebHistoryException catch (error) {
      expect(error.code, 'history.invalid_event');
      expect(error.eventIndex, 0);
      expect(error.source, isNull);
      expect(error.toString(), isNot(contains('private')));
      expect(
          original,
          _file([
            {'event_id': 'private-id', 'payload': 'private text'}
          ]));
    }
  });
}

Matcher _fails(String code, {int? index}) => throwsA(isA<WebHistoryException>()
    .having((e) => e.code, 'code', code)
    .having((e) => e.eventIndex, 'index', index));

String _file(List<Object?> events) => jsonEncode(<String, Object?>{
      'format': 'personal-os.web-history.v1',
      'exported_at': '2026-10-30T00:00:00.000Z',
      'source_revision': 42,
      'events': events,
    });

List<Map<String, Object?>> _events() => <EventEnvelope>[
      _event('goal-created', EventTypes.goalCreated, 'goal', 'goal', 0),
      _event('proposed', EventTypes.strategyProposed, 'strategy', 'plan', 0),
      _event('accepted', EventTypes.strategyAccepted, 'strategy', 'plan', 1),
    ].map(EventEnvelopeJsonCodec.encode).toList();

EventEnvelope _event(String id, String type, String subjectType,
        String subjectId, int revision) =>
    EventEnvelope(
      eventId: id,
      eventType: type,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026, 10, 29),
      recordedAt: DateTime.utc(2026, 10, 29),
      actor: ActorRef(
          actorId: 'fixture-user',
          actorType: ActorType.user,
          authoritySource: 'explicit_user_action'),
      subjectRefs: [ObjectRef(type: subjectType, id: EntityId(subjectId))],
      correlationId: 'fixture-round',
      sensitivity: Sensitivity.d2,
      payload: <String, Object?>{
        'expected_revision': revision,
        'text': '中文记录 </script> 原样保留',
        'goal_ref': <String, Object?>{
          'type': 'goal',
          'id': 'goal',
          'revision': 1
        },
      },
    );
