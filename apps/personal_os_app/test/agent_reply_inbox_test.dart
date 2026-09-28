import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/navigation/app_destination.dart';
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

    await port.signalReplyAvailable();
    expect(port.calls, 0);
    expect(inbox.pendingReply, isNull);

    unlocked = true;
    await port.signalReplyAvailable();
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

  test(
    'loads the next native reply after the current one is cleared',
    () async {
      final port = _FakeReplyPort('first reply');
      final inbox = AgentReplyInboxController(
        port: port,
        isVaultUnlocked: () => true,
      );
      addTearDown(inbox.dispose);

      await inbox.receivePendingReply();
      expect(inbox.pendingReply, 'first reply');
      expect(port.calls, 1);

      // A second Android share stays in the native slot while this one is shown.
      port.reply = 'second reply';
      await port.signalReplyAvailable();
      expect(inbox.pendingReply, 'first reply');
      expect(port.calls, 1);

      await inbox.clearPendingReply();

      expect(inbox.pendingReply, 'second reply');
      expect(port.calls, 2);
    },
  );

  test('reply availability signal has no body and waits for Vault unlock',
      () async {
    final channel = _RecordingMethodChannel();
    final inbox = AgentReplyInboxController(
      port: MethodChannelAgentReplyInboxPort(channel: channel),
      isVaultUnlocked: () => channel.vaultUnlocked,
    );
    addTearDown(inbox.dispose);

    await channel.sendFromHost(
      const MethodCall(
        MethodChannelAgentReplyInboxPort.replyAvailableMethodName,
      ),
    );
    expect(channel.outboundCalls, isEmpty);
    expect(inbox.pendingReply, isNull);

    channel.vaultUnlocked = true;
    await channel.sendFromHost(
      const MethodCall(
        MethodChannelAgentReplyInboxPort.replyAvailableMethodName,
      ),
    );
    expect(
      channel.outboundCalls.map((call) => call.method),
      <String>['takePendingReply'],
    );
    expect(channel.outboundCalls.single.arguments, isNull);
    expect(inbox.pendingReply, 'shared assistant reply');

    await expectLater(
      channel.sendFromHost(
        const MethodCall(
          MethodChannelAgentReplyInboxPort.replyAvailableMethodName,
          'reply text must not be in the marker',
        ),
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(channel.outboundCalls, hasLength(1));
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
  testWidgets('preserves an existing draft when a shared reply arrives',
      (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(390, 1800);
    tester.view.devicePixelRatio = 1;

    final port = _FakeReplyPort(null);
    final composition = AppComposition.inMemoryDemo(replyInboxPort: port);
    addTearDown(composition.strategyController.dispose);
    await composition.strategyController.openOfflineSession(
      agentId: 'generic-share-test',
    );

    await tester.pumpWidget(PersonalOsApp(composition: composition));
    await tester.tap(find.byKey(const Key('unlock-vault')));
    await tester.pumpAndSettle();
    composition.controller.navigate(AppDestination.strategy);
    await tester.pumpAndSettle();

    final replyInput = find.byKey(const Key('agent-reply-input'));
    await tester.scrollUntilVisible(
      replyInput,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(replyInput, 'my unsent draft');

    port.reply = 'shared assistant reply';
    await port.signalReplyAvailable();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(replyInput).controller!.text,
      'my unsent draft',
    );
    expect(composition.replyInbox.pendingReply, 'shared assistant reply');
    expect(composition.strategyController.hasPendingProposal, isFalse);
    expect(composition.strategyController.hasPendingReview, isFalse);

    final loadReply = find.byKey(const Key('load-received-agent-reply'));
    await tester.ensureVisible(loadReply);
    await tester.tap(loadReply);
    await tester.pumpAndSettle();
    expect(find.text('替换当前输入？'), findsOneWidget);
    await tester.tap(find.text('保留当前输入'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(replyInput).controller!.text,
      'my unsent draft',
    );

    await tester.ensureVisible(loadReply);
    await tester.tap(loadReply);
    await tester.pumpAndSettle();
    await tester.tap(find.text('替换输入'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(replyInput).controller!.text,
      'shared assistant reply',
    );

    await tester.enterText(replyInput, 'another unsent draft');
    final discardReply =
        find.byKey(const Key('discard-received-agent-reply'));
    await tester.ensureVisible(discardReply);
    await tester.tap(discardReply);
    await tester.pumpAndSettle();
    expect(composition.replyInbox.pendingReply, isNull);
    expect(
      tester.widget<TextField>(replyInput).controller!.text,
      'another unsent draft',
    );
    expect(composition.strategyController.hasPendingProposal, isFalse);
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
  AgentReplyAvailableHandler? _replyAvailableHandler;

  @override
  Future<String?> takePendingReply() async {
    calls++;
    final result = reply;
    reply = null;
    return result;
  }

  @override
  void setReplyAvailableHandler(AgentReplyAvailableHandler? handler) {
    _replyAvailableHandler = handler;
  }

  Future<void> signalReplyAvailable() async {
    final handler = _replyAvailableHandler;
    if (handler != null) await handler();
  }
}

final class _RecordingMethodChannel extends MethodChannel {
  _RecordingMethodChannel() : super('reply_channel_test');

  Future<dynamic> Function(MethodCall call)? _methodCallHandler;
  final List<MethodCall> outboundCalls = <MethodCall>[];
  bool vaultUnlocked = false;

  Future<void> sendFromHost(MethodCall call) async {
    final handler = _methodCallHandler;
    if (handler == null) throw StateError('No Dart method handler registered.');
    await handler(call);
  }

  @override
  void setMethodCallHandler(
    Future<dynamic> Function(MethodCall call)? handler,
  ) {
    _methodCallHandler = handler;
  }

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    outboundCalls.add(MethodCall(method, arguments));
    if (method == 'takePendingReply') {
      return 'shared assistant reply' as T?;
    }
    return null;
  }
}
