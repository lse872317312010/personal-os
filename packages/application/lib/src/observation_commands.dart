import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Records metadata about an already-ingested opaque blob.
///
/// This command deliberately has no path, URI, byte, hash, or content fields.
/// The blob must already exist; this boundary never reads it.
final class RecordObservationCommand {
  const RecordObservationCommand({
    required this.profileId,
    required this.blobRef,
    required this.mediaType,
    required this.observationContext,
    required this.consentRef,
    required this.actor,
    required this.correlationId,
    this.sensitivity = Sensitivity.d3,
  });

  final EntityId profileId;
  final BlobRef blobRef;
  final String mediaType;
  final String observationContext;
  final ObjectRef? consentRef;
  final ActorRef actor;
  final String correlationId;
  final Sensitivity sensitivity;
}
