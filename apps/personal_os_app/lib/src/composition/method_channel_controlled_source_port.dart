import 'package:flutter/services.dart';
import 'package:personal_os_source_api/source_api.dart';

/// Flutter composition-boundary adapter for the native controlled-source port.
///
/// Bytes, paths, URIs, provider metadata, and native exception details never
/// enter Dart. The source remains a native-owned opaque capability.
final class MethodChannelControlledSourcePort implements ControlledSourcePort {
  MethodChannelControlledSourcePort({
    MethodChannel? channel,
  }) : _channel =
            channel ?? const MethodChannel('personal_os/internal/controlled_source');

  static const _capabilities = 'capabilities';
  static const _pickPhoto = 'pickPhoto';
  static const _capturePhoto = 'capturePhoto';
  static const _release = 'release';
  static const _photoPicker = 'photoPicker';
  static const _camera = 'camera';
  static const _token = 'token';

  static const Map<String, ControlledSourceFailureCode> _codes = {
    'source.cancelled': ControlledSourceFailureCode.cancelled,
    'source.unavailable': ControlledSourceFailureCode.unavailable,
    'source.denied': ControlledSourceFailureCode.denied,
    'source.invalid_response': ControlledSourceFailureCode.invalidResponse,
    'source.expired': ControlledSourceFailureCode.sourceExpired,
    'source.consumed': ControlledSourceFailureCode.sourceConsumed,
  };

  final MethodChannel _channel;
  final Set<String> _issued = <String>{};
  final Set<String> _released = <String>{};

  @override
  Future<ControlledSourceCapabilities> capabilities() async {
    final map = _map(await _invoke<dynamic>(_capabilities));
    if (map.length != 2 ||
        map[_photoPicker] is! bool ||
        map[_camera] is! bool) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
    return ControlledSourceCapabilities(
      photoPicker: map[_photoPicker] as bool,
      camera: map[_camera] as bool,
    );
  }

  @override
  Future<OpaqueSourceToken> pickPhoto() => _acquire(_pickPhoto);

  @override
  Future<OpaqueSourceToken> capturePhoto() => _acquire(_capturePhoto);

  @override
  Future<void> release(OpaqueSourceToken token) async {
    if (_released.contains(token.value)) return;
    if (!_issued.contains(token.value)) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
    try {
      final response = await _invoke<dynamic>(
        _release,
        <String, Object?>{_token: token.value},
      );
      if (response != null) {
        throw const ControlledSourceException(
          ControlledSourceFailureCode.invalidResponse,
        );
      }
      _markReleased(token);
    } on ControlledSourceException catch (error) {
      if (error.code == ControlledSourceFailureCode.sourceExpired ||
          error.code == ControlledSourceFailureCode.sourceConsumed) {
        _markReleased(token);
      }
      rethrow;
    }
  }

  Future<OpaqueSourceToken> _acquire(String method) async {
    final map = _map(await _invoke<dynamic>(method));
    if (map.length != 1 || map[_token] is! String) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
    try {
      final token = OpaqueSourceToken(map[_token] as String);
      _issued.add(token.value);
      return token;
    } on FormatException {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw ControlledSourceException(
        _codes[error.code] ?? ControlledSourceFailureCode.unavailable,
      );
    } on MissingPluginException {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.unavailable,
      );
    } on TypeError {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
  }

  Map<Object?, Object?> _map(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
    return value;
  }

  void _markReleased(OpaqueSourceToken token) {
    _issued.remove(token.value);
    _released.add(token.value);
  }
}
