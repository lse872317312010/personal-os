import 'package:personal_os_model_fixture/model_fixture.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';
import 'package:test/test.dart';

void main() {
  AppearanceAnalysisInput input({String imageRef = 'blob://vault/photo-1'}) =>
      AppearanceAnalysisInput(
        imageRef: imageRef,
        observationContext: 'fixture test context',
      );

  test('returns explicit synthetic findings and actions', () async {
    const gateway = FixtureAppearanceAnalysisGateway();

    final result = await gateway.analyze(input());

    expect(result.findings, hasLength(2));
    expect(
      result.findings.every(
        (finding) =>
            finding.dimension.startsWith('synthetic_fixture_') &&
            finding.statement.startsWith('合成示例：'),
      ),
      isTrue,
    );
    expect(result.actions, hasLength(1));
    expect(result.actions.single.title, startsWith('合成任务：'));
    expect(result.actions.single.rationale, contains('不代表真人分析'));
  });

  test('trace reference is stable and does not expose the blob reference', () async {
    const gateway = FixtureAppearanceAnalysisGateway();

    final first = await gateway.analyze(input());
    final second = await gateway.analyze(input());
    final different = await gateway.analyze(input(imageRef: 'blob://vault/photo-2'));

    expect(first.modelTraceRef, second.modelTraceRef);
    expect(first.modelTraceRef, startsWith('fixture://appearance/fnv1a32-'));
    expect(first.modelTraceRef, isNot(contains('photo-1')));
    expect(different.modelTraceRef, isNot(first.modelTraceRef));
  });

  test('rejects anything other than a non-empty blob double-slash ref', () async {
    const gateway = FixtureAppearanceAnalysisGateway();

    for (final invalid in <String>[
      'blob:photo-1',
      'file:///photo.jpg',
      'https://example.test/photo.jpg',
      '/tmp/photo.jpg',
      'blob://',
      'blob://vault/photo 1',
    ]) {
      await expectLater(
        gateway.analyze(input(imageRef: invalid)),
        throwsArgumentError,
        reason: invalid,
      );
    }
  });

  test('empty behavior returns a traceable empty result', () async {
    const gateway = FixtureAppearanceAnalysisGateway(
      behavior: FixtureAppearanceBehavior.emptyResult,
    );

    final result = await gateway.analyze(input());

    expect(result.findings, isEmpty);
    expect(result.actions, isEmpty);
    expect(result.modelTraceRef, startsWith('fixture://appearance/'));
  });

  test('failure behavior throws the configured fixture failure', () async {
    const gateway = FixtureAppearanceAnalysisGateway(
      behavior: FixtureAppearanceBehavior.failure,
      failureMessage: 'configured failure',
    );

    await expectLater(
      gateway.analyze(input()),
      throwsA(
        isA<FixtureAppearanceAnalysisFailure>().having(
          (error) => error.message,
          'message',
          'configured failure',
        ),
      ),
    );
  });
}
