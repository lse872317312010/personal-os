import 'package:personal_os_sqlite_vault_schema/sqlite_vault_schema.dart';
import 'package:test/test.dart';

void main() {
  test('schema v1 exposes all required tables', () {
    expect(SqliteVaultSchema.version, 1);
    expect(
      SqliteVaultSchema.tables,
      containsAll(<String>{
        'event_log',
        'event_subjects',
        'projections',
        'outbox',
        'blob_metadata',
        'consent_revisions',
        'schema_metadata',
        'deletion_tombstones',
        'deletion_propagation_log',
      }),
    );
  });

  test('D4 is rejected at the persistence boundary', () {
    expect(
      () => VaultPersistenceValidator.validateSensitivity('D4'),
      throwsA(isA<VaultSchemaViolation>()),
    );
    for (final sensitivity in <String>['D0', 'D1', 'D2', 'D3']) {
      expect(
        () => VaultPersistenceValidator.validateSensitivity(sensitivity),
        returnsNormally,
      );
    }
  });

  test('subject index preserves pinned revision and reducer order', () {
    expect(
      SqliteVaultSchema.eventSubjectColumns,
      containsAll(<String>{'subject_revision', 'subject_ordinal'}),
    );
  });

  test('raw key fields are rejected recursively', () {
    expect(
      () => VaultPersistenceValidator.rejectForbiddenSecretFields(
        <String, Object?>{
          'safe': <Object?>[
            <String, Object?>{'private_key': 'must-not-persist'},
          ],
        },
      ),
      throwsA(isA<VaultSchemaViolation>()),
    );
  });

  test('linkable deletion and plaintext digest fields are rejected', () {
    for (final field in <String>[
      'target_id_digest',
      'target_id_hash',
      'target_digest',
      'target_hash',
      'object_id_hash',
      'deleted_identifier_digest',
      'content_digest',
      'plaintext_hash',
    ]) {
      expect(
        () => VaultPersistenceValidator.rejectForbiddenSecretFields(
          <String, Object?>{field: 'linkable-value'},
        ),
        throwsA(isA<VaultSchemaViolation>()),
      );
    }
  });

  test('ciphertext digest and random target token field names are allowed', () {
    expect(
      () => VaultPersistenceValidator.rejectForbiddenSecretFields(
        <String, Object?>{
          'ciphertext_digest': 'digest-of-ciphertext',
          'target_token': 'random-opaque-token',
        },
      ),
      returnsNormally,
    );
  });

  test('ordinary typed payload shape passes secret field validation', () {
    expect(
      () => VaultPersistenceValidator.rejectForbiddenSecretFields(
        <String, Object?>{
          'claim_id': 'claim-1',
          'confidence': 0.8,
          'evidence_refs': <String>['blob-1'],
        },
      ),
      returnsNormally,
    );
  });

  test('atomic append contract includes all write stages in order', () {
    expect(SqliteVaultSchema.atomicAppendStatements, <String>[
      'INSERT INTO event_log',
      'INSERT INTO event_subjects',
      'INSERT INTO projections',
      'INSERT INTO outbox',
    ]);
  });
}
