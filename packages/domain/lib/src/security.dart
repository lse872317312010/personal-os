enum Sensitivity { d0, d1, d2, d3, d4 }

enum ActorType { user, agent, connector, importer, system }

/// Audit identity carried by a domain event.
final class ActorRef {
  ActorRef({
    required String actorId,
    required this.actorType,
    required String authoritySource,
    String? sessionOrRunId,
    String? onBehalfOf,
    Iterable<String> capabilityRefs = const <String>[],
  })  : actorId = _nonBlank(actorId, 'actorId'),
        authoritySource = _nonBlank(authoritySource, 'authoritySource'),
        sessionOrRunId = _optionalNonBlank(sessionOrRunId, 'sessionOrRunId'),
        onBehalfOf = _optionalNonBlank(onBehalfOf, 'onBehalfOf'),
        capabilityRefs = List<String>.unmodifiable(
          capabilityRefs.map(
            (reference) => _nonBlank(reference, 'capabilityRefs'),
          ),
        ) {
    if (actorType != ActorType.user && onBehalfOf == null) {
      throw ArgumentError('Non-user actors require onBehalfOf');
    }
  }

  factory ActorRef.fromJson(Map<String, Object?> json) => ActorRef(
        actorId: json['actor_id']! as String,
        actorType: ActorType.values.byName(json['actor_type']! as String),
        authoritySource: json['authority_source']! as String,
        sessionOrRunId: json['session_or_run_id'] as String?,
        onBehalfOf: json['on_behalf_of'] as String?,
        capabilityRefs:
            (json['capability_refs'] as List<Object?>? ?? const <Object?>[])
                .cast<String>(),
      );

  final String actorId;
  final ActorType actorType;
  final String authoritySource;
  final String? sessionOrRunId;
  final String? onBehalfOf;
  final List<String> capabilityRefs;

  Map<String, Object?> toJson() => <String, Object?>{
        'actor_id': actorId,
        'actor_type': actorType.name,
        'authority_source': authoritySource,
        if (sessionOrRunId != null) 'session_or_run_id': sessionOrRunId,
        if (onBehalfOf != null) 'on_behalf_of': onBehalfOf,
        'capability_refs': capabilityRefs,
      };
}

Sensitivity maximumSensitivity(Iterable<Sensitivity> values) {
  var result = Sensitivity.d0;
  for (final value in values) {
    if (value.index > result.index) result = value;
  }
  return result;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

String? _optionalNonBlank(String? value, String label) =>
    value == null ? null : _nonBlank(value, label);
