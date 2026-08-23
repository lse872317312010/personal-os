import 'dart:convert';
import 'dart:typed_data';

import 'package:personal_os_events/events.dart';

import 'package:personal_os_storage_api/storage_api.dart';

/// A fully in-memory snapshot of everything needed to restore a Personal OS
/// Vault on a fresh device, without ever touching the Keystore, SQLCipher, or
/// FileProvider. Wave 17a only implements the pure-Dart packaging layer:
/// the bytes this produces are deterministic, hashable, and signable so that
/// RecoveryScreen (Wave 17c) can verify them offline before unlocking.
///
/// The on-disk envelope layout (version 1) is intentionally a single JSON
/// document rather than a real tar.gz so that:
///   1. We can unit-test it without bringing in `archive` / `tar` packages.
///   2. The signature covers exactly one byte range (no streaming surprises).
///   3. The recovery verifier (Wave 17c) can parse it with the exact same
///      EventEnvelopeJsonCodec that M1 already ships.
///
/// Format (all UTF-8, all JSON, single document):
///
/// {
///   "schema_version": 1,
///   "exported_at": "2026-08-23T12:00:00Z",      // RFC3339 UTC
///   "composition_mode": "demo|devSqlite|prodEncrypted",
///   "events": [ ...EventEnvelopeJsonCodec.encode list... ],
///   "blob_manifest": [ { "ref":"...", "media_type":"...", "byte_length":N,
///                        "sha256_hex":"..." }, ... ],
///   "event_count": N,
///   "blob_count":  M,
///   "passphrase_challenge": "..." | null,       // sha256(passphrase) when set
/// }
///
/// The signature (computed by VaultExporter.sign) is a detached HMAC-SHA256
/// over the exact bytes of the JSON document above, keyed by the same
/// passphrase used for `passphrase_challenge` (or a fixed dev seed if no
/// passphrase). This is deliberately NOT a cryptographic replacement for
/// SQLCipher — it only guards against accidental truncation / tampering
/// in transit. Wave 18 will replace the HMAC seed with a real Keystore key.
sealed class VaultExportEnvelope {
  const VaultExportEnvelope();

  Map<String, Object?> toJson();
  Uint8List toBytes();
  String get sha256Hex;
  String get signatureHex;
}

/// Configuration handed to [VaultExporter.export].
final class VaultExportRequest {
  const VaultExportRequest({
    required this.compositionMode,
    this.includeBlobs = false,
    this.passphrase,
  });

  /// String label persisted inside the envelope so the recovery side can
  /// refuse to restore a `prodEncrypted` export onto a `devSqlite` device
  /// without an explicit user override.
  final String compositionMode;

  /// When true, the exporter will iterate `blobStore` and embed each blob's
  /// logical metadata (not bytes) into `blob_manifest`. Wave 17a deliberately
  /// keeps this off by default so the export file stays small; Wave 18 will
  /// add a streaming binary bundle mode.
  final bool includeBlobs;

  /// Optional user passphrase. When non-null, the exporter writes
  /// `passphrase_challenge` = sha256(passphrase).toHex() and signs the
  /// document with HMAC-SHA256(key=passphrase). When null, signs with a
  /// fixed dev seed and writes `passphrase_challenge: null`.
  final String? passphrase;
}

/// Raised by [VaultExporter.export] when the source [EventStore] returns
/// an event the M1 codec refuses to encode (D4 payload, unknown field,
/// non-JSON value, etc.). The envelope is NOT written.
final class VaultExportRejected implements Exception {
  const VaultExportRejected(this.reasonCode, this.detail);

  final String reasonCode;
  final String detail;

  @override
  String toString() => 'VaultExportRejected($reasonCode): $detail';
}

/// Pure-Dart packager. Has zero platform dependencies. No Keystore, no
/// FileProvider, no SQLCipher. Safe to run under `flutter test` and in
/// CI without an Android emulator.
///
/// Usage in AppComposition.demo() / devSqlite() / prodEncrypted():
///
///   final exporter = VaultExporter();
///   final envelope = await exporter.export(
///     request: VaultExportRequest(
///       compositionMode: composition.name,
///       includeBlobs: false,
///     ),
///     eventStore: eventStore,
///     blobStore: null, // omit in demo mode; Wave 18 wires real blob layer
///   );
///   // envelope.toBytes() → share / FileProvider / USB / NAS
///   // envelope.sha256Hex → show in UI for user verification
///   // envelope.signatureHex → recovery side verifies
///
final class VaultExporter {
  const VaultExporter();

  /// Produces a fully in-memory [VaultExportEnvelope]. Never throws partial
  /// state: if any event fails to encode, the whole call raises
  /// [VaultExportRejected] and no bytes are produced.
  Future<VaultExportEnvelope> export({
    required VaultExportRequest request,
    required EventStore eventStore,
    BlobStore? blobStore,
    DateTime? now,
  }) async {
    final DateTime exportedAt = now ?? DateTime.now().toUtc();
    final List<Map<String, Object?>> encodedEvents = <Map<String, Object?>>[];
    final List<EventEnvelope> events = <EventEnvelope>[];

    // 1. Drain every event the store will give us. We deliberately use a
    //    very wide subject scan rather than a new readAll() port because
    //    adding a port is a bigger contract change than Wave 17 should
    //    ship. For demo / devSqlite this covers everything currently in
    //    the store. prodEncrypted will use the same scan; if performance
    //    ever matters we can add readAll() in a separate PR.
    //    For now we accept events handed in directly by the caller.
    //    (see _readAllEvents below for the real implementation note)
    events.addAll(await _readAllEvents(eventStore));

    for (final EventEnvelope e in events) {
      try {
        encodedEvents.add(EventEnvelopeJsonCodec.encode(e));
     } on EventCodecException catch (ex) {
        throw VaultExportRejected(ex.reasonCode, ex.message);
      }
    }

    // 2. Optional blob manifest (metadata only — bytes are never embedded).
    final List<Map<String, Object?>> blobManifest = <Map<String, Object?>>[];
    if (request.includeBlobs && blobStore != null) {
      // Wave 17a intentionally does not enumerate blobs: BlobStore has no
      // list() port by design (blobs are capability-addressed). The
      // manifest is populated from event source_refs in Wave 18.
      blobManifest.add(<String, Object?>{
        'note': 'blob_byte_bundle_deferred_to_wave_18',
      });
    }

    // 3. Build the canonical JSON document.
    final String passphraseChallenge;
    if (request.passphrase != null) {
      final List<int> digest = _sha256(utf8.encode(request.passphrase!));
      passphraseChallenge = _hex(digest);
    } else {
      passphraseChallenge = '';
    }

    final Map<String, Object?> doc = <String, Object?>{
      'schema_version': 1,
      'exported_at': exportedAt.toIso8601String(),
      'composition_mode': request.compositionMode,
      'events': encodedEvents,
      'blob_manifest': blobManifest,
      'event_count': encodedEvents.length,
      'blob_count': blobManifest.length,
      'passphrase_challenge': passphraseChallenge.isEmpty ? null : passphraseChallenge,
    };

    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));

    // 4. Detached HMAC-SHA256 signature.
    final List<int> signingKey = request.passphrase != null
        ? utf8.encode(request.passphrase!)
        : utf8.encode(_devSigningSeed);
    final List<int> sig = _hmacSha256(signingKey, bytes);
    final List<int> digest = _sha256(bytes);

    return _ExportedEnvelope(
      document: doc,
      bytes: bytes,
      sha256Hex: _hex(digest),
      signatureHex: _hex(sig),
    );
  }

  /// For now we cannot read all events — EventStore only exposes
  /// readBySubject / readById. Wave 18 will add readAll to the port.
  /// Until then, demo / devSqlite exports will return an empty event
  /// list when called from the UI; the AppComposition layer will pass
  /// events it already holds in memory for the demo.
  Future<List<EventEnvelope>> _readAllEvents(EventStore store) async {
    // No-op until readAll port lands. Callers that already hold events
    // in memory should use exportFromSnapshot below.
    return const <EventEnvelope>[];
  }

  /// Alternate entry point used when the composition already has a
  /// materialised event list (e.g. InMemoryEventStore.readEvents()).
  /// This is the path ExportScreen actually calls today.
  Future<VaultExportEnvelope> exportFromSnapshot({
    required VaultExportRequest request,
    required List<EventEnvelope> events,
    DateTime? now,
  }) async {
    final DateTime exportedAt = now ?? DateTime.now().toUtc();
    final List<Map<String, Object?>> encodedEvents = <Map<String, Object?>>[];

    for (final EventEnvelope e in events) {
      try {
        encodedEvents.add(EventEnvelopeJsonCodec.encode(e));
      } on EventCodecException catch (ex) {
        throw VaultExportRejected(ex.reasonCode, ex.message);
      }
    }

    final String passphraseChallenge;
    if (request.passphrase != null) {
      passphraseChallenge = _hex(_sha256(utf8.encode(request.passphrase!)));
    } else {
      passphraseChallenge = '';
    }

    final Map<String, Object?> doc = <String, Object?>{
      'schema_version': 1,
      'exported_at': exportedAt.toIso8601String(),
      'composition_mode': request.compositionMode,
      'events': encodedEvents,
      'blob_manifest': const <Map<String, Object?>>[],
      'event_count': encodedEvents.length,
      'blob_count': 0,
      'passphrase_challenge': passphraseChallenge.isEmpty ? null : passphraseChallenge,
    };

    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(doc)));
    final List<int> signingKey = request.passphrase != null
        ? utf8.encode(request.passphrase!)
        : utf8.encode(_devSigningSeed);
    final List<int> sig = _hmacSha256256(signingKey, bytes);
    final List<int> digest = _sha256(bytes);

    return _ExportedEnvelope(
      document: doc,
      bytes: bytes,
      sha256Hex: _hex(digest),
      signatureHex: _hex(sig),
    );
  }

  static const String _devSigningSeed =
      'personal-os-vault-export-dev-signing-seed-v1';
}

final class _ExportedEnvelope implements VaultExportEnvelope {
  const _ExportedEnvelope({
    required this.document,
    required this.bytes,
    required this.sha256Hex,
    required this.signatureHex,
  });

  final Map<String, Object?> document;
  @override
  final Uint8List bytes;
  @override
  final String sha256Hex;
  @override
  final String signatureHex;

  @override
  Map<String, Object?> toJson() => document;
}

// ---------------------------------------------------------------------------
// Minimal SHA-256 / HMAC-SHA256 / hex helpers.
//
// We avoid depending on `package:crypto` here so that `packages/storage_api`
// stays a pure-Dart package with no extra deps. The implementation below is
// a straightforward port of RFC 6234 / RFC 2104 and is exercised by unit
// tests against known vectors. For production Keystore-backed signing,
// Wave 18 replaces this with real platform keys.
// ---------------------------------------------------------------------------

const int _kBlockSize = 64; // SHA-256 block size in bytes

List<int> _sha256(List<int> data) {
  final sha = _Sha256();
  sha.update(data);
  return sha.digest();
}

List<int> _hmacSha256(List<int> key, List<int> message) {
  return _hmacSha256256(key, message);
}

List<int> _hmacSha256256(List<int> key, List<int> message) {
  List<int> k = List<int>.from(key);
  if (k.length > _kBlockSize) {
    k = _sha256(k);
  }
  while (k.length < _kBlockSize) {
    k.add(0);
  }
  final List<int> ipad = List<int>.filled(_kBlockSize, 0x36);
  final List<int> opad = List<int>.filled(_kBlockSize, 0x5c);
  for (int i = 0; i < _kBlockSize; i++) {
    ipad[i] ^= k[i];
    opad[i] ^= k[i];
  }
  final List<int> inner = _sha256(<int>[...ipad, ...message]);
  return _sha256(<int>[...opad, ...inner]);
}

String _hex(List<int> bytes) {
  final StringBuffer sb = StringBuffer();
  for (final int b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

// --- SHA-256 (FIPS 180-4) --------------------------------------------------

final class _Sha256 {
  _Sha256() : _h = <int>[
              0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
              0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
            ];

  final List<int> _buffer = <int>[];
  int _totalLen = 0;

  void update(List<int> data) {
    _totalLen += data.length;
    _buffer.addAll(data);
    while (_buffer.length >= 64) {
      _processBlock(_buffer.sublist(0, 64));
      _buffer.removeRange(0, 64);
    }
  }

  List<int> digest() {
    final int bitLen = _totalLen * 8;
    _buffer.add(0x80);
    while (_buffer.length % 64 != 56) {
      _buffer.add(0);
    }
    // 64-bit big-endian length
    _buffer.add((bitLen >> 56) & 0xff);
    _buffer.add((bitLen >> 48) & 0xff);
    _buffer.add((bitLen >> 40) & 0xff);
    _buffer.add((bitLen >> 32) & 0xff);
    _buffer.add((bitLen >> 24) & 0xff);
    _buffer.add((bitLen >> 16) & 0xff);
    _buffer.add((bitLen >> 8) & 0xff);
    _buffer.add(bitLen & 0xff);
    while (_buffer.isNotEmpty) {
      _processBlock(_buffer.sublist(0, 64));
      _buffer.removeRange(0, 64);
    }
    final List<int> out = <int>[];
    for (final int h in _h) {
      out.add((h >> 24) & 0xff);
      out.add((h >> 16) & 0xff);
      out.add((h >> 8) & 0xff);
      out.add(h & 0xff);
    }
    return out;
  }

  static const List<int> _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  final List<int> _h;

  void _processBlock(List<int> block) {
    final List<int> w = List<int>.filled(64, 0);
    for (int i = 0; i < 16; i++) {
      w[i] = (block[i * 4] << 24) |
          (block[i * 4 + 1] << 16) |
          (block[i * 4 + 2] << 8) |
          block[i * 4 + 3];
    }
    for (int i = 16; i < 64; i++) {
      final int s0 = _rotr(w[i - 15], 7) ^
          _rotr(w[i - 15], 18) ^
          (w[i - 15] >> 3);
      final int s1 = _rotr(w[i - 2], 17) ^
          _rotr(w[i - 2], 19) ^
          (w[i - 2] >> 10);
      w[i] = _add32(_add32(_add32(w[i - 16], s0), w[i - 7]), s1);
    }
    int a = _h[0], b = _h[1], c = _h[2], d = _h[3];
    int e = _h[4], f = _h[5], g = _h[6], hh = _h[7];
    for (int i = 0; i < 64; i++) {
      final int S1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final int ch = (e & f) ^ (~e & g);
      final int temp1 = _add32(
          _add32(_add32(_add32(_add32(hh, S1), ch), _k[i]), w[i]),
          0);
      final int S0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final int maj = (a & b) ^ (a & c) ^ (b & c);
      final int temp2 = _add32(S0, maj);
      hh = g;
      g = f;
      f = e;
      e = _add32(d, temp1);
      d = c;
      c = b;
      b = a;
      a = _add32(temp1, temp2);
    }
    _h[0] = _add32(_h[0], a);
    _h[1] = _add32(_h[1], b);
    _h[2] = _add32(_h[2], c);
    _h[3] = _add32(_h[3], d);
    _h[4] = _add32(_h[4], e);
    _h[5] = _add32(_h[5], f);
    _h[6] = _add32(_h[6], g);
    _h[7] = _add32(_h[7], hh);
  }

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  static int _add32(int a, int b) => (a + b) & 0xffffffff;
}
