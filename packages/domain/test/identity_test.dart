import 'package:personal_os_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('persisted identity invariants', () {
    test('EntityId rejects blank values at runtime', () {
      expect(() => EntityId(''), throwsArgumentError);
      expect(() => EntityId('  \n'), throwsArgumentError);
      expect(EntityId('entity-1').value, 'entity-1');
    });

    test('Revision rejects negative values at runtime', () {
      expect(() => Revision(-1), throwsArgumentError);
      expect(Revision(0).value, 0);
      expect(Revision(2).next, Revision(3));
    });

    test('SchemaVersion rejects zero and negative values at runtime', () {
      expect(() => SchemaVersion(-1), throwsArgumentError);
      expect(() => SchemaVersion(0), throwsArgumentError);
      expect(SchemaVersion(1).value, 1);
    });

    test('ObjectRef rejects blank type and invalid decoded revision', () {
      expect(
        () => ObjectRef(type: ' ', id: EntityId('object-1')),
        throwsArgumentError,
      );
      expect(
        () => ObjectRef.fromJson(<String, Object?>{
          'type': 'goal',
          'id': 'goal-1',
          'revision': -1,
        }),
        throwsArgumentError,
      );
    });
  });
}
