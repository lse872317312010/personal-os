import 'dart:convert';

import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('requires the MCP initialize handshake before listing tools', () async {
    final adapter = _adapter(_EventStore());

    final premature = await _request(
      adapter,
      1,
      'tools/list',
      const <String, Object?>{},
    );
    expect(_errorCode(premature), -32002);

    final initialized = await _request(
      adapter,
      2,
      'initialize',
      const <String, Object?>{
        'protocolVersion': personalOsMcpTransportVersion,
        'clientInfo': <String, Object?>{'name': 'test-harness'},
      },
    );
    final initializeResult = initialized!['result']! as Map<String, Object?>;
    expect(
      initializeResult['protocolVersion'],
      personalOsMcpTransportVersion,
    );

    final notification = await adapter.handle(
      const <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
    );
    expect(notification, isNull);

    final listed = await _request(
      adapter,
      3,
      'tools/list',
      const <String, Object?>{},
    );
    final result = listed!['result']! as Map<String, Object?>;
    final tools = result['tools']! as List<Object?>;
    expect(
      tools.map((item) => (item! as Map<String, Object?>)['name']).toSet(),
      <String>{
        PersonalOsMcpTools.openSession,
        PersonalOsMcpTools.queryContext,
        PersonalOsMcpTools.getObject,
        PersonalOsMcpTools.submitProposal,
        PersonalOsMcpTools.submitReview,
        PersonalOsMcpTools.closeSession,
      },
    );
  });

  test('tool calls cannot escalate a granted capability', () async {
    final store = _EventStore();
    final adapter = _adapter(store);
    await _initialize(adapter);

    final opened = await _tool(
      adapter,
      1,
      PersonalOsMcpTools.openSession,
      const <String, Object?>{
        'agent_id': 'read-only-harness',
        'purpose': 'read strategy context',
        'capabilities': <Object?>['context.query'],
      },
    );
    final sessionId = opened['session_id']! as String;

    final denied = await _toolResult(
      adapter,
      2,
      PersonalOsMcpTools.submitProposal,
      <String, Object?>{
        'session_id': sessionId,
        'bundle': _proposal(sessionId, 'denied'),
      },
    );
    expect(denied['isError'], isTrue);
    expect(_toolErrorCode(denied), AgentProtocolError.accessDenied);
    expect(
      store.events.where(
        (event) => event.eventType == EventTypes.strategyProposed,
      ),
      isEmpty,
    );
  });

  test('proposal revision is owned by adapter and revokeAll fails closed',
      () async {
    final store = _EventStore();
    final adapter = _adapter(store);
    await _initialize(adapter);

    final opened = await _tool(
      adapter,
      1,
      PersonalOsMcpTools.openSession,
      const <String, Object?>{
        'agent_id': 'writer-harness',
        'purpose': 'propose bounded strategy',
        'capabilities': <Object?>['proposal.submit'],
      },
    );
    final sessionId = opened['session_id']! as String;

    final submitted = await _tool(
      adapter,
      2,
      PersonalOsMcpTools.submitProposal,
      <String, Object?>{
        'session_id': sessionId,
        'bundle': _proposal(sessionId, 'accepted'),
      },
    );
    expect(submitted['object_id'], startsWith('strategy-'));
    expect(submitted['session_revision'], 2);

    adapter.revokeAll();
    await _initialize(adapter);
    final denied = await _toolResult(
      adapter,
      3,
      PersonalOsMcpTools.submitProposal,
      <String, Object?>{
        'session_id': sessionId,
        'bundle': _proposal(sessionId, 'after-revoke'),
      },
    );
    expect(denied['isError'], isTrue);
    expect(_toolErrorCode(denied), AgentProtocolError.accessDenied);
  });

  test('unsupported versions and internal failures stay redacted', () async {
    final adapter = _adapter(_FailingEventStore());
    final unsupported = await _request(
      adapter,
      1,
      'initialize',
      const <String, Object?>{'protocolVersion': 'future-version'},
    );
    expect(
        _errorStableCode(unsupported), AgentProtocolError.unsupportedVersion);

    await _initialize(adapter);
    final failed = await _toolResult(
      adapter,
      2,
      PersonalOsMcpTools.openSession,
      const <String, Object?>{
        'agent_id': 'harness',
        'purpose': 'failure boundary',
        'capabilities': <Object?>['context.query'],
      },
    );
    expect(failed['isError'], isTrue);
    expect(_toolErrorCode(failed), AgentProtocolError.internalError);
    expect(jsonEncode(failed), isNot(contains('secret database path')));
  });
}

PersonalOsMcpJsonRpcAdapter _adapter(EventStore store) {
  final ids = _Ids();
  return PersonalOsMcpJsonRpcAdapter(
    service: PersonalOsAgentProtocolService(
      eventStore: store,
      strategyLoop: StrategyLoopUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      actionFeedback: ActionFeedbackUseCase(
        eventStore: store,
        ids: ids,
        clock: const _Clock(),
      ),
      contextSource: const _NoContext(),
      ids: ids,
      clock: const _Clock(),
    ),
    profileId: EntityId('primary-user'),
  );
}

Future<void> _initialize(PersonalOsMcpJsonRpcAdapter adapter) async {
  final response = await _request(
    adapter,
    100,
    'initialize',
    const <String, Object?>{
      'protocolVersion': personalOsMcpTransportVersion,
    },
  );
  expect(response?['error'], isNull);
  await adapter.handle(
    const <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    },
  );
}

Future<Map<String, Object?>?> _request(
  PersonalOsMcpJsonRpcAdapter adapter,
  Object id,
  String method,
  Map<String, Object?> params,
) =>
    adapter.handle(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });

Future<Map<String, Object?>> _toolResult(
  PersonalOsMcpJsonRpcAdapter adapter,
  Object id,
  String name,
  Map<String, Object?> arguments,
) async {
  final response = await _request(
    adapter,
    id,
    'tools/call',
    <String, Object?>{'name': name, 'arguments': arguments},
  );
  return response!['result']! as Map<String, Object?>;
}

Future<Map<String, Object?>> _tool(
  PersonalOsMcpJsonRpcAdapter adapter,
  Object id,
  String name,
  Map<String, Object?> arguments,
) async {
  final result = await _toolResult(adapter, id, name, arguments);
  expect(result['isError'], isFalse);
  final content = result['content']! as List<Object?>;
  final item = content.single! as Map<String, Object?>;
  return Map<String, Object?>.from(
    jsonDecode(item['text']! as String) as Map,
  );
}

int? _errorCode(Map<String, Object?>? response) {
  final error = response?['error'];
  return error is Map ? error['code'] as int? : null;
}

String? _errorStableCode(Map<String, Object?>? response) {
  final error = response?['error'];
  if (error is! Map) return null;
  final data = error['data'];
  return data is Map ? data['code'] as String? : null;
}

String? _toolErrorCode(Map<String, Object?> result) {
  final content = result['content']! as List<Object?>;
  final item = content.single! as Map<String, Object?>;
  final payload = jsonDecode(item['text']! as String);
  return (payload! as Map<String, Object?>)['code']! as String;
}

Map<String, Object?> _proposal(String sessionId, String suffix) =>
    <String, Object?>{
      'protocol_version': personalOsProtocolV0,
      'proposal_id': 'proposal-$suffix',
      'session_id': sessionId,
      'created_at': '2026-09-19T00:00:00Z',
      'strategy': <String, Object?>{
        'title': 'Bounded strategy',
        'rationale': 'Collect deterministic evidence',
        'goal_refs': <Object?>[
          <String, Object?>{
            'type': 'goal',
            'id': 'goal-1',
            'revision': 1,
          },
        ],
        'asset_refs': <Object?>[],
        'actions': <Object?>[
          <String, Object?>{
            'id': 'action-1',
            'instruction': 'Run the bounded action',
          },
        ],
      },
    };

class _EventStore implements EventStore {
  final List<EventEnvelope> events = <EventEnvelope>[];

  @override
  Future<void> appendAll(List<EventEnvelope> events) async {
    this.events.addAll(events);
  }

  @override
  Future<EventEnvelope?> readById(String eventId) async {
    for (final event in events) {
      if (event.eventId == eventId) return event;
    }
    return null;
  }

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async {
    final matches = events
        .where(
          (event) => event.subjectRefs.any(
            (candidate) =>
                candidate.type == subject.type && candidate.id == subject.id,
          ),
        )
        .toList(growable: false);
    return limit == null
        ? matches
        : matches.take(limit).toList(growable: false);
  }
}

final class _FailingEventStore implements EventStore {
  @override
  Future<void> appendAll(List<EventEnvelope> events) =>
      Future<void>.error(Exception('secret database path'));

  @override
  Future<EventEnvelope?> readById(String eventId) async => null;

  @override
  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  }) async =>
      <EventEnvelope>[];
}

final class _Ids implements IdGenerator {
  int _next = 0;

  @override
  String nextId(String namespace) => '$namespace-${++_next}';
}

final class _Clock implements Clock {
  const _Clock();

  @override
  DateTime now() => DateTime.utc(2026, 9, 19);
}

final class _NoContext implements AgentContextSource {
  const _NoContext();

  @override
  Future<ContextRecord?> get({
    required EntityId sessionId,
    required ObjectRef ref,
  }) async =>
      null;

  @override
  Future<ContextPage> query({
    required EntityId sessionId,
    required String purpose,
    required Set<String> objectTypes,
    String? cursor,
    int limit = 100,
  }) async =>
      ContextPage(records: const <ContextRecord>[]);
}
