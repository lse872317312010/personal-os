import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_policy/policy.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 20, 12);

  ConsentGrant grant({
    ConsentStatus status = ConsentStatus.active,
    DateTime? from,
    DateTime? until,
  }) =>
      ConsentGrant(
        consentId: 'consent-1',
        revision: 2,
        subjectId: 'user-1',
        authorizedActorId: 'agent-1',
        purposes: {'appearance_review'},
        resources: {'portrait'},
        actions: {'derive'},
        maximumSensitivity: Sensitivity.d3,
        validFrom: from ?? now.subtract(const Duration(hours: 1)),
        validUntil: until ?? now.add(const Duration(hours: 1)),
        status: status,
      );

  ConsentRequest request({
    String purpose = 'appearance_review',
    Sensitivity sensitivity = Sensitivity.d3,
    int revision = 2,
  }) =>
      ConsentRequest(
        consentId: 'consent-1',
        consentRevision: revision,
        subjectId: 'user-1',
        actorId: 'agent-1',
        purpose: purpose,
        resource: 'portrait',
        action: 'derive',
        sensitivity: sensitivity,
      );

  test('D4 can never be persisted or derived', () {
    expect(authorizePersistence(Sensitivity.d4).reasonCode,
        PolicyReason.d4PersistenceForbidden);
    final derived = deriveSensitivity(
      inputs: [Sensitivity.d1, Sensitivity.d4],
      declaredMinimum: Sensitivity.d0,
    );
    expect(derived.policy.outcome, PolicyOutcome.deny);
    expect(derived.policy.reasonCode, PolicyReason.d4ProcessingForbidden);
  });

  test('derived sensitivity inherits the maximum input or declared floor', () {
    expect(
      deriveSensitivity(
        inputs: [Sensitivity.d1, Sensitivity.d3],
        declaredMinimum: Sensitivity.d2,
      ).sensitivity,
      Sensitivity.d3,
    );
    expect(
      deriveSensitivity(
        inputs: [Sensitivity.d0],
        declaredMinimum: Sensitivity.d2,
      ).sensitivity,
      Sensitivity.d2,
    );
  });

  test('consent succeeds only on exact active scoped grant', () {
    expect(
      evaluateConsent(consent: grant(), request: request(), evaluatedAt: now)
          .isAllowed,
      isTrue,
    );
    expect(
      evaluateConsent(consent: null, request: request(), evaluatedAt: now)
          .reasonCode,
      PolicyReason.consentMissing,
    );
    expect(
      evaluateConsent(
        consent: grant(status: ConsentStatus.revoked),
        request: request(),
        evaluatedAt: now,
      ).reasonCode,
      PolicyReason.consentInactive,
    );
    expect(
      evaluateConsent(
        consent: grant(),
        request: request(purpose: 'advertising'),
        evaluatedAt: now,
      ).reasonCode,
      PolicyReason.consentPurposeMismatch,
    );
    expect(
      evaluateConsent(
        consent: grant(),
        request: request(revision: 1),
        evaluatedAt: now,
      ).reasonCode,
      PolicyReason.consentRevisionMismatch,
    );
    expect(
      evaluateConsent(
        consent: grant(until: now),
        request: request(),
        evaluatedAt: now,
      ).reasonCode,
      PolicyReason.consentExpired,
    );
  });

  test('non-user actors cannot grant consent or accept review', () {
    final agent = ActorRef(
      actorId: 'agent-1',
      actorType: ActorType.agent,
      authoritySource: 'consent',
      onBehalfOf: 'user-1',
    );
    expect(
      authorizeProtectedOperation(
        actor: agent,
        operation: ProtectedOperation.grantConsent,
      ).reasonCode,
      PolicyReason.consentGrantRequiresUser,
    );
    expect(
      authorizeProtectedOperation(
        actor: agent,
        operation: ProtectedOperation.acceptReview,
      ).reasonCode,
      PolicyReason.reviewAcceptanceRequiresUser,
    );
  });

  test('MVP R3 is always draft-only, even with confirmation; R4 denies', () {
    expect(evaluateRisk(risk: RiskLevel.r3).outcome, PolicyOutcome.draftOnly);
    final unconfirmedExecution =
        evaluateRisk(risk: RiskLevel.r3, executeExternalAction: true);
    expect(unconfirmedExecution.outcome, PolicyOutcome.draftOnly);
    expect(
      unconfirmedExecution.reasonCode,
      PolicyReason.r3MvpExecutionForbidden,
    );
    expect(
      evaluateRisk(
        risk: RiskLevel.r3,
        executeExternalAction: true,
        userConfirmed: true,
      ).outcome,
      PolicyOutcome.draftOnly,
    );
    expect(evaluateRisk(risk: RiskLevel.r4).outcome, PolicyOutcome.deny);
  });
}
