import 'dart:async';
import 'dart:typed_data';

import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_security_api/security_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';
import 'package:test/test.dart';

void main() {
  late _FakeRepository repository;
  late _FakeCryptography cryptography;
  late List<BlobEngineEvent> log;
  late EncryptedBlobEngine engine;

  final access = BlobAccessContext(
    actorRef: 'user:owner',
    purpose: 'appearance-analysis',
    consentRef: 'consent:appearance-v1',
  );

  setUp(() {
    repository = _FakeRepository();
    cryptography = _FakeCryptography();
    cryptography.operations = repository.operations;
    log = <BlobEngineEvent>[];
    engine = EncryptedBlobEngine(
      repository: repository,
      cryptography: cryptography,
      safeLog: log.add,
      clock: () => DateTime.utc(2026, 8, 20),
    );
  });

  test('rejects D4 before creating resources or listening to input', () async {
    var listened = false;
    final input = Stream<List<int>>.multi((controller) {
      listened = true;
      controller.add(<int>[1]);
      controller.close();
    });

    await expectLater(
      engine.put(
        bytes: input,
        mediaType: 'image/jpeg',
        sensitivity: Sensitivity.d4,
        access: access,
      ),
      throwsA(isA<BlobAccessDenied>()),
    );

    expect(listened, isFalse);
    expect(repository.beginWriteCalls, 0);
    expect(cryptography.beginSealCalls, 0);
  });

  test('requires a consent binding before listening or touching storage',
      () async {
    final missingConsent = BlobAccessContext(
      actorRef: 'user:owner',
      purpose: 'appearance-analysis',
    );
    var listened = false;
    final input = Stream<List<int>>.multi((controller) {
      listened = true;
      controller.close();
    });

    await expectLater(
      engine.put(
        bytes: input,
        mediaType: 'image/jpeg',
        sensitivity: Sensitivity.d3,
        access: missingConsent,
      ),
      throwsA(_safeException('consent_required')),
    );
    expect(listened, isFalse);
    expect(repository.beginWriteCalls, 0);
    expect(cryptography.beginSealCalls, 0);
  });

  test('rejects a blank consent binding at the access boundary', () {
    expect(
      () => BlobAccessContext(
        actorRef: 'user:owner',
        purpose: 'appearance-analysis',
        consentRef: '  ',
      ),
      throwsArgumentError,
    );
  });

  test('successful put stores ciphertext and zeroizes owned input', () async {
    final callerChunk = <int>[10, 20, 30];
    final ref = await engine.put(
      bytes: Stream<List<int>>.value(callerChunk),
      mediaType: 'image/jpeg',
      sensitivity: Sensitivity.d3,
      access: access,
    );

    expect(repository.readable(ref), <int>[11, 21, 31]);
    expect(repository.readable(ref), isNot(callerChunk));
    expect(callerChunk, <int>[10, 20, 30],
        reason: 'caller memory is not owned');
    expect(cryptography.seenPlaintext.single, isNot(same(callerChunk)));
    expect(cryptography.seenPlaintext.single, everyElement(0));
    expect(repository.lastMetadata!.plaintextLength, 3);
    expect(repository.lastMetadata!.key.purpose, KeyPurpose.blob);
  });

  for (final failure in _PutFailure.values) {
    test('${failure.name} failure aborts, destroys key, and exposes no partial',
        () async {
      repository.failure = failure;
      cryptography.failSeal = failure == _PutFailure.crypto;

      await expectLater(
        engine.put(
          bytes: Stream<List<int>>.value(<int>[7, 8]),
          mediaType: 'secret/path/hash.jpg',
          sensitivity: Sensitivity.d3,
          access: access,
        ),
        throwsA(_safeException('put_failed')),
      );

      expect(repository.lastWrite!.abortCalls, 1);
      expect(cryptography.destroyed, [cryptography.key]);
      expect(repository.readable(repository.lastWrite!.ref), isNull);
      expect(log, [BlobEngineEvent.putFailed]);
    });
  }

  test('rejects a non-blob key and destroys it', () async {
    cryptography.key = KeyHandle(
      id: 'not-a-loggable-key',
      purpose: KeyPurpose.vaultMaster,
      version: 1,
    );

    await expectLater(
      engine.put(
        bytes: const Stream<List<int>>.empty(),
        mediaType: 'image/jpeg',
        sensitivity: Sensitivity.d3,
        access: access,
      ),
      throwsA(_safeException('put_failed')),
    );
    expect(repository.lastWrite!.abortCalls, 1);
    expect(cryptography.destroyed, [cryptography.key]);
  });

  test('open supports half-open ranges across ciphertext chunks', () async {
    final ref = await engine.put(
      bytes: Stream<List<int>>.fromIterable([
        <int>[0, 1, 2],
        <int>[3, 4, 5],
      ]),
      mediaType: 'application/octet-stream',
      sensitivity: Sensitivity.d2,
      access: access,
    );
    repository.readChunkSize = 2;

    final bytes = await engine
        .openRead(ref,
            access: access, range: BlobByteRange(start: 2, endExclusive: 5))
        .expand((chunk) => chunk)
        .toList();
    expect(bytes, <int>[2, 3, 4]);
  });

  test('preserves the stable plaintext length mismatch error', () async {
    final ref = await _put(engine, access);
    repository.plaintextLengthOverride = 99;

    await expectLater(
      engine.openRead(ref, access: access).drain<void>(),
      throwsA(_safeException('plaintext_length_mismatch')),
    );
    expect(log.last, BlobEngineEvent.openFailed);
  });

  test('does not allow a different consent to access the blob', () async {
    final ref = await _put(engine, access);
    final otherConsent = BlobAccessContext(
      actorRef: access.actorRef,
      purpose: access.purpose,
      consentRef: 'consent:other-v1',
    );

    await expectLater(
      engine.openRead(ref, access: otherConsent).drain<void>(),
      throwsA(_safeException('consent_mismatch')),
    );
    expect(cryptography.seenPlaintext, isEmpty);
  });

  test('delete destroys key before ciphertext and is idempotent', () async {
    final ref = await _put(engine, access);

    expect(await engine.delete(ref, access: access), BlobDeleteResult.deleted);
    expect(repository.operations, <String>['destroy-key', 'delete-ciphertext']);
    expect(repository.readable(ref), isNull);
    expect(
      await engine.delete(ref, access: access),
      BlobDeleteResult.alreadyAbsent,
    );
  });

  test('ciphertext cleanup failure is safe and retryable', () async {
    final ref = await _put(engine, access);
    repository.deleteFailuresRemaining = 1;

    await expectLater(
      engine.delete(ref, access: access),
      throwsA(_safeException('ciphertext_cleanup_failed')),
    );
    expect(repository.readable(ref), isNotNull);
    expect(cryptography.destroyed, [cryptography.key]);

    expect(await engine.delete(ref, access: access), BlobDeleteResult.deleted);
    expect(cryptography.destroyed, [cryptography.key]);
    expect(repository.readable(ref), isNull);
  });

  test('adapter secrets never escape exceptions or structured logs', () async {
    repository.openFailure = true;
    final secret = 'ref-path-content-hash';
    final ref = BlobRef(secret);

    Object? error;
    try {
      await engine.openRead(ref, access: access).drain<void>();
    } on Object catch (caught) {
      error = caught;
    }
    expect(error, _safeException('open_failed'));
    expect(error.toString(), isNot(contains(secret)));
    expect(log, [BlobEngineEvent.openFailed]);
  });

  test('metadata and key-destruction failures are redacted', () async {
    final ref = await _put(engine, access);
    repository.metadataFailure = true;

    await expectLater(
      engine.metadata(ref, access: access),
      throwsA(_safeException('metadata_failed')),
    );
    expect(log.last, BlobEngineEvent.metadataFailed);

    repository.metadataFailure = false;
    cryptography.destroyFailure = true;
    await expectLater(
      engine.delete(ref, access: access),
      throwsA(_safeException('delete_failed')),
    );
    expect(log.last, BlobEngineEvent.deleteFailed);
    expect(repository.readable(ref), isNotNull);
  });
}

Matcher _safeException(String code) => isA<BlobEngineException>()
    .having((error) => error.code, 'code', code)
    .having((error) => error.toString(), 'redacted', isNot(contains('secret')));

Future<BlobRef> _put(EncryptedBlobEngine engine, BlobAccessContext access) =>
    engine.put(
      bytes: Stream<List<int>>.value(<int>[1, 2, 3]),
      mediaType: 'image/jpeg',
      sensitivity: Sensitivity.d3,
      access: access,
    );

enum _PutFailure { crypto, write, commit }

final class _FakeCryptography implements BlobCryptographyPort {
  int beginSealCalls = 0;
  bool failSeal = false;
  bool destroyFailure = false;
  KeyHandle key =
      KeyHandle(id: 'blob-key', purpose: KeyPurpose.blob, version: 1);
  final List<Uint8List> seenPlaintext = <Uint8List>[];
  final List<KeyHandle> destroyed = <KeyHandle>[];
  List<String>? operations;

  @override
  Future<BlobSealSession> beginSeal() async {
    beginSealCalls++;
    return _FakeSealSession(this);
  }

  @override
  Future<void> destroyKey(KeyHandle key) async {
    if (destroyFailure) throw StateError('secret key ref/path/hash');
    destroyed.add(key);
    operations?.add('destroy-key');
  }

  @override
  Stream<Uint8List> open({
    required KeyHandle key,
    required Stream<Uint8List> ciphertext,
  }) async* {
    await for (final chunk in ciphertext) {
      yield Uint8List.fromList(chunk.map((byte) => byte - 1).toList());
    }
  }
}

final class _FakeSealSession implements BlobSealSession {
  _FakeSealSession(this.owner);
  final _FakeCryptography owner;

  @override
  KeyHandle get key => owner.key;

  @override
  Stream<Uint8List> seal(Stream<Uint8List> plaintext) async* {
    await for (final chunk in plaintext) {
      owner.seenPlaintext.add(chunk);
      if (owner.failSeal) throw StateError('secret/path/hash crypto failure');
      yield Uint8List.fromList(chunk.map((byte) => byte + 1).toList());
    }
  }
}

final class _FakeRepository implements CiphertextBlobRepository {
  int beginWriteCalls = 0;
  _PutFailure? failure;
  bool openFailure = false;
  bool metadataFailure = false;
  int deleteFailuresRemaining = 0;
  int? plaintextLengthOverride;
  int? readChunkSize;
  int _nextRef = 0;
  _FakeWrite? lastWrite;
  CiphertextBlobMetadata? lastMetadata;
  final Map<BlobRef, _Stored> _stored = <BlobRef, _Stored>{};
  final List<String> operations = <String>[];

  List<int>? readable(BlobRef ref) => _stored[ref]?.ciphertext;

  @override
  Future<CiphertextBlobWrite> beginWrite(
      {required BlobAccessContext access}) async {
    beginWriteCalls++;
    final write = _FakeWrite(this, BlobRef('opaque-${_nextRef++}'));
    lastWrite = write;
    return write;
  }

  @override
  Future<CiphertextBlobRead?> open(BlobRef ref,
      {required BlobAccessContext access}) async {
    if (openFailure) throw StateError('ref-path-content-hash');
    final stored = _stored[ref];
    if (stored == null) return null;
    final metadata = plaintextLengthOverride == null
        ? stored.metadata
        : CiphertextBlobMetadata(
            key: stored.metadata.key,
            mediaType: stored.metadata.mediaType,
            consentRef: stored.metadata.consentRef,
            plaintextLength: plaintextLengthOverride!,
            sensitivity: stored.metadata.sensitivity,
            createdAt: stored.metadata.createdAt,
          );
    return CiphertextBlobRead(
      metadata: metadata,
      ciphertext: _ciphertextChunks(stored.ciphertext, readChunkSize),
    );
  }

  @override
  Future<CiphertextBlobMetadata?> metadata(
    BlobRef ref, {
    required BlobAccessContext access,
  }) async {
    if (metadataFailure) throw StateError('secret metadata ref/path/hash');
    return _stored[ref]?.metadata;
  }

  @override
  Future<bool> deleteCiphertext(BlobRef ref,
      {required BlobAccessContext access}) async {
    operations.add('delete-ciphertext');
    if (deleteFailuresRemaining-- > 0) throw StateError('secret cleanup path');
    return _stored.remove(ref) != null;
  }
}

Stream<Uint8List> _ciphertextChunks(List<int> bytes, int? chunkSize) async* {
  final size = chunkSize ?? bytes.length;
  if (bytes.isEmpty) {
    yield Uint8List(0);
    return;
  }
  for (var start = 0; start < bytes.length; start += size) {
    final end = start + size < bytes.length ? start + size : bytes.length;
    yield Uint8List.fromList(bytes.sublist(start, end));
  }
}

final class _FakeWrite implements CiphertextBlobWrite {
  _FakeWrite(this.owner, this.ref);
  final _FakeRepository owner;
  @override
  final BlobRef ref;
  final List<int> ciphertext = <int>[];
  int abortCalls = 0;

  @override
  Future<void> write(Stream<Uint8List> ciphertextStream) async {
    await for (final chunk in ciphertextStream) {
      if (owner.failure == _PutFailure.write) {
        throw StateError('secret write path/hash');
      }
      ciphertext.addAll(chunk);
    }
  }

  @override
  Future<void> commit(CiphertextBlobMetadata metadata) async {
    if (owner.failure == _PutFailure.commit) {
      throw StateError('secret commit ref/path/hash');
    }
    owner.lastMetadata = metadata;
    owner._stored[ref] = _Stored(metadata, List<int>.from(ciphertext));
  }

  @override
  Future<void> abort() async {
    abortCalls++;
    ciphertext.clear();
    owner._stored.remove(ref);
  }
}

final class _Stored {
  _Stored(this.metadata, this.ciphertext);
  final CiphertextBlobMetadata metadata;
  final List<int> ciphertext;
}
