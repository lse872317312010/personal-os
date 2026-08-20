import 'package:personal_os_contract_runner/contract_runner.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('decodes versioned object references', () {
    final ref = decodeRef('claim:CL1@3');
    expect(ref.type, 'claim');
    expect(ref.id, EntityId('CL1'));
    expect(ref.revision, Revision(3));
  });

  test('rejects malformed object references', () {
    expect(() => decodeRef('missing-colon'), throwsFormatException);
  });
}
