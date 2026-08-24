import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import '../composition/native_sqlcipher_session_coordinator.dart';
import '../navigation/app_destination.dart';

enum SubmissionStatus { idle, running, succeeded, failed }

/// UI-safe metadata for an observation. Blob references and event payloads
/// deliberately never leave the application boundary.
final class ObservationMetadata {
  const ObservationMetadata({
    required this.occurredAt,
    required this.mediaType,
  });

  final DateTime occurredAt;
  final String mediaType;
}

final class AppController extends ChangeNotifier {
  AppController({
    required AnalyzeAppearanceUseCase analyzeAppearance,
    required ActionFeedbackUseCase actionFeedback,
    required EntityId profileId,
    required ActorRef actor,
    AppearanceSessionQueryHandler? sessionQuery,
    ConsentLifecycleUseCase? consentLifecycle,
    RecordObservationUseCase? recordObservation,
    VaultSession? vaultSession,
    SecureVaultPort? secureVault,
    SecureSessionCoordinator? sessionCoordinator,
    ControlledSourcePort? sourcePort,
    IngestAppearanceFromSourceUseCase? ingestAppearanceFromSource,
  })  : _analyzeAppearance = analyzeAppearance,
        _actionFeedback = actionFeedback,
        _profileId = profileId,
        _actor = actor,
        _sessionQuery = sessionQuery,
        _consentLifecycle = consentLifecycle,
        _recordObservation = recordObservation,
        _vaultSession = vaultSession,
        _secureVault = secureVault,
        _sessionCoordinator = sessionCoordinator,
        _sourcePort = sourcePort,
        _ingestAppearanceFromSource = ingestAppearanceFromSource {
    if (_sessionCoordinator != null) {
      _sessionCoordinator!.onSessionInvalidated = _handleSessionInvalidated;
    }
    if (actor.actorType != ActorType.user) {
      throw ArgumentError.value(actor.actorType, 'actor', 'must be user');
    }
    if (secureVault != null && sessionCoordinator != null) {
      throw ArgumentError(
        'secureVault and sessionCoordinator are mutually exclusive',
      );
    }
    if (vaultSession == null &&
        (secureVault != null || sessionCoordinator != null)) {
      throw ArgumentError(
        'vaultSession must be provided with secure session access',
      );
    }
  }

  final AnalyzeAppearanceUseCase _analyzeAppearance;
  final ActionFeedbackUseCase _actionFeedback;
  final EntityId _profileId;
  final ActorRef _actor;
  final AppearanceSessionQueryHandler? _sessionQuery;
  final ConsentLifecycleUseCase? _consentLifecycle;
  final RecordObservationUseCase? _recordObservation;
  final VaultSession? _vaultSession;
  final SecureVaultPort? _secureVault;
  final SecureSessionCoordinator? _sessionCoordinator;
  final ControlledSourcePort? _sourcePort;
  final IngestAppearanceFromSourceUseCase? _ingestAppearanceFromSource;

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
  List<ObservationMetadata> _observations = const <ObservationMetadata>[];
  OpaqueVaultSession? _opaqueVaultSession;
  bool _bootstrapped = false;
  bool _bootstrapping = false;
  int _consentStateRevision = 0;
  int _consentRevision = 0;
  int _lifecycleEpoch = 0;

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
  List<ObservationMetadata> get observations => _observations;
  int get observationCount => _observations.length;
  bool get sourceAvailable =>
      _sourcePort != null && _ingestAppearanceFromSource != null;
  ObservationMetadata? get latestObservation =>
      _observations.isEmpty ? null : _observations.first;
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
    if (_vaultSession != null &&
        (_secureVault != null || _sessionCoordinator != null)) {
      unawaited(_unlockSecureVault());
      return;
    }
    _vaultUnlocked = true;
    notifyListeners();
    if (_sessionQuery != null) unawaited(bootstrap());
  }

  Future<void> _unlockSecureVault() async {
    final epoch = ++_lifecycleEpoch;
    final vaultSession = _vaultSession!;
    final coordinator = _sessionCoordinator;
    final secureVault = _secureVault;
    try {
      await vaultSession.unlock(reason: 'Open Personal OS vault');
      final session = coordinator != null
          ? await coordinator.open(grant: vaultSession.requireGrant())
          : await secureVault!.open(grant: vaultSession.requireGrant());
      if (!session.isActive) {
        throw const SecurityException(SecurityErrorCode.providerUnavailable);
      }
      if (epoch != _lifecycleEpoch) {
        if (coordinator != null) {
          await coordinator.close(session);
        } else {
          await secureVault!.close(session);
        }
        return;
      }
      _opaqueVaultSession = session;
      _vaultUnlocked = true;
      _errorCode = null;
      if (_sessionQuery != null) unawaited(bootstrap());
    } on SecurityException catch (error) {
      if (epoch != _lifecycleEpoch) return;
      _vaultUnlocked = false;
      _errorCode = error.code.wireValue;
      await vaultSession.lock();
    } on Object {
      if (epoch != _lifecycleEpoch) return;
      _vaultUnlocked = false;
      _errorCode = SecurityErrorCode.providerUnavailable.wireValue;
      await vaultSession.lock();
    }
    notifyListeners();
  }

  /// Rebuilds the controller's volatile view from persisted profile events.
  ///
  /// Consent is intentionally not inferred from the appearance session. Until
  /// the consent lifecycle is event-backed, a recreated controller remains
  /// denied by default.
  Future<void> bootstrap() async {
    final query = _sessionQuery;
    if (_bootstrapped || _bootstrapping || query == null || !_vaultUnlocked) {
      return;
    }
    _bootstrapping = true;
    final epoch = _lifecycleEpoch;
    try {
      final view = await query.execute(
        GetAppearanceHistoryQuery(profileId: _profileId),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _applySession(view);
      _bootstrapped = true;
    } on Object {
      if (epoch == _lifecycleEpoch && _vaultUnlocked) {
        _errorCode = 'persistence.read_failed';
      }
    } finally {
      _bootstrapping = false;
    }
    if (epoch == _lifecycleEpoch && _vaultUnlocked) {
      notifyListeners();
    }
  }

  void _applySession(AppearanceSessionView view) {
    final eventTimes = <String, DateTime>{
      for (final event in view.events) event.eventId: event.occurredAt,
    };
    final observations = <ObservationMetadata>[];
    for (final observation in view.observations) {
      final occurredAt = eventTimes[observation.eventId];
      if (occurredAt != null) {
        observations.add(
          ObservationMetadata(
            occurredAt: occurredAt,
            mediaType: observation.mediaType,
          ),
        );
      }
    }
    observations.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    _observations = List<ObservationMetadata>.unmodifiable(observations);
    _taskStates
      ..clear()
      ..addEntries(
        view.tasks.map(
          (task) => MapEntry<String, String>(task.id, task.state),
        ),
      );
    _planStarted = view.plan != null;
    if (view.hasAnalysis && view.goal != null && view.plan != null) {
      _result = AppearanceLoopResult(
        claimIds: view.claims.map((claim) => claim.id).toList(growable: false),
        goalId: view.goal!.id,
        planId: view.plan!.id,
        taskIds: view.tasks.map((task) => task.id).toList(growable: false),
        eventIds:
            view.events.map((event) => event.eventId).toList(growable: false),
      );
    }
    final review = view.review;
    _reviewId = review?.id;
    _reviewState = review?.state;
    final consent = view.consent;
    _consentGranted = consent?.state == ConsentState.granted.name;
    _consentStateRevision = consent?.stateRevision ?? 0;
    _consentRevision = consent?.consentRevision ?? 0;
  }

  void _handleSessionInvalidated(SecurityException error) {
    lockVault(errorCode: error.code.wireValue);
  }

  void lockVault({String? errorCode}) {
    _lifecycleEpoch++;
    final opaqueSession = _opaqueVaultSession;
    _opaqueVaultSession = null;
    if (opaqueSession != null &&
        (_secureVault != null || _sessionCoordinator != null) &&
        _vaultSession != null) {
      unawaited(_closeSecureVault(opaqueSession));
    }
    _vaultUnlocked = false;
    _destination = AppDestination.home;
    // Do not retain decrypted session state while the vault is locked. A
    // subsequent unlock must rebuild it from the event-backed read model.
    _result = null;
    _taskStates.clear();
    _planStarted = false;
    _reviewId = null;
    _reviewState = null;
    _observations = const <ObservationMetadata>[];
    _consentGranted = false;
    _consentStateRevision = 0;
    _consentRevision = 0;
    _bootstrapped = false;
    _bootstrapping = false;
    _submission = SubmissionStatus.idle;
    _errorCode = errorCode;
    _feedbackSubmission = SubmissionStatus.idle;
    _feedbackCode = null;
    notifyListeners();
  }

  Future<void> _closeSecureVault(OpaqueVaultSession session) async {
    final coordinator = _sessionCoordinator;
    final secureVault = _secureVault;
    try {
      if (coordinator != null) {
        await coordinator.close(session);
      } else {
        await secureVault!.close(session);
      }
    } catch (_) {
      // The capability was already removed locally; never expose a close
      // failure or retain a native session after the UI is locked.
    } finally {
      await _vaultSession!.lock();
    }
  }

  Future<void> setConsent(bool granted) {
    if (_consentLifecycle != null) {
      return _setPersistedConsent(granted);
    }
    _consentGranted = granted;
    notifyListeners();
    return Future<void>.value();
  }

  Future<void> _setPersistedConsent(bool granted) async {
    if (granted == _consentGranted) return;
    final epoch = _lifecycleEpoch;
    try {
      if (granted) {
        final consentRevision =
            _consentRevision == 0 ? 1 : _consentRevision + 1;
        final result = await _consentLifecycle!.grant(
          GrantConsentCommand(
            profileId: _profileId,
            consentId: 'local-appearance-consent',
            consentRevision: consentRevision,
            expectedConsentStateRevision: _consentStateRevision,
            actor: _actor,
            correlationId: _correlation('grant-consent'),
          ),
        );
        if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
        _consentStateRevision = result.stateRevision;
        _consentRevision = consentRevision;
        _consentGranted = true;
      } else if (_consentStateRevision > 0) {
        final result = await _consentLifecycle!.revoke(
          RevokeConsentCommand(
            profileId: _profileId,
            consentId: 'local-appearance-consent',
            consentRevision: _consentRevision,
            expectedConsentStateRevision: _consentStateRevision,
            actor: _actor,
            correlationId: _correlation('revoke-consent'),
          ),
        );
        if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
        _consentStateRevision = result.stateRevision;
        _consentGranted = false;
      }
    } on Object {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _errorCode = 'consent_persistence_failed';
      _consentGranted = false;
    }
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
    // A new secure attempt invalidates any prior in-memory result. Keeping it
    // would let a failed fail-closed analysis render as the previous success.
    _result = null;
    final epoch = _lifecycleEpoch;
    final correlationId = _correlation('appearance');
    notifyListeners();
    try {
      if (_recordObservation != null) {
        await _recordObservation.execute(
          RecordObservationCommand(
            profileId: _profileId,
            blobRef: BlobRef(blobReference),
            mediaType: 'image/*',
            observationContext: observationContext,
            consentRef: ObjectRef(
              type: 'consent',
              id: EntityId('local-appearance-consent'),
              revision: Revision(_activeConsentRevision),
            ),
            actor: _actor,
            correlationId: correlationId,
          ),
        );
        if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
        _observations = List<ObservationMetadata>.unmodifiable(
          <ObservationMetadata>[
            ObservationMetadata(
              occurredAt: DateTime.now().toUtc(),
              mediaType: 'image/*',
            ),
            ..._observations,
          ],
        );
        notifyListeners();
      }
      final result = await _analyzeAppearance.execute(
        AnalyzeAppearanceCommand(
          profileId: _profileId,
          imageRef: blobReference,
          actor: _actor,
          correlationId: correlationId,
          observationContext: observationContext,
          consentRefs: <ObjectRef>[
            ObjectRef(
              type: 'consent',
              id: EntityId('local-appearance-consent'),
              revision: Revision(_activeConsentRevision),
            ),
          ],
        ),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _result = result;
      _submission = SubmissionStatus.succeeded;
      _destination = AppDestination.claims;
    } on ObservationUseCaseFailure catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code;
    } on AppearanceUseCaseFailure catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code;
    } on SecurityException catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code.wireValue;
    } on Object {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = 'unexpected_failure';
    }
    notifyListeners();
  }

  Future<void> pickPhotoAndAnalyze({
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
    final source = _sourcePort;
    final ingest = _ingestAppearanceFromSource;
    if (source == null || ingest == null) {
      _fail('source_unavailable');
      return;
    }
    if (observationContext.trim().isEmpty) {
      _fail(ObservationFailureCode.invalidContext);
      return;
    }

    _submission = SubmissionStatus.running;
    _errorCode = null;
    // See analyzeBlobReference: a failed secure attempt must not retain the
    // claims from an earlier successful attempt.
    _result = null;
    final epoch = _lifecycleEpoch;
    OpaqueSourceToken? token;
    notifyListeners();
    try {
      token = await source.pickPhoto();
      final consentRef = ObjectRef(
        type: 'consent',
        id: EntityId('local-appearance-consent'),
        revision: Revision(_activeConsentRevision),
      );
      final result = await ingest.execute(
        IngestAppearanceFromSourceCommand(
          source: token,
          mediaType: 'image/*',
          access: BlobAccessContext(
            actorRef: _actor.actorId,
            purpose: 'appearance-analysis',
            consentRef: 'consent:${consentRef.id.value}',
          ),
          profileId: _profileId,
          observationContext: observationContext,
          consentRef: consentRef,
          actor: _actor,
          correlationId: _correlation('source-appearance'),
        ),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _result = result.analysis;
      _submission = SubmissionStatus.succeeded;
      _destination = AppDestination.claims;
    } on ObservationUseCaseFailure catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code;
    } on SourceBlobIngestionException catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code;
    } on AppearanceUseCaseFailure catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code;
    } on SecurityException catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = error.code.wireValue;
    } on ControlledSourceException catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = switch (error.code) {
        ControlledSourceFailureCode.cancelled => 'source_unavailable',
        ControlledSourceFailureCode.denied => 'source_denied',
        _ => 'source_unavailable',
      };
    } on Object {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _submission = SubmissionStatus.failed;
      _errorCode = 'source_unavailable';
    } finally {
      if (token != null) {
        try {
          await source.release(token);
        } catch (_) {
          // Native expiry and one-shot consume make release best effort.
        }
      }
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
    final epoch = _lifecycleEpoch;
    await _runFeedback(() async {
      await _actionFeedback.completeTask(
        CompleteTaskCommand(
          taskId: EntityId(taskId),
          profileId: _profileId,
          expectedTaskRevision: 1,
          actor: _actor,
          correlationId: _correlation('complete-task'),
          executionSummary: '用户在移动端确认完成',
          sensitivity: Sensitivity.d2,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return 'stale';
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
    final epoch = _lifecycleEpoch;
    await _runFeedback(() async {
      await _actionFeedback.skipTask(
        SkipTaskCommand(
          taskId: EntityId(taskId),
          profileId: _profileId,
          expectedTaskRevision: 1,
          actor: _actor,
          correlationId: _correlation('skip-task'),
          reason: '用户在移动端选择跳过',
          sensitivity: Sensitivity.d2,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return 'stale';
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
    final epoch = _lifecycleEpoch;
    await _runFeedback(() async {
      final created = await _actionFeedback.createReview(
        CreateReviewCommand(
          profileId: _profileId,
          actor: _actor,
          correlationId: _correlation('create-review'),
          sourceRefs:
              taskIds.map((id) => ObjectRef(type: 'task', id: EntityId(id))),
          sensitivity: Sensitivity.d3,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return 'stale';
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
    final epoch = _lifecycleEpoch;
    await _runFeedback(() async {
      await _actionFeedback.decideReview(
        DecideReviewCommand(
          reviewId: EntityId(id),
          profileId: _profileId,
          expectedReviewRevision: 1,
          actor: _actor,
          correlationId: _correlation('decide-review'),
          decision: decision,
          sensitivity: Sensitivity.d3,
          consentRefs: _appearanceConsentRefs,
        ),
      );
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return 'stale';
      _reviewState =
          decision == ReviewDecision.accept ? 'accepted' : 'rejected';
      return decision == ReviewDecision.accept
          ? 'review_accepted'
          : 'review_rejected';
    });
  }

  List<ObjectRef> get _appearanceConsentRefs => <ObjectRef>[
        ObjectRef(
          type: 'consent',
          id: EntityId('local-appearance-consent'),
          revision: Revision(_activeConsentRevision),
        ),
      ];

  int get _activeConsentRevision =>
      _consentRevision == 0 ? 1 : _consentRevision;

  String _correlation(String operation) =>
      'mobile-$operation-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _runFeedback(Future<String> Function() operation) async {
    if (!_vaultUnlocked) {
      _feedbackFail('vault_locked');
      return;
    }
    _feedbackSubmission = SubmissionStatus.running;
    _feedbackCode = null;
    final epoch = _lifecycleEpoch;
    notifyListeners();
    try {
      final code = await operation();
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _feedbackCode = code;
      _feedbackSubmission = SubmissionStatus.succeeded;
    } on FeedbackUseCaseFailure catch (error) {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
      _feedbackSubmission = SubmissionStatus.failed;
      _feedbackCode = error.code;
    } on Object {
      if (epoch != _lifecycleEpoch || !_vaultUnlocked) return;
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
