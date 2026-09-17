import 'dart:convert';

import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

const personalOsProtocolV0 = 'personal-os.mcp.v0';

final class AgentProtocolException implements FormatException {
  const AgentProtocolException(this.code, this.message);

  final String code;
  @override
  final String message;
  @override
  int? get offset => null;
  @override
  Object? get source => null;
}

abstract final class AgentProtocolError {
  static const invalidRequest = 'invalid_request';
  static const unsupportedVersion = 'unsupported_version';
  static const unpinnedReference = 'unpinned_reference';
}

final class ContextRecord {
  ContextRecord({
    required this.ref,
    required Map<String, Object?> data,
    Iterable<String> redactedFields = const <String>[],
  })  : data = Map<String, Object?>.unmodifiable(data),
        redactedFields = List<String>.unmodifiable(redactedFields) {
    if (ref.revision == null) {
      throw const AgentProtocolException(
        AgentProtocolError.unpinnedReference,
        'context records require pinned references',
      );
    }
  }

  final ObjectRef ref;
  final Map<String, Object?> data;
  final List<String> redactedFields;

  Map<String, Object?> toJson() => <String, Object?>{
        'ref': ref.toJson(),
        'data': data,
        'redacted_fields': redactedFields,
      };
}

final class ContextBundle {
  ContextBundle({
    required this.bundleId,
    required this.sessionId,
    required this.createdAt,
    required this.purpose,
    required Iterable<ContextRecord> records,
    this.cursor,
    this.hasMore = false,
  }) : records = List<ContextRecord>.unmodifiable(records);

  final String bundleId;
  final EntityId sessionId;
  final DateTime createdAt;
  final String purpose;
  final List<ContextRecord> records;
  final String? cursor;
  final bool hasMore;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocol_version': personalOsProtocolV0,
        'bundle_id': bundleId,
        'session_id': sessionId.value,
        'created_at': createdAt.toUtc().toIso8601String(),
        'scope': <String, Object?>{
          'purpose': purpose,
          'object_types': records.map((item) => item.ref.type).toSet().toList(),
        },
        'objects': records.map((item) => item.toJson()).toList(),
        if (cursor != null) 'cursor': cursor,
        'has_more': hasMore,
      };
}

final class StrategyProposalBundle {
  StrategyProposalBundle({
    required this.proposalId,
    required this.sessionId,
    required this.createdAt,
    required this.title,
    required this.rationale,
    required Iterable<ObjectRef> goalRefs,
    required Iterable<ObjectRef> assetRefs,
    required Iterable<Map<String, Object?>> actions,
    Iterable<String> assumptions = const <String>[],
    this.parentStrategy,
  })  : goalRefs = List<ObjectRef>.unmodifiable(goalRefs),
        assetRefs = List<ObjectRef>.unmodifiable(assetRefs),
        actions = List<Map<String, Object?>>.unmodifiable(
          actions.map(Map<String, Object?>.unmodifiable),
        ),
        assumptions = List<String>.unmodifiable(assumptions) {
    _requirePinned(<ObjectRef>[
      ...this.goalRefs,
      ...this.assetRefs,
      if (parentStrategy != null) parentStrategy!,
    ]);
  }

  final String proposalId;
  final EntityId sessionId;
  final DateTime createdAt;
  final String title;
  final String rationale;
  final List<ObjectRef> goalRefs;
  final List<ObjectRef> assetRefs;
  final List<Map<String, Object?>> actions;
  final List<String> assumptions;
  final ObjectRef? parentStrategy;

  SubmitStrategyProposalCommand toCommand({
    required ActorRef agent,
    required EntityId profileId,
    required int expectedSessionRevision,
    required String correlationId,
    Sensitivity sensitivity = Sensitivity.d2,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
  }) =>
      SubmitStrategyProposalCommand(
        actor: agent,
        profileId: profileId,
        correlationId: correlationId,
        sessionId: sessionId,
        expectedSessionRevision: expectedSessionRevision,
        title: title,
        rationale: rationale,
        goalRefs: goalRefs,
        assetRefs: assetRefs,
        actions: actions,
        assumptions: assumptions,
        parentStrategy: parentStrategy,
        sensitivity: sensitivity,
        consentRefs: consentRefs,
      );
}

abstract final class ContextBundleCodec {
  static String encode(ContextBundle bundle) =>
      jsonEncode(_canonicalize(bundle.toJson()));
}

abstract final class ProposalBundleCodec {
  static StrategyProposalBundle decodeString(String source) {
    final Object? value;
    try {
      value = jsonDecode(source);
    } on FormatException {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'proposal bundle is not valid JSON',
      );
    }
    if (value is! Map) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'proposal bundle must be an object',
      );
    }
    return decode(Map<String, Object?>.from(value));
  }

  static StrategyProposalBundle decode(Map<String, Object?> json) {
    if (json['protocol_version'] != personalOsProtocolV0) {
      throw const AgentProtocolException(
        AgentProtocolError.unsupportedVersion,
        'unsupported protocol_version',
      );
    }
    final strategy = _map(json['strategy'], 'strategy');
    final goals = _refs(strategy['goal_refs'], 'goal_refs');
    final assets =
        _refs(strategy['asset_refs'] ?? const <Object?>[], 'asset_refs');
    final rawActions = _list(strategy['actions'], 'actions');
    final actions = rawActions
        .map((value) => _map(value, 'action'))
        .toList(growable: false);
    if (goals.isEmpty || actions.isEmpty) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'proposal requires at least one goal and action',
      );
    }
    final rawAssumptions =
        _list(strategy['assumptions'] ?? const <Object?>[], 'assumptions');
    if (rawAssumptions.any((value) => value is! String)) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'assumptions must contain strings',
      );
    }

    return StrategyProposalBundle(
      proposalId: _string(json['proposal_id'], 'proposal_id'),
      sessionId: EntityId(_string(json['session_id'], 'session_id')),
      createdAt: _time(json['created_at'], 'created_at'),
      title: _string(strategy['title'], 'title'),
      rationale: _string(strategy['rationale'], 'rationale'),
      goalRefs: goals,
      assetRefs: assets,
      actions: actions,
      assumptions: rawAssumptions.cast<String>(),
      parentStrategy: strategy['parent_strategy'] == null
          ? null
          : _ref(strategy['parent_strategy'], 'parent_strategy'),
    );
  }
}

ObjectRef _ref(Object? value, String field) {
  final map = _map(value, field);
  final revision = map['revision'];
  if (revision is! int || revision < 0) {
    throw AgentProtocolException(
      AgentProtocolError.unpinnedReference,
      '$field requires a non-negative revision',
    );
  }
  return ObjectRef(
    type: _string(map['type'], '$field.type'),
    id: EntityId(_string(map['id'], '$field.id')),
    revision: Revision(revision),
  );
}

List<ObjectRef> _refs(Object? value, String field) => _list(value, field)
    .map((item) => _ref(item, field))
    .toList(growable: false);

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be an object',
    );
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String field) {
  if (value is! List) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be an array',
    );
  }
  return List<Object?>.from(value);
}

String _string(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be a non-blank string',
    );
  }
  return value;
}

DateTime _time(Object? value, String field) {
  final parsed = DateTime.tryParse(_string(value, field));
  if (parsed == null) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be an ISO-8601 timestamp',
    );
  }
  return parsed.toUtc();
}

void _requirePinned(Iterable<ObjectRef> refs) {
  if (refs.any((ref) => ref.revision == null)) {
    throw const AgentProtocolException(
      AgentProtocolError.unpinnedReference,
      'proposal references must be pinned',
    );
  }
}

Object? _canonicalize(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList();
  return value;
}
