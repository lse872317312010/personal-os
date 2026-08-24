import 'dart:convert';
import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:personal_os_sync_api/sync_api.dart';

abstract final class SyncFailureReason {
  static const emptyBatch = 'empty_batch';
  static const d4SyncForbidden = 'd4_sync_forbidden';
  static const unsupportedProtocolVersion = 'unsupported_protocol_version';
  static const accountMismatch = 'account_mismatch';
  static const unknownSender = 'unknown_sender';
  static const epochMismatch = 'epoch_mismatch';
  static const sequenceGap = 'sequence_gap';
  static const sequenceOverlap = 'sequence_overlap';
  static const replayConflict = 'replay_conflict';
  static const sequenceCountMismatch = 'sequence_count_mismatch';
  static const invalidEnvelope = 'invalid_envelope';
  static const invalidPageLimit = 'invalid_page_limit';
  static const pageResponseInvalid = 'page_response_invalid';
  static const eventEncodeFailed = 'event_encode_failed';
  static const payloadDecodeFailed = 'payload_decode_failed';
  static const cryptographyFailed = 'cryptography_failed';
  static const appendFailed = 'append_failed';
  static const batchNotCommitted = 'batch_not_committed';
  static const relayAckMismatch = 'relay_ack_mismatch';
  static const transportFailed = 'transport_failed';
}

enum SyncDisposition { applied, pushed, duplicate, rejected }

final class SyncResult {
  const SyncResult._({
    required this.disposition,
    this.reasonCode,
    this.cursor,
    this.envelopeId,
    this.eventCount = 0,
  });

  factory SyncResult.success({
    required SyncDisposition disposition,
    required OpaqueSyncCursor cursor,
    required String envelopeId,
    required int eventCount,
  }) =>
      SyncResult._(
        disposition: disposition,
        cursor: cursor,
        envelopeId: envelopeId,
        eventCount: eventCount,
      );

  factory SyncResult.rejected(String reasonCode, {String? envelopeId}) =>
      SyncResult._(
        disposition: SyncDisposition.rejected,
        reasonCode: reasonCode,
        envelopeId: envelopeId,
      );

  final SyncDisposition disposition;
  final String? reasonCode;
  final OpaqueSyncCursor? cursor;
  final String? envelopeId;
  final int eventCount;
}

final class SyncPullResult {
  SyncPullResult({
    required List<SyncResult> items,
    required this.cursor,
    required this.hasMore,
  }) : items = List.unmodifiable(items);

  final List<SyncResult> items;
  final OpaqueSyncCursor cursor;
  final bool hasMore;
  bool get rejected =>
      items.any((item) => item.disposition == SyncDisposition.rejected);
}

/// Trusted-device sync orchestration. Cryptographic operations are delegated
/// to [SyncCryptographyPort]; this class never substitutes an insecure cipher.
final class SyncWorker {
  SyncWorker({
    required this.deviceId,
    required this.accountPseudonym,
    required this.recipientEpoch,
    required Set<String> trustedSenderDeviceIds,
    required SyncPort transport,
    required SyncCryptographyPort cryptography,
    required EventStore eventStore,
    Map<String, int> lastReceivedSequenceBySender = const {},
  })  : _trustedSenders = Set.unmodifiable(trustedSenderDeviceIds),
        _transport = transport,
        _cryptography = cryptography,
        _eventStore = eventStore,
        _lastReceived = Map.of(lastReceivedSequenceBySender) {
    if (deviceId.isEmpty ||
        accountPseudonym.isEmpty ||
        recipientEpoch.isEmpty) {
      throw ArgumentError('sync identity values must not be empty');
    }
  }

  static const protocolVersion = 1;
  static const payloadVersion = 1;

  final String deviceId;
  final String accountPseudonym;
  final String recipientEpoch;
  final Set<String> _trustedSenders;
  final SyncPort _transport;
  final SyncCryptographyPort _cryptography;
  final EventStore _eventStore;
  final Map<String, int> _lastReceived;
  final Set<String> _acceptedEnvelopeIds = <String>{};
  final Map<String, DeviceSequenceRange> _acceptedEnvelopeRanges = {};

  int lastReceivedSequence(String senderDeviceId) =>
      _lastReceived[senderDeviceId] ?? -1;

  Future<SyncResult> pushBatch({
    required String envelopeId,
    required List<EventEnvelope> events,
    required DeviceSequenceRange sequence,
    required OpaqueSyncCursor cursor,
  }) async {
    if (events.isEmpty)
      return SyncResult.rejected(SyncFailureReason.emptyBatch);
    if (envelopeId.trim().isEmpty) {
      return SyncResult.rejected(SyncFailureReason.invalidEnvelope);
    }
    if (events.any((event) => event.sensitivity == Sensitivity.d4)) {
      return SyncResult.rejected(SyncFailureReason.d4SyncForbidden);
    }
    if (sequence.count != events.length) {
      return SyncResult.rejected(SyncFailureReason.sequenceCountMismatch);
    }

    final metadata = _metadata(
      envelopeId: envelopeId,
      senderDeviceId: deviceId,
      sequence: sequence,
    );
    late final Uint8List plaintext;
    try {
      plaintext = Uint8List.fromList(
        utf8.encode(jsonEncode(<String, Object?>{
          'payload_version': payloadVersion,
          'events': events.map(EventEnvelopeJsonCodec.encode).toList(),
        })),
      );
    } on Object {
      return SyncResult.rejected(SyncFailureReason.eventEncodeFailed);
    }
    late final SealedSyncPayload sealed;
    try {
      sealed = await _cryptography.seal(
        trustedPlaintext: plaintext,
        recipientEpoch: recipientEpoch,
        authenticatedMetadata: metadata,
      );
    } on Object {
      return SyncResult.rejected(SyncFailureReason.cryptographyFailed);
    } finally {
      _zeroize(plaintext);
    }
    if (sealed.recipientEpoch != recipientEpoch) {
      return SyncResult.rejected(SyncFailureReason.epochMismatch);
    }
    final envelope = EncryptedSyncEnvelope(
      protocolVersion: protocolVersion,
      envelopeId: envelopeId,
      accountPseudonym: accountPseudonym,
      senderDeviceId: deviceId,
      recipientEpoch: recipientEpoch,
      sequence: sequence,
      ciphertext: sealed.ciphertext,
      signature: sealed.signature,
    );
    late final SyncPushReceipt receipt;
    try {
      receipt = await _transport.push(
        deviceId: deviceId,
        envelopes: [envelope],
        cursor: cursor,
      );
    } on Object {
      return SyncResult.rejected(SyncFailureReason.transportFailed);
    }
    if (receipt.acceptedEnvelopeIds.length != 1 ||
        receipt.acceptedEnvelopeIds.single != envelopeId) {
      return SyncResult.rejected(SyncFailureReason.relayAckMismatch);
    }
    return SyncResult.success(
      disposition: SyncDisposition.pushed,
      cursor: receipt.cursor,
      envelopeId: envelopeId,
      eventCount: events.length,
    );
  }

  /// Pulls one page and commits envelopes one at a time. A rejected envelope
  /// never advances its sender sequence or the returned durable cursor.
  Future<SyncPullResult> pullPage({
    required OpaqueSyncCursor cursor,
    int limit = 100,
  }) async {
    if (limit <= 0 || limit > 1000) {
      return SyncPullResult(
        items: [SyncResult.rejected(SyncFailureReason.invalidPageLimit)],
        cursor: cursor,
        hasMore: false,
      );
    }
    late final SyncPage page;
    try {
      page = await _transport.pull(
        deviceId: deviceId,
        cursor: cursor,
        limit: limit,
      );
    } on Object {
      return SyncPullResult(
        items: [SyncResult.rejected(SyncFailureReason.transportFailed)],
        cursor: cursor,
        hasMore: false,
      );
    }
    if (page.envelopes.length > limit) {
      return SyncPullResult(
        items: [SyncResult.rejected(SyncFailureReason.pageResponseInvalid)],
        cursor: cursor,
        hasMore: false,
      );
    }
    final pageEnvelopeIds = <String>{};
    for (final envelope in page.envelopes) {
      if (!pageEnvelopeIds.add(envelope.envelopeId)) {
        return SyncPullResult(
          items: [
            SyncResult.rejected(
              SyncFailureReason.replayConflict,
              envelopeId: envelope.envelopeId,
            )
          ],
          cursor: cursor,
          hasMore: false,
        );
      }
    }
    final results = <SyncResult>[];
    final stagedLastReceived = Map<String, int>.of(_lastReceived);
    final stagedEnvelopeIds = <String>{};
    final stagedEvents = <EventEnvelope>[];
    for (final envelope in page.envelopes) {
      final item = await _prepareReceive(
        envelope,
        cursor,
        stagedLastReceived,
        stagedEnvelopeIds,
      );
      results.add(item.result);
      if (item.result.disposition == SyncDisposition.rejected) break;
      stagedEvents.addAll(item.events);
    }
    if (results.every(
      (result) => result.disposition != SyncDisposition.rejected,
    )) {
      try {
        if (stagedEvents.isNotEmpty) {
          await _eventStore.appendAll(stagedEvents);
        }
      } on Object {
        final failed = results.map((result) {
          if (result.disposition != SyncDisposition.applied) return result;
          return SyncResult.rejected(
            SyncFailureReason.appendFailed,
            envelopeId: result.envelopeId,
          );
        }).toList(growable: false);
        return SyncPullResult(
          items: failed,
          cursor: cursor,
          hasMore: page.hasMore,
        );
      }
      _lastReceived
        ..clear()
        ..addAll(stagedLastReceived);
      _acceptedEnvelopeIds.addAll(stagedEnvelopeIds);
      for (final envelope in page.envelopes) {
        if (stagedEnvelopeIds.contains(envelope.envelopeId)) {
          _acceptedEnvelopeRanges[envelope.envelopeId] = envelope.sequence;
        }
      }
    }
    final rejected =
        results.any((result) => result.disposition == SyncDisposition.rejected);
    final committedResults = rejected
        ? results.map((result) {
            if (result.disposition != SyncDisposition.applied) return result;
            return SyncResult.rejected(
              SyncFailureReason.batchNotCommitted,
              envelopeId: result.envelopeId,
            );
          }).toList(growable: false)
        : results;
    return SyncPullResult(
      items: committedResults,
      // A relay cursor represents the whole page. Never checkpoint it when an
      // envelope failed, even if earlier envelopes in that page committed.
      cursor: rejected ? cursor : page.cursor,
      hasMore: page.hasMore,
    );
  }

  Future<_PreparedReceive> _prepareReceive(
    EncryptedSyncEnvelope envelope,
    OpaqueSyncCursor durableCursor,
    Map<String, int> stagedLastReceived,
    Set<String> stagedEnvelopeIds,
  ) async {
    final rejection = _validateMetadata(envelope);
    if (rejection != null) {
      return _PreparedReceive.rejected(
        SyncResult.rejected(rejection, envelopeId: envelope.envelopeId),
      );
    }
    final acceptedRange = _acceptedEnvelopeRanges[envelope.envelopeId];
    if (acceptedRange != null &&
        (acceptedRange.first != envelope.sequence.first ||
            acceptedRange.last != envelope.sequence.last)) {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.replayConflict,
          envelopeId: envelope.envelopeId,
        ),
      );
    }
    final previous = stagedLastReceived[envelope.senderDeviceId] ?? -1;
    if (envelope.sequence.last <= previous) {
      final knownReplay = _acceptedEnvelopeIds.contains(envelope.envelopeId) ||
          stagedEnvelopeIds.contains(envelope.envelopeId);
      if (!knownReplay) {
        return _PreparedReceive.rejected(
          SyncResult.rejected(
            SyncFailureReason.sequenceOverlap,
            envelopeId: envelope.envelopeId,
          ),
        );
      }
      return _PreparedReceive.result(
        SyncResult.success(
          disposition: SyncDisposition.duplicate,
          cursor: durableCursor,
          envelopeId: envelope.envelopeId,
          eventCount: 0,
        ),
      );
    }
    if (envelope.sequence.first <= previous) {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.sequenceOverlap,
          envelopeId: envelope.envelopeId,
        ),
      );
    }
    if (envelope.sequence.first != previous + 1) {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.sequenceGap,
          envelopeId: envelope.envelopeId,
        ),
      );
    }

    Uint8List plaintext;
    try {
      plaintext = await _cryptography.open(
        payload: SealedSyncPayload(
          recipientEpoch: envelope.recipientEpoch,
          ciphertext: envelope.ciphertext,
          signature: envelope.signature,
        ),
        authenticatedMetadata: _metadata(
          envelopeId: envelope.envelopeId,
          senderDeviceId: envelope.senderDeviceId,
          sequence: envelope.sequence,
        ),
      );
    } on Object {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.cryptographyFailed,
          envelopeId: envelope.envelopeId,
        ),
      );
    }

    late final List<EventEnvelope> events;
    try {
      events = _decodePayload(plaintext);
    } on Object {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.payloadDecodeFailed,
          envelopeId: envelope.envelopeId,
        ),
      );
    } finally {
      _zeroize(plaintext);
    }
    if (events.length != envelope.sequence.count) {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.sequenceCountMismatch,
          envelopeId: envelope.envelopeId,
        ),
      );
    }
    if (events.any((event) => event.sensitivity == Sensitivity.d4)) {
      return _PreparedReceive.rejected(
        SyncResult.rejected(
          SyncFailureReason.d4SyncForbidden,
          envelopeId: envelope.envelopeId,
        ),
      );
    }
    stagedLastReceived[envelope.senderDeviceId] = envelope.sequence.last;
    stagedEnvelopeIds.add(envelope.envelopeId);
    return _PreparedReceive.events(
      SyncResult.success(
        disposition: SyncDisposition.applied,
        cursor: durableCursor,
        envelopeId: envelope.envelopeId,
        eventCount: events.length,
      ),
      events,
    );
  }

  String? _validateMetadata(EncryptedSyncEnvelope envelope) {
    if (envelope.envelopeId.trim().isEmpty) {
      return SyncFailureReason.invalidEnvelope;
    }
    if (envelope.protocolVersion != protocolVersion) {
      return SyncFailureReason.unsupportedProtocolVersion;
    }
    if (envelope.accountPseudonym != accountPseudonym) {
      return SyncFailureReason.accountMismatch;
    }
    if (!_trustedSenders.contains(envelope.senderDeviceId)) {
      return SyncFailureReason.unknownSender;
    }
    if (envelope.recipientEpoch != recipientEpoch) {
      return SyncFailureReason.epochMismatch;
    }
    return null;
  }

  Uint8List _metadata({
    required String envelopeId,
    required String senderDeviceId,
    required DeviceSequenceRange sequence,
  }) =>
      Uint8List.fromList(utf8.encode(jsonEncode(<String, Object>{
        'protocol_version': protocolVersion,
        'envelope_id': envelopeId,
        'account_pseudonym': accountPseudonym,
        'sender_device_id': senderDeviceId,
        'recipient_epoch': recipientEpoch,
        'sequence': sequence.toJson(),
      })));

  static List<EventEnvelope> _decodePayload(Uint8List plaintext) {
    final decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
    if (decoded is! Map<String, Object?> ||
        decoded.length != 2 ||
        decoded['payload_version'] != payloadVersion ||
        decoded['events'] is! List<Object?>) {
      throw const FormatException('invalid sync payload');
    }
    return (decoded['events']! as List<Object?>).map((value) {
      if (value is! Map<String, Object?>) {
        throw const FormatException('event must be an object');
      }
      return EventEnvelopeJsonCodec.decode(value);
    }).toList(growable: false);
  }

  static void _zeroize(Uint8List bytes) {
    try {
      bytes.fillRange(0, bytes.length, 0);
    } on Object {
      // Best effort: callers still must use a cryptographic adapter that owns
      // and clears any internal copies it creates.
    }
  }
}

final class _PreparedReceive {
  const _PreparedReceive(this.result, this.events);

  _PreparedReceive.result(SyncResult result)
      : this(result, const <EventEnvelope>[]);

  _PreparedReceive.rejected(SyncResult result)
      : this(result, const <EventEnvelope>[]);

  _PreparedReceive.events(SyncResult result, List<EventEnvelope> events)
      : this(result, events);

  final SyncResult result;
  final List<EventEnvelope> events;
}
