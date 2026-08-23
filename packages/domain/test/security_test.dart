import 'package:personal_os_domain/domain.dart';
import 'package:test/test.dart';

void main() {
  group('ActorRef', () {
    test('rejects blank persisted identifiers', () {
      expect(() => _actor(actorId: ' '), throwsArgumentError);
      expect(() => _actor(authoritySource: '\n'), throwsArgumentError);
      expect(() => _actor(sessionOrRunId: ' '), throwsArgumentError);
      expect(() => _actor(onBehalfOf: '\t'), throwsArgumentError);
      expect(
          () => _actor(capabilityRefs: ['capture', '']), throwsArgumentError);
    });

    test('requires delegation identity for non-user actors', () {
      expect(
        () => ActorRef(
          actorId: 'agent-1',
          actorType: ActorType.agent,
          authoritySource: 'local-policy',
        ),
        throwsArgumentError,
      );
    });

    test('defensively copies and freezes capability references', () {
      final source = <String>['appearance.capture'];
      final actor = _actor(capabilityRefs: source);

      source.add('appearance.analyse');

      expect(actor.capabilityRefs, ['appearance.capture']);
      expect(
        () => actor.capabilityRefs.add('appearance.export'),
        throwsUnsupportedError,
      );
    });
  });
}

ActorRef _actor({
  String actorId = 'user-1',
  String authoritySource = 'local-user',
  String? sessionOrRunId,
  String? onBehalfOf,
  Iterable<String> capabilityRefs = const <String>[],
}) =>
    ActorRef(
      actorId: actorId,
      actorType: ActorType.user,
      authoritySource: authoritySource,
      sessionOrRunId: sessionOrRunId,
      onBehalfOf: onBehalfOf,
      capabilityRefs: capabilityRefs,
    );
