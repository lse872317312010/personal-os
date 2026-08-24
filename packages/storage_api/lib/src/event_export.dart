import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';

/// Explicit export policy. A policy is a ceiling, never an authorization
/// grant: D4 is rejected independently and can never be exported.
final class EventExportPolicy {
  EventExportPolicy({required this.maxSensitivity}) {
    if (maxSensitivity == Sensitivity.d4) {
      throw ArgumentError.value(
        maxSensitivity,
        'maxSensitivity',
        'D4 cannot be exported',
      );
    }
  }

  final Sensitivity maxSensitivity;

  bool allows(Sensitivity sensitivity) =>
      sensitivity != Sensitivity.d4 &&
      sensitivity.index <= maxSensitivity.index;
}

/// Immutable, validated input to an export operation.
///
/// The event remains an [EventEnvelope]; the export boundary never provides a
/// mutable map or a mutable event copy to adapters.
final class EventExportRequest {
  EventExportRequest({
    required Iterable<EventEnvelope> events,
    required this.policy,
  }) : events = List<EventEnvelope>.unmodifiable(events) {
    if (this.events.isEmpty) {
      throw ArgumentError.value(events, 'events', 'must not be empty');
    }
    for (final event in this.events) {
      validateEventExportEligibility(event, policy);
    }
  }

  final List<EventEnvelope> events;
  final EventExportPolicy policy;
}

/// Safe metadata that accompanies opaque export bytes.
///
/// This intentionally excludes event IDs, subject IDs, paths, hashes, key
/// identifiers, SQL details, and content-derived fields.
final class EventExportEnvelopeMetadata {
  EventExportEnvelopeMetadata({
    required String format,
    required this.schemaVersion,
    required this.eventCount,
    required this.maxSensitivity,
    required DateTime createdAt,
  })  : format = _nonBlank(format, 'format'),
        createdAt = _utc(createdAt) {
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]*$').hasMatch(this.format)) {
      throw ArgumentError.value(
        format,
        'format',
        'must be a stable opaque format token',
      );
    }
    if (schemaVersion <= 0) {
      throw ArgumentError.value(
        schemaVersion,
        'schemaVersion',
        'must be greater than zero',
      );
    }
    if (eventCount <= 0) {
      throw ArgumentError.value(eventCount, 'eventCount', 'must be positive');
    }
    if (maxSensitivity == Sensitivity.d4) {
      throw ArgumentError.value(
        maxSensitivity,
        'maxSensitivity',
        'D4 cannot be exported',
      );
    }
  }

  final String format;
  final int schemaVersion;
  final int eventCount;
  final Sensitivity maxSensitivity;
  final DateTime createdAt;
}

/// Adapter-produced export result.
///
/// The bytes are opaque to the application layer and are defensively copied.
/// This type does not provide a text decoder, path, key, hash, or share
/// operation. Adapters must produce authenticated/encrypted bytes; plaintext
/// export is outside this contract and must not be implemented as a shortcut.
final class OpaqueEventExport {
  OpaqueEventExport({
    required List<int> bytes,
    required this.metadata,
  }) : _bytes = Uint8List.fromList(bytes) {
    if (_bytes.isEmpty) {
      throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
    }
  }

  final Uint8List _bytes;
  final EventExportEnvelopeMetadata metadata;

  /// Returns a defensive copy; callers cannot mutate the adapter result.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  @override
  String toString() => 'OpaqueEventExport(<redacted>)';
}

/// Read-only event export port. It has no append, update, delete, path, key,
/// or plaintext serialization operation.
abstract interface class EventExportPort {
  Future<OpaqueEventExport> export(EventExportRequest request);
}

/// Shared fail-closed validation required before an adapter receives events.
void validateEventExportEligibility(
  EventEnvelope event,
  EventExportPolicy policy,
) {
  if (!policy.allows(event.sensitivity)) {
    throw EventExportDenied.sensitivityNotAllowed;
  }
  _rejectForbiddenFields(event.payload);
  _rejectForbiddenFields(event.integrity);
  _rejectForbiddenFields(event.extensions);
}

final class EventExportDenied implements Exception {
  const EventExportDenied({required this.code, required this.reason});

  static const sensitivityNotAllowed = EventExportDenied(
    code: 'EVENT_EXPORT_SENSITIVITY_NOT_ALLOWED',
    reason: 'The event sensitivity exceeds the export policy.',
  );

  static const forbiddenField = EventExportDenied(
    code: 'EVENT_EXPORT_FORBIDDEN_FIELD',
    reason: 'The event contains a field that cannot cross the export boundary.',
  );

  final String code;
  final String reason;

  @override
  String toString() => 'EventExportDenied($code)';
}

const _forbiddenFieldNames = <String>{
  'key',
  'keyid',
  'keyalias',
  'keymaterial',
  'secret',
  'secretkey',
  'password',
  'passphrase',
  'token',
  'path',
  'filepath',
  'uri',
  'url',
  'hash',
  'contenthash',
  'digest',
};

void _rejectForbiddenFields(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key is String &&
          _forbiddenFieldNames.contains(_fieldName(entry.key as String))) {
        throw EventExportDenied.forbiddenField;
      }
      _rejectForbiddenFields(entry.value);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _rejectForbiddenFields(item);
    }
  }
}

String _fieldName(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

DateTime _utc(DateTime value) => value.toUtc();
