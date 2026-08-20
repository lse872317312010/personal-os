import 'package:personal_os_domain/domain.dart';

import 'deep_freeze.dart';

/// M1 append-only event envelope. Payload meaning is owned by each event type.
final class EventEnvelope {
  EventEnvelope({
    required String eventId,
    required String eventType,
    required this.eventVersion,
    required this.occurredAt,
    required this.recordedAt,
    required this.actor,
    required String correlationId,
    required this.sensitivity,
    required Map<String, Object?> payload,
    Iterable<ObjectRef> subjectRefs = const <ObjectRef>[],
    this.causationId,
    Iterable<ObjectRef> sourceRefs = const <ObjectRef>[],
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
    Map<String, Object?> integrity = const <String, Object?>{},
    Map<String, Object?> extensions = const <String, Object?>{},
  })  : eventId = _nonBlank(eventId, 'eventId'),
        eventType = _nonBlank(eventType, 'eventType'),
        correlationId = _nonBlank(correlationId, 'correlationId'),
        subjectRefs = List<ObjectRef>.unmodifiable(subjectRefs),
        sourceRefs = List<ObjectRef>.unmodifiable(sourceRefs),
        consentRefs = List<ObjectRef>.unmodifiable(consentRefs),
        payload = deepFreezeMap(payload),
        integrity = deepFreezeMap(integrity),
        extensions = deepFreezeMap(extensions) {
    if (eventVersion <= 0) {
      throw ArgumentError.value(eventVersion, 'eventVersion', 'must be > 0');
    }
  }

  final String eventId;
  final String eventType;
  final int eventVersion;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final ActorRef actor;
  final List<ObjectRef> subjectRefs;
  final String correlationId;
  final String? causationId;
  final List<ObjectRef> sourceRefs;
  final List<ObjectRef> consentRefs;
  final Sensitivity sensitivity;
  final Map<String, Object?> payload;
  final Map<String, Object?> integrity;

  /// Unknown non-critical top-level fields retained for forward compatibility.
  final Map<String, Object?> extensions;

  int? get expectedRevision => payload['expected_revision'] as int?;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}
