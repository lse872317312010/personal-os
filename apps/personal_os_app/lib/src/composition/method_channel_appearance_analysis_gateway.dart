import 'package:flutter/services.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';

final class SecureModelGatewayFailure implements Exception {
  const SecureModelGatewayFailure(this.code);

  final String code;

  @override
  String toString() => 'SecureModelGatewayFailure($code)';
}

final class MethodChannelAppearanceAnalysisGateway
    implements
        AppearanceAnalysisGateway,
        AppearanceModelCapabilityGateway,
        AppearanceModelCredentialGateway {
  const MethodChannelAppearanceAnalysisGateway({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('personal_os/internal/appearance_model');

  final MethodChannel _channel;

  @override
  Future<bool> configureRuntimeCredential() async {
    try {
      final configured = await _channel.invokeMethod<Object?>(
        'configureRuntimeCredential',
      );
      return _boolean(configured);
    } on PlatformException catch (error) {
      throw SecureModelGatewayFailure(_stableFailureCode(error.code));
    } on Object {
      throw const SecureModelGatewayFailure('model.invalid_response');
    }
  }

  @override
  Future<void> clearRuntimeCredential() async {
    try {
      await _channel.invokeMethod<void>('clearRuntimeCredential');
    } on PlatformException catch (error) {
      throw SecureModelGatewayFailure(_stableFailureCode(error.code));
    } on Object {
      throw const SecureModelGatewayFailure('model.adapter_unavailable');
    }
  }

  @override
  Future<AppearanceModelCapabilities> inspectCapabilities() async {
    late final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('inspectCapabilities');
    } on PlatformException catch (error) {
      throw SecureModelGatewayFailure(_stableFailureCode(error.code));
    } on Object {
      throw const SecureModelGatewayFailure('model.adapter_unavailable');
    }
    try {
      final value = _map(raw);
      return AppearanceModelCapabilities(
        configured: _boolean(value['configured']),
        supportedBoundaries: _boundedList(
          value['supportedBoundaries'],
          2,
        ).map(_processingBoundary),
        runtimeCredentialReady:
            _boolean(value['runtimeCredentialReady']),
      );
    } on Object {
      throw const SecureModelGatewayFailure('model.invalid_response');
    }
  }

  @override
  Future<AppearanceAnalysisResult> analyze(
    AppearanceAnalysisInput input,
  ) async {
    late final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('analyzeAppearance', {
        'imageRef': input.imageRef,
        'observationContext': input.observationContext,
        'locale': input.locale,
        'promptVersion': input.promptVersion,
        'processingBoundary': input.processingBoundary.name,
      });
    } on PlatformException catch (error) {
      throw SecureModelGatewayFailure(_stableFailureCode(error.code));
    } on Object {
      throw const SecureModelGatewayFailure('model.adapter_unavailable');
    }
    try {
      return _decodeResult(raw);
    } on Object {
      throw const SecureModelGatewayFailure('model.invalid_response');
    }
  }
}

AppearanceAnalysisResult _decodeResult(Object? raw) {
  final value = _map(raw);
  return AppearanceAnalysisResult(
    findings: _boundedList(value['findings'], 32).map((item) {
      final finding = _map(item);
      return AppearanceFinding(
        dimension: _string(finding['dimension']),
        statement: _string(finding['statement']),
        confidence: _number(finding['confidence']).toDouble(),
        kind: switch (_string(finding['kind'])) {
          'observableFact' => AppearanceFindingKind.observableFact,
          'uncertainInference' => AppearanceFindingKind.uncertainInference,
          _ => throw const FormatException(),
        },
      );
    }),
    actions: _boundedList(value['actions'], 14).map((item) {
      final action = _map(item);
      return AppearanceActionSuggestion(
        title: _string(action['title']),
        rationale: _string(action['rationale']),
        dayOffset: _integer(action['dayOffset']),
        requiresHumanConfirmation:
            _boolean(action['requiresHumanConfirmation']),
      );
    }),
    modelTraceRef: _string(value['modelTraceRef']),
    modelId: _string(value['modelId']),
    promptVersion: _string(value['promptVersion']),
    inputSummaryRef: _string(value['inputSummaryRef']),
    risks: _boundedList(value['risks'], 32).map((item) {
      final risk = _map(item);
      return AppearanceRisk(
        code: _string(risk['code']),
        statement: _string(risk['statement']),
      );
    }),
    humanConfirmations: _boundedList(value['humanConfirmations'], 32).map((item) {
      final confirmation = _map(item);
      return AppearanceHumanConfirmation(
        code: _string(confirmation['code']),
        prompt: _string(confirmation['prompt']),
      );
    }),
  );
}

Map<Object?, Object?> _map(Object? value) => value is Map
    ? value.cast<Object?, Object?>()
    : throw const FormatException();

List<Object?> _list(Object? value) =>
    value is List ? value.cast<Object?>() : throw const FormatException();

List<Object?> _boundedList(Object? value, int maximumLength) {
  final items = _list(value);
  if (items.length > maximumLength) throw const FormatException();
  return items;
}

String _string(Object? value) =>
    value is String && value.isNotEmpty ? value : throw const FormatException();

num _number(Object? value) =>
    value is num ? value : throw const FormatException();

int _integer(Object? value) =>
    value is int ? value : throw const FormatException();

bool _boolean(Object? value) =>
    value is bool ? value : throw const FormatException();

AppearanceProcessingBoundary _processingBoundary(Object? value) =>
    switch (_string(value)) {
      'onDevice' => AppearanceProcessingBoundary.onDevice,
      'externalProcessor' => AppearanceProcessingBoundary.externalProcessor,
      _ => throw const FormatException(),
    };

String _stableFailureCode(String code) => switch (code) {
      'model.invalid_request' ||
      'model.vault_unavailable' ||
      'model.adapter_unavailable' ||
      'model.invalid_response' ||
      'model.media_too_large' ||
      'model.media_transcode_unavailable' =>
        code,
      _ => 'model.adapter_unavailable',
    };
