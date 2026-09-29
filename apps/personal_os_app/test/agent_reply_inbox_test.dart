import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_app/src/navigation/app_destination.dart';
import 'package:personal_os_app/src/agent_interop/agent_reply_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('keeps a reply until acknowledged and does not read while locked', () async {
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
    expect(port.reply, 'assistant reply');

    unlocked = true;
    await inbox.receivePendingReply();
    expect(inbox.pendingReply, 'assistant reply');
    await inbox.clearPendingReply();
    expect(port.reply, isNull);
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

  test('keeps a reply queued when Vault locks during a native read', () async {
    final port = _DelayedReplyPort('reply interrupted by lock');
    var unlocked = true;
    final inbox = AgentReplyInboxController(
      port: port,
      isVaultUnlocked: () => unlocked,
    );
    addTearDown(inbox.dispose);

    final received = Completer<void>();
    inbox.addListener(() {
      if (inbox.pendingReply != null && !received.isCompleted) {
        received.complete();
      }
    });

    final loading = inbox.receivePendingReply();
    await port.readStarted.future;
    unlocked = false;
    inbox.clearForVaultLock();

    // Unlock again before the old read returns. Its stale generation must
    // trigger a fresh read instead of leaving the inbox waiting forever.
    unlocked = true;
    await inbox.receivePendingReply();
    port.releaseRead.complete();
    await loading;
    await received.future;

    expect(inbox.pendingReply, 'reply interrupted by lock');
    expect(port.reply, 'reply interrupted by lock');
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
      if (call.method == 'peekPendingReply') return 'shared assistant reply';
      if (call.method == 'pendingReplyCount') return 1;
      if (call.method == 'takeDroppedReplyCount') return 0;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final inbox = AgentReplyInboxController(
      port: const MethodChannelAgentReplyInboxPort(),
      isVaultUnlocked: () => true,
    );
    addTearDown(inbox.dispose);

    await inbox.receivePendingReply();

    expect(inbox.pendingReply, 'shared assistant reply');
    expect(
      calls.map((call) => call.method),
      <String>[
        'peekPendingReply',
        'pendingReplyCount',
        'takeDroppedReplyCount',
      ],
    );
    expect(
      calls.every((call) => call.arguments == null),
      isTrue,
    );
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

      // Later shares remain queued while this reply is being reviewed.
      port.enqueue('second reply');
      await port.signalReplyAvailable();
      expect(inbox.pendingReply, 'first reply');
      expect(inbox.queuedReplyCount, 1);
      expect(port.calls, 1);

      await inbox.clearPendingReply();

      expect(inbox.pendingReply, 'second reply');
      expect(inbox.queuedReplyCount, 0);
      expect(port.calls, 2);
    },
  );

  test(
      'reports queue size and dropped replies without replacing the active reply',
      () async {
    final port = _FakeReplyPort('first reply');
    final inbox = AgentReplyInboxController(
      port: port,
      isVaultUnlocked: () => true,
    );
    addTearDown(inbox.dispose);

    await inbox.receivePendingReply();
    port.enqueue('second reply');
    port.droppedReplyCount = 2;
    await port.signalReplyAvailable();

    expect(inbox.pendingReply, 'first reply');
    expect(inbox.queuedReplyCount, 1);
    expect(inbox.droppedReplyCount, 2);
    expect(port.calls, 1);

    await inbox.clearPendingReply();

    expect(inbox.pendingReply, 'second reply');
    expect(inbox.queuedReplyCount, 0);
    expect(inbox.droppedReplyCount, 2);
  });

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
      <String>[
        'peekPendingReply',
        'pendingReplyCount',
        'takeDroppedReplyCount',
      ],
    );
    expect(
      channel.outboundCalls.every((call) => call.arguments == null),
      isTrue,
    );
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
    expect(channel.outboundCalls, hasLength(3));
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
    port.enqueue('second assistant reply');
    port.droppedReplyCount = 1;
    await port.signalReplyAvailable();
    await tester.pumpAndSettle();
    expect(
      find.textContaining('另有 1 条回复等待处理。'),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 条新回复未保留'),
      findsOneWidget,
    );
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
  testWidgets(
    'preserves an existing draft when a shared reply arrives',
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

      port.enqueue('shared assistant reply');
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

      await tester.ensureVisible(replyInput);
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
    },
  );

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
  _FakeReplyPort(String? reply) {
    if (reply != null) _replies.add(reply);
  }

  final List<String> _replies = <String>[];
  int calls = 0;
  int droppedReplyCount = 0;
  AgentReplyAvailableHandler? _replyAvailableHandler;

  String? get reply => _replies.isEmpty ? null : _replies.first;

  void enqueue(String reply) => _replies.add(reply);

  @override
  Future<String?> peekPendingReply() async {
    calls++;
    return reply;
  }

  @override
  Future<void> acknowledgePendingReply() async {
    if (_replies.isNotEmpty) _replies.removeAt(0);
  }

  @override
  Future<int> pendingReplyCount() async => _replies.length;

  @override
  Future<int> takeDroppedReplyCount() async {
    final count = droppedReplyCount;
    droppedReplyCount = 0;
    return count;
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

final class _DelayedReplyPort implements AgentReplyInboxPort {
  _DelayedReplyPort(this.reply);

  final String reply;
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> releaseRead = Completer<void>();

  @override
  Future<String?> peekPendingReply() async {
    if (!readStarted.isCompleted) readStarted.complete();
    await releaseRead.future;
    return reply;
  }

  @override
  Future<void> acknowledgePendingReply() async {}

  @override
  Future<int> pendingReplyCount() async => 1;

  @override
  Future<int> takeDroppedReplyCount() async => 0;

  @override
  void setReplyAvailableHandler(AgentReplyAvailableHandler? handler) {}
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
    if (method == 'peekPendingReply') {
      return 'shared assistant reply' as T?;
    }
    if (method == 'acknowledgePendingReply') return null;
    if (method == 'pendingReplyCount') return 0 as T?;
    if (method == 'takeDroppedReplyCount') return 0 as T?;
    return null;
  }
}
