import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'observation_commands.dart';

abstract final class ObservationFailureCode {
  static const userActorRequired = 'observation.user_actor_required';
  static const invalidProfile = 'observation.invalid_profile';
  static const invalidCorrelation = 'observation.invalid_correlation';
  static const consentRequired = 'observation.consent_required';
  static const invalidConsent = 'observation.invalid_consent';
  static const invalidBlobRef = 'observation.invalid_blob_ref';
  static const invalidMediaType = 'observation.invalid_media_type';
  static const invalidContext = 'observation.invalid_context';
  static const d4Forbidden = 'observation.d4_forbidden';
  static const appendFailed = 'observation.append_failed';
  static const rollbackUnavailable = 'observation.rollback_unavailable';
}

final class ObservationUseCaseFailure implements Exception {
  const ObservationUseCaseFailure(this.code);

  final String code;

  @override
  String toString() => 'ObservationUseCaseFailure($code)';
}

final class RecordObservationResult {
  const RecordObservationResult(
      {required this.observationId, required this.eventId});

  final String observationId;
  final String eventId;
}

/// Records one profile-scoped observation for an existing opaque blob.
///
/// No blob adapter is consulted here. In particular, this use case does not
/// open files, read bytes, invoke a picker, or perform encryption.
final class RecordObservationUseCase {
  const RecordObservationUseCase({
    required EventStore eventStore,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final IdGenerator _ids;
  final Clock _clock;

  Future<RecordObservationResult> execute(
    RecordObservationCommand command,
  ) async {
    _validate(command);
    final now = _clock.now().toUtc();
    final observationId = _ids.nextId('observation');
    final event = EventEnvelope(
      eventId: _ids.nextId('event'),
      eventType: EventTypes.observationRecorded,
      eventVersion: 1,
      occurredAt: now,
      recordedAt: now,
      actor: command.actor,
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'observation', id: EntityId(observationId)),
        ObjectRef(type: 'profile', id: command.profileId),
      ],
      correlationId: command.correlationId.trim(),
      consentRefs: <ObjectRef>[command.consentRef!],
      sensitivity: command.sensitivity,
      payload: <String, Object?>{
        'observation_id': observationId,
        'blob_ref': command.blobRef.encode(),
        'media_type': command.mediaType.trim(),
        'observation_context': command.observationContext.trim(),
      },
    );

    try {
      // The single append is the atomic unit. No partial event is published
      // if the store rejects the batch.
      await _eventStore.appendAll(<EventEnvelope>[event]);
    } catch (_) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.appendFailed,
      );
    }
    return RecordObservationResult(
      observationId: observationId,
      eventId: event.eventId,
    );
  }

  void _validate(RecordObservationCommand command) {
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
    final consent = command.consentRef;
    if (consent == null) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.consentRequired,
      );
    }
    if (consent.type != 'consent' || consent.id.value.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidConsent,
      );
    }
    final blob = command.blobRef.encode();
    if (!blob.startsWith('blob://') ||
        blob.length == 'blob://'.length ||
        blob.trim() != blob ||
        blob.contains(RegExp(r'\s'))) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidBlobRef,
      );
    }
    if (command.mediaType.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidMediaType,
      );
    }
    if (command.observationContext.trim().isEmpty) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.invalidContext,
      );
    }
    if (command.sensitivity == Sensitivity.d4) {
      throw const ObservationUseCaseFailure(
        ObservationFailureCode.d4Forbidden,
      );
    }
  }
}
