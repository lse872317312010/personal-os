import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/agent_interop/agent_completion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('personal_os/test/agent_completion');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('sends the approved prompt only and never passes a credential', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'configureCredential' => true,
        'complete' => '{"strategy":{}}',
        'clearCredential' => null,
        _ => null,
      };
    });
    final port = MethodChannelAgentCompletionPort(channel: channel);

    expect(await port.configureCredential(), isTrue);
    expect(await port.complete('approved prompt'), '{"strategy":{}}');
    await port.clearCredential();

    expect(calls.map((call) => call.method), <String>[
      'configureCredential',
      'complete',
      'clearCredential',
    ]);
    expect(calls.first.arguments, isNull);
    expect(calls[1].arguments, <String, Object?>{'prompt': 'approved prompt'});
    expect(calls.map((call) => call.arguments.toString()).join(),
        isNot(contains('sk-secret')));
  });

  test('rejects an oversized prompt before it reaches the platform channel',
      () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      called = true;
      return 'unexpected';
    });
    final port = MethodChannelAgentCompletionPort(channel: channel);

    await expectLater(
      port.complete('x' * (maximumAgentPromptLength + 1)),
      throwsA(
        isA<AgentCompletionFailure>().having(
          (failure) => failure.code,
          'code',
          'agent.invalid_request',
        ),
      ),
    );
    expect(called, isFalse);
  });

  test('maps native errors to stable provider-neutral codes', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'agent.request_failed');
    });
    final port = MethodChannelAgentCompletionPort(channel: channel);

    await expectLater(
      port.complete('approved prompt'),
      throwsA(
        isA<AgentCompletionFailure>().having(
          (failure) => failure.code,
          'code',
          'agent.request_failed',
        ),
      ),
    );
  });
}
