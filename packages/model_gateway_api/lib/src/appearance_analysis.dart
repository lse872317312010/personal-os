abstract interface class AppearanceAnalysisGateway {
  Future<AppearanceAnalysisResult> analyze(AppearanceAnalysisInput input);
}

abstract interface class AppearanceModelCapabilityGateway {
  Future<AppearanceModelCapabilities> inspectCapabilities();
}

abstract interface class AppearanceModelCredentialGateway {
  Future<bool> configureRuntimeCredential();
  Future<void> clearRuntimeCredential();
}

abstract final class AppearanceModelGatewayFailureCode {
  static const invalidRequest = 'model.invalid_request';
  static const vaultUnavailable = 'model.vault_unavailable';
  static const adapterUnavailable = 'model.adapter_unavailable';
  static const invalidResponse = 'model.invalid_response';
  static const mediaTooLarge = 'model.media_too_large';
  static const mediaTranscodeUnavailable = 'model.media_transcode_unavailable';

  static const values = <String>{
    invalidRequest,
    vaultUnavailable,
    adapterUnavailable,
    invalidResponse,
    mediaTooLarge,
    mediaTranscodeUnavailable,
  };
}

/// Stable, redacted failure crossing a model-gateway boundary.
///
/// Only enumerated wire codes are accepted so provider messages, filesystem
/// paths, credentials, and raw response details cannot be smuggled through the
/// application layer as an error string.
final class AppearanceModelGatewayFailure implements Exception {
  AppearanceModelGatewayFailure(String code)
      : code = AppearanceModelGatewayFailureCode.values.contains(code)
            ? code
            : AppearanceModelGatewayFailureCode.adapterUnavailable;

  final String code;

  @override
  String toString() => 'AppearanceModelGatewayFailure($code)';
}

final class AppearanceModelCapabilities {
  AppearanceModelCapabilities({
    required this.configured,
    required Iterable<AppearanceProcessingBoundary> supportedBoundaries,
    required this.runtimeCredentialReady,
  }) : supportedBoundaries = Set<AppearanceProcessingBoundary>.unmodifiable(
          supportedBoundaries,
        ) {
    if (!configured && this.supportedBoundaries.isNotEmpty) {
      throw ArgumentError(
        'an unconfigured gateway cannot advertise processing boundaries',
      );
    }
    if (configured && this.supportedBoundaries.isEmpty) {
      throw ArgumentError(
        'a configured gateway must advertise a processing boundary',
      );
    }
    if (runtimeCredentialReady &&
        !this
            .supportedBoundaries
            .contains(AppearanceProcessingBoundary.externalProcessor)) {
      throw ArgumentError(
        'runtime credentials are only valid for external processing',
      );
    }
  }

  final bool configured;
  final Set<AppearanceProcessingBoundary> supportedBoundaries;
  final bool runtimeCredentialReady;

  bool get externalProcessingConfigured =>
      configured &&
      supportedBoundaries.contains(
        AppearanceProcessingBoundary.externalProcessor,
      );

  bool get externalProcessingAvailable =>
      externalProcessingConfigured && runtimeCredentialReady;

  bool get onDeviceProcessingAvailable =>
      configured &&
      supportedBoundaries.contains(AppearanceProcessingBoundary.onDevice);
}

enum AppearanceProcessingBoundary { onDevice, externalProcessor }

final class AppearanceAnalysisInput {
  AppearanceAnalysisInput({
    required String imageRef,
    required this.observationContext,
    this.locale = 'zh-CN',
    String promptVersion = 'appearance-v1',
    this.processingBoundary = AppearanceProcessingBoundary.onDevice,
  })  : imageRef = _nonBlank(imageRef, 'imageRef'),
        promptVersion = _nonBlank(promptVersion, 'promptVersion');

  final String imageRef;
  final String observationContext;
  final String locale;
  final String promptVersion;
  final AppearanceProcessingBoundary processingBoundary;
}

final class AppearanceAnalysisResult {
  AppearanceAnalysisResult({
    required Iterable<AppearanceFinding> findings,
    required Iterable<AppearanceActionSuggestion> actions,
    required String modelTraceRef,
    String modelId = 'unspecified-model',
    String promptVersion = 'appearance-v1',
    String inputSummaryRef = 'unavailable',
    Iterable<AppearanceRisk> risks = const <AppearanceRisk>[],
    Iterable<AppearanceHumanConfirmation> humanConfirmations =
        const <AppearanceHumanConfirmation>[],
  })  : findings = List<AppearanceFinding>.unmodifiable(findings),
        actions = List<AppearanceActionSuggestion>.unmodifiable(actions),
        modelTraceRef = _nonBlank(modelTraceRef, 'modelTraceRef'),
        modelId = _nonBlank(modelId, 'modelId'),
        promptVersion = _nonBlank(promptVersion, 'promptVersion'),
        inputSummaryRef = _nonBlank(inputSummaryRef, 'inputSummaryRef'),
        risks = List<AppearanceRisk>.unmodifiable(risks),
        humanConfirmations =
            List<AppearanceHumanConfirmation>.unmodifiable(humanConfirmations) {
    final confirmationCodes = <String>{};
    for (final confirmation in this.humanConfirmations) {
      if (!confirmationCodes.add(confirmation.code)) {
        throw ArgumentError.value(
          confirmation.code,
          'humanConfirmations',
          'must not contain duplicate codes',
        );
      }
    }
  }

  final List<AppearanceFinding> findings;
  final List<AppearanceActionSuggestion> actions;
  final String modelTraceRef;
  final String modelId;
  final String promptVersion;

  /// Opaque adapter-generated reference to a bounded input summary.
  ///
  /// This must not be a file path, provider URI, raw byte digest, API key, or
  /// model response. It exists only to correlate a trace with adapter-owned
  /// audit data.
  final String inputSummaryRef;
  final List<AppearanceRisk> risks;
  final List<AppearanceHumanConfirmation> humanConfirmations;
}

enum AppearanceFindingKind { observableFact, uncertainInference }

final class AppearanceFinding {
  AppearanceFinding({
    required String dimension,
    required String statement,
    required this.confidence,
    this.kind = AppearanceFindingKind.uncertainInference,
  })  : dimension = _nonBlank(dimension, 'dimension'),
        statement = _nonBlank(statement, 'statement') {
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final String dimension;
  final String statement;
  final double confidence;
  final AppearanceFindingKind kind;
}

final class AppearanceActionSuggestion {
  AppearanceActionSuggestion({
    required String title,
    required String rationale,
    this.dayOffset = 0,
    this.requiresHumanConfirmation = false,
  })  : title = _nonBlank(title, 'title'),
        rationale = _nonBlank(rationale, 'rationale') {
    if (dayOffset < 0 || dayOffset > 6) {
      throw ArgumentError.value(dayOffset, 'dayOffset', 'must be in [0, 6]');
    }
  }

  final String title;
  final String rationale;
  final int dayOffset;
  final bool requiresHumanConfirmation;
}

final class AppearanceRisk {
  AppearanceRisk({required String code, required String statement})
      : code = _stableCode(code, 'code'),
        statement = _nonBlank(statement, 'statement');

  final String code;
  final String statement;
}

final class AppearanceHumanConfirmation {
  AppearanceHumanConfirmation({required String code, required String prompt})
      : code = _stableCode(code, 'code'),
        prompt = _nonBlank(prompt, 'prompt');

  final String code;
  final String prompt;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}

String _stableCode(String value, String label) {
  final code = _nonBlank(value, label);
  if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(code)) {
    throw ArgumentError.value(
      value,
      label,
      'must be a stable lower_snake_case code',
    );
  }
  return code;
}
