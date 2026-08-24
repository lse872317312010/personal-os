import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:personal_os_in_memory_relay/in_memory_relay.dart';
import 'package:personal_os_sync_api/sync_api.dart';
import 'package:test/test.dart';

void main() {
  EncryptedSyncEnvelope envelope({
    required String id,
    required int first,
    int? last,
    String deviceId = 'redmi-turbo',
    String account = 'opaque-account',
    Uint8List? ciphertext,
  }) =>
      EncryptedSyncEnvelope(
        protocolVersion: 1,
        envelopeId: id,
        accountPseudonym: account,
        senderDeviceId: deviceId,
        recipientEpoch: 'epoch-1',
        sequence: DeviceSequenceRange(first: first, last: last ?? first),
        ciphertext: ciphertext ?? Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList([7, 8]),
      );

  test('envelope id is idempotent and bytes are copied defensively', () async {
    final relay = InMemoryRelay();
    final initial = relay.registerDevice(
      deviceId: 'redmi-turbo',
      accountPseudonym: 'opaque-account',
    );
    relay.registerDevice(
      deviceId: 'windows-home',
      accountPseudonym: 'opaque-account',
    );
    final bytes = Uint8List.fromList(utf8.encode('sealed-value'));
    final item = envelope(id: 'env-1', first: 0, ciphertext: bytes);
    final first = await relay.push(
      deviceId: 'redmi-turbo',
      envelopes: [item],
      cursor: initial,
    );
    bytes.fillRange(0, bytes.length, 0);
    final duplicate = await relay.push(
      deviceId: 'redmi-turbo',
      envelopes: [item],
      cursor: first.cursor,
    );
    expect(duplicate.acceptedEnvelopeIds, ['env-1']);
    expect(relay.storedEnvelopeCount, 1);

    final page = await relay.pull(
      deviceId: 'windows-home',
      cursor: initial,
    );
    expect(utf8.decode(page.envelopes.single.ciphertext), 'sealed-value');
    final returned = page.envelopes.single.ciphertext;
    returned[0] = 0;
    final again = await relay.pull(
      deviceId: 'windows-home',
      cursor: initial,
    );
    expect(utf8.decode(again.envelopes.single.ciphertext), 'sealed-value');
    expect(identical(item, page.envelopes.single), isFalse);
  });

  test('opaque cursor paginates without exposing an offset contract', () async {
    final relay = InMemoryRelay();
    final initial = relay.registerDevice(
      deviceId: 'redmi-turbo',
      accountPseudonym: 'opaque-account',
    );
    relay.registerDevice(
      deviceId: 'windows-home',
      accountPseudonym: 'opaque-account',
    );
    await relay.push(
      deviceId: 'redmi-turbo',
      envelopes: [
        envelope(id: 'env-1', first: 0),
        envelope(id: 'env-2', first: 1),
        envelope(id: 'env-3', first: 2),
      ],
      cursor: initial,
    );
    final first = await relay.pull(
      deviceId: 'windows-home',
      cursor: initial,
      limit: 2,
    );
    expect(first.envelopes.map((item) => item.envelopeId), ['env-1', 'env-2']);
    expect(first.hasMore, isTrue);
    expect(first.cursor.toString(), isNot(contains(first.cursor.encode())));
    final second = await relay.pull(
      deviceId: 'windows-home',
      cursor: first.cursor,
      limit: 2,
    );
    expect(second.envelopes.single.envelopeId, 'env-3');
    expect(second.hasMore, isFalse);
    await expectLater(
      relay.pull(
        deviceId: 'windows-home',
        cursor: OpaqueSyncCursor('forged'),
      ),
      throwsA(
        isA<RelayRejected>().having(
          (error) => error.reasonCode,
          'reasonCode',
          RelayRejectionReason.invalidCursor,
        ),
      ),
    );
  });

  test('sequence gaps are observable transport facts only', () async {
    final relay = InMemoryRelay();
    final initial = relay.registerDevice(
      deviceId: 'redmi-turbo',
      accountPseudonym: 'opaque-account',
    );
    await relay.push(
      deviceId: 'redmi-turbo',
      envelopes: [
        envelope(id: 'env-1', first: 0),
        envelope(id: 'env-2', first: 3, last: 4),
      ],
      cursor: initial,
    );
    final gap = relay.observedSequenceGaps.single;
    expect(gap.deviceId, 'redmi-turbo');
    expect(gap.firstMissing, 1);
    expect(gap.lastMissing, 2);
    expect(gap.observedAtEnvelopeId, 'env-2');
    expect(() => relay.observedSequenceGaps.clear(), throwsUnsupportedError);
  });

  test('revoked sender is rejected before a new envelope is stored', () async {
    final relay = InMemoryRelay();
    final initial = relay.registerDevice(
      deviceId: 'redmi-turbo',
      accountPseudonym: 'opaque-account',
    );
    relay.revokeDevice('redmi-turbo');
    await expectLater(
      relay.push(
        deviceId: 'redmi-turbo',
        envelopes: [envelope(id: 'env-1', first: 0)],
        cursor: initial,
      ),
      throwsA(
        isA<RelayRejected>().having(
          (error) => error.reasonCode,
          'reasonCode',
          RelayRejectionReason.revokedDevice,
        ),
      ),
    );
    expect(relay.storedEnvelopeCount, 0);
  });

  test('sender identity mismatch rejects the whole push', () async {
    final relay = InMemoryRelay();
    final initial = relay.registerDevice(
      deviceId: 'redmi-turbo',
      accountPseudonym: 'opaque-account',
    );
    await expectLater(
      relay.push(
        deviceId: 'redmi-turbo',
        envelopes: [envelope(id: 'env-1', first: 0, deviceId: 'other')],
        cursor: initial,
      ),
      throwsA(isA<RelayRejected>()),
    );
    expect(relay.storedEnvelopeCount, 0);
  });

  test('accounts have isolated logs and account-bound cursors', () async {
    final relay = InMemoryRelay();
    final alphaCursor = relay.registerDevice(
      deviceId: 'alpha-phone',
      accountPseudonym: 'account-alpha',
    );
    final betaCursor = relay.registerDevice(
      deviceId: 'beta-phone',
      accountPseudonym: 'account-beta',
    );
    await relay.push(
      deviceId: 'alpha-phone',
      envelopes: [
        envelope(
          id: 'shared-id',
          first: 0,
          deviceId: 'alpha-phone',
          account: 'account-alpha',
        ),
      ],
      cursor: alphaCursor,
    );
    await relay.push(
      deviceId: 'beta-phone',
      envelopes: [
        envelope(
          id: 'shared-id',
          first: 0,
          deviceId: 'beta-phone',
          account: 'account-beta',
        ),
      ],
      cursor: betaCursor,
    );

    final alphaPage = await relay.pull(
      deviceId: 'alpha-phone',
      cursor: alphaCursor,
    );
    expect(alphaPage.envelopes.map((item) => item.envelopeId), ['shared-id']);
    final betaPage = await relay.pull(
      deviceId: 'beta-phone',
      cursor: betaCursor,
    );
    expect(betaPage.envelopes.map((item) => item.envelopeId), ['shared-id']);
    expect(relay.storedEnvelopeCount, 2);
    await expectLater(
      relay.pull(deviceId: 'beta-phone', cursor: alphaPage.cursor),
      throwsA(
        isA<RelayRejected>().having(
          (error) => error.reasonCode,
          'reasonCode',
          RelayRejectionReason.cursorAccountMismatch,
        ),
      ),
    );
  });

  test('unregistered and account-mismatched pushes fail closed', () async {
    final relay = InMemoryRelay();
    await expectLater(
      relay.push(
        deviceId: 'unknown',
        envelopes: [envelope(id: 'env-0', first: 0, deviceId: 'unknown')],
        cursor: OpaqueSyncCursor.initial(),
      ),
      throwsA(
        isA<RelayRejected>().having(
          (error) => error.reasonCode,
          'reasonCode',
          RelayRejectionReason.unregisteredDevice,
        ),
      ),
    );
    final initial = relay.registerDevice(
      deviceId: 'redmi-turbo',
      accountPseudonym: 'account-alpha',
    );
    await expectLater(
      relay.push(
        deviceId: 'redmi-turbo',
        envelopes: [
          envelope(id: 'env-1', first: 0, account: 'account-beta'),
        ],
        cursor: initial,
      ),
      throwsA(
        isA<RelayRejected>().having(
          (error) => error.reasonCode,
          'reasonCode',
          RelayRejectionReason.accountMismatch,
        ),
      ),
    );
    expect(relay.storedEnvelopeCount, 0);
  });

  test('package boundary has no event/domain dependency or business schema', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final implementation = File(
      'lib/src/in_memory_relay.dart',
    ).readAsStringSync();
    expect(pubspec, isNot(contains('personal_os_' 'events')));
    expect(pubspec, isNot(contains('personal_os_' 'domain')));
    expect(implementation, isNot(contains('Event' 'Envelope')));
    for (final forbidden in [
      'event_' 'type',
      'object_' 'id',
      'sensitivity',
      'consent',
      'appearance_' 'analysis',
    ]) {
      expect(implementation.toLowerCase(), isNot(contains(forbidden)));
    }
  });
}
