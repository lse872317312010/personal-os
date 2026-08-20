import 'dart:convert';

import 'package:personal_os_domain/domain.dart';

import 'event_envelope.dart';
import 'reducer.dart';

/// Stable machine-readable reason codes for persisted JSON rejection.
abstract final class EventCodecReason {
  static const invalidJson = 'invalid_json';
  static const invalidShape = 'invalid_shape';
  static const unknownField = 'unknown_field';
  static const unsupportedSchemaVersion = 'unsupported_schema_version';
  static const unsupportedEventVersion = 'unsupported_event_version';
  static const unknownActorType = 'unknown_actor_type';
  static const unknownSensitivity = 'unknown_sensitivity';
  static const d4PersistenceForbidden = 'd4_persistence_forbidden';
  static const invalidTimestamp = 'invalid_timestamp';
  static const nonJsonValue = 'non_json_value';
}

final class EventCodecException implements FormatException {
  const EventCodecException(this.reasonCode, this.message, [this.source]);

  final String reasonCode;
  @override
  final String message;
  @override
  final Object? source;
  @override
  int? get offset => null;

  @override
  String toString() => 'EventCodecException($reasonCode): $message';
}

/// Versioned, strict JSON codec for an [EventEnvelope].
///
/// Unknown top-level fields are rejected. Forward-compatible non-critical data
/// must be placed explicitly under `extensions`; this prevents a new critical
/// field from being silently interpreted as harmless metadata.
abstract final class EventEnvelopeJsonCodec {
  static const schemaVersion = 1;
  static const supportedEventVersion = 1;

  static const _fields = <String>{
    'schema_version',
    'event_id',
    'event_type',
    'event_version',
    'occurred_at',
    'recorded_at',
    'actor',
    'subject_refs',
    'correlation_id',
    'causation_id',
    'source_refs',
    'consent_refs',
    'sensitivity',
    'payload',
    'integrity',
    'extensions',
  };

  static Map<String, Object?> encode(EventEnvelope event) {
    if (event.eventVersion != supportedEventVersion) {
      throw EventCodecException(
        EventCodecReason.unsupportedEventVersion,
        'event_version ${event.eventVersion} is not supported',
      );
    }
    _ensurePersistable(event.sensitivity);
    final value = <String, Object?>{
      'schema_version': schemaVersion,
      'event_id': event.eventId,
      'event_type': event.eventType,
      'event_version': event.eventVersion,
      'occurred_at': _encodeTime(event.occurredAt),
      'recorded_at': _encodeTime(event.recordedAt),
      'actor': event.actor.toJson(),
      'subject_refs': event.subjectRefs.map((ref) => ref.toJson()).toList(),
      'correlation_id': event.correlationId,
      if (event.causationId != null) 'causation_id': event.causationId,
      'source_refs': event.sourceRefs.map((ref) => ref.toJson()).toList(),
      'consent_refs': event.consentRefs.map((ref) => ref.toJson()).toList(),
      'sensitivity': event.sensitivity.name,
      'payload': event.payload,
      'integrity': event.integrity,
      'extensions': event.extensions,
    };
    _assertJsonValue(value);
    return value;
  }

  static String encodeString(EventEnvelope event) =>
      jsonEncode(_canonicalize(encode(event)));

  static EventEnvelope decode(Map<String, Object?> json) {
    _rejectUnknownFields(json, _fields, 'event envelope');
    _requireVersion(json, 'schema_version', schemaVersion);
    final eventVersion = _requiredInt(json, 'event_version');
    if (eventVersion != supportedEventVersion) {
      throw EventCodecException(
        EventCodecReason.unsupportedEventVersion,
        'event_version $eventVersion is not supported',
      );
    }
    final sensitivity = _decodeSensitivity(_requiredString(json, 'sensitivity'));
    _ensurePersistable(sensitivity);
    return EventEnvelope(
      eventId: _requiredString(json, 'event_id'),
      eventType: _requiredString(json, 'event_type'),
      eventVersion: eventVersion,
      occurredAt: _requiredTime(json, 'occurred_at'),
      recordedAt: _requiredTime(json, 'recorded_at'),
      actor: _decodeActor(_requiredMap(json, 'actor')),
      subjectRefs: _decodeRefs(json, 'subject_refs'),
      correlationId: _requiredString(json, 'correlation_id'),
      causationId: _optionalString(json, 'causation_id'),
      sourceRefs: _decodeRefs(json, 'source_refs'),
      consentRefs: _decodeRefs(json, 'consent_refs'),
      sensitivity: sensitivity,
      payload: _requiredMap(json, 'payload'),
      integrity: _requiredMap(json, 'integrity'),
      extensions: _requiredMap(json, 'extensions'),
    );
  }

  static EventEnvelope decodeString(String source) {
    try {
      final value = jsonDecode(source);
      if (value is! Map<String, Object?>) {
        throw const EventCodecException(
          EventCodecReason.invalidShape,
          'event JSON must be an object',
        );
      }
      return decode(value);
    } on EventCodecException {
      rethrow;
    } on FormatException catch (error) {
      throw EventCodecException(
        EventCodecReason.invalidJson,
        error.message,
        source,
      );
    } on Object catch (error) {
      throw EventCodecException(
        EventCodecReason.invalidShape,
        'invalid event JSON: $error',
        source,
      );
    }
  }
}

abstract final class ObjectProjectionJsonCodec {
  static const schemaVersion = 1;
  static const _fields = <String>{
    'schema_version',
    'object_type',
    'id',
    'revision',
    'state',
    'last_event_id',
    'attributes',
  };

  static Map<String, Object?> encode(ObjectProjection projection) {
    final value = <String, Object?>{
      'schema_version': schemaVersion,
      'object_type': projection.objectType,
      'id': projection.id.value,
      'revision': projection.revision.value,
      'state': projection.state,
      'last_event_id': projection.lastEventId,
      'attributes': projection.attributes,
    };
    _assertJsonValue(value);
    return value;
  }

  static String encodeString(ObjectProjection projection) =>
      jsonEncode(_canonicalize(encode(projection)));

  static ObjectProjection decode(Map<String, Object?> json) {
    _rejectUnknownFields(json, _fields, 'object projection');
    _requireVersion(json, 'schema_version', schemaVersion);
    return ObjectProjection(
      objectType: _requiredString(json, 'object_type'),
      id: EntityId(_requiredString(json, 'id')),
      revision: Revision(_requiredInt(json, 'revision')),
      state: _requiredString(json, 'state'),
      lastEventId: _requiredString(json, 'last_event_id'),
      attributes: _requiredMap(json, 'attributes'),
    );
  }

  static ObjectProjection decodeString(String source) {
    try {
      final value = jsonDecode(source);
      if (value is! Map<String, Object?>) {
        throw const EventCodecException(
          EventCodecReason.invalidShape,
          'projection JSON must be an object',
        );
      }
      return decode(value);
    } on EventCodecException {
      rethrow;
    } on FormatException catch (error) {
      throw EventCodecException(
        EventCodecReason.invalidJson,
        error.message,
        source,
      );
    } on Object catch (error) {
      throw EventCodecException(
        EventCodecReason.invalidShape,
        'invalid projection JSON: $error',
        source,
      );
    }
  }
}

String _encodeTime(DateTime value) => value.toUtc().toIso8601String();

DateTime _requiredTime(Map<String, Object?> json, String key) {
  final raw = _requiredString(json, key);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$')
      .hasMatch(raw)) {
    throw EventCodecException(
      EventCodecReason.invalidTimestamp,
      '$key must be an explicit UTC RFC 3339 timestamp',
    );
  }
  final value = DateTime.tryParse(raw);
  if (value == null || !value.isUtc) {
    throw EventCodecException(
      EventCodecReason.invalidTimestamp,
      '$key is not a valid timestamp',
    );
  }
  return value;
}

ActorRef _decodeActor(Map<String, Object?> json) {
  const fields = <String>{
    'actor_id',
    'actor_type',
    'authority_source',
    'session_or_run_id',
    'on_behalf_of',
    'capability_refs',
  };
  _rejectUnknownFields(json, fields, 'actor');
  final typeName = _requiredString(json, 'actor_type');
  final type = switch (typeName) {
    'user' => ActorType.user,
    'agent' => ActorType.agent,
    'connector' => ActorType.connector,
    'importer' => ActorType.importer,
    'system' => ActorType.system,
    _ => throw EventCodecException(
        EventCodecReason.unknownActorType,
        'unknown actor_type: $typeName',
      ),
  };
  final capabilities = _requiredList(json, 'capability_refs');
  if (capabilities.any((value) => value is! String)) {
    throw const EventCodecException(
      EventCodecReason.invalidShape,
      'capability_refs must contain only strings',
    );
  }
  return ActorRef(
    actorId: _requiredString(json, 'actor_id'),
    actorType: type,
    authoritySource: _requiredString(json, 'authority_source'),
    sessionOrRunId: _optionalString(json, 'session_or_run_id'),
    onBehalfOf: _optionalString(json, 'on_behalf_of'),
    capabilityRefs: capabilities.cast<String>(),
  );
}

Sensitivity _decodeSensitivity(String name) => switch (name) {
      'd0' => Sensitivity.d0,
      'd1' => Sensitivity.d1,
      'd2' => Sensitivity.d2,
      'd3' => Sensitivity.d3,
      'd4' => Sensitivity.d4,
      _ => throw EventCodecException(
          EventCodecReason.unknownSensitivity,
          'unknown sensitivity: $name',
        ),
    };

void _ensurePersistable(Sensitivity sensitivity) {
  if (sensitivity == Sensitivity.d4) {
    throw const EventCodecException(
      EventCodecReason.d4PersistenceForbidden,
      'D4 data must never be encoded in or decoded from persistent JSON',
    );
  }
}

List<ObjectRef> _decodeRefs(Map<String, Object?> json, String key) =>
    _requiredList(json, key).map((value) {
      if (value is! Map<String, Object?>) {
        throw EventCodecException(
          EventCodecReason.invalidShape,
          '$key must contain only objects',
        );
      }
      const fields = <String>{'type', 'id', 'revision'};
      _rejectUnknownFields(value, fields, '$key reference');
      final revision = value['revision'];
      if (revision != null && (revision is! int || revision < 0)) {
        throw EventCodecException(
          EventCodecReason.invalidShape,
          '$key revision must be a non-negative integer',
        );
      }
      return ObjectRef(
        type: _requiredString(value, 'type'),
        id: EntityId(_requiredString(value, 'id')),
        revision: revision == null ? null : Revision(revision),
      );
    }).toList(growable: false);

void _requireVersion(Map<String, Object?> json, String key, int supported) {
  final actual = _requiredInt(json, key);
  if (actual != supported) {
    throw EventCodecException(
      EventCodecReason.unsupportedSchemaVersion,
      '$key $actual is not supported',
    );
  }
}

void _rejectUnknownFields(
  Map<String, Object?> json,
  Set<String> fields,
  String context,
) {
  final unknown = json.keys.where((key) => !fields.contains(key)).toList()..sort();
  if (unknown.isNotEmpty) {
    throw EventCodecException(
      EventCodecReason.unknownField,
      'unknown $context field(s): ${unknown.join(', ')}',
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw EventCodecException(
      EventCodecReason.invalidShape,
      '$key must be a non-blank string',
    );
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw EventCodecException(
      EventCodecReason.invalidShape,
      '$key must be null or a non-blank string',
    );
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int || value < 0) {
    throw EventCodecException(
      EventCodecReason.invalidShape,
      '$key must be a non-negative integer',
    );
  }
  return value;
}

Map<String, Object?> _requiredMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw EventCodecException(
      EventCodecReason.invalidShape,
      '$key must be an object',
    );
  }
  return value;
}

List<Object?> _requiredList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List<Object?>) {
    throw EventCodecException(
      EventCodecReason.invalidShape,
      '$key must be an array',
    );
  }
  return value;
}

Object? _canonicalize(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List<Object?>) return value.map(_canonicalize).toList();
  return value;
}

void _assertJsonValue(Object? value) {
  try {
    jsonEncode(value);
  } on Object catch (error) {
    throw EventCodecException(
      EventCodecReason.nonJsonValue,
      'value is not JSON encodable: $error',
      value,
    );
  }
}
