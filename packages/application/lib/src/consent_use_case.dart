import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'consent_commands.dart';

abstract final class ConsentFailureCode {
  static const userActorRequired = 'consent.user_actor_required';
  static const invalidConsent = 'consent.invalid_consent';
  static const invalidCorrelation = 'consent.invalid_correlation';
  static const invalidExpectedRevision = 'consent.invalid_expected_revision';
}

final class ConsentUseCaseFailure implements Exception {
  const ConsentUseCaseFailure(this.code);

  final String code;
}

final class ConsentLifecycleResult {
  const ConsentLifecycleResult({
    required this.stateRevision,
    required this.eventIds,
  });

  final int stateRevision;
  final List<String> eventIds;
}

/// Writes the consent lifecycle as ordinary profile-scoped events.
///
/// This use case does not grant permission merely because a UI checkbox is
/// selected. Policy consumers must read the resulting exact event stream and
/// continue to fail closed when that stream cannot be read.
final class ConsentLifecycleUseCase {
  const ConsentLifecycleUseCase({
    required EventStore eventStore,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final IdGenerator _ids;
  final Clock _clock;

  Future<ConsentLifecycleResult> grant(GrantConsentCommand command) async {
    _validateActor(command.actor);
    _validateCommon(
        command.consentId, command.consentRevision, command.correlationId);
    if (command.expectedConsentStateRevision < 0) {
      throw const ConsentUseCaseFailure(
        ConsentFailureCode.invalidExpectedRevision,
      );
    }
    final now = _clock.now().toUtc();
    final payload = _grantPayload(command, now);
    final requested = _event(
      command: command,
      type: EventTypes.consentRequested,
      expectedRevision: command.expectedConsentStateRevision,
      payload: payload,
      now: now,
    );
    final granted = _event(
      command: command,
      type: EventTypes.consentGranted,
      expectedRevision: command.expectedConsentStateRevision + 1,
      payload: payload,
      now: now,
      causationId: requested.eventId,
    );
    await _eventStore.appendAll(<EventEnvelope>[requested, granted]);
    return ConsentLifecycleResult(
      stateRevision: command.expectedConsentStateRevision + 2,
      eventIds: List<String>.unmodifiable(<String>[
        requested.eventId,
        granted.eventId,
      ]),
    );
  }

  Future<ConsentLifecycleResult> revoke(RevokeConsentCommand command) async {
    _validateActor(command.actor);
    _validateCommon(
        command.consentId, command.consentRevision, command.correlationId);
    if (command.expectedConsentStateRevision < 0) {
      throw const ConsentUseCaseFailure(
        ConsentFailureCode.invalidExpectedRevision,
      );
    }
    final now = _clock.now().toUtc();
    final event = _event(
      command: command,
      type: EventTypes.consentRevoked,
      expectedRevision: command.expectedConsentStateRevision,
      payload: <String, Object?>{
        'expected_revision': command.expectedConsentStateRevision,
        'consent_revision': command.consentRevision,
      },
      now: now,
    );
    await _eventStore.appendAll(<EventEnvelope>[event]);
    return ConsentLifecycleResult(
      stateRevision: command.expectedConsentStateRevision + 1,
      eventIds: <String>[event.eventId],
    );
  }

  void _validateActor(ActorRef actor) {
    if (actor.actorType != ActorType.user) {
      throw const ConsentUseCaseFailure(ConsentFailureCode.userActorRequired);
    }
  }

  void _validateCommon(String consentId, int revision, String correlationId) {
    if (consentId.trim().isEmpty || revision <= 0) {
      throw const ConsentUseCaseFailure(ConsentFailureCode.invalidConsent);
    }
    if (correlationId.trim().isEmpty) {
      throw const ConsentUseCaseFailure(ConsentFailureCode.invalidCorrelation);
    }
  }

  Map<String, Object?> _grantPayload(
    GrantConsentCommand command,
    DateTime now,
  ) {
    final (purposes, actions) = switch (command.scope) {
      ConsentScope.appearanceReview => (
          const <String>['appearance_review'],
          const <String>['derive'],
        ),
      ConsentScope.externalProcessing => (
          const <String>['external_processing'],
          const <String>['transmit'],
        ),
    };
    return <String, Object?>{
      'expected_revision': 0,
      'consent_id': command.consentId,
      'consent_revision': command.consentRevision,
      'subject_id': command.profileId.value,
      'authorized_actor_id': command.actor.actorId,
      'purposes': purposes,
      'resources': const <String>['portrait'],
      'actions': actions,
      'scope': command.scope.name,
      'maximum_sensitivity': Sensitivity.d3.name,
      'valid_from': now.toIso8601String(),
      'valid_until': now.add(const Duration(hours: 8)).toIso8601String(),
    };
  }

  EventEnvelope _event({
    required Object command,
    required String type,
    required int expectedRevision,
    required Map<String, Object?> payload,
    required DateTime now,
    String? causationId,
  }) {
    final profileId = command is GrantConsentCommand
        ? command.profileId
        : (command as RevokeConsentCommand).profileId;
    final actor = command is GrantConsentCommand
        ? command.actor
        : (command as RevokeConsentCommand).actor;
    final correlationId = command is GrantConsentCommand
        ? command.correlationId
        : (command as RevokeConsentCommand).correlationId;
    final consentId = command is GrantConsentCommand
        ? command.consentId
        : (command as RevokeConsentCommand).consentId;
    return EventEnvelope(
      eventId: _ids.nextId('event'),
      eventType: type,
      eventVersion: 1,
      occurredAt: now,
      recordedAt: now,
      actor: actor,
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'consent', id: EntityId(consentId)),
        ObjectRef(type: 'profile', id: profileId),
      ],
      correlationId: correlationId,
      causationId: causationId,
      consentRefs: const <ObjectRef>[],
      sensitivity: Sensitivity.d2,
      payload: <String, Object?>{
        ...payload,
        'expected_revision': expectedRevision,
      },
    );
  }
}
