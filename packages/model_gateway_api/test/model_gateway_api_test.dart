import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:test/test.dart';

void main() {
  group('AppearanceModelCapabilities', () {
    test('external availability requires configuration and credentials', () {
      final capabilities = AppearanceModelCapabilities(
        configured: true,
        supportedBoundaries: const <AppearanceProcessingBoundary>{
          AppearanceProcessingBoundary.externalProcessor,
        },
        runtimeCredentialReady: true,
      );
      expect(capabilities.externalProcessingConfigured, isTrue);
      expect(capabilities.externalProcessingAvailable, isTrue);
    });

    test('external configuration is visible before credentials are ready', () {
      final capabilities = AppearanceModelCapabilities(
        configured: true,
        supportedBoundaries: const <AppearanceProcessingBoundary>{
          AppearanceProcessingBoundary.externalProcessor,
        },
        runtimeCredentialReady: false,
      );

      expect(capabilities.externalProcessingConfigured, isTrue);
      expect(capabilities.externalProcessingAvailable, isFalse);
    });

    test('unconfigured gateway cannot advertise a processing boundary', () {
      expect(
        () => AppearanceModelCapabilities(
          configured: false,
          supportedBoundaries: const <AppearanceProcessingBoundary>{
            AppearanceProcessingBoundary.onDevice,
          },
          runtimeCredentialReady: false,
        ),
        throwsArgumentError,
      );
    });

    test('on-device gateway cannot advertise external credentials', () {
      expect(
        () => AppearanceModelCapabilities(
          configured: true,
          supportedBoundaries: const <AppearanceProcessingBoundary>{
            AppearanceProcessingBoundary.onDevice,
          },
          runtimeCredentialReady: true,
        ),
        throwsArgumentError,
      );
    });

    test('configured gateway must advertise a processing boundary', () {
      expect(
        () => AppearanceModelCapabilities(
          configured: true,
          supportedBoundaries: const <AppearanceProcessingBoundary>{},
          runtimeCredentialReady: false,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AppearanceAnalysisInput', () {
    test('accepts valid input with default locale', () {
      final input = AppearanceAnalysisInput(
        imageRef: 'blob-abc123',
        observationContext: 'front-facing natural light',
      );
      expect(input.imageRef, 'blob-abc123');
      expect(input.observationContext, 'front-facing natural light');
      expect(input.locale, 'zh-CN');
      expect(input.promptVersion, 'appearance-v1');
      expect(
        input.processingBoundary,
        AppearanceProcessingBoundary.onDevice,
      );
    });

    test('accepts explicit locale', () {
      final input = AppearanceAnalysisInput(
        imageRef: 'blob-1',
        observationContext: 'ctx',
        locale: 'en-US',
      );
      expect(input.locale, 'en-US');
    });

    test('accepts explicit external processing boundary', () {
      final input = AppearanceAnalysisInput(
        imageRef: 'blob-1',
        observationContext: 'ctx',
        processingBoundary: AppearanceProcessingBoundary.externalProcessor,
      );
      expect(
        input.processingBoundary,
        AppearanceProcessingBoundary.externalProcessor,
      );
    });

    test('rejects blank imageRef', () {
      expect(
        () =>
            AppearanceAnalysisInput(imageRef: '  ', observationContext: 'ctx'),
        throwsArgumentError,
      );
    });

    test('rejects empty imageRef', () {
      expect(
        () => AppearanceAnalysisInput(imageRef: '', observationContext: 'ctx'),
        throwsArgumentError,
      );
    });

    test('rejects blank promptVersion', () {
      expect(
        () => AppearanceAnalysisInput(
          imageRef: 'blob-1',
          observationContext: 'ctx',
          promptVersion: '  ',
        ),
        throwsArgumentError,
      );
    });
  });

  group('AppearanceFinding', () {
    test('accepts valid finding', () {
      final finding = AppearanceFinding(
        dimension: 'skin_tone',
        statement: 'warm undertone',
        confidence: 0.82,
      );
      expect(finding.dimension, 'skin_tone');
      expect(finding.statement, 'warm undertone');
      expect(finding.confidence, 0.82);
      expect(finding.kind, AppearanceFindingKind.uncertainInference);
    });

    test('accepts boundary confidence values', () {
      expect(
          AppearanceFinding(dimension: 'd', statement: 's', confidence: 0.0)
              .confidence,
          0.0);
      expect(
          AppearanceFinding(dimension: 'd', statement: 's', confidence: 1.0)
              .confidence,
          1.0);
    });

    test('rejects confidence below zero', () {
      expect(
        () =>
            AppearanceFinding(dimension: 'd', statement: 's', confidence: -0.1),
        throwsArgumentError,
      );
    });

    test('rejects confidence above one', () {
      expect(
        () =>
            AppearanceFinding(dimension: 'd', statement: 's', confidence: 1.1),
        throwsArgumentError,
      );
    });

    test('rejects blank dimension', () {
      expect(
        () =>
            AppearanceFinding(dimension: '  ', statement: 's', confidence: 0.5),
        throwsArgumentError,
      );
    });

    test('rejects blank statement', () {
      expect(
        () => AppearanceFinding(dimension: 'd', statement: '', confidence: 0.5),
        throwsArgumentError,
      );
    });
  });

  group('AppearanceActionSuggestion', () {
    test('accepts valid suggestion', () {
      final suggestion = AppearanceActionSuggestion(
        title: 'Use moisturizer',
        rationale: 'dry skin detected',
      );
      expect(suggestion.title, 'Use moisturizer');
      expect(suggestion.rationale, 'dry skin detected');
    });

    test('rejects blank title', () {
      expect(
        () => AppearanceActionSuggestion(title: '  ', rationale: 'r'),
        throwsArgumentError,
      );
    });

    test('rejects blank rationale', () {
      expect(
        () => AppearanceActionSuggestion(title: 't', rationale: ''),
        throwsArgumentError,
      );
    });

    test('accepts a bounded seven-day offset and confirmation flag', () {
      final suggestion = AppearanceActionSuggestion(
        title: 'Compare',
        rationale: 'Build a baseline',
        dayOffset: 6,
        requiresHumanConfirmation: true,
      );
      expect(suggestion.dayOffset, 6);
      expect(suggestion.requiresHumanConfirmation, isTrue);
    });

    test('rejects an action outside the seven-day window', () {
      expect(
        () => AppearanceActionSuggestion(
          title: 'Compare',
          rationale: 'Build a baseline',
          dayOffset: 7,
        ),
        throwsArgumentError,
      );
    });
  });

  group('AppearanceAnalysisResult', () {
    test('accepts valid result', () {
      final result = AppearanceAnalysisResult(
        findings: [
          AppearanceFinding(
              dimension: 'skin', statement: 'oily', confidence: 0.9),
        ],
        actions: [
          AppearanceActionSuggestion(
              title: 'Use toner', rationale: 'oil control'),
        ],
        modelTraceRef: 'trace-xyz',
      );
      expect(result.findings, hasLength(1));
      expect(result.actions, hasLength(1));
      expect(result.modelTraceRef, 'trace-xyz');
      expect(result.modelId, 'unspecified-model');
      expect(result.promptVersion, 'appearance-v1');
      expect(result.inputSummaryRef, 'unavailable');
    });

    test('rejects blank modelTraceRef', () {
      expect(
        () => AppearanceAnalysisResult(
          findings: const [],
          actions: const [],
          modelTraceRef: '  ',
        ),
        throwsArgumentError,
      );
    });

    test('findings list is unmodifiable', () {
      final result = AppearanceAnalysisResult(
        findings: [
          AppearanceFinding(dimension: 'd', statement: 's', confidence: 0.5),
        ],
        actions: const [],
        modelTraceRef: 'trace-1',
      );
      expect(
        () => result.findings.add(
          AppearanceFinding(dimension: 'd2', statement: 's2', confidence: 0.5),
        ),
        throwsUnsupportedError,
      );
    });

    test('actions list is unmodifiable', () {
      final result = AppearanceAnalysisResult(
        findings: const [],
        actions: [
          AppearanceActionSuggestion(title: 't', rationale: 'r'),
        ],
        modelTraceRef: 'trace-1',
      );
      expect(
        () => result.actions.add(
          AppearanceActionSuggestion(title: 't2', rationale: 'r2'),
        ),
        throwsUnsupportedError,
      );
    });

    test('empty findings and actions are allowed', () {
      final result = AppearanceAnalysisResult(
        findings: const [],
        actions: const [],
        modelTraceRef: 'trace-empty',
      );
      expect(result.findings, isEmpty);
      expect(result.actions, isEmpty);
    });

    test('accepts structured risk and human-confirmation metadata', () {
      final result = AppearanceAnalysisResult(
        findings: const <AppearanceFinding>[],
        actions: const <AppearanceActionSuggestion>[],
        modelTraceRef: 'trace-1',
        modelId: 'provider-model-1',
        promptVersion: 'appearance-v2',
        inputSummaryRef: 'audit://input/1',
        risks: <AppearanceRisk>[
          AppearanceRisk(code: 'low_light', statement: 'Image is too dark.'),
        ],
        humanConfirmations: <AppearanceHumanConfirmation>[
          AppearanceHumanConfirmation(
            code: 'confirm_hair_shape',
            prompt: 'Does this match what you see?',
          ),
        ],
      );
      expect(result.risks.single.code, 'low_light');
      expect(result.humanConfirmations.single.code, 'confirm_hair_shape');
    });

    test('rejects duplicate human-confirmation codes', () {
      expect(
        () => AppearanceAnalysisResult(
          findings: const <AppearanceFinding>[],
          actions: const <AppearanceActionSuggestion>[],
          modelTraceRef: 'trace-1',
          humanConfirmations: <AppearanceHumanConfirmation>[
            AppearanceHumanConfirmation(code: 'confirm', prompt: 'First?'),
            AppearanceHumanConfirmation(code: 'confirm', prompt: 'Second?'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('rejects unstable risk codes', () {
      expect(
        () => AppearanceRisk(code: 'Low-Light', statement: 'Too dark.'),
        throwsArgumentError,
      );
    });
  });
}
