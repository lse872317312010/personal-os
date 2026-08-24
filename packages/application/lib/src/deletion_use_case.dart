import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'application_ports.dart';
import 'deletion_commands.dart';

abstract final class DeletionFailureCode {
  static const userActorRequired = 'deletion.user_actor_required';
  static const invalidProfile = 'deletion.invalid_profile';
  static const invalidDeletion = 'deletion.invalid_deletion';
  static const invalidCorrelation = 'deletion.invalid_correlation';
  static const invalidExpectedRevision = 'deletion.invalid_expected_revision';
  static const invalidTombstone = 'deletion.invalid_tombstone';
  static const invalidErasedRefs = 'deletion.invalid_erased_refs';
}

final class DeletionUseCaseFailure implements Exception {
  const DeletionUseCaseFailure(this.code);

  final String code;
}

final class DeletionResult {
  const DeletionResult({
    required this.deletionId,
    required this.tombstoneRef,
    required this.revision,
    required this.eventIds,
  });

  final EntityId deletionId;
  final String tombstoneRef;
  final int revision;
  final List<String> eventIds;
}

/// Records the deletion barrier and tombstone protocol.
///
/// This use case does not delete blobs, files, keys, or physical records. The
/// values in [CompleteDeletionCommand.erasedRefs] are logical object refs only;
/// paths, hashes, content, and adapter diagnostics are rejected before the
/// completion event is appended.
final class DeletionUseCase {
  const DeletionUseCase({
    required EventStore eventStore,
    required IdGenerator ids,
    required Clock clock,
  })  : _eventStore = eventStore,
        _ids = ids,
        _clock = clock;

  final EventStore _eventStore;
  final IdGenerator _ids;
  final Clock _clock;

  Future<DeletionResult> request(RequestDeletionCommand command) async {
    _validateActor(command.actor);
    _validateProfile(command.profileId);
    _validateDeletion(command.deletionId);
    _validateCorrelation(command.correlationId);
    if (command.expectedDeletionRevision != 0) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.invalidExpectedRevision,
      );
    }

    final now = _clock.now().toUtc();
    final tombstoneRef = _opaqueTombstoneRef();
    final event = _event(
      command: command,
      type: EventTypes.deletionRequested,
      expectedRevision: command.expectedDeletionRevision,
      tombstoneRef: tombstoneRef,
      now: now,
    );
    await _eventStore.appendAll(<EventEnvelope>[event]);
    return DeletionResult(
      deletionId: command.deletionId,
      tombstoneRef: tombstoneRef,
      revision: command.expectedDeletionRevision + 1,
      eventIds: List<String>.unmodifiable(<String>[event.eventId]),
    );
  }

  Future<DeletionResult> complete(CompleteDeletionCommand command) async {
    _validateActor(command.actor);
    _validateProfile(command.profileId);
    _validateDeletion(command.deletionId);
    _validateCorrelation(command.correlationId);
    _validateTombstone(command.tombstoneRef);
    _validateErasedRefs(command.erasedRefs);
    if (command.expectedDeletionRevision != 1) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.invalidExpectedRevision,
      );
    }

    final now = _clock.now().toUtc();
    final event = _event(
      command: command,
      type: EventTypes.deletionCompleted,
      expectedRevision: command.expectedDeletionRevision,
      tombstoneRef: command.tombstoneRef,
      erasedRefs: command.erasedRefs,
      now: now,
    );
    await _eventStore.appendAll(<EventEnvelope>[event]);
    return DeletionResult(
      deletionId: command.deletionId,
      tombstoneRef: command.tombstoneRef,
      revision: command.expectedDeletionRevision + 1,
      eventIds: List<String>.unmodifiable(<String>[event.eventId]),
    );
  }

  // This is an opaque logical token, not a cryptographic random value. The
  // platform may replace IdGenerator with a stronger implementation later.
  String _opaqueTombstoneRef() => _ids.nextId('opaque');

  EventEnvelope _event({
    required Object command,
    required String type,
    required int expectedRevision,
    required String tombstoneRef,
    required DateTime now,
    List<String> erasedRefs = const <String>[],
  }) {
    final profileId = command is RequestDeletionCommand
        ? command.profileId
        : (command as CompleteDeletionCommand).profileId;
    final deletionId = command is RequestDeletionCommand
        ? command.deletionId
        : (command as CompleteDeletionCommand).deletionId;
    final actor = command is RequestDeletionCommand
        ? command.actor
        : (command as CompleteDeletionCommand).actor;
    final correlationId = command is RequestDeletionCommand
        ? command.correlationId
        : (command as CompleteDeletionCommand).correlationId;
    return EventEnvelope(
      eventId: _ids.nextId('event'),
      eventType: type,
      eventVersion: 1,
      occurredAt: now,
      recordedAt: now,
      actor: actor,
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'deletion', id: deletionId),
        ObjectRef(type: 'profile', id: profileId),
        if (type == EventTypes.deletionCompleted)
          ObjectRef(type: 'tombstone', id: EntityId(tombstoneRef)),
      ],
      correlationId: correlationId,
      sensitivity: Sensitivity.d3,
      payload: <String, Object?>{
        'expected_revision': expectedRevision,
        'profile_ref': 'profile:${profileId.value}',
        'tombstone_id': tombstoneRef,
        'contains_content_hash': false,
        if (type == EventTypes.deletionCompleted)
          'erased_refs': List<String>.unmodifiable(erasedRefs),
      },
    );
  }

  void _validateActor(ActorRef actor) {
    if (actor.actorType != ActorType.user) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.userActorRequired,
      );
    }
  }

  void _validateProfile(EntityId profileId) {
    if (profileId.value.trim().isEmpty) {
      throw const DeletionUseCaseFailure(DeletionFailureCode.invalidProfile);
    }
  }

  void _validateDeletion(EntityId deletionId) {
    if (deletionId.value.trim().isEmpty) {
      throw const DeletionUseCaseFailure(DeletionFailureCode.invalidDeletion);
    }
  }

  void _validateCorrelation(String correlationId) {
    if (correlationId.trim().isEmpty) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.invalidCorrelation,
      );
    }
  }

  void _validateTombstone(String value) {
    if (!_opaqueToken.hasMatch(value)) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.invalidTombstone,
      );
    }
  }

  void _validateErasedRefs(List<String> refs) {
    if (refs.isEmpty || refs.toSet().length != refs.length) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.invalidErasedRefs,
      );
    }
    if (refs.any((ref) => !_isLogicalRef(ref))) {
      throw const DeletionUseCaseFailure(
        DeletionFailureCode.invalidErasedRefs,
      );
    }
  }
}

// Logical references only: no slash, backslash, hash, whitespace, or payload.
final _logicalRef = RegExp(r'^[a-z][a-z0-9_.-]*:[A-Za-z0-9_.-]+$');
final _opaqueToken = RegExp(r'^[A-Za-z0-9_.-]+$');
const _forbiddenReferenceTypes = <String>{
  'content',
  'data',
  'file',
  'hash',
  'path',
  'uri',
};

bool _isLogicalRef(String value) {
  if (!_logicalRef.hasMatch(value)) return false;
  final type = value.substring(0, value.indexOf(':'));
  return !_forbiddenReferenceTypes.contains(type);
}
