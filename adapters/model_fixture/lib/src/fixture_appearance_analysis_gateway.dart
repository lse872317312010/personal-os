import 'dart:convert';

import 'package:personal_os_model_gateway_api/model_gateway_api.dart';

/// Selects the deterministic behavior of [FixtureAppearanceAnalysisGateway].
enum FixtureAppearanceBehavior {
  syntheticSuccess,
  emptyResult,
  failure,
}

/// A deliberate, configurable failure emitted by the fixture gateway.
final class FixtureAppearanceAnalysisFailure implements Exception {
  const FixtureAppearanceAnalysisFailure([
    this.message = 'Synthetic appearance analysis failure.',
  ]);

  final String message;

  @override
  String toString() => 'FixtureAppearanceAnalysisFailure: $message';
}

/// Deterministic test/demo implementation of [AppearanceAnalysisGateway].
///
/// This adapter does not read the referenced blob, inspect a person, access the
/// filesystem, or use the network. Its findings and actions are fixed synthetic
/// fixtures. It accepts only opaque `blob://` references so callers cannot
/// accidentally pass raw bytes, local paths, or remote URLs.
final class FixtureAppearanceAnalysisGateway
    implements AppearanceAnalysisGateway {
  const FixtureAppearanceAnalysisGateway({
    this.behavior = FixtureAppearanceBehavior.syntheticSuccess,
    this.failureMessage = 'Synthetic appearance analysis failure.',
  });

  final FixtureAppearanceBehavior behavior;
  final String failureMessage;

  @override
  Future<AppearanceAnalysisResult> analyze(
    AppearanceAnalysisInput input,
  ) async {
    _validateBlobRef(input.imageRef);
    final traceRef = _stableTraceRef(input);

    return switch (behavior) {
      FixtureAppearanceBehavior.syntheticSuccess => AppearanceAnalysisResult(
          findings: <AppearanceFinding>[
            AppearanceFinding(
              dimension: 'synthetic_fixture_hair',
              statement: '合成示例：发型轮廓可建立一个可复核的基线。',
              confidence: 0.8,
            ),
            AppearanceFinding(
              dimension: 'synthetic_fixture_style',
              statement: '合成示例：整体风格可通过一次低成本实验验证。',
              confidence: 0.7,
            ),
          ],
          actions: <AppearanceActionSuggestion>[
            AppearanceActionSuggestion(
              title: '合成任务：记录一次造型对照',
              rationale: '仅用于验证 Personal OS 行动反馈闭环，不代表真人分析。',
            ),
          ],
          modelTraceRef: traceRef,
        ),
      FixtureAppearanceBehavior.emptyResult => AppearanceAnalysisResult(
          findings: const <AppearanceFinding>[],
          actions: const <AppearanceActionSuggestion>[],
          modelTraceRef: traceRef,
        ),
      FixtureAppearanceBehavior.failure =>
        throw FixtureAppearanceAnalysisFailure(failureMessage),
    };
  }
}

void _validateBlobRef(String value) {
  const prefix = 'blob://';
  final opaquePart =
      value.startsWith(prefix) ? value.substring(prefix.length) : '';
  if (opaquePart.isEmpty ||
      opaquePart.trim() != opaquePart ||
      opaquePart.contains(RegExp(r'\s'))) {
    throw ArgumentError.value(
      value,
      'imageRef',
      'must be a non-empty opaque blob:// reference',
    );
  }
}

String _stableTraceRef(AppearanceAnalysisInput input) {
  final material =
      '${input.imageRef}\u0000${input.observationContext}\u0000${input.locale}';
  var hash = 0x811c9dc5;
  for (final byte in utf8.encode(material)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return 'fixture://appearance/fnv1a32-${hash.toRadixString(16).padLeft(8, '0')}';
}
