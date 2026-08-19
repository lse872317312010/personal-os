import 'package:personal_os_domain/domain.dart';

import 'consent.dart';
import 'risk.dart';

enum ProtectedOperation { grantConsent, acceptReview }

/// Operations that establish user authority can never be delegated to an
/// agent, connector, importer, or system actor.
PolicyDecision authorizeProtectedOperation({
  required ActorRef actor,
  required ProtectedOperation operation,
}) {
  if (actor.actorType != ActorType.user) {
    return PolicyDecision.denied(
      operation == ProtectedOperation.grantConsent
          ? PolicyReason.consentGrantRequiresUser
          : PolicyReason.reviewAcceptanceRequiresUser,
    );
  }
  return PolicyDecision.allowed();
}

PolicyDecision authorizeWithConsent({
  required ActorRef actor,
  required ConsentGrant? consent,
  required ConsentRequest request,
  required DateTime evaluatedAt,
}) {
  if (actor.actorType == ActorType.user) return PolicyDecision.allowed();
  if (actor.onBehalfOf == null || actor.onBehalfOf != request.subjectId) {
    return PolicyDecision.denied(PolicyReason.actorSubjectMismatch);
  }
  final consentDecision = evaluateConsent(
    consent: consent,
    request: request,
    evaluatedAt: evaluatedAt,
  );
  if (!consentDecision.isAllowed) return consentDecision;
  if (!actor.capabilityRefs.contains(consent!.consentId)) {
    return PolicyDecision.denied(PolicyReason.capabilityReferenceMissing);
  }
  return PolicyDecision.allowed();
}

