import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_os_app/src/agent_interop/agent_handoff.dart';
import 'package:personal_os_app/src/agent_interop/automatic_agent_gateway.dart';
import 'package:personal_os_app/src/agent_interop/local_agent_event_store.dart';
import 'package:personal_os_app/src/app.dart';
import 'package:personal_os_app/src/composition/app_composition.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_in_memory/in_memory.dart';

void main() {
  test(
      'automatic HTTP transport carries context and CSRF without model credentials',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/status')) {
        return http.Response(
            '{"csrf":"nonce","connected":true,"connection_id":"saved/one","connection_revision":"version-one"}',
            200);
      }
      expect(request.headers['X-Personal-OS-CSRF'], 'nonce');
      expect(request.headers.containsKey('Authorization'), false);
      if (request.url.path.endsWith('/models')) {
        expect(request.url.queryParameters['connection_id'], 'saved/one');
        expect(
            request.url.queryParameters['connection_revision'], 'version-one');
        return http.Response('{"models":[{"id":"test"}]}', 200);
      }
      final body = jsonDecode(request.body) as Map;
      expect(body['connection_id'], 'saved/one');
      expect(body['connection_revision'], 'version-one');
      expect(body['context'], '{"session_id":"one"}');
      expect(body['stage'], 'proposal');
      return http.Response('{"reply":"completed bundle"}', 200);
    });
    final gateway = LocalAutomaticAgentGateway(
        origin: Uri.parse('http://127.0.0.1:8787/'), client: client);
    expect(
        await gateway.request(
            model: 'test',
            prompt: 'use personal context',
            context: '{"session_id":"one"}',
            stage: 'proposal'),
        'completed bundle');
    expect((await gateway.models()).single['id'], 'test');
    expect(requests.map((e) => e.url.path), <String>[
      '/api/agent/status',
      '/api/agent/request',
      '/api/agent/models'
    ]);
    gateway.cancel();
  });

  testWidgets('automatic next action and confirmation fit a phone viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppComposition.localAgent(
        gateway: _TestGateway(), eventStore: InMemoryEventStore());
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await app.strategyController.savePersonalContext(goal: '学习');
    await app.automaticAgent!.connect();
    await app.automaticAgent!.generate();
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    final action = find.byKey(const Key('strategy-focus-instruction'));
    final confirm = find.byKey(const Key('accept-proposal'));
    expect(action, findsOneWidget);
    expect(tester.getBottomRight(confirm).dy, lessThan(784));
    expect(find.byKey(const Key('agent-reply-input')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one phone feedback click records the chosen status and reviews',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final status in <ExecutionStatus>[
      ExecutionStatus.completed,
      ExecutionStatus.skipped,
    ]) {
      final gateway = _TestGateway();
      final store = LocalAgentEventStore(gateway);
      await store.load();
      final app =
          AppComposition.localAgent(gateway: gateway, eventStore: store);
      addTearDown(app.strategyController.dispose);
      addTearDown(app.automaticAgent!.dispose);
      await app.strategyController.savePersonalContext(goal: '每天学十分钟');
      await app.automaticAgent!.connect();
      await app.automaticAgent!.generate();
      await tester.pumpWidget(PersonalOsApp(composition: app));
      await tester.pumpAndSettle();
      expect(_eventPayloads(gateway, 'execution.recorded'), isEmpty);
      await tester.tap(find.byKey(const Key('accept-proposal')));
      await tester.pumpAndSettle();
      expect(_eventPayloads(gateway, 'execution.recorded'), isEmpty);
      final button = find.byKey(Key(status == ExecutionStatus.completed
          ? 'feedback-completed'
          : 'feedback-skipped'));
      expect(tester.getBottomRight(button).dy, lessThan(784));
      expect(find.byKey(const Key('record-execution')), findsNothing);
      expect(find.byKey(const Key('record-outcome')), findsNothing);
      if (status == ExecutionStatus.completed) {
        await tester.enterText(find.byKey(const Key('feedback-note')), '有点累');
      }
      final writes = gateway.historyWrites;
      await tester.tap(button);
      await tester.pumpAndSettle();
      final execution = _eventPayloads(gateway, 'execution.recorded').single;
      final outcome = _eventPayloads(gateway, 'outcome.recorded').single;
      expect(execution['status'], status.name);
      expect(outcome['valence'], 'neutral');
      expect(outcome['metrics'], isEmpty);
      expect(
          outcome['observation'],
          status == ExecutionStatus.completed
              ? '用户反馈：这一步已完成。 补充：有点累'
              : '用户反馈：这次没有执行这一步。');
      expect(
          gateway.historyWrites, writes + 2); // feedback batch, then AI review
      expect(gateway.stages, <String>['proposal', 'review']);
      expect(app.strategyController.hasPendingReview, true);
      expect(gateway.contexts.last, contains(status.name));
      expect(find.byKey(const Key('accept-review')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('feedback write and model failures retry without duplicate facts',
      (tester) async {
    final gateway = _TestGateway();
    final store = LocalAgentEventStore(gateway);
    await store.load();
    final app = AppComposition.localAgent(gateway: gateway, eventStore: store);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await app.strategyController.savePersonalContext(goal: '记录真实反馈');
    await app.automaticAgent!.connect();
    await app.automaticAgent!.generate();
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('accept-proposal')));
    await tester.pumpAndSettle();
    final note = find.byKey(const Key('feedback-note'));
    await tester.enterText(note, '完成十分钟，需要再简化');
    final feedback = find.byKey(const Key('feedback-completed'));
    await tester.ensureVisible(feedback);
    gateway.rejectNextHistoryWrite = true;
    await tester.tap(feedback);
    await tester.pumpAndSettle();
    expect(app.strategyController.executionId, isNull);
    expect(app.strategyController.outcomeId, isNull);
    expect(_eventPayloads(gateway, 'execution.recorded'), isEmpty);
    expect(_eventPayloads(gateway, 'outcome.recorded'), isEmpty);
    expect(tester.widget<TextField>(note).controller!.text, '完成十分钟，需要再简化');
    expect(gateway.stages, <String>['proposal']);
    gateway.failure = const AgentGatewayException('provider_unreachable');
    await tester.tap(feedback);
    await tester.pumpAndSettle();
    expect(app.strategyController.executionId, isNotNull);
    expect(app.strategyController.outcomeId, isNotNull);
    expect(app.automaticAgent!.error, contains('无法访问 AI 服务'));
    final savedEvents = jsonEncode(gateway.events);
    await app.automaticAgent!.saveFeedback(ExecutionStatus.completed);
    expect(jsonEncode(gateway.events), savedEvents);
    await tester.pumpWidget(const SizedBox.shrink());
    gateway.failure = null;
    final restoredStore = LocalAgentEventStore(gateway);
    await restoredStore.load();
    final restored =
        AppComposition.localAgent(gateway: gateway, eventStore: restoredStore);
    addTearDown(restored.strategyController.dispose);
    addTearDown(restored.automaticAgent!.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: restored));
    await tester.pumpAndSettle();
    expect(restored.strategyController.outcomeId, isNotNull);
    expect(find.byKey(const Key('ask-agent-next')), findsNothing);
    expect(_eventPayloads(gateway, 'execution.recorded'), hasLength(1));
    expect(_eventPayloads(gateway, 'outcome.recorded'), hasLength(1));
    expect(gateway.stages, <String>['proposal', 'review', 'review']);
    expect(restored.strategyController.hasPendingReview, true);
    expect(gateway.contexts.last, contains('完成十分钟，需要再简化'));
    expect(tester.takeException(), isNull);
  });

  test('feedback saves offline and ignores double submission during review',
      () async {
    final gateway = _TestGateway();
    final store = LocalAgentEventStore(gateway);
    await store.load();
    final app = AppComposition.localAgent(gateway: gateway, eventStore: store);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    final agent = app.automaticAgent!, strategy = app.strategyController;
    await strategy.savePersonalContext(goal: '先保存事实');
    await agent.connect();
    await agent.generate();
    await strategy.decideProposal(ProposalDecision.accept);
    await strategy.activateStrategy();
    gateway.connected = false;
    await agent.connect();
    await agent.saveFeedback(ExecutionStatus.skipped);
    expect(strategy.outcomeId, isNotNull);
    expect(gateway.stages, <String>['proposal']);
    gateway.connected = true;
    await agent.connect();
    gateway.delayed = Completer<String>();
    gateway.nextRequestStarted = Completer<void>();
    final review = agent.generate();
    await gateway.nextRequestStarted!.future
        .timeout(const Duration(seconds: 5));
    expect(agent.busy, true);
    final events = jsonEncode(gateway.events);
    await agent.saveFeedback(ExecutionStatus.completed, note: '重复点击');
    expect(jsonEncode(gateway.events), events);
    expect(gateway.stages, <String>['proposal', 'review']);
    gateway.delayed!.complete(buildDemoAgentReply(gateway.contexts.last));
    await review;
    expect(strategy.hasPendingReview, true);
    expect(_eventPayloads(gateway, 'execution.recorded').single['status'],
        'skipped');
    expect(agent.busy, false);
  });

  testWidgets('reopening resumes saved feedback and then an accepted review',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TestGateway();
    final first = await _pendingReviewApp(gateway);
    final evidence = jsonEncode(gateway.events);
    first.strategyController.dispose();
    first.automaticAgent!.dispose();
    Future<AppComposition> reopen() async {
      final store = LocalAgentEventStore(gateway);
      await store.load();
      final app =
          AppComposition.localAgent(gateway: gateway, eventStore: store);
      addTearDown(app.strategyController.dispose);
      addTearDown(app.automaticAgent!.dispose);
      await tester.pumpWidget(PersonalOsApp(composition: app));
      await tester.pumpAndSettle();
      return app;
    }

    final review = await reopen();
    expect(gateway.stages, <String>['proposal', 'review']);
    expect(review.strategyController.reviewState, 'draft');
    expect(find.byKey(const Key('accept-review')), findsOneWidget);
    final evidenceCount = (jsonDecode(evidence) as List).length;
    expect(jsonEncode(gateway.events.take(evidenceCount).toList()), evidence);
    await review.strategyController.decideReview(ReviewDecision.accept);
    await tester.pumpWidget(const SizedBox.shrink());
    final next = await reopen();
    expect(gateway.stages, <String>['proposal', 'review', 'revision']);
    expect(next.strategyController.hasPendingProposal, true);
    expect(next.strategyController.parentStrategyRef, isNotNull);
    expect(find.byKey(const Key('accept-proposal')), findsOneWidget);
    expect(_eventPayloads(gateway, 'execution.recorded'), hasLength(1));
    expect(_eventPayloads(gateway, 'outcome.recorded'), hasLength(1));
    expect(gateway.contexts.last, contains('已保存的反馈'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saving a connection continues an offline goal after closing setup',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TestGateway()..connected = false;
    final store = LocalAgentEventStore(gateway);
    await store.load();
    final app = AppComposition.localAgent(gateway: gateway, eventStore: store);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('automatic-goal')), '离线先保存目标');
    await tester.pumpAndSettle();
    final saveGoal = find.byKey(const Key('automatic-save-goal'));
    await tester.ensureVisible(saveGoal);
    await tester.pumpAndSettle();
    await tester.tap(saveGoal);
    await tester.pumpAndSettle();
    expect(gateway.stages, isEmpty);
    expect(find.text('资料已保存，连接后会自动继续计划或复盘'), findsOneWidget);
    final setup = find.byKey(const Key('add-agent-connection'));
    await tester.ensureVisible(setup);
    await tester.tap(setup);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('connection-name')), '续接模型');
    await tester.ensureVisible(find.byKey(const Key('connection-url')));
    await tester.enterText(
        find.byKey(const Key('connection-url')), 'http://127.0.0.1:9000/v1');
    await tester.ensureVisible(find.byKey(const Key('connection-model')));
    await tester.enterText(
        find.byKey(const Key('connection-model')), 'resume-model');
    gateway.connected = true;
    final saveConnection = find.byKey(const Key('save-agent-connection'));
    await tester.ensureVisible(saveConnection);
    await tester.tap(saveConnection);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('connection-name')), findsNothing);
    expect(gateway.stages, <String>['proposal']);
    expect(gateway.providersUsed, <String>['chat-completions']);
    expect(app.strategyController.hasPendingProposal, true);
    expect(_eventPayloads(gateway, 'goal.created'), hasLength(1));
    expect(_eventPayloads(gateway, 'execution.recorded'), isEmpty);
    expect(tester.getBottomRight(find.byKey(const Key('accept-proposal'))).dy,
        lessThan(784));
    expect(tester.takeException(), isNull);
  });

  test(
      'automatic continuation attempts once and keeps failure until explicit retry',
      () async {
    final gateway = _TestGateway();
    final app = await _pendingReviewApp(gateway);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    final agent = app.automaticAgent!;
    gateway.failure = const AgentGatewayException('provider_unreachable');
    expect(await agent.resumePending(), true);
    final failure = agent.error;
    final facts = jsonEncode(gateway.events);
    expect(gateway.stages, <String>['proposal', 'review']);
    expect(await agent.resumePending(), false);
    expect(await agent.reconnectAndResume(), false);
    expect(agent.error, failure);
    expect(gateway.stages, <String>['proposal', 'review']);
    gateway.connectionRevision = 'test-revision-2';
    expect(await agent.reconnectAndResume(), true);
    expect(await agent.reconnectAndResume(), false);
    expect(agent.error, failure);
    expect(jsonEncode(gateway.events), facts);
    gateway.failure = null;
    expect(await agent.reconnectAndResume(retryPending: true), true);
    expect(gateway.stages, <String>['proposal', 'review', 'review', 'review']);
    expect(app.strategyController.hasPendingReview, true);
    expect(_eventPayloads(gateway, 'execution.recorded'), hasLength(1));
    expect(_eventPayloads(gateway, 'outcome.recorded'), hasLength(1));
  });

  test(
      'automatic continuation respects drafts, activation and rejected decisions',
      () async {
    final gateway = _TestGateway();
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    final strategy = app.strategyController, agent = app.automaticAgent!;
    await strategy.savePersonalContext(goal: '决定由我确认');
    await agent.connect();
    await agent.generate();
    expect(await agent.resumePending(), false);
    await strategy.decideProposal(ProposalDecision.reject);
    expect(await agent.reconnectAndResume(), false);
    expect(gateway.stages, <String>['proposal']);
    await agent.generate();
    await strategy.decideProposal(ProposalDecision.accept);
    expect(await agent.resumePending(), false);
    expect(strategy.strategyState, 'accepted');
    await strategy.activateStrategy();
    expect(await agent.resumePending(), false);
    expect(strategy.executionId, isNull);
    gateway.replyStrategyId = strategy.strategyId;
    await strategy.recordFeedback(executionStatus: ExecutionStatus.skipped);
    await agent.generate();
    expect(agent.error, isNull);
    expect(await agent.resumePending(), false);
    expect(strategy.reviewState, 'draft');
    await strategy.decideReview(ReviewDecision.reject);
    expect(await agent.reconnectAndResume(), false);
    expect(strategy.reviewState, 'rejected');
    expect(gateway.stages, <String>['proposal', 'proposal', 'review']);
  });

  test('reset during automatic continuation discards the late reply', () async {
    final gateway = _TestGateway();
    final app = await _pendingReviewApp(gateway);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    final agent = app.automaticAgent!, strategy = app.strategyController;
    gateway.delayed = Completer<String>();
    gateway.nextRequestStarted = Completer<void>();
    final pending = agent.resumePending();
    await gateway.nextRequestStarted!.future
        .timeout(const Duration(seconds: 5));
    final reply = buildDemoAgentReply(gateway.contexts.last);
    final events = jsonEncode(gateway.events);
    agent.reset();
    strategy.reset();
    gateway.delayed!.complete(reply);
    expect(await pending, false);
    expect(jsonEncode(gateway.events), events);
    expect(strategy.reviewId, isNull);
    expect(agent.busy, false);
  });

  test('connection probe sends only model identity and acquires CSRF first',
      () async {
    final requests = <http.Request>[];
    final gateway = LocalAutomaticAgentGateway(
        origin: Uri.parse('http://127.0.0.1:8787/'),
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/status')) {
            return http.Response(
                '{"csrf":"nonce","connection_id":"one","connection_revision":"revision"}',
                200);
          }
          expect(request.url.path, '/api/agent/check');
          expect(request.headers['X-Personal-OS-CSRF'], 'nonce');
          expect(request.headers.containsKey('Authorization'), false);
          expect(jsonDecode(request.body), <String, Object?>{
            'model': 'test',
            'connection_id': 'one',
            'connection_revision': 'revision',
          });
          return http.Response('{"ok":true,"model":"test"}', 200);
        }));
    expect((await gateway.checkConnection(model: 'test'))['ok'], true);
    expect(requests.map((e) => e.url.path),
        <String>['/api/agent/status', '/api/agent/check']);
    gateway.cancel();
  });

  testWidgets(
      'phone connection test reports success or failure without changing history',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final longName = List<String>.filled(15, 'abcdefghij').join();
    final gateway = _TestGateway()
      ..modelDisplayName = 'A very long model display name $longName';
    final store = InMemoryEventStore();
    final app = AppComposition.localAgent(gateway: gateway, eventStore: store);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await app.strategyController.savePersonalContext(goal: '连接测试不能改变这个目标');
    await app.automaticAgent!.connect();
    await app.automaticAgent!.generate();
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    final originalEvents =
        store.readEvents().map((e) => e.event.eventId).toList();
    final context = app.strategyController.contextBundle;
    expect(find.byKey(const Key('automatic-check-connection')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('automatic-connection')));
    await tester.tap(find.text('使用 test-agent'));
    await tester.pumpAndSettle();
    final check = find.byKey(const Key('automatic-check-connection'));
    await tester.ensureVisible(check);
    await tester.pumpAndSettle();
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(gateway.checks, 1);
    expect(find.text('AI 服务已响应。'), findsOneWidget);
    expect(store.readEvents().map((e) => e.event.eventId), originalEvents);
    expect(app.strategyController.contextBundle, context);
    expect(gateway.stages, <String>['proposal']);
    gateway.checkFailure = const AgentGatewayException('provider_unreachable');
    await tester.ensureVisible(check);
    await tester.pumpAndSettle();
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(gateway.checks, 2);
    expect(app.automaticAgent!.connectionCheckMessage, isNull);
    expect(app.automaticAgent!.error, contains('无法访问 AI 服务'));
    expect(app.strategyController.personalGoal, '连接测试不能改变这个目标');
    expect(store.readEvents().map((e) => e.event.eventId), originalEvents);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'saved context edits survive reload and reach the next Agent request',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TestGateway();
    final store = LocalAgentEventStore(gateway);
    await store.load();
    final app = AppComposition.localAgent(gateway: gateway, eventStore: store);
    final strategy = app.strategyController, agent = app.automaticAgent!;
    addTearDown(strategy.dispose);
    addTearDown(agent.dispose);
    await strategy.savePersonalContext(
      goal: '学习二十分钟',
      successCriteria: '一周学习三次',
      currentState: '平日很累',
      constraints: '不买新课程',
    );
    await agent.connect();
    await agent.generate();
    await strategy.decideProposal(ProposalDecision.accept);
    await strategy.activateStrategy();
    final strategyId = strategy.strategyId;
    final oldGoal = Map.of(strategy.personalGoalRecord!['ref'] as Map);
    final oldEvents = jsonEncode(gateway.events);
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('我的目标与资料'));
    await tester.tap(find.text('我的目标与资料'));
    await tester.pumpAndSettle();
    final profileDetails = find.byKey(const Key('automatic-profile-details'));
    await tester.ensureVisible(profileDetails);
    await tester.tap(profileDetails);
    await tester.pumpAndSettle();
    String text(String key) =>
        tester.widget<TextField>(find.byKey(Key(key))).controller!.text;
    expect(text('automatic-goal'), '学习二十分钟');
    expect(text('automatic-success-criteria'), '一周学习三次');
    expect(text('automatic-conditions'), '平日很累');
    expect(text('automatic-constraints'), '不买新课程');
    await tester.enterText(find.byKey(const Key('automatic-goal')), '学习十分钟');
    await tester.enterText(
        find.byKey(const Key('automatic-success-criteria')), '一周学习四次');
    await tester.enterText(
        find.byKey(const Key('automatic-conditions')), '周末有时间');
    await tester.enterText(
        find.byKey(const Key('automatic-constraints')), '不花钱');
    await tester.tap(find.byKey(const Key('automatic-profile-details')));
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('automatic-save-goal'));
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(strategy.strategyId, strategyId);
    expect(strategy.strategyState, 'active');
    expect(strategy.personalGoalRecord!['ref'],
        <String, Object?>{...oldGoal.cast<String, Object?>(), 'revision': 3});
    expect(gateway.stages, <String>['proposal']);
    final originalCount = (jsonDecode(oldEvents) as List).length;
    expect(jsonEncode(gateway.events.take(originalCount).toList()), oldEvents);
    final updatedEvents = jsonEncode(gateway.events);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(jsonEncode(gateway.events), updatedEvents);
    await tester.pumpWidget(const SizedBox.shrink());
    final restoredStore = LocalAgentEventStore(gateway);
    await restoredStore.load();
    final restored =
        AppComposition.localAgent(gateway: gateway, eventStore: restoredStore);
    addTearDown(restored.strategyController.dispose);
    addTearDown(restored.automaticAgent!.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: restored));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('我的目标与资料'));
    await tester.tap(find.text('我的目标与资料'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('automatic-profile-details')));
    await tester.tap(find.byKey(const Key('automatic-profile-details')));
    await tester.pumpAndSettle();
    expect(text('automatic-goal'), '学习十分钟');
    expect(text('automatic-success-criteria'), '一周学习四次');
    expect(text('automatic-conditions'), '周末有时间');
    expect(text('automatic-constraints'), '不花钱');
    await restored.strategyController.recordExecution(
        actionId: restored.strategyController.strategyActions.first.id,
        executionStatus: ExecutionStatus.completed,
        note: '用户实际完成');
    await restored.automaticAgent!.saveOutcome('完成十分钟');
    final context = jsonDecode(gateway.contexts.last) as Map;
    final objects = (context['objects'] as List).cast<Map>();
    expect(
        objects.where((e) => e['ref']['type'] == 'goal').single['data']
            ['title'],
        '学习十分钟');
    expect(
        objects
            .where((e) => e['ref']['type'] == 'personal_asset')
            .single['data']['content'],
        '周末有时间');
    expect(
        objects.where((e) => e['ref']['type'] == 'constraint').single['data']
            ['content'],
        '不花钱');
    expect(gateway.stages, <String>['proposal', 'review']);
    await restored.strategyController
        .updatePersonalContext(goal: '学习十分钟', currentState: '');
    expect(restored.strategyController.personalCurrentState, '');
    await restored.automaticAgent!.decideReview(ReviewDecision.accept);
    final revised = jsonDecode(gateway.contexts.last) as Map;
    expect(
        (revised['objects'] as List)
            .cast<Map>()
            .where((e) => e['ref']['type'] == 'personal_asset'),
        isEmpty);
    expect(gateway.stages, <String>['proposal', 'review', 'revision']);
    expect(tester.takeException(), isNull);
  });

  test('reset ignores a late connection check result', () async {
    final gateway = _TestGateway()
      ..delayedCheck = Completer<Map<String, Object?>>();
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    final agent = app.automaticAgent!;
    addTearDown(agent.dispose);
    addTearDown(app.strategyController.dispose);
    await agent.connect();
    final pending = agent.checkConnection();
    expect(agent.checkingConnection, true);
    agent.reset();
    gateway.delayedCheck!
        .complete(<String, Object?>{'ok': true, 'model': 'test'});
    await pending;
    expect(agent.connectionCheckMessage, isNull);
    expect(agent.checkingConnection, false);
    expect(agent.busy, false);
  });

  testWidgets(
      'automatic plan -> human action -> switch Agent -> automatic review -> next plan',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TestGateway()
      ..connections = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'first',
          'label': '第一个 Agent',
          'kind': 'responses',
          'model': 'test'
        },
        <String, Object?>{
          'id': 'second',
          'label': '第二个 Agent',
          'kind': 'agent-http',
          'model': 'second-model'
        },
      ]
      ..connectionId = 'first'
      ..provider = 'responses';
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-reply-input')), findsNothing);
    expect(find.byKey(const Key('copy-agent-prompt')), findsNothing);
    await tester.enterText(find.byKey(const Key('automatic-goal')), '每天学习');
    final profileDetails = find.byKey(const Key('automatic-profile-details'));
    await tester.ensureVisible(profileDetails);
    await tester.tap(profileDetails);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('automatic-conditions')), '晚上只有十分钟');
    await tester.tap(find.byKey(const Key('automatic-profile-details')));
    await tester.pumpAndSettle();
    final saveProfile = find.byKey(const Key('automatic-save-goal'));
    await tester.tap(saveProfile);
    await tester.pumpAndSettle();
    expect(gateway.stages, <String>['proposal']);
    expect(app.strategyController.hasPendingProposal, true);
    expect(find.byKey(const Key('strategy-focus-instruction')), findsOneWidget);
    expect(app.strategyController.executionId, isNull);
    await tester.tap(find.byKey(const Key('accept-proposal')));
    await tester.pumpAndSettle();
    expect(app.strategyController.strategyState, 'active');
    final originalStrategy = app.strategyController.strategyId;
    final connection = find.byKey(const Key('automatic-connection'));
    await tester.ensureVisible(connection);
    await tester.tap(connection);
    await tester.pumpAndSettle();
    final picker = find.byKey(const Key('automatic-connection-picker'));
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二个 Agent').last);
    await tester.pumpAndSettle();
    expect(app.strategyController.strategyId, originalStrategy);
    expect(app.strategyController.personalGoal, '每天学习');
    final outcome = find.byKey(const Key('feedback-note'));
    await tester.ensureVisible(outcome);
    await tester.enterText(outcome, '完成了十分钟，但二十分钟太长');
    final save = find.byKey(const Key('feedback-completed'));
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(gateway.stages, <String>['proposal', 'review']);
    expect(app.strategyController.hasPendingReview, true);
    final acceptReview = find.byKey(const Key('accept-review'));
    await tester.ensureVisible(acceptReview);
    await tester.tap(acceptReview);
    await tester.pumpAndSettle();
    expect(gateway.stages, <String>['proposal', 'review', 'revision']);
    expect(gateway.providersUsed,
        <String>['responses', 'agent-http', 'agent-http']);
    expect(app.strategyController.hasPendingProposal, true);
    expect(app.strategyController.parentStrategyRef, isNotNull);
    expect(app.strategyController.executionId, isNull);
    expect(gateway.contexts.last, contains('二十分钟太长'));
    expect(find.byKey(const Key('automatic-saved-context')), findsNothing);
    await tester.ensureVisible(find.text('我的目标与资料'));
    await tester.tap(find.text('我的目标与资料'));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('automatic-profile-details')));
    await tester.tap(find.byKey(const Key('automatic-profile-details')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.byKey(const Key('automatic-conditions')))
            .controller!
            .text,
        '晚上只有十分钟');
    final history = find.byKey(const Key('automatic-history'));
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    await tester.ensureVisible(history);
    await tester.tap(find.text('行动历史'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: history, matching: find.text('实际结果')),
        findsOneWidget);
    expect(
        find.descendant(
            of: history, matching: find.textContaining('完成了十分钟，但二十分钟太长')),
        findsOneWidget);
    expect(find.descendant(of: history, matching: find.text('AI 复盘 · 已接受')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a phone user saves, edits and removes an AI connection in the app',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TestGateway()
      ..provider = 'chatgpt'
      ..connectionId = 'chatgpt'
      ..connections = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'chatgpt',
          'label': 'ChatGPT',
          'kind': 'chatgpt',
          'model': ''
        },
      ];
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    final connection = find.byKey(const Key('automatic-connection'));
    await tester.ensureVisible(connection);
    await tester.tap(connection);
    await tester.pumpAndSettle();
    final add = find.byKey(const Key('add-agent-connection'));
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('connection-name')), '我的模型');
    await tester.ensureVisible(find.byKey(const Key('connection-url')));
    await tester.enterText(
        find.byKey(const Key('connection-url')), 'http://127.0.0.1:9000/v1');
    await tester.ensureVisible(find.byKey(const Key('connection-model')));
    await tester.enterText(
        find.byKey(const Key('connection-model')), 'bridge-model');
    final key = find.byKey(const Key('connection-key'));
    await tester.ensureVisible(key);
    await tester.enterText(key, 'test-only-secret');
    expect(
        tester
            .widget<TextField>(
                find.descendant(of: key, matching: find.byType(TextField)))
            .obscureText,
        true);
    await tester.tap(find.byKey(const Key('save-agent-connection')));
    await tester.pumpAndSettle();
    expect(gateway.lastSetup!['api_key'], 'test-only-secret');
    expect(app.automaticAgent!.connectionName, '我的模型');
    expect(app.automaticAgent!.model, 'bridge-model');
    expect(key, findsNothing);
    expect(app.automaticAgent!.connections.last.containsKey('api_key'), false);
    final edit = find.text('编辑此连接');
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const Key('connection-key')),
                matching: find.byType(TextField)))
            .controller!
            .text,
        isEmpty);
    final remove = find.text('删除连接（保留目标与历史）');
    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(app.automaticAgent!.connectionId, 'chatgpt');
    expect(find.byKey(const Key('automatic-connection-picker')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('lock/reset cancels an in-flight reply and prevents stale plan import',
      () async {
    final gateway = _TestGateway()..delayed = Completer<String>();
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    final agent = app.automaticAgent!, strategy = app.strategyController;
    addTearDown(agent.dispose);
    addTearDown(strategy.dispose);
    await strategy.savePersonalContext(goal: '学习');
    await agent.connect();
    final request = agent.generate();
    await gateway.started.future;
    final reply = buildDemoAgentReply(gateway.contexts.single);
    agent.reset();
    strategy.reset();
    gateway.delayed!.complete(reply);
    await request;
    expect(strategy.strategyId, isNull);
    expect(strategy.contextBundle, isNull);
    expect(agent.busy, false);
    expect(gateway.cancellations, greaterThan(0));
  });

  test(
      'invalid and interrupted model replies preserve current state and can be retried',
      () async {
    final gateway = _TestGateway()
      ..failure = const AgentGatewayException('provider_response_interrupted');
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    final agent = app.automaticAgent!, strategy = app.strategyController;
    addTearDown(agent.dispose);
    addTearDown(strategy.dispose);
    await strategy.savePersonalContext(goal: '学习');
    await agent.connect();
    await agent.generate();
    expect(strategy.strategyId, isNull);
    expect(agent.error, contains('未完成'));
    gateway.failure = null;
    gateway.invalid = true;
    await agent.generate();
    expect(strategy.strategyId, isNull);
    expect(agent.error, contains('校验'));
    gateway.invalid = false;
    await agent.generate();
    expect(strategy.hasPendingProposal, true);
    expect(agent.error, isNull);
    final count = gateway.stages.length;
    await agent.generate();
    expect(gateway.stages.length, count);
  });

  test(
      'local history reload restores the accepted plan and refuses a stale writer',
      () async {
    final gateway = _TestGateway(),
        store = LocalAgentEventStore(_TestGateway());
    // Use one service-backed history for independent application lifetimes.
    final firstStore = LocalAgentEventStore(gateway);
    await firstStore.load();
    final app =
        AppComposition.localAgent(gateway: gateway, eventStore: firstStore);
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await app.strategyController.savePersonalContext(goal: '持久化目标');
    await app.automaticAgent!.connect();
    await app.automaticAgent!.generate();
    await app.strategyController.decideProposal(ProposalDecision.accept);
    await app.strategyController.activateStrategy();
    final restoredStore = LocalAgentEventStore(gateway);
    await restoredStore.load();
    final restored =
        AppComposition.localAgent(gateway: gateway, eventStore: restoredStore);
    addTearDown(restored.strategyController.dispose);
    addTearDown(restored.automaticAgent!.dispose);
    await restored.strategyController.bootstrap();
    await restored.strategyController.refreshContextForHandoff();
    expect(restored.strategyController.strategyState, 'active');
    expect(restored.strategyController.personalGoal, '持久化目标');
    await store
        .load(); // Separate empty server: no implicit merge or overwrite.
    expect(await store.readById('missing'), isNull);
    final stale = LocalAgentEventStore(gateway);
    await stale.load();
    await restored.strategyController.recordExecution(
        actionId: restored.strategyController.strategyActions.first.id,
        executionStatus: ExecutionStatus.completed,
        note: '用户确认');
    await expectLater(stale.appendAll(const []), throwsA(isA<Exception>()));
  });
}

// Test-only inference. Production localAgent composition has no fixture model.
Future<AppComposition> _pendingReviewApp(_TestGateway gateway) async {
  final store = LocalAgentEventStore(gateway);
  await store.load();
  final app = AppComposition.localAgent(gateway: gateway, eventStore: store);
  final strategy = app.strategyController, agent = app.automaticAgent!;
  await strategy.savePersonalContext(goal: '续接闭环');
  await agent.connect();
  await agent.generate();
  await strategy.decideProposal(ProposalDecision.accept);
  await strategy.activateStrategy();
  await strategy.recordFeedback(
      executionStatus: ExecutionStatus.completed, note: '已保存的反馈');
  return app;
}

List<Map> _eventPayloads(_TestGateway gateway, String type) => gateway.events
    .cast<Map>()
    .where((event) => event['event_type'] == type)
    .map((event) => event['payload'] as Map)
    .toList();

final class _TestGateway implements AutomaticAgentGateway {
  bool connected = true;
  String connectionRevision = 'test-revision-1';
  String? replyStrategyId;
  bool rejectNextHistoryWrite = false;
  int historyWrites = 0;
  final List<String> stages = <String>[], contexts = <String>[];
  final List<String> providersUsed = <String>[];
  String provider = 'test-agent';
  String? modelDisplayName;
  int checks = 0;
  AgentGatewayException? checkFailure;
  Completer<Map<String, Object?>>? delayedCheck;
  String? connectionId;
  List<Map<String, Object?>> connections = <Map<String, Object?>>[];
  Map<String, Object?>? lastSetup;
  Map<String, Object?>? get currentConnection =>
      connections.where((e) => e['id'] == connectionId).firstOrNull;
  String get modelId {
    final configured = currentConnection?['model'] as String?;
    return configured?.isNotEmpty == true ? configured! : 'test';
  }

  final started = Completer<void>();
  Completer<String>? delayed;
  Completer<void>? nextRequestStarted;
  AgentGatewayException? failure;
  bool invalid = false;
  int cancellations = 0, revision = 0;
  List<Object?> events = <Object?>[];
  @override
  Uri get signInPage => Uri.parse('http://127.0.0.1:8787/connect');
  @override
  Future<Map<String, Object?>> status() async => <String, Object?>{
        'connected': connected,
        'provider': provider,
        'connection_id': connectionId,
        'connection_revision': connectionRevision,
        'connection_name': currentConnection?['label'],
        'connections': connections,
        'account': null,
        'accounts': <Object?>[]
      };
  @override
  Future<List<Map<String, Object?>>> models() async => <Map<String, Object?>>[
        <String, Object?>{
          'id': modelId,
          'name': modelDisplayName ?? 'Test model'
        }
      ];
  @override
  Future<Map<String, Object?>> checkConnection({required String model}) async {
    checks++;
    if (checkFailure != null) throw checkFailure!;
    if (delayedCheck != null) return delayedCheck!.future;
    return <String, Object?>{'ok': true, 'model': model};
  }

  @override
  Future<String> request(
      {required String model,
      required String prompt,
      required String context,
      required String stage}) async {
    stages.add(stage);
    providersUsed.add(provider);
    contexts.add(context);
    if (nextRequestStarted != null && !nextRequestStarted!.isCompleted) {
      nextRequestStarted!.complete();
    }
    if (!started.isCompleted) started.complete();
    if (failure != null) throw failure!;
    if (delayed != null) return delayed!.future;
    if (invalid) return '{}';
    final value =
        jsonDecode(buildDemoAgentReply(context, strategyId: replyStrategyId))
            as Map<String, Object?>;
    if (value['strategy'] is Map) {
      (value['strategy'] as Map)['title'] = '测试模型自动计划';
    }
    return jsonEncode(value);
  }

  @override
  Future<Map<String, Object?>> get(String path) async =>
      <String, Object?>{'revision': revision, 'events': events};
  @override
  Future<Map<String, Object?>> post(
      String path, Map<String, Object?> body) async {
    if (path.startsWith('/api/agent/connections')) {
      if (path.endsWith('/select')) {
        connectionId = body['connection_id'] as String;
      } else if (path.endsWith('/remove')) {
        connections.removeWhere((e) => e['id'] == body['connection_id']);
        connectionId = 'chatgpt';
      } else {
        lastSetup = Map<String, Object?>.from(body);
        connectionId = body['id'] as String? ?? 'saved-connection';
        connections.removeWhere((e) => e['id'] == connectionId);
        connections.add(<String, Object?>{
          'id': connectionId,
          'label': body['label'],
          'kind': body['kind'],
          'base_url': body['base_url'] ?? '',
          'agent_url': body['agent_url'] ?? '',
          'model': body['model'],
          'has_api_key': (body['api_key'] as String?)?.isNotEmpty == true
        });
      }
      provider = connections.firstWhere((e) => e['id'] == connectionId)['kind']
          as String;
      return <String, Object?>{
        'active': connectionId,
        'connections': connections
      };
    }
    if (body['revision'] != revision) {
      throw const AgentGatewayException('history_conflict');
    }
    historyWrites++;
    if (rejectNextHistoryWrite) {
      rejectNextHistoryWrite = false;
      throw const AgentGatewayException('history_write_failed');
    }
    events = body['events'] as List<Object?>;
    return <String, Object?>{'revision': ++revision};
  }

  @override
  void cancel() {
    cancellations++;
  }
}
