import 'package:personal_os_domain/domain.dart';

import 'risk.dart';

final class SensitivityDecision {
  const SensitivityDecision.allowed(this.sensitivity)
      : policy = const PolicyDecision(
          PolicyOutcome.allow,
          PolicyReason.allowed,
        );

  const SensitivityDecision.denied(this.sensitivity, String reasonCode)
      : policy = const PolicyDecision(PolicyOutcome.deny, reasonCode);

  final Sensitivity sensitivity;
  final PolicyDecision policy;
}

SensitivityDecision deriveSensitivity({
  required Iterable<Sensitivity> inputs,
  required Sensitivity declaredMinimum,
}) {
  final inherited = maximumSensitivity(<Sensitivity>[
    ...inputs,
    declaredMinimum,
  ]);
  if (inherited == Sensitivity.d4) {
    return const SensitivityDecision.denied(
      Sensitivity.d4,
      PolicyReason.d4ProcessingForbidden,
    );
  }
  return SensitivityDecision.allowed(inherited);
}

/// Lowering sensitivity is never automatic. A separate user review must
/// approve a tested transformation; callers cannot silently relabel data.
PolicyDecision requestDeclassification({
  required Sensitivity from,
  required Sensitivity to,
}) {
  if (from == Sensitivity.d4) {
    return PolicyDecision.denied(PolicyReason.d4ProcessingForbidden);
  }
  if (to.index >= from.index) return PolicyDecision.allowed();
  return const PolicyDecision(
    PolicyOutcome.requireUserConfirmation,
    PolicyReason.declassificationReviewRequired,
  );
}
