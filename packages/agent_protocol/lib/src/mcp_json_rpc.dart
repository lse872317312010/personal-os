import 'dart:convert';

import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import 'bundles.dart';
import 'service.dart';

const personalOsMcpTransportVersion = '2025-06-18';

/// A transport-neutral MCP JSON-RPC boundary.
///
/// This adapter deliberately does not open a socket. Android may place a
/// loopback-only, user-controlled HTTP transport around it after the separate
/// transport threat-model gate passes.
final class PersonalOsMcpJsonRpcAdapter {
  PersonalOsMcpJsonRpcAdapter({
    required PersonalOsAgentProtocolService service,
    required EntityId profileId,
    String authoritySource = 'mcp_loopback',
  })  : _service = service,
        _profileId = profileId,
        _authoritySource = authoritySource;

  final PersonalOsAgentProtocolService _service;
  final EntityId _profileId;
  final String _authoritySource;
  final Map<String, _SessionBinding> _sessions = <String, _SessionBinding>{};

  bool _initializeAccepted = false;
  bool _clientReady = false;

  Future<Map<String, Object?>?> handle(
    Map<String, Object?> request,
  ) async {
    final hasId = request.containsKey('id');
    final id = request['id'];
    try {
      if (request['jsonrpc'] != '2.0') {
        throw const _JsonRpcFailure(-32600, 'invalid_request');
      }
      if (hasId && id is! String && id is! num && id != null) {
        throw const _JsonRpcFailure(-32600, 'invalid_request');
      }
      final method = _string(request['method'], 'method');
      final params = request['params'] == null
          ? <String, Object?>{}
          : _map(request['params'], 'params');

      if (method == 'initialize') {
        if (!hasId) return null;
        return _success(id, _initialize(params));
      }
      if (method == 'notifications/initialized') {
        if (_initializeAccepted) _clientReady = true;
        return hasId ? _success(id, <String, Object?>{}) : null;
      }
      if (method == 'tools/list') {
        _requireReady();
        if (!hasId) return null;
        return _success(id, <String, Object?>{'tools': _toolDefinitions});
      }
      if (method == 'tools/call') {
        _requireReady();
        if (!hasId) return null;
        return _success(id, await _callTool(params));
      }
      throw const _JsonRpcFailure(-32601, 'method_not_found');
    } on _JsonRpcFailure catch (error) {
      return hasId ? _error(id, error.jsonRpcCode, error.code) : null;
    } on AgentProtocolException catch (error) {
      return hasId ? _error(id, -32602, error.code) : null;
    } catch (_) {
      return hasId
          ? _error(id, -32603, AgentProtocolError.internalError)
          : null;
    }
  }

  /// Drops every volatile network binding. A Vault lock or transport stop must
  /// call this even if durable Agent sessions are already closed separately.
  void revokeAll() {
    _sessions.clear();
    _initializeAccepted = false;
    _clientReady = false;
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final requested = _string(params['protocolVersion'], 'protocolVersion');
    if (requested != personalOsMcpTransportVersion) {
      throw const AgentProtocolException(
        AgentProtocolError.unsupportedVersion,
        'unsupported MCP transport version',
      );
    }
    _initializeAccepted = true;
    _clientReady = false;
    return <String, Object?>{
      'protocolVersion': personalOsMcpTransportVersion,
      'capabilities': <String, Object?>{
        'tools': <String, Object?>{'listChanged': false},
      },
      'serverInfo': <String, Object?>{
        'name': 'personal-os-android',
        'version': personalOsProtocolV0,
      },
    };
  }

  void _requireReady() {
    if (!_clientReady) {
      throw const _JsonRpcFailure(-32002, 'session_not_initialized');
    }
  }

  Future<Map<String, Object?>> _callTool(
    Map<String, Object?> params,
  ) async {
    try {
      final name = _string(params['name'], 'name');
      final arguments = params['arguments'] == null
          ? <String, Object?>{}
          : _map(params['arguments'], 'arguments');
      final payload = await _dispatchTool(name, arguments);
      return _toolResult(payload);
    } on AgentProtocolException catch (error) {
      return _toolFailure(error.code);
    } on StrategyLoopFailure {
      return _toolFailure(AgentProtocolError.validationFailed);
    } on FeedbackUseCaseFailure {
      return _toolFailure(AgentProtocolError.validationFailed);
    } catch (_) {
      return _toolFailure(AgentProtocolError.internalError);
    }
  }

  Future<Map<String, Object?>> _dispatchTool(
    String name,
    Map<String, Object?> arguments,
  ) async {
    switch (name) {
      case PersonalOsMcpTools.openSession:
        return _openSession(arguments);
      case PersonalOsMcpTools.queryContext:
        return _queryContext(arguments);
      case PersonalOsMcpTools.getObject:
        return _getObject(arguments);
      case PersonalOsMcpTools.submitProposal:
        return _submitProposal(arguments);
      case PersonalOsMcpTools.submitReview:
        return _submitReview(arguments);
      case PersonalOsMcpTools.closeSession:
        return _closeSession(arguments);
      default:
        throw const AgentProtocolException(
          AgentProtocolError.invalidRequest,
          'unknown Personal OS tool',
        );
    }
  }

  Future<Map<String, Object?>> _openSession(
    Map<String, Object?> arguments,
  ) async {
    final agentId = _string(arguments['agent_id'], 'agent_id');
    final purpose = _string(arguments['purpose'], 'purpose');
    final requested = _strings(arguments['capabilities'], 'capabilities');
    final actor = ActorRef(
      actorId: agentId,
      actorType: ActorType.agent,
      authoritySource: _authoritySource,
      onBehalfOf: _profileId.value,
      capabilityRefs: requested,
    );
    final grant = await _service.openSession(
      agent: actor,
      profileId: _profileId,
      purpose: purpose,
      requestedCapabilities: requested,
    );
    final binding = _SessionBinding(
      agentId: agentId,
      purpose: purpose,
      capabilities: grant.capabilities,
      revision: grant.revision,
    );
    _sessions[grant.sessionId.value] = binding;
    return <String, Object?>{
      'protocol_version': grant.protocolVersion,
      'session_id': grant.sessionId.value,
      'session_revision': grant.revision,
      'capabilities': grant.capabilities,
    };
  }

  Future<Map<String, Object?>> _queryContext(
    Map<String, Object?> arguments,
  ) async {
    final sessionId = _sessionId(arguments);
    final binding = _binding(sessionId);
    final bundle = await _service.queryContext(
      sessionId: sessionId,
      purpose: binding.purpose,
      objectTypes: _strings(
              arguments['object_types'] ?? const <Object?>[], 'object_types')
          .toSet(),
      cursor: _optionalString(arguments['cursor'], 'cursor'),
      limit: arguments['limit'] == null
          ? 100
          : _integer(arguments['limit'], 'limit'),
    );
    final decoded = jsonDecode(bundle);
    if (decoded is! Map) {
      throw const AgentProtocolException(
        AgentProtocolError.internalError,
        'invalid context response',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  Future<Map<String, Object?>> _getObject(
    Map<String, Object?> arguments,
  ) async {
    final sessionId = _sessionId(arguments);
    _binding(sessionId);
    final record = await _service.getObject(
      sessionId: sessionId,
      ref: _objectRef(arguments['ref']),
    );
    if (record == null) {
      throw const AgentProtocolException(
        AgentProtocolError.notFound,
        'object not found',
      );
    }
    return record.toJson();
  }

  Future<Map<String, Object?>> _submitProposal(
    Map<String, Object?> arguments,
  ) async {
    final sessionId = _sessionId(arguments);
    final binding = _binding(sessionId);
    final bundleJson = _bundleJson(arguments['bundle'], 'bundle');
    final result = await _service.submitProposal(
      bundleJson: bundleJson,
      agent: _agent(sessionId, binding),
      profileId: _profileId,
      expectedSessionRevision: binding.revision,
    );
    binding.revision += 1;
    return <String, Object?>{
      'object_id': result.objectId.value,
      'event_ids': result.eventIds,
      'session_revision': binding.revision,
    };
  }

  Future<Map<String, Object?>> _submitReview(
    Map<String, Object?> arguments,
  ) async {
    final sessionId = _sessionId(arguments);
    final binding = _binding(sessionId);
    final result = await _service.submitReview(
      bundleJson: _bundleJson(arguments['bundle'], 'bundle'),
      agent: _agent(sessionId, binding),
      profileId: _profileId,
    );
    return <String, Object?>{
      'review_id': result.reviewId,
      'event_id': result.eventId,
      'session_revision': binding.revision,
    };
  }

  Future<Map<String, Object?>> _closeSession(
    Map<String, Object?> arguments,
  ) async {
    final sessionId = _sessionId(arguments);
    final binding = _binding(sessionId);
    await _service.closeSession(
      sessionId: sessionId,
      profileId: _profileId,
      expectedRevision: binding.revision,
      agent: _agent(sessionId, binding),
      failed: arguments['failed'] == null
          ? false
          : _boolean(arguments['failed'], 'failed'),
    );
    _sessions.remove(sessionId.value);
    return <String, Object?>{
      'session_id': sessionId.value,
      'closed': true,
    };
  }

  EntityId _sessionId(Map<String, Object?> arguments) =>
      EntityId(_string(arguments['session_id'], 'session_id'));

  _SessionBinding _binding(EntityId sessionId) {
    final binding = _sessions[sessionId.value];
    if (binding == null) {
      throw const AgentProtocolException(
        AgentProtocolError.accessDenied,
        'Agent session access denied',
      );
    }
    return binding;
  }

  ActorRef _agent(EntityId sessionId, _SessionBinding binding) => ActorRef(
        actorId: binding.agentId,
        actorType: ActorType.agent,
        authoritySource: _authoritySource,
        sessionOrRunId: sessionId.value,
        onBehalfOf: _profileId.value,
        capabilityRefs: binding.capabilities,
      );
}

final class _SessionBinding {
  _SessionBinding({
    required this.agentId,
    required this.purpose,
    required Iterable<String> capabilities,
    required this.revision,
  }) : capabilities = List<String>.unmodifiable(capabilities);

  final String agentId;
  final String purpose;
  final List<String> capabilities;
  int revision;
}

final class _JsonRpcFailure implements Exception {
  const _JsonRpcFailure(this.jsonRpcCode, this.code);

  final int jsonRpcCode;
  final String code;
}

Map<String, Object?> _success(Object? id, Map<String, Object?> result) =>
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    };

Map<String, Object?> _error(Object? id, int code, String stableCode) =>
    <String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'error': <String, Object?>{
        'code': code,
        'message': stableCode,
        'data': <String, Object?>{'code': stableCode, 'retryable': false},
      },
    };

Map<String, Object?> _toolResult(Map<String, Object?> payload) =>
    <String, Object?>{
      'content': <Object?>[
        <String, Object?>{'type': 'text', 'text': jsonEncode(payload)},
      ],
      'isError': false,
    };

Map<String, Object?> _toolFailure(String code) => <String, Object?>{
      'content': <Object?>[
        <String, Object?>{
          'type': 'text',
          'text': jsonEncode(<String, Object?>{
            'code': code,
            'retryable': false,
          }),
        },
      ],
      'isError': true,
    };

String _bundleJson(Object? value, String field) {
  if (value is String && value.trim().isNotEmpty) return value;
  if (value is Map) return jsonEncode(Map<String, Object?>.from(value));
  throw AgentProtocolException(
    AgentProtocolError.invalidRequest,
    '$field must be a JSON object or string',
  );
}

ObjectRef _objectRef(Object? value) {
  final json = _map(value, 'ref');
  final revision = _integer(json['revision'], 'revision');
  if (revision <= 0) {
    throw const AgentProtocolException(
      AgentProtocolError.unpinnedReference,
      'revision must be positive',
    );
  }
  return ObjectRef(
    type: _string(json['type'], 'type'),
    id: EntityId(_string(json['id'], 'id')),
    revision: Revision(revision),
  );
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be an object',
    );
  }
  return Map<String, Object?>.from(value);
}

List<String> _strings(Object? value, String field) {
  if (value is! List || value.any((item) => item is! String)) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be an array of strings',
    );
  }
  return List<String>.unmodifiable(value.cast<String>());
}

String _string(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be a non-blank string',
    );
  }
  return value.trim();
}

String? _optionalString(Object? value, String field) =>
    value == null ? null : _string(value, field);

int _integer(Object? value, String field) {
  if (value is! int) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be an integer',
    );
  }
  return value;
}

bool _boolean(Object? value, String field) {
  if (value is! bool) {
    throw AgentProtocolException(
      AgentProtocolError.invalidRequest,
      '$field must be a boolean',
    );
  }
  return value;
}

const _toolDefinitions = <Map<String, Object?>>[
  <String, Object?>{
    'name': PersonalOsMcpTools.openSession,
    'description': 'Open a short-lived, capability-scoped Agent session.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'required': <String>['agent_id', 'purpose', 'capabilities'],
      'properties': <String, Object?>{
        'agent_id': <String, Object?>{'type': 'string'},
        'purpose': <String, Object?>{'type': 'string'},
        'capabilities': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
      },
      'additionalProperties': false,
    },
  },
  <String, Object?>{
    'name': PersonalOsMcpTools.queryContext,
    'description': 'Read a policy-approved page of pinned context.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'required': <String>['session_id'],
      'properties': <String, Object?>{
        'session_id': <String, Object?>{'type': 'string'},
        'object_types': <String, Object?>{
          'type': 'array',
          'items': <String, Object?>{'type': 'string'},
        },
        'cursor': <String, Object?>{'type': 'string'},
        'limit': <String, Object?>{'type': 'integer'},
      },
      'additionalProperties': false,
    },
  },
  <String, Object?>{
    'name': PersonalOsMcpTools.getObject,
    'description': 'Read one exact, revision-pinned object.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'required': <String>['session_id', 'ref'],
      'properties': <String, Object?>{
        'session_id': <String, Object?>{'type': 'string'},
        'ref': <String, Object?>{'type': 'object'},
      },
      'additionalProperties': false,
    },
  },
  <String, Object?>{
    'name': PersonalOsMcpTools.submitProposal,
    'description': 'Submit a proposal for later user confirmation.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'required': <String>['session_id', 'bundle'],
      'properties': <String, Object?>{
        'session_id': <String, Object?>{'type': 'string'},
        'bundle': <String, Object?>{
          'type': <String>['object', 'string']
        },
      },
      'additionalProperties': false,
    },
  },
  <String, Object?>{
    'name': PersonalOsMcpTools.submitReview,
    'description': 'Submit an evidence-pinned review draft.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'required': <String>['session_id', 'bundle'],
      'properties': <String, Object?>{
        'session_id': <String, Object?>{'type': 'string'},
        'bundle': <String, Object?>{
          'type': <String>['object', 'string']
        },
      },
      'additionalProperties': false,
    },
  },
  <String, Object?>{
    'name': PersonalOsMcpTools.closeSession,
    'description': 'Close the current volatile and durable Agent session.',
    'inputSchema': <String, Object?>{
      'type': 'object',
      'required': <String>['session_id'],
      'properties': <String, Object?>{
        'session_id': <String, Object?>{'type': 'string'},
        'failed': <String, Object?>{'type': 'boolean'},
      },
      'additionalProperties': false,
    },
  },
];
