import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'appearance_use_case.dart';
import 'application_ports.dart';
import 'observation_commands.dart';
import 'observation_use_case.dart';

/// Command for native source-token ingestion. The token is never dereferenced,
/// serialized into an event, or converted into bytes in Dart.
final class IngestAppearanceFromSourceCommand {
  const IngestAppearanceFromSourceCommand({
    required this.source,
    required this.mediaType,
    required this.access,
    required this.profileId,
    required this.observationContext,
    required this.consentRef,
    required this.actor,
    required this.correlationId,
    this.locale = 'zh-CN',
    this.sensitivity = Sensitivity.d3,
  });

  final OpaqueSourceToken source;
  final String mediaType;
  final BlobAccessContext access;
  final EntityId profileId;
  final String observationContext;
  final ObjectRef? consentRef;
  final ActorRef actor;
  final String correlationId;
  final String locale;
  final Sensitivity sensitivity;
}

/// Composes native source streaming directly into encrypted blob storage and
/// then runs the existing opaque-BlobRef observation/analysis loop.
final class IngestAppearanceFromSourceUseCase {
  const IngestAppearanceFromSourceUseCase({
    required SourceBlobIngestionPort ingestion,
    required RecordObservationUseCase recordObservation,
    required AnalyzeAppearanceUseCase analyzeAppearance,
  })  : _ingestion = ingestion,
        _recordObservation = recordObservation,
        _analyzeAppearance = analyzeAppearance;

  final SourceBlobIngestionPort _ingestion;
  final RecordObservationUseCase _recordObservation;
  final AnalyzeAppearanceUseCase _analyzeAppearance;

  Future<IngestAppearanceFromSourceResult> execute(
    IngestAppearanceFromSourceCommand command,
  ) async {
    // Reject policy-sensitive requests before the native source can be read.
    if (command.consentRef == null) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.consentRequired,
      );
    }
    if (command.sensitivity == Sensitivity.d4) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.d4Forbidden,
      );
    }
    final blobRef = await _ingestion.ingestSource(
      source: command.source,
      mediaType: command.mediaType,
      sensitivity: command.sensitivity,
      access: command.access,
    );

    var eventCommitted = false;
    try {
      // Analyze first so a model/policy failure can discard the new BlobRef
      // without leaving an observation event that points to deleted data.
      final analysis = await _analyzeAppearance.execute(
        AnalyzeAppearanceCommand(
          profileId: command.profileId,
          imageRef: blobRef.encode(),
          actor: command.actor,
          correlationId: command.correlationId,
          observationContext: command.observationContext,
          consentRefs: command.consentRef == null
              ? const <ObjectRef>[]
              : <ObjectRef>[command.consentRef!],
          locale: command.locale,
        ),
      );
      eventCommitted = true;
      final observation = await _recordObservation.execute(
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
      eventCommitted = true;
      return IngestAppearanceFromSourceResult(
        blobRef: blobRef,
        observation: observation,
        analysis: analysis,
      );
    } catch (error) {
      // Once either operation committed, retain the blob for retry; deleting
      // it would leave persisted events with a dangling reference.
      if (!eventCommitted) {
        await _discardSafely(blobRef, command.access);
      }
      if (error is AppearanceUseCaseFailure ||
          error is ObservationUseCaseFailure) {
        rethrow;
      }
      throw const AppearanceUseCaseFailure(
        AppearanceFailureCode.analysisFailed,
      );
    }

  Future<void> _discardSafely(
    BlobRef ref,
    BlobAccessContext access,
  ) async {
    try {
      await _ingestion.discard(ref: ref, access: access);
    } catch (_) {
      // Preserve the stable failure and never leak adapter details.
    }
  }
  }
}
