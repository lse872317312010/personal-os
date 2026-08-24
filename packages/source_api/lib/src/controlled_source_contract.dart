/// The only source kinds exposed by the controlled local media boundary.
enum ControlledSourceKind { photoPicker, camera }

/// Stable, platform-neutral failure identities.
enum ControlledSourceFailureCode {
  cancelled,
  unavailable,
  denied,
  invalidResponse,
  sourceExpired,
  sourceConsumed,
  sourceWriteFailed,
}

/// A source handle that is intentionally opaque to Dart callers.
///
/// A token is not a path, URI, content URI, file descriptor, or provider
/// identifier. Native code owns the source and decides when it expires.
final class OpaqueSourceToken {
  OpaqueSourceToken(String value) : value = _validate(value);

  final String value;

  static String _validate(String value) {
    if (!RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(value)) {
      throw const FormatException('invalid opaque source token');
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is OpaqueSourceToken && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Capabilities reported without exposing provider, path, or URI metadata.
final class ControlledSourceCapabilities {
  const ControlledSourceCapabilities({
    required this.photoPicker,
    required this.camera,
  });

  final bool photoPicker;
  final bool camera;
}

/// Adapter-neutral controlled source port.
///
/// Implementations must keep all URI/path/provider details native-side and
/// return only OpaqueSourceToken or ControlledSourceFailureCode.
abstract interface class ControlledSourcePort {
  Future<ControlledSourceCapabilities> capabilities();
  Future<OpaqueSourceToken> pickPhoto();
  Future<OpaqueSourceToken> capturePhoto();
  Future<String> ingestToBlob(OpaqueSourceToken token);
  Future<void> deleteBlob(String blobRef);
  Future<void> release(OpaqueSourceToken token);
}

/// Stable boundary failure. Its string representation contains no platform
/// message, URI, path, provider, or exception details.
final class ControlledSourceException implements Exception {
  const ControlledSourceException(this.code);

  final ControlledSourceFailureCode code;

  @override
  String toString() => 'ControlledSourceException($code)';
}

/// Minimal fake for contract and application tests.
final class FakeControlledSourcePort implements ControlledSourcePort {
  FakeControlledSourcePort({
    this.capabilitiesValue = const ControlledSourceCapabilities(
      photoPicker: true,
      camera: false,
    ),
  });

  final ControlledSourceCapabilities capabilitiesValue;
  final Set<String> released = <String>{};
  ControlledSourceFailureCode? nextFailure;

  @override
  Future<ControlledSourceCapabilities> capabilities() async {
    _throwIfConfigured();
    return capabilitiesValue;
  }

  @override
  Future<OpaqueSourceToken> pickPhoto() async {
    _throwIfConfigured();
    return OpaqueSourceToken('fake_photo_token_01');
  }

  @override
  Future<OpaqueSourceToken> capturePhoto() async {
    _throwIfConfigured();
    if (!capabilitiesValue.camera) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.unavailable,
      );
    }
    return OpaqueSourceToken('fake_camera_token_01');
  }

  @override
  Future<String> ingestToBlob(OpaqueSourceToken token) async {
    _throwIfConfigured();
    return 'blob://fake-source-00000001';
  }

  @override
  Future<void> deleteBlob(String blobRef) async {
    _throwIfConfigured();
  }

  @override
  Future<void> release(OpaqueSourceToken token) async {
    _throwIfConfigured();
    released.add(token.value);
  }

  void _throwIfConfigured() {
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) {
      throw ControlledSourceException(failure);
    }
  }
}
