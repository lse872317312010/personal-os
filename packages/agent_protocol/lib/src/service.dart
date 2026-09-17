import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'bundles.dart';

abstract final class PersonalOsMcpTools {
  static const openSession = 'personal_os.open_session';
  static const queryContext = 'personal_os.query_context';
  static const getObject = 'personal_os.get_object';
  static const submitProposal = 'personal_os.submit_proposal';
  static const closeSession = 'personal_os.close_session';
}

final class AgentSessionGrant {
  const AgentSessionGrant({
    required this.sessionId,
    required this.revision,
    required this.protocolVersion,
    required this.capabilities,
  });

  final EntityId sessionId;
  final int revision;
  final String protocolVersion;
  final List<String> capabilities;
}

final class ContextPage {
  ContextPage({
    required Iterable<ContextRecord> records,
    this.cursor,
    this.hasMore = false,
  }) : records = List<ContextRecord>.unmodifiable(records);

  final List<ContextRecord> records;
  final String? cursor;
  final bool hasMore;
}

/// Local policy-aware source. Implementations expose only approved records.
abstract interface class AgentContextSource {
  Future<ContextPage> query({
    required EntityId sessionId,
    required String purpose,
    required Set<String> objectTypes,
    String? cursor,
    int limit = 100,
  });

  Future<ContextRecord?> get({
    required EntityId sessionId,
    required ObjectRef ref,
  });
}

/// Transport-neutral implementation behind MCP tools and offline exchange.
final class PersonalOsAgentProtocolService {
  const PersonalOsAgentProtocolService({
    required EventStore eventStore,
    required StrategyLoopUseCase strategyLoop,
    required AgentContextSource contextSource,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _strategyLoop = strategyLoop,
        _contextSource = contextSource,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final StrategyLoopUseCase _strategyLoop;
  final AgentContextSource _contextSource;
  final IdGenerator _ids;
  final Clock _clock;

  Future<AgentSessionGrant> openSession({
    required ActorRef agent,
    required EntityId profileId,
    required String purpose,
    required Iterable<String> requestedCapabilities,
    Sensitivity sensitivity = Sensitivity.d2,
  }) async {
    if (agent.actorType != ActorType.agent ||
        purpose.trim().isEmpty ||
        sensitivity == Sensitivity.d4) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'invalid Agent session request',
      );
    }
    final allowed = requestedCapabilities
        .where(_supportedCapabilities.contains)
        .toSet()
        .toList(growable: false)
      ..sort();
    final sessionId = EntityId(_ids.nextId('agent_session'));
    final eventId = _ids.nextId('event');
    final now = _clock.now().toUtc();
    await _eventStore.appendAll(<EventEnvelope>[
      EventEnvelope(
        eventId: eventId,
        eventType: EventTypes.agentSessionOpened,
        eventVersion: 1,
        occurredAt: now,
        recordedAt: now,
        actor: agent,
        subjectRefs: <ObjectRef>[
          ObjectRef(type: 'agent_session', id: sessionId),
          ObjectRef(type: 'profile', id: profileId),
        ],
        correlationId: sessionId.value,
        sensitivity: sensitivity,
        payload: <String, Object?>{
          'expected_revision': 0,
          'agent_id': agent.actorId,
          'protocol_version': personalOsProtocolV0,
          'purpose': purpose.trim(),
          'capabilities': allowed,
        },
      ),
    ]);
    return AgentSessionGrant(
      sessionId: sessionId,
      revision: 1,
      protocolVersion: personalOsProtocolV0,
      capabilities: allowed,
    );
  }

  Future<String> queryContext({
    required EntityId sessionId,
    required String purpose,
    required Set<String> objectTypes,
    String? cursor,
    int limit = 100,
  }) async {
    if (purpose.trim().isEmpty || limit <= 0 || limit > 500) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'invalid context query',
      );
    }
    final page = await _contextSource.query(
      sessionId: sessionId,
      purpose: purpose,
      objectTypes: objectTypes,
      cursor: cursor,
      limit: limit,
    );
    return ContextBundleCodec.encode(
      ContextBundle(
        bundleId: _ids.nextId('context_bundle'),
        sessionId: sessionId,
        createdAt: _clock.now(),
        purpose: purpose.trim(),
        records: page.records,
        cursor: page.cursor,
        hasMore: page.hasMore,
      ),
    );
  }

  Future<ContextRecord?> getObject({
    required EntityId sessionId,
    required ObjectRef ref,
  }) {
    if (ref.revision == null) {
      throw const AgentProtocolException(
        AgentProtocolError.unpinnedReference,
        'get_object requires a pinned reference',
      );
    }
    return _contextSource.get(sessionId: sessionId, ref: ref);
  }

  Future<StrategyLoopResult> submitProposal({
    required String bundleJson,
    required ActorRef agent,
    required EntityId profileId,
    required int expectedSessionRevision,
    Iterable<ObjectRef> consentRefs = const <ObjectRef>[],
    Sensitivity sensitivity = Sensitivity.d2,
  }) {
    final proposal = ProposalBundleCodec.decodeString(bundleJson);
    if (agent.sessionOrRunId != proposal.sessionId.value) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'Agent identity does not match proposal session',
      );
    }
    return _strategyLoop.submitProposal(
      proposal.toCommand(
        agent: agent,
        profileId: profileId,
        expectedSessionRevision: expectedSessionRevision,
        correlationId: proposal.proposalId,
        sensitivity: sensitivity,
        consentRefs: consentRefs,
      ),
    );
  }

  Future<void> closeSession({
    required EntityId sessionId,
    required EntityId profileId,
    required int expectedRevision,
    required ActorRef agent,
    bool failed = false,
    Sensitivity sensitivity = Sensitivity.d2,
  }) async {
    if (agent.actorType != ActorType.agent ||
        agent.sessionOrRunId != sessionId.value ||
        expectedRevision < 0 ||
        sensitivity == Sensitivity.d4) {
      throw const AgentProtocolException(
        AgentProtocolError.invalidRequest,
        'invalid Agent session close request',
      );
    }
    final now = _clock.now().toUtc();
    await _eventStore.appendAll(<EventEnvelope>[
      EventEnvelope(
        eventId: _ids.nextId('event'),
        eventType: failed
            ? EventTypes.agentSessionFailed
            : EventTypes.agentSessionClosed,
        eventVersion: 1,
        occurredAt: now,
        recordedAt: now,
        actor: agent,
        subjectRefs: <ObjectRef>[
          ObjectRef(type: 'agent_session', id: sessionId),
          ObjectRef(type: 'profile', id: profileId),
        ],
        correlationId: sessionId.value,
        sensitivity: sensitivity,
        payload: <String, Object?>{
          'expected_revision': expectedRevision,
        },
      ),
    ]);
  }
}

const _supportedCapabilities = <String>{
  'context.query',
  'object.get',
  'proposal.submit',
};
