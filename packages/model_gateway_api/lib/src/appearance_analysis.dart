abstract interface class AppearanceAnalysisGateway {
  Future<AppearanceAnalysisResult> analyze(AppearanceAnalysisInput input);
}

final class AppearanceAnalysisInput {
  AppearanceAnalysisInput({
    required String imageRef,
    required this.observationContext,
    this.locale = 'zh-CN',
  }) : imageRef = _nonBlank(imageRef, 'imageRef');

  final String imageRef;
  final String observationContext;
  final String locale;
}

final class AppearanceAnalysisResult {
  AppearanceAnalysisResult({
    required Iterable<AppearanceFinding> findings,
    required Iterable<AppearanceActionSuggestion> actions,
    required String modelTraceRef,
  })  : findings = List<AppearanceFinding>.unmodifiable(findings),
        actions = List<AppearanceActionSuggestion>.unmodifiable(actions),
        modelTraceRef = _nonBlank(modelTraceRef, 'modelTraceRef');

  final List<AppearanceFinding> findings;
  final List<AppearanceActionSuggestion> actions;
  final String modelTraceRef;
}

final class AppearanceFinding {
  AppearanceFinding({
    required String dimension,
    required String statement,
    required this.confidence,
  })  : dimension = _nonBlank(dimension, 'dimension'),
        statement = _nonBlank(statement, 'statement') {
    if (confidence < 0 || confidence > 1) {
      throw ArgumentError.value(confidence, 'confidence', 'must be in [0, 1]');
    }
  }

  final String dimension;
  final String statement;
  final double confidence;
}

final class AppearanceActionSuggestion {
  AppearanceActionSuggestion({
    required String title,
    required String rationale,
  })  : title = _nonBlank(title, 'title'),
        rationale = _nonBlank(rationale, 'rationale');

  final String title;
  final String rationale;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}
