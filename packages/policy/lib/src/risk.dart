enum RiskLevel { r0, r1, r2, r3, r4 }

enum PolicyOutcome { allow, draftOnly, requireUserConfirmation, deny }

/// Stable, content-free codes suitable for audit records and contract tests.
abstract final class PolicyReason {
  static const allowed = 'POLICY_ALLOWED';
  static const d4ProcessingForbidden = 'D4_PROCESSING_FORBIDDEN';
  static const d4PersistenceForbidden = 'D4_PERSISTENCE_FORBIDDEN';
  static const consentMissing = 'CONSENT_MISSING';
  static const consentNotYetValid = 'CONSENT_NOT_YET_VALID';
  static const consentExpired = 'CONSENT_EXPIRED';
  static const consentInactive = 'CONSENT_INACTIVE';
  static const consentRevisionMismatch = 'CONSENT_REVISION_MISMATCH';
  static const consentSubjectMismatch = 'CONSENT_SUBJECT_MISMATCH';
  static const consentActorMismatch = 'CONSENT_ACTOR_MISMATCH';
  static const consentPurposeMismatch = 'CONSENT_PURPOSE_MISMATCH';
  static const consentResourceMismatch = 'CONSENT_RESOURCE_MISMATCH';
  static const consentActionMismatch = 'CONSENT_ACTION_MISMATCH';
  static const consentSensitivityExceeded = 'CONSENT_SENSITIVITY_EXCEEDED';
  static const actorSubjectMismatch = 'ACTOR_SUBJECT_MISMATCH';
  static const capabilityReferenceMissing = 'CAPABILITY_REFERENCE_MISSING';
  static const consentGrantRequiresUser = 'CONSENT_GRANT_REQUIRES_USER';
  static const reviewAcceptanceRequiresUser = 'REVIEW_ACCEPTANCE_REQUIRES_USER';
  static const r2ConfirmationRequired = 'R2_CONFIRMATION_REQUIRED';
  static const r3DraftOnly = 'R3_DRAFT_ONLY';
  static const r3MvpExecutionForbidden = 'R3_MVP_EXECUTION_FORBIDDEN';
  static const r4Forbidden = 'R4_FORBIDDEN';
  static const declassificationReviewRequired =
      'DECLASSIFICATION_REVIEW_REQUIRED';
}

final class PolicyDecision {
  const PolicyDecision(this.outcome, this.reasonCode);

  factory PolicyDecision.allowed() =>
      const PolicyDecision(PolicyOutcome.allow, PolicyReason.allowed);
  factory PolicyDecision.denied(String reason) =>
      PolicyDecision(PolicyOutcome.deny, reason);

  final PolicyOutcome outcome;
  final String reasonCode;

  bool get isAllowed => outcome == PolicyOutcome.allow;
}

PolicyDecision evaluateRisk({
  required RiskLevel risk,
  bool executeExternalAction = false,
  bool userConfirmed = false,
}) {
  switch (risk) {
    case RiskLevel.r0:
    case RiskLevel.r1:
      return PolicyDecision.allowed();
    case RiskLevel.r2:
      return userConfirmed
          ? PolicyDecision.allowed()
          : const PolicyDecision(
              PolicyOutcome.requireUserConfirmation,
              PolicyReason.r2ConfirmationRequired,
            );
    case RiskLevel.r3:
      // AUTHORIZATION.md freezes all MVP external execution. Confirmation is
      // captured only for a future capability and cannot authorize it today.
      return PolicyDecision(
        PolicyOutcome.draftOnly,
        executeExternalAction
            ? PolicyReason.r3MvpExecutionForbidden
            : PolicyReason.r3DraftOnly,
      );
    case RiskLevel.r4:
      return PolicyDecision.denied(PolicyReason.r4Forbidden);
  }
}
