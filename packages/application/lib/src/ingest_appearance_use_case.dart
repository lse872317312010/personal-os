import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';

import 'appearance_commands.dart';
import 'appearance_use_case.dart';
import 'application_ports.dart';
import 'ingest_observation_use_case.dart';
import 'observation_commands.dart';
import 'observation_use_case.dart';

/// Raw bytes are accepted only at this boundary. They are passed directly to
/// the blob ingestion port and are never copied into an event or model input.
final class IngestAppearanceAnalysisCommand {
  const IngestAppearanceAnalysisCommand({
    required this.bytes,
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

  final Stream<List<int>> bytes;
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

final class IngestAppearanceAnalysisResult {
  const IngestAppearanceAnalysisResult({
    required this.blobRef,
    required this.observation,
    required this.analysis,
  });

  /// Opaque in-process capability. Callers must not log or expose it.
  final BlobRef blobRef;
  final RecordObservationResult observation;
  final AppearanceLoopResult analysis;
}

/// Connects encrypted blob ingestion to the existing observation and
/// appearance-analysis flow.
///
/// The composition root supplies the concrete ingestion adapter. This use
/// case knows only the adapter-neutral contract and compensates the blob if
/// either downstream application operation fails. Failure details remain
/// those of the stable application/blob error types.
final class IngestAppearanceAnalysisUseCase {
  const IngestAppearanceAnalysisUseCase({
    required BlobIngestionContract ingestion,
    required RecordObservationUseCase recordObservation,
    required AnalyzeAppearanceUseCase analyzeAppearance,
  })  : _ingestion = ingestion,
        _recordObservation = recordObservation,
        _analyzeAppearance = analyzeAppearance;

  final BlobIngestionContract _ingestion;
  final RecordObservationUseCase _recordObservation;
  final AnalyzeAppearanceUseCase _analyzeAppearance;

  Future<IngestAppearanceAnalysisResult> execute(
    IngestAppearanceAnalysisCommand command,
  ) async {
    if (_ingestion is! BlobIngestionRollback) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.rollbackUnavailable,
      );
    }
    final rollback = _ingestion as BlobIngestionRollback;
    final blobRef = await _ingestion.ingest(
      bytes: command.bytes,
      mediaType: command.mediaType,
      sensitivity: command.sensitivity,
      access: command.access,
    );

    try {
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
      return IngestAppearanceAnalysisResult(
        blobRef: blobRef,
        observation: observation,
        analysis: analysis,
      );
    } catch (_) {
      try {
        await rollback.discard(ref: blobRef, access: command.access);
      } catch (_) {
        // Preserve the original stable application failure.
      }
      rethrow;
    }
  }
}
