import 'dart:convert';
import 'dart:io';

import 'package:personal_os_events/events.dart';
import 'package:personal_os_in_memory/in_memory.dart';
import 'package:personal_os_policy/policy.dart';

import 'decoder.dart';
import 'models.dart';

const _supportedTypes = <String>{
  EventTypes.sourceRegistered,
  EventTypes.observationRecorded,
  EventTypes.baselineCreated,
  EventTypes.opportunityIdentified,
  EventTypes.recommendationCreated,
  EventTypes.executionRecorded,
  EventTypes.outcomeRecorded,
  EventTypes.constraintRecorded,
  EventTypes.claimProposed,
  EventTypes.claimConfirmed,
  EventTypes.claimDisputed,
  EventTypes.claimExpired,
  EventTypes.claimWithdrawn,
  EventTypes.goalCreated,
  EventTypes.goalActivated,
  EventTypes.goalPaused,
  EventTypes.goalCompleted,
  EventTypes.planDrafted,
  EventTypes.planApproved,
  EventTypes.planActivated,
  EventTypes.planPaused,
  EventTypes.planCompleted,
  EventTypes.planStopped,
  EventTypes.taskPlanned,
  EventTypes.taskReady,
  EventTypes.taskInProgress,
  EventTypes.taskCompleted,
  EventTypes.taskSkipped,
  EventTypes.taskFailed,
  EventTypes.taskStopped,
  EventTypes.consentRequested,
  EventTypes.consentGranted,
  EventTypes.consentRevoked,
  EventTypes.consentExpired,
  EventTypes.reviewCreated,
  EventTypes.reviewUserReviewed,
  EventTypes.reviewAccepted,
  EventTypes.reviewRejected,
  EventTypes.modelRevisionProposed,
  EventTypes.modelRevisionAccepted,
  EventTypes.deletionRequested,
  EventTypes.deletionCompleted,
  EventTypes.conflictDetected,
  EventTypes.conflictResolutionProposed,
  EventTypes.conflictResolved,
  EventTypes.conflictDismissed,
};

Future<CorpusReport> runManifest(String manifestPath) async {
  final paths = await loadFixturePaths(manifestPath);
  final reports = <FixtureReport>[];
  for (final path in paths) {
    try {
      reports.add(runFixture(decodeFixture(await File(path).readAsString())));
    } on Object catch (error) {
      reports.add(FixtureReport(
        sequenceId: _basenameWithoutJson(path),
        status: CheckStatus.fail,
        checks: <EventCheck>[
          EventCheck(
            eventId: '<fixture>',
            occurrence: 1,
            status: CheckStatus.fail,
            actual: 'decode_error',
            expected: 'valid_fixture',
            reasonCode: error.runtimeType.toString(),
          ),
        ],
        summary: const <String, int>{'fail': 1, 'pass': 0, 'unsupported': 0},
      ));
    }
  }
  return CorpusReport(List.unmodifiable(reports));
}

FixtureReport runFixture(FixtureDocument fixture) {
  final store = InMemoryEventStore();
  final occurrences = <String, int>{};
  final checks = <EventCheck>[];
  for (var index = 0; index < fixture.events.length; index++) {
    final event = fixture.events[index];
    final occurrence = occurrences.update(
      event.eventId,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    final expected = index < fixture.expectedResults.length
        ? fixture.expectedResults[index]
        : 'unspecified';
    final persistence = authorizePersistence(event.sensitivity);
    if (!persistence.isAllowed) {
      checks.add(EventCheck(
        eventId: event.eventId,
        occurrence: occurrence,
        status: expected == 'rejected' ? CheckStatus.pass : CheckStatus.fail,
        actual: 'rejected',
        expected: expected,
        reasonCode: persistence.reasonCode,
      ));
      continue;
    }
    if (!_supportedTypes.contains(event.eventType)) {
      checks.add(EventCheck(
        eventId: event.eventId,
        occurrence: occurrence,
        status: CheckStatus.unsupported,
        actual: 'not_run',
        expected: expected,
        reasonCode: 'unsupported_event_type',
      ));
      continue;
    }
    final result = store.appendTransaction(<EventEnvelope>[event]);
    final actual = result.committed
        ? result.duplicateEventIds.isEmpty
            ? 'applied'
            : 'ignored_duplicate'
        : 'rejected';
    if (!result.committed &&
        (result.reasonCode == ReductionReason.missingSubject ||
            result.reasonCode == ReductionReason.illegalStateTransition)) {
      checks.add(EventCheck(
        eventId: event.eventId,
        occurrence: occurrence,
        status: CheckStatus.unsupported,
        actual: actual,
        expected: expected,
        reasonCode: 'fixture_requires_unimplemented_projection_or_seed',
      ));
      continue;
    }
    checks.add(EventCheck(
      eventId: event.eventId,
      occurrence: occurrence,
      status: actual == expected ? CheckStatus.pass : CheckStatus.fail,
      actual: actual,
      expected: expected,
      reasonCode: result.reasonCode,
    ));
  }
  if (fixture.projectionAssertionCount > 0 || fixture.invariantCount > 0) {
    checks.add(EventCheck(
      eventId: '<fixture-assertions>',
      occurrence: 1,
      status: CheckStatus.unsupported,
      actual: 'not_run',
      expected: 'verified',
      reasonCode: 'projection_and_cross_object_assertions_not_implemented',
    ));
  }
  final summary = <String, int>{'fail': 0, 'pass': 0, 'unsupported': 0};
  for (final check in checks) {
    summary[check.status.name] = summary[check.status.name]! + 1;
  }
  final status = summary['fail']! > 0
      ? CheckStatus.fail
      : summary['unsupported']! > 0
          ? CheckStatus.unsupported
          : CheckStatus.pass;
  return FixtureReport(
    sequenceId: fixture.sequenceId,
    status: status,
    checks: List.unmodifiable(checks),
    summary: Map.unmodifiable(summary),
  );
}

String encodeStableReport(CorpusReport report) => '${jsonEncode(report.toJson())}\n';

String _basenameWithoutJson(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  return name.endsWith('.json') ? name.substring(0, name.length - 5) : name;
}
