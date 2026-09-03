import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
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
  static const appearanceConsentRequired = 'APPEARANCE_CONSENT_REQUIRED';
  static const externalProcessingConsentRequired =
      'EXTERNAL_PROCESSING_CONSENT_REQUIRED';
}

/// Production adapter from the application port to the fail-closed policy core.
///
/// On-device appearance analysis requires one revision-pinned
/// `appearance_review / portrait / derive / D3` consent. External processing
/// additionally requires a distinct revision-pinned
/// `external_processing / portrait / transmit / D3` consent. Repository errors
/// deny rather than allowing the model invocation to proceed.
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
  static const _externalPurpose = 'external_processing';
  static const _externalAction = 'transmit';

  final ConsentRevisionRepository _consents;
  final PolicyClock _clock;

  @override
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
    AppearanceProcessingBoundary processingBoundary =
        AppearanceProcessingBoundary.onDevice,
  }) async {
    // Prevent a caller from downgrading the classification to broaden access.
    if (sensitivity != Sensitivity.d3) {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.invalidSensitivity,
      );
    }

    final expectedConsentCount =
        processingBoundary == AppearanceProcessingBoundary.onDevice ? 1 : 2;
    if (consentRefs.length != expectedConsentCount ||
        consentRefs.any(
          (ref) => ref.type != _consentType || ref.revision == null,
        ) ||
        consentRefs.map((ref) => ref.id.value).toSet().length !=
            consentRefs.length) {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.invalidConsentReference,
      );
    }

    final grants = <ConsentGrant?>[];
    late final DateTime evaluatedAt;
    try {
      for (final ref in consentRefs) {
        grants.add(await _consents.findRevision(
          consentId: ref.id.value,
          revision: ref.revision!.value,
        ));
      }
      evaluatedAt = _clock.now().toUtc();
    } on Object {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.repositoryFailure,
      );
    }

    if (processingBoundary == AppearanceProcessingBoundary.onDevice) {
      final decision = _evaluateScope(
        ref: consentRefs.single,
        grant: grants.single,
        profileId: profileId,
        actor: actor,
        purpose: _purpose,
        action: _action,
        evaluatedAt: evaluatedAt,
      );
      return decision.isAllowed
          ? const PolicyVerdict.allow()
          : PolicyVerdict.deny(decision.reasonCode);
    }

    var appearanceAllowed = false;
    var externalProcessingAllowed = false;
    for (var index = 0; index < consentRefs.length; index++) {
      final ref = consentRefs[index];
      final grant = grants[index];
      if (_evaluateScope(
        ref: ref,
        grant: grant,
        profileId: profileId,
        actor: actor,
        purpose: _purpose,
        action: _action,
        evaluatedAt: evaluatedAt,
      ).isAllowed) {
        appearanceAllowed = true;
      }
      if (_evaluateScope(
        ref: ref,
        grant: grant,
        profileId: profileId,
        actor: actor,
        purpose: _externalPurpose,
        action: _externalAction,
        evaluatedAt: evaluatedAt,
      ).isAllowed) {
        externalProcessingAllowed = true;
      }
    }
    if (!appearanceAllowed) {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.appearanceConsentRequired,
      );
    }
    if (!externalProcessingAllowed) {
      return const PolicyVerdict.deny(
        AppearancePolicyReason.externalProcessingConsentRequired,
      );
    }
    return const PolicyVerdict.allow();
  }

  PolicyDecision _evaluateScope({
    required ObjectRef ref,
    required ConsentGrant? grant,
    required EntityId profileId,
    required ActorRef actor,
    required String purpose,
    required String action,
    required DateTime evaluatedAt,
  }) =>
      evaluateConsent(
        consent: grant,
        request: ConsentRequest(
          consentId: ref.id.value,
          consentRevision: ref.revision!.value,
          subjectId: profileId.value,
          actorId: actor.actorId,
          purpose: purpose,
          resource: _resource,
          action: action,
          sensitivity: Sensitivity.d3,
        ),
        evaluatedAt: evaluatedAt,
      );
}
