import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/agent_interop/agent_reply_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('does not take a reply until the Vault is unlocked', () async {
    final port = _FakeReplyPort('assistant reply');
    var unlocked = false;
    final inbox = AgentReplyInboxController(
      port: port,
      isVaultUnlocked: () => unlocked,
    );
    addTearDown(inbox.dispose);

    await inbox.receivePendingReply();
    expect(port.calls, 0);
    expect(inbox.pendingReply, isNull);

    unlocked = true;
    await inbox.receivePendingReply();
    expect(port.calls, 1);
    expect(inbox.pendingReply, 'assistant reply');
    expect(inbox.vaultOpen, isTrue);

    unlocked = false;
    inbox.clearForVaultLock();
    expect(inbox.pendingReply, isNull);
    expect(inbox.vaultOpen, isFalse);
  });

  test('rejects empty and oversized replies before exposing them', () async {
    const unlocked = true;
    final empty = AgentReplyInboxController(
      port: _FakeReplyPort('  '),
      isVaultUnlocked: () => unlocked,
    );
    final oversized = AgentReplyInboxController(
      port: _FakeReplyPort(
        List<String>.filled(
          AgentReplyInboxController.maxReplyBytes + 1,
          'x',
        ).join(),
      ),
      isVaultUnlocked: () => unlocked,
    );
    addTearDown(empty.dispose);
    addTearDown(oversized.dispose);

    await empty.receivePendingReply();
    await oversized.receivePendingReply();
    expect(empty.pendingReply, isNull);
    expect(oversized.pendingReply, isNull);
  });

  test('reads through a named vendor-neutral method channel', () async {
    const channel = MethodChannel(
      MethodChannelAgentReplyInboxPort.channelName,
    );
    final calls = <MethodCall>[];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return 'shared assistant reply';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final inbox = AgentReplyInboxController(
      port: const MethodChannelAgentReplyInboxPort(),
      isVaultUnlocked: () => true,
    );
    addTearDown(inbox.dispose);

    await inbox.receivePendingReply();

    expect(inbox.pendingReply, 'shared assistant reply');
    expect(calls.map((call) => call.method), <String>['takePendingReply']);
    expect(calls.single.arguments, isNull);
  });

  testWidgets('received replies are shown after unlock and never auto-imported',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;

    final port = _FakeReplyPort('plain assistant reply');
    final composition = AppComposition.inMemoryDemo(replyInboxPort: port);
    addTearDown(composition.strategyController.dispose);
    await composition.strategyController.openOfflineSession(
      agentId: 'generic-share-test',
    );

    await tester.pumpWidget(PersonalOsApp(composition: composition));
    expect(port.calls, 0);
    expect(find.text('我的 Personal OS'), findsOneWidget);

    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();

    expect(port.calls, 1);
    expect(
        find.byKey(const Key('incoming-agent-reply-banner')), findsOneWidget);
    expect(composition.strategyController.hasPendingProposal, isFalse);
    expect(composition.strategyController.hasPendingReview, isFalse);

    await tester.tap(find.text('查看回复'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('agent-reply-input')),
      300,
      scrollable: find.byType(Scrollable).first,
    );

    final replyField =
        tester.widget<TextField>(find.byKey(const Key('agent-reply-input')));
    expect(replyField.controller!.text, 'plain assistant reply');
    expect(composition.strategyController.hasPendingProposal, isFalse);
    expect(composition.strategyController.hasPendingReview, isFalse);

    await tester.ensureVisible(find.byKey(const Key('import-agent-reply')));
    await tester.tap(find.byKey(const Key('import-agent-reply')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('agent-reply-input')))
          .controller!
          .text,
      'plain assistant reply',
    );
    expect(composition.strategyController.hasPendingProposal, isFalse);

    await tester.tap(find.byKey(const Key('lock-vault')));
    await tester.pumpAndSettle();
    expect(composition.replyInbox.pendingReply, isNull);
    expect(composition.controller.vaultUnlocked, isFalse);
  });
  testWidgets('does not attach a reply when its session was not restored',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;

    final port = _FakeReplyPort('reply from an unknown session');
    final composition = AppComposition.inMemoryDemo(replyInboxPort: port);
    addTearDown(composition.strategyController.dispose);

    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看回复'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('orphaned-agent-reply')), findsOneWidget);
    expect(find.byKey(const Key('agent-reply-input')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('open-agent-session')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('discard-orphaned-agent-reply')));
    await tester.pumpAndSettle();
    expect(composition.replyInbox.pendingReply, isNull);
    expect(find.byKey(const Key('orphaned-agent-reply')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('open-agent-session')))
          .onPressed,
      isNotNull,
    );
  });
}

final class _FakeReplyPort implements AgentReplyInboxPort {
  _FakeReplyPort(this.reply);

  String? reply;
  int calls = 0;

  @override
  Future<String?> takePendingReply() async {
    calls++;
    final result = reply;
    reply = null;
    return result;
  }
}
