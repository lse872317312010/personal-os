import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('stable errors expose code and fixed safe message only', () {
    const error = PersistenceException.d4PersistenceForbidden();

    expect(error.code, PersistenceErrorCode.d4PersistenceForbidden);
    expect(error.safeMessage, 'This data cannot be persisted by policy.');
    expect(error.toString(), 'PersistenceException(persistence.d4_forbidden)');
  });

  test('event conflict never carries adapter detail across the boundary', () {
    final error = EventAppendConflict('event_id collision: secret-event-id');

    expect(error.code, PersistenceErrorCode.eventConflict);
    expect(error.message, 'event_conflict');
    expect(error.safeMessage, contains('conflicts'));
    expect(error.toString(), isNot(contains('secret-event-id')));
  });

  test('revision conflicts retain stable legacy reason for compatibility', () {
    final error = EventAppendConflict('revision_conflict');

    expect(error.code, PersistenceErrorCode.revisionConflict);
    expect(error.message, 'revision_conflict');
    expect(error.safeMessage, contains('latest state'));
  });
}
