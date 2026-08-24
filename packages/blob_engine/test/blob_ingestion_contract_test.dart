import 'dart:async';

import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  final access = BlobAccessContext(
    actorRef: 'user:owner',
    purpose: 'appearance-analysis',
    consentRef: 'consent:appearance-v1',
  );

  test('validates consent, sensitivity, and media type before listening',
      () async {
    final store = _RecordingStore();
    final ingestion = EncryptedBlobIngestion(store: store, maxBytes: 4);

    for (final request in <({String? consent, Sensitivity sensitivity, String mediaType, String code})>[
      (consent: null, sensitivity: Sensitivity.d3, mediaType: 'image/jpeg', code: 'consent_required'),
      (consent: access.consentRef, sensitivity: Sensitivity.d4, mediaType: 'image/jpeg', code: 'd4_persistence_forbidden'),
      (consent: access.consentRef, sensitivity: Sensitivity.d3, mediaType: 'secret/path', code: 'invalid_media_type'),
    ]) {
      var listened = false;
      final input = Stream<List<int>>.multi((controller) {
        listened = true;
        controller.add(<int>[1]);
        controller.close();
      });
      final requestAccess = BlobAccessContext(
        actorRef: access.actorRef,
        purpose: access.purpose,
        consentRef: request.consent,
      );

      await expectLater(
        ingestion.ingest(
          bytes: input,
          mediaType: request.mediaType,
          sensitivity: request.sensitivity,
          access: requestAccess,
        ),
        throwsA(_ingestionError(request.code)),
      );
      expect(listened, isFalse);
    }
    expect(store.putCalls, 0);
  });

  test('passes a bounded stream and exposes no raw bytes to the contract',
      () async {
    final store = _RecordingStore();
    final ingestion = EncryptedBlobIngestion(store: store, maxBytes: 3);

    await ingestion.ingest(
      bytes: Stream<List<int>>.fromIterable([
        <int>[1, 2],
        <int>[3],
      ]),
      mediaType: 'image/jpeg',
      sensitivity: Sensitivity.d3,
      access: access,
    );
    expect(store.received, <int>[1, 2, 3]);
    expect(store.putCalls, 1);
  });

  test('rejects over-limit input with a stable redacted error', () async {
    final store = _RecordingStore();
    final ingestion = EncryptedBlobIngestion(store: store, maxBytes: 3);

    await expectLater(
      ingestion.ingest(
        bytes: Stream<List<int>>.value(<int>[1, 2, 3, 4]),
        mediaType: 'image/jpeg',
        sensitivity: Sensitivity.d3,
        access: access,
      ),
      throwsA(_ingestionError('payload_too_large')),
    );
    expect(store.received, isEmpty);
  });

  test('redacts payload failures and fails closed before returning a ref',
      () async {
    final store = _RecordingStore();
    final ingestion = EncryptedBlobIngestion(store: store, maxBytes: 4);
    const secret = 'payload path and provider URI';

    await expectLater(
      ingestion.ingest(
        bytes: Stream<List<int>>.multi((controller) {
          controller.add(<int>[1]);
          controller.addError(StateError(secret));
          controller.close();
        }),
        mediaType: 'image/jpeg',
        sensitivity: Sensitivity.d3,
        access: access,
      ),
      throwsA(_ingestionError('ingestion_failed')),
    );
    expect(store.putCalls, 1);
    expect(store.returnedRefs, isEmpty);
  });

  test('discard is safe for missing and repeated refs', () async {
    final store = _RecordingStore()
      ..deleteResult = BlobDeleteResult.alreadyAbsent;
    final ingestion = EncryptedBlobIngestion(store: store, maxBytes: 4);
    final ref = BlobRef('blob://opaque-ref');

    await ingestion.discard(ref: ref, access: access);
    await ingestion.discard(ref: ref, access: access);

    expect(store.deleteCalls, 2);
    expect(store.deletedRefs, [ref, ref]);
  });
}

Matcher _ingestionError(String code) => isA<BlobIngestionException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.toString(), 'redacted', isNot(contains('secret')));

final class _RecordingStore implements BlobStore {
  int putCalls = 0;
  int deleteCalls = 0;
  final List<int> received = <int>[];
  final List<BlobRef> returnedRefs = <BlobRef>[];
  final List<BlobRef> deletedRefs = <BlobRef>[];
  BlobDeleteResult deleteResult = BlobDeleteResult.deleted;

  @override
  Future<BlobRef> put({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    putCalls++;
    await for (final chunk in bytes) {
      received.addAll(chunk);
    }
    final ref = BlobRef('blob://opaque-ref');
    returnedRefs.add(ref);
    return ref;
  }

  @override
  Stream<List<int>> openRead(BlobRef ref, {required BlobAccessContext access, BlobByteRange? range}) =>
      const Stream<List<int>>.empty();

  @override
  Future<BlobMetadata> metadata(BlobRef ref, {required BlobAccessContext access}) =>
      throw UnimplementedError();

  @override
  Future<BlobDeleteResult> delete(BlobRef ref, {required BlobAccessContext access}) async {
    deleteCalls++;
    deletedRefs.add(ref);
    return deleteResult;
  }
}
