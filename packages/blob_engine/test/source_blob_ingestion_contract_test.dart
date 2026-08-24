import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  test('source contract accepts only an opaque token and returns a BlobRef',
      () async {
    final adapter = _FakeSourceBlobAdapter();
    final token = OpaqueSourceToken('source_token_0001');

    final ref = await adapter.ingestSource(
      source: token,
      mediaType: 'image/jpeg',
      sensitivity: Sensitivity.d3,
      access: _access,
    );

    expect(ref, BlobRef('blob://opaque-source-1'));
    expect(adapter.tokens, [token]);
  });

  test('source contract exposes stable expiry without platform details',
      () async {
    final adapter = _FakeSourceBlobAdapter()
      ..failure = const SourceBlobIngestionException('source_expired');

    await expectLater(
      adapter.ingestSource(
        source: OpaqueSourceToken('source_token_0001'),
        mediaType: 'image/jpeg',
        sensitivity: Sensitivity.d3,
        access: _access,
      ),
      throwsA(isA<SourceBlobIngestionException>()
          .having((error) => error.code, 'code', 'source_expired')
          .having((error) => error.toString(), 'safe', isNot(contains('/')))),
    );
  });
}

final _access = BlobAccessContext(
  actorRef: 'user:owner',
  purpose: 'appearance-analysis',
  consentRef: 'consent:appearance-v1',
);

final class _FakeSourceBlobAdapter implements SourceBlobIngestionContract {
  SourceBlobIngestionException? failure;
  final List<OpaqueSourceToken> tokens = <OpaqueSourceToken>[];

  @override
  Future<BlobRef> ingestSource({
    required OpaqueSourceToken source,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    if (failure != null) throw failure!;
    tokens.add(source);
    return BlobRef('blob://opaque-source-1');
  }
}
