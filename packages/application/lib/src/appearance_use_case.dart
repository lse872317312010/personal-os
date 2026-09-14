import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'appearance_commands.dart';
import 'application_ports.dart';

abstract final class AppearanceFailureCode {
  static const policyDenied = 'policy_denied';
  static const emptyAnalysis = 'empty_analysis';
  static const invalidAnalysis = 'invalid_analysis';
  static const analysisFailed = 'analysis_failed';
}

final class AppearanceUseCaseFailure implements Exception {
  const AppearanceUseCaseFailure(this.code, [this.detail]);

  final String code;
  final String? detail;

  @override
  String toString() =>
      'AppearanceUseCaseFailure($code${detail == null ? '' : ': $detail'})';
}

final class AppearanceLoopResult {
  const AppearanceLoopResult({
    required this.claimIds,
    required this.goalId,
    required this.planId,
    required this.taskIds,
    required this.eventIds,
  });

  final List<String> claimIds;
  final String goalId;
  final String planId;
  final List<String> taskIds;
  final List<String> eventIds;
}

/// Minimal appearance loop: analyze evidence, record proposed claims, establish
/// a goal and draft plan, then create executable tasks in one atomic append.
final class AnalyzeAppearanceUseCase {
  const AnalyzeAppearanceUseCase({
    required EventStore eventStore,
    required AppearanceAnalysisGateway modelGateway,
    required AppearancePolicyPort policy,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _modelGateway = modelGateway,
        _policy = policy,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final AppearanceAnalysisGateway _modelGateway;
  final AppearancePolicyPort _policy;
  final IdGenerator _ids;
  final Clock _clock;

  Future<AppearanceLoopResult> execute(AnalyzeAppearanceCommand command) async {
    const sensitivity = Sensitivity.d3;
    final verdict = await _policy.authorizeAnalysis(
      actor: command.actor,
      profileId: command.profileId,
      consentRefs: command.consentRefs,
      sensitivity: sensitivity,
      processingBoundary: command.processingBoundary,
    );
    if (!verdict.allowed) {
      throw AppearanceUseCaseFailure(
        AppearanceFailureCode.policyDenied,
        verdict.reasonCode,
      );
    }

    late final AppearanceAnalysisResult analysis;
    try {
      analysis = await _modelGateway.analyze(
        AppearanceAnalysisInput(
          imageRef: command.imageRef,
          observationContext: command.observationContext,
          locale: command.locale,
          promptVersion: command.promptVersion,
          processingBoundary: command.processingBoundary,
        ),
      );
    } on AppearanceModelGatewayFailure catch (error) {
      // The gateway API admits only enumerated redacted wire codes. Preserve
      // those actionable codes without exposing adapter/provider diagnostics.
      throw AppearanceUseCaseFailure(error.code);
    } catch (_) {
      // Unknown adapter failures are never allowed to expose paths, URIs,
      // credentials, provider messages, or raw response details.
      throw const AppearanceUseCaseFailure(
        AppearanceFailureCode.analysisFailed,
      );
    }
    if (analysis.findings.isEmpty || analysis.actions.isEmpty) {
      throw const AppearanceUseCaseFailure(AppearanceFailureCode.emptyAnalysis);
    }
    if (analysis.promptVersion != command.promptVersion) {
      throw const AppearanceUseCaseFailure(
        AppearanceFailureCode.invalidAnalysis,
      );
    }

    final now = _clock.now().toUtc();
    final profileRef = ObjectRef(type: 'profile', id: command.profileId);
    final goalId = _ids.nextId('goal');
    final planId = _ids.nextId('plan');
    final claimIds = <String>[];
    final taskIds = <String>[];
    final events = <EventEnvelope>[];

    EventEnvelope event({
      required String type,
      required ObjectRef subject,
      required Map<String, Object?> payload,
      Iterable<ObjectRef> sourceRefs = const <ObjectRef>[],
    }) =>
        EventEnvelope(
          eventId: _ids.nextId('event'),
          eventType: type,
          eventVersion: 1,
          occurredAt: now,
          recordedAt: now,
          actor: command.actor,
          correlationId: command.correlationId,
          subjectRefs: <ObjectRef>[subject, profileRef],
          sourceRefs: sourceRefs,
          consentRefs: command.consentRefs,
          sensitivity: sensitivity,
          payload: payload,
        );

    for (final finding in analysis.findings) {
      final claimId = _ids.nextId('claim');
      claimIds.add(claimId);
      events.add(event(
        type: EventTypes.claimProposed,
        subject: ObjectRef(type: 'claim', id: EntityId(claimId)),
        payload: <String, Object?>{
          'expected_revision': 0,
          'dimension': finding.dimension,
          'statement': finding.statement,
          'confidence': finding.confidence,
          'finding_kind': finding.kind.name,
          'evidence_blob_ref': command.imageRef,
          'model_trace_ref': analysis.modelTraceRef,
          'model_id': analysis.modelId,
          'prompt_version': analysis.promptVersion,
          'input_summary_ref': analysis.inputSummaryRef,
          'processing_boundary': command.processingBoundary.name,
        },
      ));
    }

    events.add(event(
      type: EventTypes.goalCreated,
      subject: ObjectRef(type: 'goal', id: EntityId(goalId)),
      payload: <String, Object?>{
        'expected_revision': 0,
        'title': '改善外貌呈现',
        'claim_refs': claimIds,
      },
    ));
    events.add(event(
      type: EventTypes.planDrafted,
      subject: ObjectRef(type: 'plan', id: EntityId(planId)),
      payload: <String, Object?>{
        'expected_revision': 0,
        'goal_ref': goalId,
        'title': '外貌改善行动计划',
        'risk_codes': analysis.risks.map((risk) => risk.code).toList(),
        'human_confirmation_codes': analysis.humanConfirmations
            .map((confirmation) => confirmation.code)
            .toList(),
      },
    ));

    for (final action in analysis.actions) {
      final taskId = _ids.nextId('task');
      taskIds.add(taskId);
      events.add(event(
        type: EventTypes.taskPlanned,
        subject: ObjectRef(type: 'task', id: EntityId(taskId)),
        payload: <String, Object?>{
          'expected_revision': 0,
          'plan_ref': planId,
          'title': action.title,
          'rationale': action.rationale,
          'day_offset': action.dayOffset,
          'requires_human_confirmation': action.requiresHumanConfirmation,
        },
      ));
    }

    try {
      // Keep the complete analysis loop atomic and redact adapter diagnostics.
      await _eventStore.appendAll(events);
    } catch (_) {
      throw const AppearanceUseCaseFailure(
        AppearanceFailureCode.analysisFailed,
      );
    }
    return AppearanceLoopResult(
      claimIds: List<String>.unmodifiable(claimIds),
      goalId: goalId,
      planId: planId,
      taskIds: List<String>.unmodifiable(taskIds),
      eventIds: List<String>.unmodifiable(events.map((e) => e.eventId)),
    );
  }
}
