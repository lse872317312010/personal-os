import 'dart:typed_data';

import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'observation_commands.dart';
import 'observation_use_case.dart';

/// External input for the only application path that creates a blob-backed
/// observation. It contains bytes only at this ingress boundary; the event
/// written by the use case contains the resulting opaque [BlobRef] only.
final class IngestObservationCommand {
  const IngestObservationCommand({
    required this.bytes,
    required this.mediaType,
    required this.sensitivity,
    required this.access,
    required this.profileId,
    required this.observationContext,
    required this.consentRef,
    required this.actor,
    required this.correlationId,
  });

  final Stream<List<int>> bytes;
  final String mediaType;
  final Sensitivity sensitivity;
  final BlobAccessContext access;
  final EntityId profileId;
  final String observationContext;
  final ObjectRef? consentRef;
  final ActorRef actor;
  final String correlationId;
}

/// Securely ingests external bytes before recording an observation.
///
/// The application never receives plaintext after ingestion and never puts
/// paths, URIs, bytes, or content hashes in the event payload. D4 is rejected
/// by the ingestion contract before the input stream is listened to.
final class IngestObservationUseCase {
  const IngestObservationUseCase({
    required BlobIngestionContract ingestion,
    required RecordObservationUseCase recordObservation,
  })  : _ingestion = ingestion,
        _recordObservation = recordObservation;

  final BlobIngestionContract _ingestion;
  final RecordObservationUseCase _recordObservation;

  Future<RecordObservationResult> execute(IngestObservationCommand command) async {
    final blobRef = await _ingestion.ingest(
      bytes: command.bytes,
      mediaType: command.mediaType,
      sensitivity: command.sensitivity,
      access: command.access,
    );
    try {
      return await _recordObservation.execute(
        RecordObservationCommand(
          profileId: command.profileId,
          blobRef: blobRef,
          mediaType: command.mediaType,
          observationContext: command.observationContext,
          consentRef: command.consentRef,
          actor: command.actor,
          correlationId: command.correlationId,
          sensitivity: command.sensitivity,
        ),
      );
    } catch (_) {
      final rollback = _ingestion;
      if (rollback is BlobIngestionRollback) {
        try {
          await rollback.discard(ref: blobRef, access: command.access);
        } catch (_) {
          // Preserve the stable append failure. Never leak rollback details.
        }
      }
      rethrow;
    }
  }
}

