import 'dart:convert';
import 'dart:typed_data';

import 'package:personal_os_sync_api/sync_api.dart';
import 'package:test/test.dart';

void main() {
  EncryptedSyncEnvelope envelope({Uint8List? ciphertext}) =>
      EncryptedSyncEnvelope(
        protocolVersion: 1,
        envelopeId: 'env-1',
        accountPseudonym: 'account-pseudo',
        senderDeviceId: 'device-a',
        recipientEpoch: 'epoch-2',
        sequence: DeviceSequenceRange(first: 4, last: 6),
        ciphertext: ciphertext ?? Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList([7, 8]),
      );

  test('wire JSON exposes only allowlisted relay fields', () {
    final json = envelope().toJson();
    expect(
      json.keys,
      unorderedEquals([
        'protocol_version',
        'envelope_id',
        'account_pseudonym',
        'sender_device_id',
        'recipient_epoch',
        'sequence',
        'ciphertext_length',
        'ciphertext',
        'signature',
      ]),
    );
    final encoded = jsonEncode(json).toLowerCase();
    for (final forbidden in [
      'event_type',
      'object_id',
      'sensitivity',
      'consent',
      'payload',
    ]) {
      expect(encoded, isNot(contains(forbidden)));
    }
  });

  test('diagnostics redact cursor, ciphertext, and signature', () {
    final item =
        envelope(ciphertext: Uint8List.fromList(utf8.encode('secret')));
    expect(item.toString(), isNot(contains('secret')));
    expect(
        item.toString(), isNot(contains(base64Encode(utf8.encode('secret')))));
    expect(item.toString(), contains('<6 bytes>'));
    expect(
      OpaqueSyncCursor('private-cursor').toString(),
      isNot(contains('private-cursor')),
    );
  });

  test('cursor and sequence rules are enforced', () {
    expect(() => OpaqueSyncCursor(''), throwsArgumentError);
    expect(OpaqueSyncCursor('next').encode(), 'next');
    expect(() => DeviceSequenceRange(first: -1, last: 0), throwsRangeError);
    expect(() => DeviceSequenceRange(first: 5, last: 4), throwsRangeError);
    final range = DeviceSequenceRange(first: 4, last: 6);
    expect(range.count, 3);
    expect(range.gapAfter(1)?.firstMissing, 2);
    expect(range.gapAfter(1)?.lastMissing, 3);
    expect(range.gapAfter(3), isNull);
    expect(range.gapAfter(5), isNull);
  });

  test('buffers and result collections use defensive copies', () {
    final source = Uint8List.fromList([1, 2, 3]);
    final item = envelope(ciphertext: source);
    source[0] = 9;
    expect(item.ciphertext, [1, 2, 3]);
    final returned = item.ciphertext;
    returned[1] = 9;
    expect(item.ciphertext, [1, 2, 3]);
    final sourceItems = [item];
    final page = SyncPage(
      envelopes: sourceItems,
      cursor: OpaqueSyncCursor('next'),
      hasMore: false,
    );
    sourceItems.clear();
    expect(page.envelopes, hasLength(1));
    expect(() => page.envelopes.clear(), throwsUnsupportedError);
    final ids = ['env-1'];
    final receipt = SyncPushReceipt(
      acceptedEnvelopeIds: ids,
      cursor: OpaqueSyncCursor('next'),
    );
    ids.clear();
    expect(receipt.acceptedEnvelopeIds, ['env-1']);
  });
}
