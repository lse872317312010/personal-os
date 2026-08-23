/// Driver-neutral SQLite/SQLCipher schema contract for Personal OS.
library;

final class SqliteVaultSchema {
  const SqliteVaultSchema._();

  static const int version = 1;
  static const String migrationAsset = 'migrations/0001_vault_schema.sql';

  static const Set<String> persistedSensitivities = <String>{
    'D0',
    'D1',
    'D2',
    'D3',
  };

  static const Set<String> tables = <String>{
    'schema_metadata',
    'event_log',
    'event_subjects',
    'projections',
    'outbox',
    'blob_metadata',
    'consent_revisions',
    'deletion_tombstones',
    'deletion_propagation_log',
  };

  /// Lossless subject-reference fields. Ordinal preserves the primary-subject
  /// position used by the reducer; revision preserves pinned references.
  static const Set<String> eventSubjectColumns = <String>{
    'event_id',
    'subject_type',
    'subject_id',
    'subject_revision',
    'subject_ordinal',
  };

  /// Column/key names rejected before any map is serialized for persistence.
  /// Values are normalized by removing `_` and `-` and lower-casing.
  static const Set<String> forbiddenSecretFields = <String>{
    'rawkey',
    'databasekey',
    'encryptionkey',
    'wrappingkey',
    'privatekey',
    'recoverycode',
    'recoverysecret',
    'apikey',
    'password',
    'accesstoken',
    'refreshtoken',
    'targetiddigest',
    'targetidhash',
    'targetdigest',
    'targethash',
    'objectiddigest',
    'objectidhash',
    'deletedidentifierdigest',
    'deletedidentifierhash',
    'contentdigest',
    'contenthash',
    'plaintextdigest',
    'plaintexthash',
    'subjecthash',
    'subjectdigest',
  };

  /// Ordered write shape required for one atomic append transaction.
  /// The future driver binds parameters and repeats subject rows as needed.
  static const List<String> atomicAppendStatements = <String>[
    'INSERT INTO event_log',
    'INSERT INTO event_subjects',
    'INSERT INTO projections',
    'INSERT INTO outbox',
  ];
}

final class VaultPersistenceValidator {
  const VaultPersistenceValidator._();

  static void validateSensitivity(String sensitivity) {
    if (!SqliteVaultSchema.persistedSensitivities.contains(sensitivity)) {
      throw VaultSchemaViolation(
          'Sensitivity $sensitivity cannot be persisted');
    }
  }

  /// Rejects secret-looking field names recursively before JSON encoding.
  /// This is defense in depth; callers must still pass typed, policy-approved
  /// payloads rather than arbitrary user maps.
  static void rejectForbiddenSecretFields(Object? value, [String path = r'$']) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final normalized = key.replaceAll(RegExp('[_-]'), '').toLowerCase();
        if (SqliteVaultSchema.forbiddenSecretFields.contains(normalized)) {
          throw VaultSchemaViolation('Forbidden secret field at $path.$key');
        }
        rejectForbiddenSecretFields(entry.value, '$path.$key');
      }
    } else if (value is Iterable) {
      var index = 0;
      for (final item in value) {
        rejectForbiddenSecretFields(item, '$path[$index]');
        index += 1;
      }
    }
  }
}

final class VaultSchemaViolation implements Exception {
  const VaultSchemaViolation(this.message);

  final String message;

  @override
  String toString() => 'VaultSchemaViolation: $message';
}
