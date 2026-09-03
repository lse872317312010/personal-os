import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/composition/method_channel_appearance_analysis_gateway.dart';
import 'package:personal_os_model_gateway_api/model_gateway_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('personal_os/test/appearance_model');
  const gateway = MethodChannelAppearanceAnalysisGateway(channel: channel);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('decodes a complete structured native result', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return _completeWireResult();
    });

    final result = await gateway.analyze(
      AppearanceAnalysisInput(
        imageRef: 'blob://1234567890abcdef',
        observationContext: 'front-facing natural light',
      ),
    );

    expect(received?.method, 'analyzeAppearance');
    expect((received?.arguments as Map)['imageRef'], 'blob://1234567890abcdef');
    expect((received?.arguments as Map)['processingBoundary'], 'onDevice');
    expect(result.modelId, 'native-fixture-v1');
    expect(result.findings.single.kind, AppearanceFindingKind.observableFact);
    expect(result.actions.single.dayOffset, 1);
    expect(result.risks.single.code, 'low_light');
    expect(result.humanConfirmations.single.code, 'confirm_hair_shape');
  });

  test('decodes redacted capability state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'inspectCapabilities');
      return <String, Object?>{
        'configured': true,
        'supportedBoundaries': <String>['externalProcessor'],
        'runtimeCredentialReady': true,
      };
    });

    final capabilities = await gateway.inspectCapabilities();

    expect(capabilities.configured, isTrue);
    expect(capabilities.externalProcessingConfigured, isTrue);
    expect(capabilities.externalProcessingAvailable, isTrue);
    expect(
      capabilities.supportedBoundaries,
      contains(AppearanceProcessingBoundary.externalProcessor),
    );
  });

  test('distinguishes configured external transport from credential readiness',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => <String, Object?>{
              'configured': true,
              'supportedBoundaries': <String>['externalProcessor'],
              'runtimeCredentialReady': false,
            });

    final capabilities = await gateway.inspectCapabilities();

    expect(capabilities.externalProcessingConfigured, isTrue);
    expect(capabilities.externalProcessingAvailable, isFalse);
  });

  test('configures runtime credential without a Dart credential value',
      () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    final accepted = await gateway.configureRuntimeCredential();

    expect(received?.method, 'configureRuntimeCredential');
    expect(received?.arguments, isNull);
    expect(accepted, isTrue);
  });

  test('reports native credential prompt cancellation without an error',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => false);

    expect(await gateway.configureRuntimeCredential(), isFalse);
  });

  test('clears runtime credential without sending arguments', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });

    await gateway.clearRuntimeCredential();

    expect(received?.method, 'clearRuntimeCredential');
    expect(received?.arguments, isNull);
  });

  test('maps malformed native output to a stable redacted failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => <String, Object?>{
              'findings': 'not-a-list',
            });

    await expectLater(
      gateway.analyze(
        AppearanceAnalysisInput(
          imageRef: 'blob://1234567890abcdef',
          observationContext: 'context',
        ),
      ),
      throwsA(
        isA<SecureModelGatewayFailure>()
            .having(
              (failure) => failure.code,
              'code',
              'model.invalid_response',
            )
            .having(
              (failure) => failure.toString(),
              'redacted',
              isNot(contains('not-a-list')),
            ),
      ),
    );
  });

  test('does not expose native platform error details', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'provider.raw_failure',
        message: 'api-key=secret provider response',
        details: '/data/user/0/private.jpg',
      );
    });

    await expectLater(
      gateway.analyze(
        AppearanceAnalysisInput(
          imageRef: 'blob://1234567890abcdef',
          observationContext: 'context',
        ),
      ),
      throwsA(
        isA<SecureModelGatewayFailure>()
            .having(
              (failure) => failure.code,
              'code',
              'model.adapter_unavailable',
            )
            .having(
              (failure) => failure.toString(),
              'redacted',
              allOf(isNot(contains('secret')), isNot(contains('/data/'))),
            ),
      ),
    );
  });
}

Map<String, Object?> _completeWireResult() => <String, Object?>{
      'findings': <Object?>[
        <String, Object?>{
          'dimension': 'hair_shape',
          'statement': 'Visible outline can be reviewed.',
          'confidence': 0.8,
          'kind': 'observableFact',
        },
      ],
      'actions': <Object?>[
        <String, Object?>{
          'title': 'Record a comparison',
          'rationale': 'Build a reviewable baseline.',
          'dayOffset': 1,
          'requiresHumanConfirmation': true,
        },
      ],
      'modelTraceRef': 'trace://native/1',
      'modelId': 'native-fixture-v1',
      'promptVersion': 'appearance-v1',
      'inputSummaryRef': 'audit://input/1',
      'risks': <Object?>[
        <String, Object?>{
          'code': 'low_light',
          'statement': 'Image may be too dark.',
        },
      ],
      'humanConfirmations': <Object?>[
        <String, Object?>{
          'code': 'confirm_hair_shape',
          'prompt': 'Does the visible outline match what you see?',
        },
      ],
    };
