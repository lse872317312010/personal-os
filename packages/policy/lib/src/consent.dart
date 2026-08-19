import 'package:personal_os_domain/domain.dart';

import 'risk.dart';

enum ConsentStatus { active, revoked, superseded }

final class ConsentGrant {
  ConsentGrant({
    required this.consentId,
    required this.revision,
    required this.subjectId,
    required this.authorizedActorId,
    required Set<String> purposes,
    required Set<String> resources,
    required Set<String> actions,
    required this.maximumSensitivity,
    required this.validFrom,
    required this.validUntil,
    required this.status,
  })  : purposes = Set<String>.unmodifiable(purposes),
        resources = Set<String>.unmodifiable(resources),
        actions = Set<String>.unmodifiable(actions);

  final String consentId;
  final int revision;
  final String subjectId;
  final String authorizedActorId;
  final Set<String> purposes;
  final Set<String> resources;
  final Set<String> actions;
  final Sensitivity maximumSensitivity;
  final DateTime validFrom;
  final DateTime validUntil;
  final ConsentStatus status;
}

final class ConsentRequest {
  const ConsentRequest({
    required this.consentId,
    required this.consentRevision,
    required this.subjectId,
    required this.actorId,
    required this.purpose,
    required this.resource,
    required this.action,
    required this.sensitivity,
  });

  final String consentId;
  final int consentRevision;
  final String subjectId;
  final String actorId;
  final String purpose;
  final String resource;
  final String action;
  final Sensitivity sensitivity;
}

PolicyDecision evaluateConsent({
  required ConsentGrant? consent,
  required ConsentRequest request,
  required DateTime evaluatedAt,
}) {
  if (request.sensitivity == Sensitivity.d4) {
    return PolicyDecision.denied(PolicyReason.d4ProcessingForbidden);
  }
  if (consent == null || consent.consentId != request.consentId) {
    return PolicyDecision.denied(PolicyReason.consentMissing);
  }
  if (consent.revision != request.consentRevision) {
    return PolicyDecision.denied(PolicyReason.consentRevisionMismatch);
  }
  if (consent.status != ConsentStatus.active) {
    return PolicyDecision.denied(PolicyReason.consentInactive);
  }
  if (evaluatedAt.isBefore(consent.validFrom)) {
    return PolicyDecision.denied(PolicyReason.consentNotYetValid);
  }
  if (!evaluatedAt.isBefore(consent.validUntil)) {
    return PolicyDecision.denied(PolicyReason.consentExpired);
  }
  if (consent.subjectId != request.subjectId) {
    return PolicyDecision.denied(PolicyReason.consentSubjectMismatch);
  }
  if (consent.authorizedActorId != request.actorId) {
    return PolicyDecision.denied(PolicyReason.consentActorMismatch);
  }
  if (!consent.purposes.contains(request.purpose)) {
    return PolicyDecision.denied(PolicyReason.consentPurposeMismatch);
  }
  if (!consent.resources.contains(request.resource)) {
    return PolicyDecision.denied(PolicyReason.consentResourceMismatch);
  }
  if (!consent.actions.contains(request.action)) {
    return PolicyDecision.denied(PolicyReason.consentActionMismatch);
  }
  if (request.sensitivity.index > consent.maximumSensitivity.index) {
    return PolicyDecision.denied(PolicyReason.consentSensitivityExceeded);
  }
  return PolicyDecision.allowed();
}

