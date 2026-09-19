import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

enum EncryptedBackupStatus { idle, running, succeeded, cancelled, failed }

enum EncryptedBackupAction { export, restore }

final class EncryptedBackupException implements Exception {
  const EncryptedBackupException(this.code);

  final String code;

  @override
  String toString() => 'EncryptedBackupException($code)';
}

abstract interface class EncryptedEventBackupPort {
  bool get available;

  Future<bool> exportEncryptedArchive({
    required String archiveJson,
    required String suggestedName,
  });

  /// Returns null when the system picker or native passphrase prompt is
  /// cancelled. Otherwise returns authenticated plaintext held only in memory.
  Future<String?> importEncryptedArchive();
}

final class MethodChannelEncryptedEventBackupPort
    implements EncryptedEventBackupPort {
  MethodChannelEncryptedEventBackupPort({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('personal_os/internal/event_backup');

  final MethodChannel _channel;

  @override
  bool get available => true;

  @override
  Future<bool> exportEncryptedArchive({
    required String archiveJson,
    required String suggestedName,
  }) async {
    final response = await _invoke(
      'exportEncryptedArchive',
      <String, Object?>{
        'archiveJson': archiveJson,
        'suggestedName': suggestedName,
      },
    );
    return switch (response['status']) {
      'completed' => true,
      'cancelled' => false,
      _ => throw const EncryptedBackupException('backup.invalid_response'),
    };
  }

  @override
  Future<String?> importEncryptedArchive() async {
    final response = await _invoke(
      'importEncryptedArchive',
      const <String, Object?>{},
    );
    return switch (response['status']) {
      'cancelled' => null,
      'completed' when response['archiveJson'] is String =>
        response['archiveJson']! as String,
      _ => throw const EncryptedBackupException('backup.invalid_response'),
    };
  }

  Future<Map<String, Object?>> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      if (raw is! Map) {
        throw const EncryptedBackupException('backup.invalid_response');
      }
      return <String, Object?>{
        for (final entry in raw.entries) entry.key.toString(): entry.value,
      };
    } on PlatformException catch (error) {
      throw EncryptedBackupException(
        _nativeFailureCodes.contains(error.code)
            ? error.code
            : 'backup.unavailable',
      );
    } on MissingPluginException {
      throw const EncryptedBackupException('backup.unavailable');
    }
  }

  static const _nativeFailureCodes = <String>{
    'backup.busy',
    'backup.vault_locked',
    'backup.invalid_request',
    'backup.too_large',
    'backup.unsupported_format',
    'backup.authentication_failed',
    'backup.crypto_failed',
    'backup.io_failed',
    'backup.unavailable',
  };
}

final class UnavailableEncryptedEventBackupPort
    implements EncryptedEventBackupPort {
  const UnavailableEncryptedEventBackupPort();

  @override
  bool get available => false;

  @override
  Future<bool> exportEncryptedArchive({
    required String archiveJson,
    required String suggestedName,
  }) {
    throw const EncryptedBackupException('backup.unavailable');
  }

  @override
  Future<String?> importEncryptedArchive() {
    throw const EncryptedBackupException('backup.unavailable');
  }
}

final class EncryptedEventBackupController extends ChangeNotifier {
  EncryptedEventBackupController({
    required EventStore eventStore,
    required EncryptedEventBackupPort port,
    required EntityId profileId,
    VoidCallback? onRestoreCompleted,
  })  : _historyReader = eventStore is CompleteProfileHistoryReader
            ? eventStore
            : null,
        _restore = EventArchiveRestoreService(eventStore: eventStore),
        _port = port,
        _profileId = profileId,
        _onRestoreCompleted = onRestoreCompleted;

  final CompleteProfileHistoryReader? _historyReader;
  final EventArchiveRestoreService _restore;
  final EncryptedEventBackupPort _port;
  final EntityId _profileId;
  final VoidCallback? _onRestoreCompleted;

  EncryptedBackupStatus _status = EncryptedBackupStatus.idle;
  EncryptedBackupAction? _action;
  String? _errorCode;
  int? _lastEventCount;
  int _epoch = 0;

  bool get available => _port.available && _historyReader != null;
  bool get running => _status == EncryptedBackupStatus.running;
  EncryptedBackupStatus get status => _status;
  EncryptedBackupAction? get action => _action;
  String? get errorCode => _errorCode;
  int? get lastEventCount => _lastEventCount;

  Future<void> exportBackup() async {
    if (!_begin(EncryptedBackupAction.export)) return;
    final operation = _epoch;
    try {
      final events =
          await _historyReader!.readCompleteProfileHistory(_profileId);
      if (events.isEmpty) {
        throw const EncryptedBackupException('backup.empty');
      }
      EventExportRequest(
        events: events,
        policy: EventExportPolicy(maxSensitivity: Sensitivity.d3),
      );
      final completed = await _port.exportEncryptedArchive(
        archiveJson: EventArchiveCodec.encode(events),
        suggestedName: _suggestedName(DateTime.now().toUtc()),
      );
      if (operation != _epoch) return;
      _lastEventCount = completed ? events.length : null;
      _status = completed
          ? EncryptedBackupStatus.succeeded
          : EncryptedBackupStatus.cancelled;
    } on EventExportDenied {
      if (operation != _epoch) return;
      _fail('backup.export_denied');
    } on EncryptedBackupException catch (error) {
      if (operation != _epoch) return;
      _fail(error.code);
    } on PersistenceException {
      if (operation != _epoch) return;
      _fail('backup.storage_failed');
    } on Object {
      if (operation != _epoch) return;
      _fail('backup.unavailable');
    }
    if (operation == _epoch) notifyListeners();
  }

  Future<void> restoreBackup() async {
    if (!_begin(EncryptedBackupAction.restore)) return;
    final operation = _epoch;
    try {
      final archiveJson = await _port.importEncryptedArchive();
      if (operation != _epoch) return;
      if (archiveJson == null) {
        _status = EncryptedBackupStatus.cancelled;
        notifyListeners();
        return;
      }
      final restored = await _restore.restore(archiveJson);
      if (operation != _epoch) return;
      _lastEventCount = restored.eventCount;
      _status = EncryptedBackupStatus.succeeded;
      notifyListeners();
      _onRestoreCompleted?.call();
      return;
    } on EventArchiveException {
      if (operation != _epoch) return;
      _fail('backup.archive_invalid');
    } on EncryptedBackupException catch (error) {
      if (operation != _epoch) return;
      _fail(error.code);
    } on PersistenceException {
      if (operation != _epoch) return;
      _fail('backup.restore_conflict');
    } on Object {
      if (operation != _epoch) return;
      _fail('backup.unavailable');
    }
    if (operation == _epoch) notifyListeners();
  }

  void reset() {
    _epoch += 1;
    _status = EncryptedBackupStatus.idle;
    _action = null;
    _errorCode = null;
    _lastEventCount = null;
    notifyListeners();
  }

  bool _begin(EncryptedBackupAction nextAction) {
    if (running) return false;
    if (!available) {
      _status = EncryptedBackupStatus.failed;
      _action = nextAction;
      _errorCode = 'backup.unavailable';
      notifyListeners();
      return false;
    }
    _epoch += 1;
    _status = EncryptedBackupStatus.running;
    _action = nextAction;
    _errorCode = null;
    _lastEventCount = null;
    notifyListeners();
    return true;
  }

  void _fail(String code) {
    _status = EncryptedBackupStatus.failed;
    _errorCode = code;
  }

  static String _suggestedName(DateTime now) =>
      'personal-os-${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}.posb';
}
