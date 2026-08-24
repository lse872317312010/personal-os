import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'appearance_commands.dart';
import 'appearance_use_case.dart';
import 'observation_commands.dart';
import 'observation_use_case.dart';

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
  final ObjectRef consentRef;
  final ActorRef actor;
  final String correlationId;
  final String locale;
  final Sensitivity sensitivity;
}

final class IngestAppearanceAnalysisResult {
  const IngestAppearanceAnalysisResult({
    required this.blobRef,
    required this.observation,
    required this.analysis,
  });

  final BlobRef blobRef;
  final RecordObservationResult observation;
  final AppearanceLoopResult analysis;
}

/// Consumes an opaque native token at the encrypted boundary. The token is
/// never converted to bytes, a URI, or a path in application code.
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

  Future<IngestAppearanceAnalysisResult> execute(
    IngestAppearanceFromSourceCommand command,
  ) async {
    _validate(command);
    late final BlobRef blobRef;
    try {
      blobRef = await _ingestion.ingestSource(
        source: command.source,
        mediaType: command.mediaType,
        sensitivity: command.sensitivity,
        access: command.access,
      );
    } catch (error) {
      if (error is BlobIngestionException) rethrow;
      if (error is ControlledSourceException) rethrow;
      throw const BlobIngestionException('ingestion_failed');
    }

    // EventStore.appendAll is atomic, but observation and analysis are two
    // application operations. Once either operation returns successfully, an
    // event may refer to this blob. From that point onward the blob is owned
    // by the event stream and must be retained for retry; deleting it would
    // create a dangling observation or analysis event.
    var eventCommitted = false;
    try {
      final analysis = await _analyzeAppearance.execute(
        AnalyzeAppearanceCommand(
          profileId: command.profileId,
          imageRef: blobRef.encode(),
          actor: command.actor,
          correlationId: command.correlationId,
          observationContext: command.observationContext,
          consentRefs: <ObjectRef>[command.consentRef],
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
      return IngestAppearanceAnalysisResult(
        blobRef: blobRef,
        observation: observation,
        analysis: analysis,
      );
    } catch (error) {
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
  }

  void _validate(IngestAppearanceFromSourceCommand command) {
    if (command.actor.actorType != ActorType.user) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.userActorRequired,
      );
    }
    if (command.profileId.value.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidProfile,
      );
    }
    if (command.correlationId.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidCorrelation,
      );
    }
    if (command.sensitivity == Sensitivity.d4) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.d4Forbidden,
      );
    }
    if (command.consentRef.type != 'consent' ||
        command.consentRef.id.value.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidConsent,
      );
    }
    if (command.access.consentRef == null) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.consentRequired,
      );
    }
    if (command.observationContext.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidContext,
      );
    }
    if (command.mediaType.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidMediaType,
      );
    }
  }

  Future<void> _discardSafely(BlobRef ref, BlobAccessContext access) async {
    try {
      await _ingestion.discard(ref: ref, access: access);
    } catch (_) {
      // Preserve the stable operation failure and never leak adapter detail.
    }
  }
}
