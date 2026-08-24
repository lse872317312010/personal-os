import 'package:personal_os_domain/domain.dart';

final class RequestDeletionCommand {
  RequestDeletionCommand({
    required this.profileId,
    required this.deletionId,
    required this.actor,
    required this.correlationId,
    this.expectedDeletionRevision = 0,
  });

  final EntityId profileId;
  final EntityId deletionId;
  final ActorRef actor;
  final String correlationId;
  final int expectedDeletionRevision;
}

final class CompleteDeletionCommand {
  CompleteDeletionCommand({
    required this.profileId,
    required this.deletionId,
    required this.tombstoneRef,
    required this.erasedRefs,
    required this.actor,
    required this.correlationId,
    required this.expectedDeletionRevision,
  });

  final EntityId profileId;
  final EntityId deletionId;
  final String tombstoneRef;
  final List<String> erasedRefs;
  final ActorRef actor;
  final String correlationId;
  final int expectedDeletionRevision;
}
