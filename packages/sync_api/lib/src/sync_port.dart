import 'dart:convert';
import 'dart:typed_data';

/// Relay-facing transport boundary. Implementations treat envelopes as opaque.
abstract interface class SyncPort {
  Future<SyncPushReceipt> push({
    required String deviceId,
    required List<EncryptedSyncEnvelope> envelopes,
    required OpaqueSyncCursor cursor,
  });

  Future<SyncPage> pull({
    required String deviceId,
    required OpaqueSyncCursor cursor,
    int limit = 100,
  });
}

/// Trusted-device boundary used by a local SyncWorker to seal/open batches.
/// Event encoding and validation remain outside this port.
abstract interface class SyncCryptographyPort {
  Future<SealedSyncPayload> seal({
    required Uint8List trustedPlaintext,
    required String recipientEpoch,
    required Uint8List authenticatedMetadata,
  });

  Future<Uint8List> open({
    required SealedSyncPayload payload,
    required Uint8List authenticatedMetadata,
  });
}

final class OpaqueSyncCursor {
  OpaqueSyncCursor(String value) : _value = value {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
  }

  factory OpaqueSyncCursor.initial() => OpaqueSyncCursor('initial');
  final String _value;
  String encode() => _value;

  @override
  String toString() => 'OpaqueSyncCursor(<redacted>)';
  @override
  bool operator ==(Object other) =>
      other is OpaqueSyncCursor && other._value == _value;
  @override
  int get hashCode => _value.hashCode;
}

final class DeviceSequenceRange {
  DeviceSequenceRange({required this.first, required this.last}) {
    if (first < 0) throw RangeError.range(first, 0, null, 'first');
    if (last < first) throw RangeError.range(last, first, null, 'last');
  }
  final int first;
  final int last;
  int get count => last - first + 1;

  SequenceGap? gapAfter(int previouslyReceived) {
    if (previouslyReceived < -1) {
      throw RangeError.range(previouslyReceived, -1, null, 'previouslyReceived');
    }
    final expected = previouslyReceived + 1;
    return first > expected
        ? SequenceGap(firstMissing: expected, lastMissing: first - 1)
        : null;
  }

  Map<String, Object> toJson() => {'first': first, 'last': last};
}

final class SequenceGap {
  SequenceGap({required this.firstMissing, required this.lastMissing}) {
    if (firstMissing < 0 || lastMissing < firstMissing) {
      throw ArgumentError('invalid missing sequence range');
    }
  }
  final int firstMissing;
  final int lastMissing;
}

final class EncryptedSyncEnvelope {
  EncryptedSyncEnvelope({
    required this.protocolVersion,
    required this.envelopeId,
    required this.accountPseudonym,
    required this.senderDeviceId,
    required this.recipientEpoch,
    required this.sequence,
    required Uint8List ciphertext,
    required Uint8List signature,
  })  : _ciphertext = Uint8List.fromList(ciphertext),
        _signature = Uint8List.fromList(signature) {
    if (protocolVersion <= 0) {
      throw RangeError.range(protocolVersion, 1, null, 'protocolVersion');
    }
    for (final value in [
      envelopeId,
      accountPseudonym,
      senderDeviceId,
      recipientEpoch,
    ]) {
      if (value.isEmpty) throw ArgumentError('metadata must not be empty');
    }
    if (_ciphertext.isEmpty) throw ArgumentError('ciphertext must not be empty');
    if (_signature.isEmpty) throw ArgumentError('signature must not be empty');
  }

  final int protocolVersion;
  final String envelopeId;
  final String accountPseudonym;
  final String senderDeviceId;
  final String recipientEpoch;
  final DeviceSequenceRange sequence;
  final Uint8List _ciphertext;
  final Uint8List _signature;
  int get ciphertextLength => _ciphertext.length;
  Uint8List get ciphertext => Uint8List.fromList(_ciphertext);
  Uint8List get signature => Uint8List.fromList(_signature);

  Map<String, Object> toJson() => {
        'protocol_version': protocolVersion,
        'envelope_id': envelopeId,
        'account_pseudonym': accountPseudonym,
        'sender_device_id': senderDeviceId,
        'recipient_epoch': recipientEpoch,
        'sequence': sequence.toJson(),
        'ciphertext_length': ciphertextLength,
        'ciphertext': base64Encode(_ciphertext),
        'signature': base64Encode(_signature),
      };

  @override
  String toString() => 'EncryptedSyncEnvelope('
      'protocolVersion: $protocolVersion, envelopeId: $envelopeId, '
      'senderDeviceId: $senderDeviceId, recipientEpoch: $recipientEpoch, '
      'sequence: ${sequence.first}-${sequence.last}, '
      'ciphertext: <${_ciphertext.length} bytes>, signature: <redacted>)';
}

final class SealedSyncPayload {
  SealedSyncPayload({
    required this.recipientEpoch,
    required Uint8List ciphertext,
    required Uint8List signature,
  })
      : _ciphertext = Uint8List.fromList(ciphertext),
        _signature = Uint8List.fromList(signature);
  final String recipientEpoch;
  final Uint8List _ciphertext;
  final Uint8List _signature;
  Uint8List get ciphertext => Uint8List.fromList(_ciphertext);
  Uint8List get signature => Uint8List.fromList(_signature);
}

final class SyncPushReceipt {
  SyncPushReceipt({
    required List<String> acceptedEnvelopeIds,
    required this.cursor,
  })
      : acceptedEnvelopeIds = List.unmodifiable(acceptedEnvelopeIds);
  final List<String> acceptedEnvelopeIds;
  final OpaqueSyncCursor cursor;
}

final class SyncPage {
  SyncPage({
    required List<EncryptedSyncEnvelope> envelopes,
    required this.cursor,
    required this.hasMore,
  }) : envelopes = List.unmodifiable(envelopes);
  final List<EncryptedSyncEnvelope> envelopes;
  final OpaqueSyncCursor cursor;
  final bool hasMore;
}
