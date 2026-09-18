import 'package:flutter/foundation.dart';
import 'package:personal_os_agent_protocol/agent_protocol.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

enum StrategyUiStatus { idle, running, ready, failed }

/// UI state for the external-Agent strategy loop.
///
/// It deliberately stays separate from [AppController] so vault unlock and the
/// legacy appearance workflow cannot retain or accidentally mutate this state.
final class StrategyLoopController extends ChangeNotifier {
  StrategyLoopController({
    required PersonalOsAgentProtocolService protocol,
    required StrategyLoopUseCase strategyLoop,
    required EntityId profileId,
    required ActorRef user,
  })  : _protocol = protocol,
        _strategyLoop = strategyLoop,
        _profileId = profileId,
        _user = user;

  final PersonalOsAgentProtocolService _protocol;
  final StrategyLoopUseCase _strategyLoop;
  final EntityId _profileId;
  final ActorRef _user;

  StrategyUiStatus _status = StrategyUiStatus.idle;
  String? _errorCode;
  EntityId? _sessionId;
  int _sessionRevision = 0;
  EntityId? _strategyId;
  int _strategyRevision = 0;
  String? _strategyState;
  EntityId? _executionId;
  EntityId? _outcomeId;
  String? _contextBundle;

  StrategyUiStatus get status => _status;
  String? get errorCode => _errorCode;
  String? get sessionId => _sessionId?.value;
  String? get strategyId => _strategyId?.value;
  String? get strategyState => _strategyState;
  String? get executionId => _executionId?.value;
  String? get outcomeId => _outcomeId?.value;
  String? get contextBundle => _contextBundle;
  bool get hasSession => _sessionId != null;
  bool get hasPendingProposal => _strategyState == 'proposed';
  bool get canActivate => _strategyState == 'accepted';
  bool get canRecordExecution => _strategyState == 'active';
  bool get canRecordOutcome => _executionId != null;

  Future<void> openOfflineSession() async {
    await _run(() async {
      final agent = _agentFor(null);
      final grant = await _protocol.openSession(
        agent: agent,
        profileId: _profileId,
        purpose: 'personal strategy proposal',
        requestedCapabilities: const <String>[
          'context.query',
          'object.get',
          'proposal.submit',
        ],
      );
      _sessionId = grant.sessionId;
      _sessionRevision = grant.revision;
      return 'session_opened';
    });
  }

  Future<void> exportContext() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      _fail('strategy.session_required');
      return;
    }
    await _run(() async {
      _contextBundle = await _protocol.queryContext(
        sessionId: sessionId,
        purpose: 'personal strategy proposal',
        objectTypes: const <String>{
          'goal',
          'personal_asset',
          'constraint',
          'strategy',
          'plan',
          'task',
          'execution',
          'outcome',
          'review',
          'observation',
        },
      );
      return 'context_exported';
    });
  }

  Future<void> importProposal(String bundleJson) async {
    final sessionId = _sessionId;
    if (sessionId == null || bundleJson.trim().isEmpty) {
      _fail('strategy.session_or_bundle_required');
      return;
    }
    await _run(() async {
      final result = await _protocol.submitProposal(
        bundleJson: bundleJson,
        agent: _agentFor(sessionId),
        profileId: _profileId,
        expectedSessionRevision: _sessionRevision,
      );
      _strategyId = result.objectId;
      _strategyRevision = 1;
      _strategyState = 'proposed';
      _sessionRevision += 1;
      return 'proposal_imported';
    });
  }

  Future<void> decideProposal(ProposalDecision decision) async {
    final strategyId = _strategyId;
    if (strategyId == null || _strategyState != 'proposed') {
      _fail('strategy.pending_proposal_required');
      return;
    }
    await _run(() async {
      await _strategyLoop.decideProposal(
        DecideStrategyProposalCommand(
          actor: _user,
          profileId: _profileId,
          correlationId: _correlation('proposal-decision'),
          strategyId: strategyId,
          expectedRevision: _strategyRevision,
          decision: decision,
        ),
      );
      _strategyRevision += 1;
      _strategyState =
          decision == ProposalDecision.accept ? 'accepted' : 'abandoned';
      return 'proposal_${decision.name}';
    });
  }

  Future<void> activateStrategy() async {
    final strategyId = _strategyId;
    if (strategyId == null || _strategyState != 'accepted') {
      _fail('strategy.accepted_strategy_required');
      return;
    }
    await _run(() async {
      await _strategyLoop.activateStrategy(
        ActivateStrategyCommand(
          actor: _user,
          profileId: _profileId,
          correlationId: _correlation('strategy-activate'),
          strategyId: strategyId,
          expectedRevision: _strategyRevision,
        ),
      );
      _strategyRevision += 1;
      _strategyState = 'active';
      return 'strategy_activated';
    });
  }

  Future<void> recordExecution({
    required String actionId,
    required ExecutionStatus executionStatus,
    String? note,
  }) async {
    final strategyId = _strategyId;
    if (strategyId == null || _strategyState != 'active') {
      _fail('strategy.active_strategy_required');
      return;
    }
    if (actionId.trim().isEmpty) {
      _fail('strategy.action_required');
      return;
    }
    await _run(() async {
      final result = await _strategyLoop.recordExecution(
        RecordStrategyExecutionCommand(
          actor: _user,
          profileId: _profileId,
          correlationId: _correlation('execution'),
          strategyRef: ObjectRef(
            type: 'strategy',
            id: strategyId,
            revision: Revision(_strategyRevision),
          ),
          actionId: EntityId(actionId.trim()),
          status: executionStatus,
          note: note,
        ),
      );
      _executionId = result.objectId;
      return 'execution_recorded';
    });
  }

  Future<void> recordOutcome({
    required String observation,
    required OutcomeValence valence,
  }) async {
    final executionId = _executionId;
    if (executionId == null || observation.trim().isEmpty) {
      _fail('strategy.execution_or_observation_required');
      return;
    }
    await _run(() async {
      final result = await _strategyLoop.recordOutcome(
        RecordStrategyOutcomeCommand(
          actor: _user,
          profileId: _profileId,
          correlationId: _correlation('outcome'),
          executionRef: ObjectRef(
            type: 'execution',
            id: executionId,
            revision: Revision(1),
          ),
          observation: observation.trim(),
          valence: valence,
        ),
      );
      _outcomeId = result.objectId;
      return 'outcome_recorded';
    });
  }

  void reset() {
    _status = StrategyUiStatus.idle;
    _errorCode = null;
    _sessionId = null;
    _sessionRevision = 0;
    _strategyId = null;
    _strategyRevision = 0;
    _strategyState = null;
    _executionId = null;
    _outcomeId = null;
    _contextBundle = null;
    notifyListeners();
  }

  ActorRef _agentFor(EntityId? sessionId) => ActorRef(
        actorId: 'offline-harness',
        actorType: ActorType.agent,
        authoritySource: 'offline_bundle',
        sessionOrRunId: sessionId?.value,
        onBehalfOf: _user.actorId,
        capabilityRefs: const <String>[
          'context.query',
          'object.get',
          'proposal.submit',
        ],
      );

  String _correlation(String operation) =>
      'mobile-$operation-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _run(Future<String> Function() operation) async {
    if (_status == StrategyUiStatus.running) return;
    _status = StrategyUiStatus.running;
    _errorCode = null;
    notifyListeners();
    try {
      await operation();
      _status = StrategyUiStatus.ready;
    } on AgentProtocolException catch (error) {
      _status = StrategyUiStatus.failed;
      _errorCode = error.code;
    } on StrategyLoopFailure catch (error) {
      _status = StrategyUiStatus.failed;
      _errorCode = error.code;
    } on Object {
      _status = StrategyUiStatus.failed;
      _errorCode = 'strategy.unexpected_failure';
    }
    notifyListeners();
  }

  void _fail(String code) {
    _status = StrategyUiStatus.failed;
    _errorCode = code;
    notifyListeners();
  }
}
