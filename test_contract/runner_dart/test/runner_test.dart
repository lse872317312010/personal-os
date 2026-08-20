import 'package:personal_os_contract_runner/contract_runner.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:test/test.dart';

void main() {
  test('reports applied supported events as pass', () {
    final report = runFixture(FixtureDocument(
      sequenceId: 'S1',
      contractTests: const <String>['CT-001'],
      events: <EventEnvelope>[_event('E1', EventTypes.goalCreated)],
      expectedResults: const <String>['applied'],
    ));
    expect(report.status, CheckStatus.pass);
    expect(report.summary['pass'], 1);
  });

  test('reports unknown reducer scope without pretending it passed', () {
    final report = runFixture(FixtureDocument(
      sequenceId: 'S1',
      contractTests: const <String>[],
      events: <EventEnvelope>[_event('E1', 'future.event')],
      expectedResults: const <String>['applied'],
    ));
    expect(report.status, CheckStatus.unsupported);
    expect(report.checks.single.reasonCode, 'unsupported_event_type');
  });

  test('duplicate occurrence is checked independently', () {
    final event = _event('E1', EventTypes.goalCreated);
    final report = runFixture(FixtureDocument(
      sequenceId: 'S1',
      contractTests: const <String>[],
      events: <EventEnvelope>[event, event],
      expectedResults: const <String>['applied', 'ignored_duplicate'],
    ));
    expect(report.status, CheckStatus.pass);
    expect(report.checks.last.occurrence, 2);
  });

  test('D4 persistence is rejected by policy, not appended', () {
    final report = runFixture(FixtureDocument(
      sequenceId: 'S1',
      contractTests: const <String>[],
      events: <EventEnvelope>[
        _event('E1', EventTypes.goalCreated, sensitivity: Sensitivity.d4),
      ],
      expectedResults: const <String>['rejected'],
    ));
    expect(report.status, CheckStatus.pass);
    expect(report.checks.single.reasonCode, 'D4_PERSISTENCE_FORBIDDEN');
  });

  test('does not promote unverified cross-object assertions to pass', () {
    final report = runFixture(FixtureDocument(
      sequenceId: 'S1',
      contractTests: const <String>['CT-105'],
      events: <EventEnvelope>[_event('E1', EventTypes.goalCreated)],
      expectedResults: const <String>['applied'],
      projectionAssertionCount: 1,
      invariantCount: 1,
    ));
    expect(report.status, CheckStatus.unsupported);
    expect(report.checks.last.eventId, '<fixture-assertions>');
    expect(
      report.checks.last.reasonCode,
      'projection_and_cross_object_assertions_not_implemented',
    );
  });
}

EventEnvelope _event(
  String id,
  String type, {
  Sensitivity sensitivity = Sensitivity.d1,
}) =>
    EventEnvelope(
      eventId: id,
      eventType: type,
      eventVersion: 1,
      occurredAt: DateTime.utc(2026),
      recordedAt: DateTime.utc(2026),
      actor: ActorRef(
        actorId: 'user:self',
        actorType: ActorType.user,
        authoritySource: 'test',
      ),
      subjectRefs: <ObjectRef>[
        ObjectRef(type: 'goal', id: EntityId('G1')),
      ],
      correlationId: 'corr:test',
      sensitivity: sensitivity,
      payload: const <String, Object?>{},
    );
