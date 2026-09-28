import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/agent_interop/agent_text_share.dart';

void main() {
  test('shares text through the vendor-neutral native channel', () async {
    const channel = MethodChannel(MethodChannelAgentTextShare.channelName);
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    const text = 'Prompt and context for an arbitrary assistant.';
    await const MethodChannelAgentTextShare().share(text);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'shareText');
    expect(calls.single.arguments, <String, Object?>{'text': text});
  });
}
