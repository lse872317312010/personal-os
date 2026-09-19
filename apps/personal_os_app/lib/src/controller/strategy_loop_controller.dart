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
    required ActionFeedbackUseCase actionFeedback,
    required EntityId profileId,
    StrategySessionQueryHandler? restoreQuery,
    required ActorRef user,
  })  : _protocol = protocol,
        _strategyLoop = strategyLoop,
        _actionFeedback = actionFeedback,
        _profileId = profileId,
        _restoreQuery = restoreQuery,
        _user = user;

  final PersonalOsAgentProtocolService _protocol;
  final StrategyLoopUseCase _strategyLoop;
  final ActionFeedbackUseCase _actionFeedback;
  final EntityId _profileId;
  final StrategySessionQueryHandler? _restoreQuery;
  final ActorRef _user;

  int _lifecycleEpoch = 0;
  bool _disposed = false;
  bool _bootstrapped = false;

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
  String _agentId = 'offline-harness';
  String? _proposalTitle;
  String? _proposalRationale;
  String? _parentStrategyRef;
  List<String> _proposalEvidenceRefs = const <String>[];
  EntityId? _reviewId;
  String? _reviewState;
  String? _reviewSummary;
  String? _reviewConclusion;
  List<String> _reviewEvidenceRefs = const <String>[];

  StrategyUiStatus get status => _status;
  String? get errorCode => _errorCode;
  String? get sessionId => _sessionId?.value;
  String? get strategyId => _strategyId?.value;
  String? get strategyState => _strategyState;
  String? get executionId => _executionId?.value;
  String? get outcomeId => _outcomeId?.value;
  String? get contextBundle => _contextBundle;
  String get agentId => _agentId;
  String? get proposalTitle => _proposalTitle;
  String? get proposalRationale => _proposalRationale;
  String? get parentStrategyRef => _parentStrategyRef;
  List<String> get proposalEvidenceRefs => _proposalEvidenceRefs;
  String? get reviewId => _reviewId?.value;
  String? get reviewState => _reviewState;
  String? get reviewSummary => _reviewSummary;
  String? get reviewConclusion => _reviewConclusion;
  List<String> get reviewEvidenceRefs => _reviewEvidenceRefs;
  bool get hasPendingReview => _reviewState == 'draft';
  bool get hasSession => _sessionId != null;
  bool get hasPendingProposal => _strategyState == 'proposed';
  bool get canActivate => _strategyState == 'accepted';
  bool get canRecordExecution => _strategyState == 'active';
  bool get canRecordOutcome => _executionId != null;
  bool get canCloseSession =>
      hasSession &&
      (_strategyId == null ||
          _outcomeId != null ||
          _strategyState == 'abandoned');

  Future<void> bootstrap() async {
    final query = _restoreQuery;
    if (query == null || _bootstrapped || _disposed) return;
    await _run((isCurrent) async {
      final view = await query.execute(_profileId);
      if (!isCurrent()) return 'stale';
      if (view != null) _applyRestoredSession(view);
      _bootstrapped = true;
      return view == null ? 'restore_empty' : 'session_restored';
    });
  }

  void _applyRestoredSession(StrategySessionView view) {
    _sessionId = view.sessionId;
    _sessionRevision = view.sessionRevision;
    _agentId = view.agentId;
    _strategyId = view.strategyId;
    _strategyRevision = view.strategyRevision;
    _strategyState = view.strategyState;
    _executionId = view.executionId;
    _outcomeId = view.outcomeId;
    _contextBundle = null;
    _proposalTitle = view.proposalTitle;
    _proposalRationale = view.proposalRationale;
    _parentStrategyRef = view.parentStrategyRef;
    _proposalEvidenceRefs = view.proposalEvidenceRefs;
    _reviewId = view.reviewId;
    _reviewState = view.reviewState;
    _reviewSummary = view.reviewSummary;
    _reviewConclusion = view.reviewConclusion;
    _reviewEvidenceRefs = view.reviewEvidenceRefs;
  }

  Future<void> openOfflineSession({required String agentId}) async {
    if (_status == StrategyUiStatus.running) return;
    final entryEpoch = _lifecycleEpoch;
    if (!_bootstrapped && _restoreQuery != null) {
      await bootstrap();
      if (_disposed ||
          entryEpoch != _lifecycleEpoch ||
          _status == StrategyUiStatus.failed) {
        return;
      }
    }
    if (hasSession) {
      _fail('strategy.session_already_open');
      return;
    }
    final normalized = agentId.trim();
    if (normalized.isEmpty || normalized.length > 100) {
      _fail('strategy.agent_id_invalid');
      return;
    }
    _agentId = normalized;
    await _run((isCurrent) async {
      final agent = _agentFor(null);
      final grant = await _protocol.openSession(
        agent: agent,
        profileId: _profileId,
        purpose: 'personal strategy proposal',
        requestedCapabilities: const <String>[
          'context.query',
          'object.get',
          'proposal.submit',
          'review.submit',
        ],
      );
      if (!isCurrent()) return 'stale';
      _sessionId = grant.sessionId;
      _sessionRevision = grant.revision;
      return 'session_opened';
    });
  }

  Future<void> closeSession() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      _fail('strategy.session_required');
      return;
    }
    if (!canCloseSession) {
      _fail('strategy.loop_must_finish_before_handoff');
      return;
    }
    await _run((isCurrent) async {
      await _protocol.closeSession(
        sessionId: sessionId,
        profileId: _profileId,
        expectedRevision: _sessionRevision,
        agent: _agentFor(sessionId),
      );
      if (!isCurrent()) return 'stale';
      _sessionId = null;
      _sessionRevision = 0;
      _strategyId = null;
      _strategyRevision = 0;
      _strategyState = null;
      _executionId = null;
      _outcomeId = null;
      _contextBundle = null;
      _proposalTitle = null;
      _proposalRationale = null;
      _parentStrategyRef = null;
      _proposalEvidenceRefs = const <String>[];
      _reviewId = null;
      _reviewState = null;
      _reviewSummary = null;
      _reviewConclusion = null;
      _reviewEvidenceRefs = const <String>[];
      return 'session_closed';
    });
  }

  Future<void> exportContext() async {
    final sessionId = _sessionId;
    if (sessionId == null) {
      _fail('strategy.session_required');
      return;
    }
    await _run((isCurrent) async {
      final bundle = await _protocol.queryContext(
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
      if (!isCurrent()) return 'stale';
      _contextBundle = bundle;
      return 'context_exported';
    });
  }

  Future<void> importReview(String bundleJson) async {
    final sessionId = _sessionId;
    if (sessionId == null || bundleJson.trim().isEmpty) {
      _fail('strategy.session_or_review_bundle_required');
      return;
    }
    await _run((isCurrent) async {
      final review = ReviewBundleCodec.decodeString(bundleJson);
      final result = await _protocol.submitReview(
        bundleJson: bundleJson,
        agent: _agentFor(sessionId),
        profileId: _profileId,
      );
      if (!isCurrent()) return 'stale';
      _reviewId = EntityId(result.reviewId);
      _reviewState = 'draft';
      _reviewSummary = review.summary;
      _reviewConclusion = review.conclusion.name;
      _reviewEvidenceRefs = <ObjectRef>[
        review.strategyRef,
        ...review.executionRefs,
        ...review.outcomeRefs,
        ...review.feedbackRefs,
      ]
          .map((ref) => '${ref.type}:${ref.id.value}@${ref.revision!.value}')
          .toList(growable: false);
      return 'review_imported';
    });
  }

  Future<void> decideReview(ReviewDecision decision) async {
    final reviewId = _reviewId;
    if (reviewId == null || _reviewState != 'draft') {
      _fail('strategy.pending_review_required');
      return;
    }
    await _run((isCurrent) async {
      await _actionFeedback.decideReview(
        DecideReviewCommand(
          reviewId: reviewId,
          profileId: _profileId,
          expectedReviewRevision: 1,
          actor: _user,
          correlationId: _correlation('review-decision'),
          decision: decision,
        ),
      );
      if (!isCurrent()) return 'stale';
      _reviewState =
          decision == ReviewDecision.accept ? 'accepted' : 'rejected';
      return 'review_${decision.name}';
    });
  }

  Future<void> importProposal(String bundleJson) async {
    final sessionId = _sessionId;
    if (sessionId == null || bundleJson.trim().isEmpty) {
      _fail('strategy.session_or_bundle_required');
      return;
    }
    await _run((isCurrent) async {
      final proposal = ProposalBundleCodec.decodeString(bundleJson);
      if (proposal.parentStrategy != null && _reviewState != 'accepted') {
        throw const AgentProtocolException(
          AgentProtocolError.invalidRequest,
          'an accepted review is required before a revised strategy',
        );
      }
      final result = await _protocol.submitProposal(
        bundleJson: bundleJson,
        agent: _agentFor(sessionId),
        profileId: _profileId,
        expectedSessionRevision: _sessionRevision,
      );
      if (!isCurrent()) return 'stale';
      _strategyId = result.objectId;
      _strategyRevision = 1;
      _strategyState = 'proposed';
      _proposalTitle = proposal.title;
      _proposalRationale = proposal.rationale;
      final parent = proposal.parentStrategy;
      _parentStrategyRef = parent == null
          ? null
          : '${parent.type}:${parent.id.value}@${parent.revision!.value}';
      _proposalEvidenceRefs = <ObjectRef>[
        ...proposal.goalRefs,
        ...proposal.assetRefs,
      ]
          .map(
            (ref) => '${ref.type}:${ref.id.value}@${ref.revision!.value}',
          )
          .toList(growable: false);
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
    await _run((isCurrent) async {
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
      if (!isCurrent()) return 'stale';
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
    await _run((isCurrent) async {
      await _strategyLoop.activateStrategy(
        ActivateStrategyCommand(
          actor: _user,
          profileId: _profileId,
          correlationId: _correlation('strategy-activate'),
          strategyId: strategyId,
          expectedRevision: _strategyRevision,
        ),
      );
      if (!isCurrent()) return 'stale';
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
    await _run((isCurrent) async {
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
      if (!isCurrent()) return 'stale';
      _executionId = result.objectId;
      _outcomeId = null;
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
    await _run((isCurrent) async {
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
      if (!isCurrent()) return 'stale';
      _outcomeId = result.objectId;
      return 'outcome_recorded';
    });
  }

  void reset() {
    if (_disposed) return;
    _lifecycleEpoch += 1;
    _bootstrapped = false;
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
    _agentId = 'offline-harness';
    _proposalTitle = null;
    _proposalRationale = null;
    _parentStrategyRef = null;
    _proposalEvidenceRefs = const <String>[];
    _reviewId = null;
    _reviewState = null;
    _reviewSummary = null;
    _reviewConclusion = null;
    _reviewEvidenceRefs = const <String>[];
    notifyListeners();
  }

  ActorRef _agentFor(EntityId? sessionId) => ActorRef(
        actorId: _agentId,
        actorType: ActorType.agent,
        authoritySource: 'offline_bundle',
        sessionOrRunId: sessionId?.value,
        onBehalfOf: _user.actorId,
        capabilityRefs: const <String>[
          'context.query',
          'object.get',
          'proposal.submit',
          'review.submit',
        ],
      );

  String _correlation(String operation) =>
      'mobile-$operation-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _run(
    Future<String> Function(bool Function() isCurrent) operation,
  ) async {
    if (_disposed || _status == StrategyUiStatus.running) return;
    final epoch = _lifecycleEpoch;
    bool isCurrent() => !_disposed && epoch == _lifecycleEpoch;
    _status = StrategyUiStatus.running;
    _errorCode = null;
    notifyListeners();
    try {
      if (!isCurrent()) return;
      await operation(isCurrent);
      if (!isCurrent()) return;
      _status = StrategyUiStatus.ready;
    } on StrategySessionRestoreFailure catch (error) {
      if (!isCurrent()) return;
      _status = StrategyUiStatus.failed;
      _errorCode = error.code;
    } on AgentProtocolException catch (error) {
      if (!isCurrent()) return;
      _status = StrategyUiStatus.failed;
      _errorCode = error.code;
    } on FeedbackUseCaseFailure catch (error) {
      if (!isCurrent()) return;
      _status = StrategyUiStatus.failed;
      _errorCode = error.code;
    } on StrategyLoopFailure catch (error) {
      if (!isCurrent()) return;
      _status = StrategyUiStatus.failed;
      _errorCode = error.code;
    } on Object {
      if (!isCurrent()) return;
      _status = StrategyUiStatus.failed;
      _errorCode = 'strategy.unexpected_failure';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycleEpoch += 1;
    super.dispose();
  }

  void _fail(String code) {
    if (_disposed) return;
    _status = StrategyUiStatus.failed;
    _errorCode = code;
    notifyListeners();
  }
}
