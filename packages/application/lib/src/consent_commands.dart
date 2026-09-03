import 'package:personal_os_domain/domain.dart';

enum ConsentScope { appearanceReview, externalProcessing }

final class GrantConsentCommand {
  const GrantConsentCommand({
    required this.profileId,
    required this.consentId,
    required this.consentRevision,
    this.expectedConsentStateRevision = 0,
    required this.actor,
    required this.correlationId,
    this.scope = ConsentScope.appearanceReview,
  });

  final EntityId profileId;
  final String consentId;
  final int consentRevision;
  final int expectedConsentStateRevision;
  final ActorRef actor;
  final String correlationId;
  final ConsentScope scope;
}

final class RevokeConsentCommand {
  const RevokeConsentCommand({
    required this.profileId,
    required this.consentId,
    required this.consentRevision,
    required this.expectedConsentStateRevision,
    required this.actor,
    required this.correlationId,
  });

  final EntityId profileId;
  final String consentId;
  final int consentRevision;
  final int expectedConsentStateRevision;
  final ActorRef actor;
  final String correlationId;
}
