import 'package:flutter/services.dart';

import 'controlled_source_contract.dart';

/// Dart-side adapter for the native controlled-source protocol.
///
/// This adapter never accepts or returns bytes, paths, URIs, or provider
/// metadata. Native code owns the source and exposes only an opaque capability
/// token.
final class MethodChannelControlledSourcePort implements ControlledSourcePort {
  MethodChannelControlledSourcePort({
    MethodChannel? channel,
  }) : _channel =
            channel ?? const MethodChannel('personal_os/internal/controlled_source');

  static const String _capabilitiesMethod = 'capabilities';
  static const String _pickPhotoMethod = 'pickPhoto';
  static const String _capturePhotoMethod = 'capturePhoto';
  static const String _releaseMethod = 'release';

  static const String _photoPickerKey = 'photoPicker';
  static const String _cameraKey = 'camera';
  static const String _tokenKey = 'token';

  static const Map<String, ControlledSourceFailureCode> _failureCodes =
      <String, ControlledSourceFailureCode>{
    'source.cancelled': ControlledSourceFailureCode.cancelled,
    'source.unavailable': ControlledSourceFailureCode.unavailable,
    'source.denied': ControlledSourceFailureCode.denied,
    'source.invalid_response': ControlledSourceFailureCode.invalidResponse,
    'source.expired': ControlledSourceFailureCode.sourceExpired,
    'source.consumed': ControlledSourceFailureCode.sourceConsumed,
  };

  final MethodChannel _channel;
  final Set<String> _issuedTokens = <String>{};
  final Set<String> _releasedTokens = <String>{};

  @override
  Future<ControlledSourceCapabilities> capabilities() async {
    final response = await _invoke<dynamic>(_capabilitiesMethod);
    final map = _strictMap(response);
    if (map.length != 2 ||
        !map.containsKey(_photoPickerKey) ||
        !map.containsKey(_cameraKey) ||
        map[_photoPickerKey] is! bool ||
        map[_cameraKey] is! bool) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
    return ControlledSourceCapabilities(
      photoPicker: map[_photoPickerKey] as bool,
      camera: map[_cameraKey] as bool,
    );
  }

  @override
  Future<OpaqueSourceToken> pickPhoto() async {
    return _acquire(_pickPhotoMethod);
  }

  @override
  Future<OpaqueSourceToken> capturePhoto() async {
    return _acquire(_capturePhotoMethod);
  }

  @override
  Future<void> release(OpaqueSourceToken token) async {
    if (_releasedTokens.contains(token.value)) {
      return;
    }
    if (!_issuedTokens.contains(token.value)) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }

    try {
      final response = await _invoke<dynamic>(
        _releaseMethod,
        <String, Object?>{_tokenKey: token.value},
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
    final response = await _invoke<dynamic>(method);
    final map = _strictMap(response);
    if (map.length != 1 || !map.containsKey(_tokenKey)) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }

    final rawToken = map[_tokenKey];
    if (rawToken is! String) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }

    try {
      final token = OpaqueSourceToken(rawToken);
      _issuedTokens.add(token.value);
      return token;
    } on FormatException {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
  }

  Future<T> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw ControlledSourceException(
        _failureCodes[error.code] ??
            ControlledSourceFailureCode.unavailable,
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

  Map<Object?, Object?> _strictMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const ControlledSourceException(
        ControlledSourceFailureCode.invalidResponse,
      );
    }
    return value;
  }

  void _markReleased(OpaqueSourceToken token) {
    _issuedTokens.remove(token.value);
    _releasedTokens.add(token.value);
  }
}
