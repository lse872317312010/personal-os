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
    'databasepath',
    'sqlcipherkey',
    'keystorealias',
    'keyalias',
    'rawexception',
    'stacktrace',
    'plaintextbytes',
    'originalbytes',
  };

  /// Ordered write shape required for one atomic append transaction.
  /// The future driver binds parameters and repeats subject rows as needed.
  static const List<String> atomicAppendStatements = <String>[
    'INSERT INTO event_log',
    'INSERT INTO event_subjects',
    'INSERT INTO projections',
    'INSERT INTO outbox',
  ];

  /// Deletion targets are deliberately opaque transport tokens.  They may be
  /// random URL-safe identifiers, but may not contain paths, SQL, or semantic
  /// separators that make them useful as a copied object identifier.
  static void validateDeletionTargetToken(String token) {
    final value = token.trim();
    if (token != value ||
        value.length < 22 ||
        value.contains(RegExp(r'[^A-Za-z0-9_-]'))) {
      throw const VaultSchemaViolation();
    }
  }
}

final class VaultPersistenceValidator {
  const VaultPersistenceValidator._();

  static void validateSensitivity(String sensitivity) {
    if (!SqliteVaultSchema.persistedSensitivities.contains(sensitivity)) {
      throw const VaultSchemaViolation();
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
          throw const VaultSchemaViolation();
        }
        if ((normalized == 'sensitivity' ||
                normalized == 'maximumsensitivity') &&
            entry.value.toString().toUpperCase() == 'D4') {
          throw const VaultSchemaViolation.d4();
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

final class VaultSchemaViolation extends PersistenceException {
  const VaultSchemaViolation() : super.schemaViolation();

  const VaultSchemaViolation.d4() : super.d4PersistenceForbidden();
}
