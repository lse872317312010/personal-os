import 'package:flutter/foundation.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import '../navigation/app_destination.dart';

enum SubmissionStatus { idle, running, succeeded, failed }

final class AppController extends ChangeNotifier {
  AppController({
    required AnalyzeAppearanceUseCase analyzeAppearance,
    required ActionFeedbackUseCase actionFeedback,
    required EntityId profileId,
    required ActorRef actor,
  })  : _analyzeAppearance = analyzeAppearance,
        _actionFeedback = actionFeedback,
        _profileId = profileId,
        _actor = actor {
    if (actor.actorType != ActorType.user) {
      throw ArgumentError.value(actor.actorType, 'actor', 'must be user');
    }
  }

  final AnalyzeAppearanceUseCase _analyzeAppearance;
  final ActionFeedbackUseCase _actionFeedback;
  final EntityId _profileId;
  final ActorRef _actor;

  bool _vaultUnlocked = false;
  bool _consentGranted = false;
  AppDestination _destination = AppDestination.home;
  SubmissionStatus _submission = SubmissionStatus.idle;
  AppearanceLoopResult? _result;
  String? _errorCode;
  SubmissionStatus _feedbackSubmission = SubmissionStatus.idle;
  String? _feedbackCode;
  final Map<String, String> _taskStates = <String, String>{};
  bool _planStarted = false;
  String? _reviewId;
  String? _reviewState;

  bool get vaultUnlocked => _vaultUnlocked;
  bool get consentGranted => _consentGranted;
  AppDestination get destination => _destination;
  SubmissionStatus get submission => _submission;
  AppearanceLoopResult? get result => _result;
  String? get errorCode => _errorCode;
  SubmissionStatus get feedbackSubmission => _feedbackSubmission;
  String? get feedbackCode => _feedbackCode;
  String taskState(String taskId) => _taskStates[taskId] ?? 'planned';
  String? get reviewId => _reviewId;
  String? get reviewState => _reviewState;
  bool get planStarted => _planStarted;
  int get completedStep {
    if (_reviewState == 'accepted' || _reviewState == 'rejected') return 5;
    if (_reviewId != null ||
        _taskStates.values.any((state) => state != 'planned')) {
      return 4;
    }
    if (_planStarted) return 3;
    if (_result != null) return 2;
    return 0;
  }

  bool get hasFinishedTask => _taskStates.values
      .any((state) => state == 'completed' || state == 'skipped');

  void unlockVault() {
    _vaultUnlocked = true;
    notifyListeners();
  }

  void lockVault() {
    _vaultUnlocked = false;
    _destination = AppDestination.home;
    notifyListeners();
  }

  void setConsent(bool granted) {
    _consentGranted = granted;
    notifyListeners();
  }

  void navigate(AppDestination destination) {
    if (!_vaultUnlocked) return;
    _destination = destination;
    notifyListeners();
  }

  Future<void> analyzeBlobReference({
    required String blobReference,
    required String observationContext,
  }) async {
    if (!_vaultUnlocked) {
      _fail('vault_locked');
      return;
    }
    if (!_consentGranted) {
      _fail('consent_required');
      return;
    }
    if (!blobReference.startsWith('blob://')) {
      _fail('blob_reference_required');
      return;
    }

    _submission = SubmissionStatus.running;
    _errorCode = null;
    notifyListeners();
    try {
      _result = await _analyzeAppearance.execute(
        AnalyzeAppearanceCommand(
          profileId: _profileId,
          imageRef: blobReference,
          actor: _actor,
          correlationId: 'mobile-${DateTime.now().microsecondsSinceEpoch}',
          observationContext: observationContext,
          consentRefs: <ObjectRef>[
            ObjectRef(
              type: 'consent',
              id: EntityId('local-appearance-consent'),
              revision: Revision(1),
            ),
          ],
        ),
      );
      _submission = SubmissionStatus.succeeded;
      _destination = AppDestination.claims;
    } on AppearanceUseCaseFailure catch (error) {
      _submission = SubmissionStatus.failed;
      _errorCode = error.code;
    } on Object {
      _submission = SubmissionStatus.failed;
      _errorCode = 'unexpected_failure';
    }
    notifyListeners();
  }

  void continueFromClaims() {
    if (_result == null) return;
    navigate(AppDestination.plan);
  }

  void startPlan() {
    if (_result == null) return;
    _planStarted = true;
    navigate(AppDestination.tasks);
  }

  Future<void> completeTask(String taskId) async {
    if (!_planStarted) {
      _feedbackFail('plan_not_started');
      return;
    }
    await _runFeedback(() async {
      await _actionFeedback.completeTask(
        CompleteTaskCommand(
          taskId: EntityId(taskId),
          expectedTaskRevision: 1,
          actor: _actor,
          correlationId: _correlation('complete-task'),
          executionSummary: '用户在移动端确认完成',
          sensitivity: Sensitivity.d2,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      _taskStates[taskId] = 'completed';
      _destination = AppDestination.review;
      return 'task_completed';
    });
  }

  Future<void> skipTask(String taskId) async {
    if (!_planStarted) {
      _feedbackFail('plan_not_started');
      return;
    }
    await _runFeedback(() async {
      await _actionFeedback.skipTask(
        SkipTaskCommand(
          taskId: EntityId(taskId),
          expectedTaskRevision: 1,
          actor: _actor,
          correlationId: _correlation('skip-task'),
          reason: '用户在移动端选择跳过',
          sensitivity: Sensitivity.d2,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      _taskStates[taskId] = 'skipped';
      _destination = AppDestination.review;
      return 'task_skipped';
    });
  }

  Future<void> createReview() async {
    if (!hasFinishedTask) {
      _feedbackFail('task_feedback_required');
      return;
    }
    final taskIds = _result?.taskIds ?? const <String>[];
    if (taskIds.isEmpty) {
      _feedbackFail('review_sources_required');
      return;
    }
    await _runFeedback(() async {
      final created = await _actionFeedback.createReview(
        CreateReviewCommand(
          actor: _actor,
          correlationId: _correlation('create-review'),
          sourceRefs: taskIds
              .map((id) => ObjectRef(type: 'task', id: EntityId(id))),
          sensitivity: Sensitivity.d3,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      _reviewId = created.reviewId;
      _reviewState = 'draft';
      return 'review_created';
    });
  }

  Future<void> decideReview(ReviewDecision decision) async {
    final id = _reviewId;
    if (id == null) {
      _feedbackFail('review_required');
      return;
    }
    await _runFeedback(() async {
      await _actionFeedback.decideReview(
        DecideReviewCommand(
          reviewId: EntityId(id),
          expectedReviewRevision: 1,
          actor: _actor,
          correlationId: _correlation('decide-review'),
          decision: decision,
          sensitivity: Sensitivity.d3,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      _reviewState = decision == ReviewDecision.accept ? 'accepted' : 'rejected';
      return decision == ReviewDecision.accept
          ? 'review_accepted'
          : 'review_rejected';
    });
  }

  List<ObjectRef> get _appearanceConsentRefs => <ObjectRef>[
        ObjectRef(
          type: 'consent',
          id: EntityId('local-appearance-consent'),
          revision: Revision(1),
        ),
      ];

  String _correlation(String operation) =>
      'mobile-$operation-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _runFeedback(Future<String> Function() operation) async {
    if (!_vaultUnlocked) {
      _feedbackFail('vault_locked');
      return;
    }
    _feedbackSubmission = SubmissionStatus.running;
    _feedbackCode = null;
    notifyListeners();
    try {
      _feedbackCode = await operation();
      _feedbackSubmission = SubmissionStatus.succeeded;
    } on FeedbackUseCaseFailure catch (error) {
      _feedbackSubmission = SubmissionStatus.failed;
      _feedbackCode = error.code;
    } on Object {
      _feedbackSubmission = SubmissionStatus.failed;
      _feedbackCode = 'unexpected_failure';
    }
    notifyListeners();
  }

  void _feedbackFail(String code) {
    _feedbackSubmission = SubmissionStatus.failed;
    _feedbackCode = code;
    notifyListeners();
  }

  void _fail(String code) {
    _submission = SubmissionStatus.failed;
    _errorCode = code;
    notifyListeners();
  }
}
