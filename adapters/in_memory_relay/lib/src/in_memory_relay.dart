import 'dart:typed_data';

import 'package:personal_os_sync_api/sync_api.dart';

/// Stable machine-readable relay rejection reasons.
abstract final class RelayRejectionReason {
  static const revokedDevice = 'revoked_device';
  static const unregisteredDevice = 'unregistered_device';
  static const accountMismatch = 'account_mismatch';
  static const cursorAccountMismatch = 'cursor_account_mismatch';
  static const registrationConflict = 'registration_conflict';
  static const invalidCursor = 'invalid_cursor';
  static const deviceMismatch = 'device_mismatch';
}

final class RelayRejected implements Exception {
  const RelayRejected(this.reasonCode);

  final String reasonCode;

  @override
  String toString() => 'RelayRejected($reasonCode)';
}

/// Transport-only observation. It deliberately carries no event semantics.
final class RelaySequenceGap {
  const RelaySequenceGap({
    required this.deviceId,
    required this.firstMissing,
    required this.lastMissing,
    required this.observedAtEnvelopeId,
  });

  final String deviceId;
  final int firstMissing;
  final int lastMissing;
  final String observedAtEnvelopeId;
}

/// Single-isolate relay that persists only encrypted sync envelopes.
///
/// This adapter cannot import domain or event packages. It does not decrypt,
/// inspect, classify, merge, or interpret ciphertext.
final class InMemoryRelay implements SyncPort {
  final List<EncryptedSyncEnvelope> _log = [];
  final Set<String> _seenEnvelopeKeys = {};
  final Map<String, int> _lastSequenceByDevice = {};
  final List<RelaySequenceGap> _gaps = [];
  final Set<String> _revokedDevices = {};
  final Map<String, String> _accountByDevice = {};
  final Map<String, _CursorPosition> _cursorPositions = {};
  final Map<String, OpaqueSyncCursor> _cursorsByPosition = {};
  int _nextCursorId = 1;

  @override
  Future<SyncPushReceipt> push({
    required String deviceId,
    required List<EncryptedSyncEnvelope> envelopes,
    required OpaqueSyncCursor cursor,
  }) async {
    final account = _accountFor(deviceId);
    if (_revokedDevices.contains(deviceId)) {
      throw const RelayRejected(RelayRejectionReason.revokedDevice);
    }
    _offsetFor(cursor, account);
    if (envelopes.any((item) => item.senderDeviceId != deviceId)) {
      throw const RelayRejected(RelayRejectionReason.deviceMismatch);
    }
    if (envelopes.any((item) => item.accountPseudonym != account)) {
      throw const RelayRejected(RelayRejectionReason.accountMismatch);
    }

    final acknowledgedIds = <String>[];
    for (final source in envelopes) {
      acknowledgedIds.add(source.envelopeId);
      final envelopeKey = '$account\u0000${source.envelopeId}';
      if (_seenEnvelopeKeys.contains(envelopeKey)) continue;

      final item = _copyEnvelope(source);
      final previous = _lastSequenceByDevice[deviceId] ?? -1;
      final gap = item.sequence.gapAfter(previous);
      if (gap != null) {
        _gaps.add(
          RelaySequenceGap(
            deviceId: deviceId,
            firstMissing: gap.firstMissing,
            lastMissing: gap.lastMissing,
            observedAtEnvelopeId: item.envelopeId,
          ),
        );
      }
      if (item.sequence.last > previous) {
        _lastSequenceByDevice[deviceId] = item.sequence.last;
      }
      _seenEnvelopeKeys.add(envelopeKey);
      _log.add(item);
    }

    return SyncPushReceipt(
      acceptedEnvelopeIds: acknowledgedIds,
      cursor: _cursorAt(account, _accountLog(account).length),
    );
  }

  @override
  Future<SyncPage> pull({
    required String deviceId,
    required OpaqueSyncCursor cursor,
    int limit = 100,
  }) async {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be greater than zero');
    }
    final account = _accountFor(deviceId);
    final accountLog = _accountLog(account);
    final offset = _offsetFor(cursor, account);
    final end = (offset + limit < accountLog.length)
        ? offset + limit
        : accountLog.length;
    final page = <EncryptedSyncEnvelope>[
      for (var index = offset; index < end; index++)
        _copyEnvelope(accountLog[index]),
    ];
    return SyncPage(
      envelopes: page,
      cursor: _cursorAt(account, end),
      hasMore: end < accountLog.length,
    );
  }

  /// Control-plane registration. The returned initial cursor is account-bound.
  OpaqueSyncCursor registerDevice({
    required String deviceId,
    required String accountPseudonym,
  }) {
    if (deviceId.isEmpty || accountPseudonym.isEmpty) {
      throw ArgumentError('registration values must not be empty');
    }
    final existing = _accountByDevice[deviceId];
    if (existing != null && existing != accountPseudonym) {
      throw const RelayRejected(RelayRejectionReason.registrationConflict);
    }
    _accountByDevice[deviceId] = accountPseudonym;
    return _cursorAt(accountPseudonym, 0);
  }

  /// Test/control-plane hook; revocation is fail-closed for subsequent pushes.
  void revokeDevice(String deviceId) {
    if (deviceId.isEmpty) throw ArgumentError('deviceId must not be empty');
    _revokedDevices.add(deviceId);
  }

  void restoreDeviceForTest(String deviceId) => _revokedDevices.remove(deviceId);

  bool isDeviceRevoked(String deviceId) => _revokedDevices.contains(deviceId);

  int get storedEnvelopeCount => _log.length;

  List<RelaySequenceGap> get observedSequenceGaps =>
      List<RelaySequenceGap>.unmodifiable(_gaps);

  String _accountFor(String deviceId) {
    final account = _accountByDevice[deviceId];
    if (account == null) {
      throw const RelayRejected(RelayRejectionReason.unregisteredDevice);
    }
    return account;
  }

  List<EncryptedSyncEnvelope> _accountLog(String account) => _log
      .where((item) => item.accountPseudonym == account)
      .toList(growable: false);

  int _offsetFor(OpaqueSyncCursor cursor, String account) {
    final position = _cursorPositions[cursor.encode()];
    if (position == null) {
      throw const RelayRejected(RelayRejectionReason.invalidCursor);
    }
    if (position.accountPseudonym != account) {
      throw const RelayRejected(RelayRejectionReason.cursorAccountMismatch);
    }
    if (position.offset > _accountLog(account).length) {
      throw const RelayRejected(RelayRejectionReason.invalidCursor);
    }
    return position.offset;
  }

  OpaqueSyncCursor _cursorAt(String account, int offset) {
    final key = '$account\u0000$offset';
    return _cursorsByPosition.putIfAbsent(key, () {
      final cursor = OpaqueSyncCursor('relay-${_nextCursorId++}');
      _cursorPositions[cursor.encode()] = _CursorPosition(account, offset);
      return cursor;
    });
  }

  static EncryptedSyncEnvelope _copyEnvelope(EncryptedSyncEnvelope source) =>
      EncryptedSyncEnvelope(
        protocolVersion: source.protocolVersion,
        envelopeId: source.envelopeId,
        accountPseudonym: source.accountPseudonym,
        senderDeviceId: source.senderDeviceId,
        recipientEpoch: source.recipientEpoch,
        sequence: DeviceSequenceRange(
          first: source.sequence.first,
          last: source.sequence.last,
        ),
        ciphertext: Uint8List.fromList(source.ciphertext),
        signature: Uint8List.fromList(source.signature),
      );
}

final class _CursorPosition {
  const _CursorPosition(this.accountPseudonym, this.offset);

  final String accountPseudonym;
  final int offset;
}
