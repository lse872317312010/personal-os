import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  group('DeleteGuard (Wave 17b)', () {
    test('canDelete is false on fresh state', () {
      final guard = DeleteGuard();
      expect(guard.canDelete, isFalse);
      expect(guard.typedConfirm, isEmpty);
      expect(guard.checklist, <bool>[false, false, false]);
    });

    test('all 3 checks + DELETE → canDelete true', () {
      final guard = DeleteGuard();
      guard.toggleChecklist(0, true);
      guard.toggleChecklist(1, true);
      guard.toggleChecklist(2, true);
      guard.setTypedConfirm('DELETE');
      expect(guard.canDelete, isTrue);
      expect(guard.blockers, isEmpty);
    });

    test('missing one checklist item → still blocked', () {
      final guard = DeleteGuard();
      guard.toggleChecklist(0, true);
      guard.toggleChecklist(2, true);
      guard.setTypedConfirm('DELETE');
      expect(guard.canDelete, isFalse);
      expect(guard.blockers.length, 1);
      expect(guard.blockers.first.code, 'checklist_1');
    });

    test('typed confirm wrong → blocked', () {
      final guard = DeleteGuard();
      guard.toggleChecklist(0, true);
      guard.toggleChecklist(1, true);
      guard.toggleChecklist(2, true);
      guard.setTypedConfirm('delete'); // lowercase
      expect(guard.canDelete, isFalse);
      expect(
          guard.blockers.any((b) => b.code == 'typed_confirm_mismatch'), isTrue);
    });

    test('can un-toggle checklist items', () {
      final guard = DeleteGuard();
      guard.toggleChecklist(0, true);
      expect(guard.checklist[0], isTrue);
      guard.toggleChecklist(0, false);
      expect(guard.checklist[0], isFalse);
    });

    test('blockers list reflects all 4 missing items', () {
      final guard = DeleteGuard();
      // nothing set
      final blockers = guard.blockers;
      expect(blockers.length, 4); // 3 checklist + 1 typed
      expect(blockers.any((b) => b.code == 'checklist_0'), isTrue);
      expect(blockers.any((b) => b.code == 'checklist_1'), isTrue);
      expect(blockers.any((b) => b.code == 'checklist_2'), isTrue);
      expect(blockers.any((b) => b.code == 'typed_confirm_mismatch'), isTrue);
    });

    test('toggleChecklist index out of range throws RangeError', () {
      final guard = DeleteGuard();
      expect(() => guard.toggleChecklist(-1, true), throwsA(isA<RangeError>()));
      expect(() => guard.toggleChecklist(3, true), throwsA(isA<RangeError>()));
    });

    test('checklist getter is unmodifiable', () {
      final guard = DeleteGuard();
      final list = guard.checklist;
      expect(() => list[0] = true, throwsUnsupportedError);
    });
  });
}
