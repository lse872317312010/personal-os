import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'event_envelope.dart';
import 'json_codec.dart';

abstract final class EventArchiveError {
  static const invalidJson = 'event_archive.invalid_json';
  static const invalidShape = 'event_archive.invalid_shape';
  static const unsupportedVersion = 'event_archive.unsupported_version';
  static const countMismatch = 'event_archive.count_mismatch';
  static const checksumMismatch = 'event_archive.checksum_mismatch';
  static const duplicateEventId = 'event_archive.duplicate_event_id';
}

final class EventArchiveException implements FormatException {
  const EventArchiveException(this.code, this.message, [this.source]);

  final String code;
  @override
  final String message;
  @override
  final Object? source;
  @override
  int? get offset => null;
}

final class DecodedEventArchive {
  DecodedEventArchive({
    required Iterable<EventEnvelope> events,
    required this.checksum,
  }) : events = List<EventEnvelope>.unmodifiable(events);

  final List<EventEnvelope> events;
  final String checksum;
}

/// Deterministic plaintext payload for an encrypted Personal OS backup.
///
/// This codec provides lossless event serialization and corruption detection.
/// It does not encrypt or persist bytes; those responsibilities remain behind
/// the platform export/import adapter.
abstract final class EventArchiveCodec {
  static const format = 'personal-os.events';
  static const schemaVersion = 1;
  static const _fields = <String>{
    'format',
    'schema_version',
    'event_count',
    'events_sha256',
    'events',
  };

  static String encode(Iterable<EventEnvelope> source) {
    final events = List<EventEnvelope>.unmodifiable(source);
    final encodedEvents =
        events.map(EventEnvelopeJsonCodec.encode).toList(growable: false);
    final canonicalEvents = _canonicalJson(encodedEvents);
    final checksum = sha256.convert(utf8.encode(canonicalEvents)).toString();
    return _canonicalJson(<String, Object?>{
      'format': format,
      'schema_version': schemaVersion,
      'event_count': events.length,
      'events_sha256': checksum,
      'events': encodedEvents,
    });
  }

  static DecodedEventArchive decode(String source) {
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException catch (error) {
      throw EventArchiveException(
        EventArchiveError.invalidJson,
        'archive is not valid JSON',
        error,
      );
    }
    if (raw is! Map) {
      throw const EventArchiveException(
        EventArchiveError.invalidShape,
        'archive must be an object',
      );
    }
    final archive = Map<String, Object?>.from(raw);
    final unknown = archive.keys.where((key) => !_fields.contains(key)).toList()
      ..sort();
    if (unknown.isNotEmpty) {
      throw EventArchiveException(
        EventArchiveError.invalidShape,
        'unknown archive field(s): ${unknown.join(', ')}',
      );
    }
    if (archive['format'] != format ||
        archive['schema_version'] != schemaVersion) {
      throw const EventArchiveException(
        EventArchiveError.unsupportedVersion,
        'unsupported event archive format or version',
      );
    }
    final count = archive['event_count'];
    final expectedChecksum = archive['events_sha256'];
    final rawEvents = archive['events'];
    if (count is! int ||
        count < 0 ||
        expectedChecksum is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedChecksum) ||
        rawEvents is! List) {
      throw const EventArchiveException(
        EventArchiveError.invalidShape,
        'archive metadata or events are invalid',
      );
    }
    if (rawEvents.length != count) {
      throw const EventArchiveException(
        EventArchiveError.countMismatch,
        'event_count does not match events',
      );
    }
    final canonicalEvents = _canonicalJson(rawEvents);
    final actualChecksum =
        sha256.convert(utf8.encode(canonicalEvents)).toString();
    if (actualChecksum != expectedChecksum) {
      throw const EventArchiveException(
        EventArchiveError.checksumMismatch,
        'event archive checksum does not match',
      );
    }

    final events = <EventEnvelope>[];
    final seenIds = <String>{};
    for (final rawEvent in rawEvents) {
      if (rawEvent is! Map) {
        throw const EventArchiveException(
          EventArchiveError.invalidShape,
          'events must contain only objects',
        );
      }
      final event =
          EventEnvelopeJsonCodec.decode(Map<String, Object?>.from(rawEvent));
      if (!seenIds.add(event.eventId)) {
        throw const EventArchiveException(
          EventArchiveError.duplicateEventId,
          'archive contains a duplicate event_id',
        );
      }
      events.add(event);
    }
    return DecodedEventArchive(
      events: events,
      checksum: actualChecksum,
    );
  }
}

String _canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final map = Map<String, Object?>.from(value);
    final keys = map.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(map[key]),
    };
  }
  if (value is List) {
    return value.map(_canonicalize).toList(growable: false);
  }
  return value;
}
