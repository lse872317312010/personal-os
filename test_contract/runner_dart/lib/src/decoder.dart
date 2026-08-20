import 'dart:convert';
import 'dart:io';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';

import 'models.dart';

FixtureDocument decodeFixture(String source) {
  final root = _map(jsonDecode(source), 'fixture');
  if (root['fixture_version'] != 1) {
    throw const FormatException('unsupported fixture_version');
  }
  final expectations = _map(root['expectations'], 'expectations');
  final rawResults = _list(expectations['event_results'], 'event_results');
  final events = _list(root['events'], 'events')
      .map((value) => decodeEvent(_map(value, 'event')))
      .toList(growable: false);
  return FixtureDocument(
    sequenceId: _string(root['sequence_id'], 'sequence_id'),
    contractTests: _list(root['contract_tests'], 'contract_tests')
        .map((value) => _string(value, 'contract_test'))
        .toList(growable: false),
    events: events,
    expectedResults: rawResults
        .map((value) => _string(_map(value, 'event_result')['result'], 'result'))
        .toList(growable: false),
    projectionAssertionCount:
        _list(expectations['projection_assertions'], 'projection_assertions')
            .length,
    invariantCount: _list(expectations['invariants'], 'invariants').length,
  );
}

EventEnvelope decodeEvent(Map<String, Object?> json) {
  final actor = _map(json['actor'], 'actor');
  final actorType = switch (_string(actor['type'], 'actor.type')) {
    'user' => ActorType.user,
    'model' => ActorType.agent,
    'device' => ActorType.connector,
    'system' => ActorType.system,
    final value => throw FormatException('unsupported actor.type: $value'),
  };
  final payload = Map<String, Object?>.of(_map(json['payload'], 'payload'));
  // The fixture vocabulary predates the reducer field name. Preserve the
  // original key while supplying the equivalent reducer input.
  if (payload['execution_record_ref'] == null && payload['execution_ref'] != null) {
    payload['execution_record_ref'] = payload['execution_ref'];
  }
  return EventEnvelope(
    eventId: _string(json['event_id'], 'event_id'),
    eventType: _string(json['event_type'], 'event_type'),
    eventVersion: _integer(json['event_version'], 'event_version'),
    occurredAt: DateTime.parse(_string(json['occurred_at'], 'occurred_at')),
    recordedAt: DateTime.parse(_string(json['recorded_at'], 'recorded_at')),
    actor: ActorRef(
      actorId: _string(actor['id'], 'actor.id'),
      actorType: actorType,
      authoritySource: 'contract_fixture',
      onBehalfOf: actorType == ActorType.user ? null : 'user:self',
    ),
    subjectRefs: _decodeRefs(json['subject_refs'], 'subject_refs'),
    correlationId: _string(json['correlation_id'], 'correlation_id'),
    causationId: json['causation_id'] as String?,
    sourceRefs: _decodeRefs(json['source_refs'], 'source_refs'),
    consentRefs: _decodeRefs(json['consent_refs'], 'consent_refs'),
    sensitivity: Sensitivity.values.byName(
      _string(json['sensitivity'], 'sensitivity').toLowerCase(),
    ),
    payload: payload,
    integrity: _map(json['integrity'], 'integrity'),
  );
}

List<ObjectRef> _decodeRefs(Object? value, String label) => _list(value, label)
    .map((item) => decodeRef(_string(item, label)))
    .toList(growable: false);

ObjectRef decodeRef(String encoded) {
  final colon = encoded.indexOf(':');
  if (colon <= 0 || colon == encoded.length - 1) {
    throw FormatException('invalid object reference: $encoded');
  }
  final type = encoded.substring(0, colon);
  final rest = encoded.substring(colon + 1);
  final revisionSeparator = rest.lastIndexOf('@');
  if (revisionSeparator < 0) {
    return ObjectRef(type: type, id: EntityId(rest));
  }
  return ObjectRef(
    type: type,
    id: EntityId(rest.substring(0, revisionSeparator)),
    revision: Revision(int.parse(rest.substring(revisionSeparator + 1))),
  );
}

Future<List<String>> loadFixturePaths(String manifestPath) async {
  final manifestFile = File(manifestPath).absolute;
  final root = _map(
    jsonDecode(await manifestFile.readAsString()),
    'manifest',
  );
  final base = manifestFile.parent;
  return _list(root['fixtures'], 'fixtures')
      .map((entry) => _map(entry, 'fixture entry'))
      .map((entry) => base.uri.resolve(_string(entry['path'], 'path')).toFilePath())
      .toList(growable: false);
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object');
  return value.cast<String, Object?>();
}

List<Object?> _list(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be an array');
  return value.cast<Object?>();
}

String _string(Object? value, String label) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$label must be a non-empty string');
  }
  return value;
}

int _integer(Object? value, String label) {
  if (value is! int) throw FormatException('$label must be an integer');
  return value;
}
