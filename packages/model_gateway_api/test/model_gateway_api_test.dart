import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:test/test.dart';

void main() {
  group('AppearanceAnalysisInput', () {
    test('accepts valid input with default locale', () {
      final input = AppearanceAnalysisInput(
        imageRef: 'blob-abc123',
        observationContext: 'front-facing natural light',
      );
      expect(input.imageRef, 'blob-abc123');
      expect(input.observationContext, 'front-facing natural light');
      expect(input.locale, 'zh-CN');
    });

    test('accepts explicit locale', () {
      final input = AppearanceAnalysisInput(
        imageRef: 'blob-1',
        observationContext: 'ctx',
        locale: 'en-US',
      );
      expect(input.locale, 'en-US');
    });

    test('rejects blank imageRef', () {
      expect(
        () => AppearanceAnalysisInput(imageRef: '  ', observationContext: 'ctx'),
        throwsArgumentError,
      );
    });

    test('rejects empty imageRef', () {
      expect(
        () => AppearanceAnalysisInput(imageRef: '', observationContext: 'ctx'),
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
    });

    test('accepts boundary confidence values', () {
      expect(AppearanceFinding(dimension: 'd', statement: 's', confidence: 0.0).confidence, 0.0);
      expect(AppearanceFinding(dimension: 'd', statement: 's', confidence: 1.0).confidence, 1.0);
    });

    test('rejects confidence below zero', () {
      expect(
        () => AppearanceFinding(dimension: 'd', statement: 's', confidence: -0.1),
        throwsArgumentError,
      );
    });

    test('rejects confidence above one', () {
      expect(
        () => AppearanceFinding(dimension: 'd', statement: 's', confidence: 1.1),
        throwsArgumentError,
      );
    });

    test('rejects blank dimension', () {
      expect(
        () => AppearanceFinding(dimension: '  ', statement: 's', confidence: 0.5),
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
  });

  group('AppearanceAnalysisResult', () {
    test('accepts valid result', () {
      final result = AppearanceAnalysisResult(
        findings: [
          AppearanceFinding(dimension: 'skin', statement: 'oily', confidence: 0.9),
        ],
        actions: [
          AppearanceActionSuggestion(title: 'Use toner', rationale: 'oil control'),
        ],
        modelTraceRef: 'trace-xyz',
      );
      expect(result.findings, hasLength(1));
      expect(result.actions, hasLength(1));
      expect(result.modelTraceRef, 'trace-xyz');
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
  });
}
