import 'package:personal_os_events/events.dart';

enum CheckStatus { pass, unsupported, fail }

final class FixtureDocument {
  const FixtureDocument({
    required this.sequenceId,
    required this.contractTests,
    required this.events,
    required this.expectedResults,
    this.projectionAssertionCount = 0,
    this.invariantCount = 0,
  });

  final String sequenceId;
  final List<String> contractTests;
  final List<EventEnvelope> events;
  final List<String> expectedResults;
  final int projectionAssertionCount;
  final int invariantCount;
}

final class EventCheck {
  const EventCheck({
    required this.eventId,
    required this.occurrence,
    required this.status,
    required this.actual,
    required this.expected,
    this.reasonCode,
  });

  final String eventId;
  final int occurrence;
  final CheckStatus status;
  final String actual;
  final String expected;
  final String? reasonCode;

  Map<String, Object?> toJson() => <String, Object?>{
        'actual': actual,
        'event_id': eventId,
        'expected': expected,
        'occurrence': occurrence,
        if (reasonCode != null) 'reason_code': reasonCode,
        'status': status.name,
      };
}

final class FixtureReport {
  const FixtureReport({
    required this.sequenceId,
    required this.status,
    required this.checks,
    required this.summary,
  });

  final String sequenceId;
  final CheckStatus status;
  final List<EventCheck> checks;
  final Map<String, int> summary;

  Map<String, Object?> toJson() => <String, Object?>{
        'checks': checks.map((check) => check.toJson()).toList(),
        'sequence_id': sequenceId,
        'status': status.name,
        'summary': summary,
      };
}

final class CorpusReport {
  const CorpusReport(this.fixtures);

  final List<FixtureReport> fixtures;

  bool get hasFailures =>
      fixtures.any((fixture) => fixture.status == CheckStatus.fail);

  Map<String, Object?> toJson() {
    var passed = 0;
    var unsupported = 0;
    var failed = 0;
    for (final fixture in fixtures) {
      passed += fixture.summary['pass'] ?? 0;
      unsupported += fixture.summary['unsupported'] ?? 0;
      failed += fixture.summary['fail'] ?? 0;
    }
    return <String, Object?>{
      'adapter': 'dart-in-memory-v1',
      'fixtures': fixtures.map((fixture) => fixture.toJson()).toList(),
      'runner_version': 1,
      'status': failed > 0
          ? CheckStatus.fail.name
          : unsupported > 0
              ? CheckStatus.unsupported.name
              : CheckStatus.pass.name,
      'summary': <String, int>{
        'fail': failed,
        'pass': passed,
        'unsupported': unsupported,
      },
    };
  }
}
