import 'dart:convert';

import 'event_envelope.dart';
import 'json_codec.dart';
import 'reducer.dart';

/// A read-only, replayed preview. The source revision is provenance, never a
/// destination store's optimistic concurrency token. No storage or AI is used.
final class WebHistoryPreview {
  WebHistoryPreview._(this.sourceRevision, this.exportedAt,
      List<EventEnvelope> events, Map<String, ObjectProjection> projections)
      : events = List<EventEnvelope>.unmodifiable(events),
        projections = Map<String, ObjectProjection>.unmodifiable(projections);

  final int sourceRevision;
  final DateTime exportedAt;
  final List<EventEnvelope> events;
  final Map<String, ObjectProjection> projections;
}

/// Errors deliberately contain no imported text, IDs or raw codec exceptions.
final class WebHistoryException implements FormatException {
  const WebHistoryException(this.code, {this.eventIndex});
  final String code;
  final int? eventIndex;
  @override
  String get message => code;
  @override
  Object? get source => null;
  @override
  int? get offset => null;
  @override
  String toString() => 'WebHistoryException($code)';
}

/// Decodes the gateway's plaintext export and replays it through the same core
/// reducer as the event store. This validates compatibility and lifecycle order,
/// not authenticity, user consent or the truth of imported observations.
abstract final class WebHistoryCodec {
  static const format = 'personal-os.web-history.v1';
  // Downloads are pretty-printed, unlike the compact gateway request body.
  static const maxSourceBytes = 32000000;
  static const maxEventCount = 20000;
  static const _fields = <String>{
    'format',
    'exported_at',
    'source_revision',
    'events'
  };

  static WebHistoryPreview preview(String source) {
    if (source.length > maxSourceBytes ||
        utf8.encode(source).length > maxSourceBytes) {
      throw const WebHistoryException('history.file_too_large');
    }
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException {
      throw const WebHistoryException('history.invalid_json');
    }
    if (raw is! Map<String, Object?> ||
        raw.length != _fields.length ||
        raw.keys.any((key) => !_fields.contains(key))) {
      throw const WebHistoryException('history.invalid_shape');
    }
    if (raw['format'] != format) {
      throw const WebHistoryException('history.unsupported_format');
    }
    final revision = raw['source_revision'];
    final timestamp = raw['exported_at'];
    final values = raw['events'];
    if (revision is! int ||
        revision < 0 ||
        revision > 9007199254740991 ||
        timestamp is! String ||
        values is! List<Object?>) {
      throw const WebHistoryException('history.invalid_shape');
    }
    // Match the gateway's Date.toISOString() output and reject normalized dates
    // such as February 30 rather than accepting DateTime's overflow handling.
    final exportedAt = DateTime.tryParse(timestamp);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
            .hasMatch(timestamp) ||
        exportedAt == null ||
        exportedAt.toUtc().toIso8601String() != timestamp) {
      throw const WebHistoryException('history.invalid_timestamp');
    }
    if (values.length > maxEventCount) {
      throw const WebHistoryException('history.too_many_events');
    }
    // Reserve space for a destination revision/wrapper in the 8 MB write API.
    if (utf8.encode(jsonEncode(values)).length > 7999000) {
      throw const WebHistoryException('history.events_too_large');
    }
    final events = <EventEnvelope>[];
    final ids = <String>{};
    var projections = <String, ObjectProjection>{};
    var seen = <String>{};
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      final EventEnvelope event;
      try {
        if (value is! Map<String, Object?>) {
          throw const FormatException();
        }
        event = EventEnvelopeJsonCodec.decode(value);
      } on Object {
        throw WebHistoryException('history.invalid_event', eventIndex: index);
      }
      if (!ids.add(event.eventId)) {
        throw WebHistoryException('history.duplicate_event', eventIndex: index);
      }
      final ReductionResult result;
      try {
        result = reduceCore(
            projections: projections, seenEventIds: seen, event: event);
      } on Object {
        throw WebHistoryException('history.invalid_event', eventIndex: index);
      }
      if (result.disposition != ReductionDisposition.applied) {
        throw WebHistoryException('history.invalid_chain', eventIndex: index);
      }
      projections = result.projections;
      seen = result.seenEventIds;
      events.add(event);
    }
    return WebHistoryPreview._(revision, exportedAt, events, projections);
  }
}
