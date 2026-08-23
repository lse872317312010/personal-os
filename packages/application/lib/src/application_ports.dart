import 'package:personal_os_domain/domain.dart';

/// Narrow fail-closed boundary expected from the policy package.
///
/// The application depends on this capability rather than a concrete policy
/// engine. An adapter can map the future policy package onto this interface.
abstract interface class AppearancePolicyPort {
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
  });
}

final class PolicyVerdict {
  const PolicyVerdict._({required this.allowed, required this.reasonCode});

  const PolicyVerdict.allow() : this._(allowed: true, reasonCode: null);

  const PolicyVerdict.deny(String reasonCode)
      : this._(allowed: false, reasonCode: reasonCode);

  final bool allowed;
  final String? reasonCode;
}

abstract interface class IdGenerator {
  String nextId(String namespace);
}

abstract interface class Clock {
  DateTime now();
}
