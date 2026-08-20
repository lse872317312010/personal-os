import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_policy/policy.dart';

/// Exact-revision consent lookup required by the appearance policy adapter.
///
/// Implementations must not fall back to a latest or mutable revision.
abstract interface class ConsentRevisionRepository {
  Future<ConsentGrant?> findRevision({
    required String consentId,
    required int revision,
  });
}

/// Time source used for consent validity checks.
abstract interface class PolicyClock {
  DateTime now();
}

abstract final class AppearancePolicyReason {
  static const invalidConsentReference = 'INVALID_CONSENT_REFERENCE';
  static const invalidSensitivity = 'APPEARANCE_SENSITIVITY_MUST_BE_D3';
  static const repositoryFailure = 'CONSENT_REPOSITORY_FAILURE';
}

/// Production adapter from the application port to the fail-closed policy core.
///
/// Appearance analysis has one immutable authorization scope:
/// `appearance_review / portrait / derive / D3`. Exactly one revision-pinned
/// Consent reference is required. Repository errors deny rather than allowing
/// the model invocation to proceed.
final class AppearancePolicyAdapter implements AppearancePolicyPort {
  const AppearancePolicyAdapter({
    required ConsentRevisionRepository consents,
    required PolicyClock clock,
  })  : _consents = consents,
        _clock = clock;

  static const _consentType = 'consent';
  static const _purpose = 'appearance_review';
  static const _resource = 'portrait';
  static const _action = 'derive';

  final ConsentRevisionRepository _consents;
  final PolicyClock _clock;

  @override
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
  }) async {
    // Prevent a caller from downgrading the classification to broaden access.
    if (sensitivity != Sensitivity.d3) {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.invalidSensitivity,
      );
    }

    if (consentRefs.length != 1 ||
        consentRefs.single.type != _consentType ||
        consentRefs.single.revision == null) {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.invalidConsentReference,
      );
    }
    final ref = consentRefs.single;

    ConsentGrant? grant;
    DateTime evaluatedAt;
    try {
      grant = await _consents.findRevision(
        consentId: ref.id.value,
        revision: ref.revision!.value,
      );
      evaluatedAt = _clock.now().toUtc();
    } on Object {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.repositoryFailure,
      );
    }

    final decision = evaluateConsent(
      consent: grant,
      request: ConsentRequest(
        consentId: ref.id.value,
        consentRevision: ref.revision!.value,
        subjectId: profileId.value,
        actorId: actor.actorId,
        purpose: _purpose,
        resource: _resource,
        action: _action,
        sensitivity: Sensitivity.d3,
      ),
      evaluatedAt: evaluatedAt,
    );
    return decision.isAllowed
        ? const PolicyVerdict.allow()
        : PolicyVerdict.deny(decision.reasonCode);
  }
}
