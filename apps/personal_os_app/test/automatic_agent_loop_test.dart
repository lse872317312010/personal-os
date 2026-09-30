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
  test('automatic HTTP transport carries context and CSRF without model credentials', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/status')) {
        return http.Response('{"csrf":"nonce","connected":true}', 200);
      }
      expect(request.headers['X-Personal-OS-CSRF'], 'nonce');
      expect(request.headers.containsKey('Authorization'), false);
      final body = jsonDecode(request.body) as Map;
      expect(body['context'], '{"session_id":"one"}');
      expect(body['stage'], 'proposal');
      return http.Response('{"reply":"completed bundle"}', 200);
    });
    final gateway = LocalAutomaticAgentGateway(origin: Uri.parse('http://127.0.0.1:8787/'), client: client);
    expect(await gateway.request(model: 'test', prompt: 'use personal context', context: '{"session_id":"one"}', stage: 'proposal'), 'completed bundle');
    expect(requests.map((e) => e.url.path), <String>['/api/agent/status', '/api/agent/request']);
    gateway.cancel();
  });

  testWidgets('automatic next action and confirmation fit a phone viewport', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppComposition.localAgent(gateway: _TestGateway(), eventStore: InMemoryEventStore());
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

  testWidgets(
      'automatic plan -> human action -> automatic review -> human acceptance -> next plan',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _TestGateway();
    final app = AppComposition.localAgent(
        gateway: gateway, eventStore: InMemoryEventStore());
    addTearDown(app.strategyController.dispose);
    addTearDown(app.automaticAgent!.dispose);
    await tester.pumpWidget(PersonalOsApp(composition: app));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-reply-input')), findsNothing);
    expect(find.byKey(const Key('copy-agent-prompt')), findsNothing);
    await tester.enterText(find.byKey(const Key('automatic-goal')), '每天学习');
    await tester.enterText(
        find.byKey(const Key('automatic-conditions')), '晚上只有十分钟');
    await tester.tap(find.byKey(const Key('automatic-save-goal')));
    await tester.pumpAndSettle();
    expect(gateway.stages, <String>['proposal']);
    expect(app.strategyController.hasPendingProposal, true);
    expect(find.byKey(const Key('strategy-focus-instruction')), findsOneWidget);
    expect(app.strategyController.executionId, isNull);
    await tester.tap(find.byKey(const Key('accept-proposal')));
    await tester.pumpAndSettle();
    expect(app.strategyController.strategyState, 'active');
    await tester.tap(find.byKey(const Key('record-execution')));
    await tester.pumpAndSettle();
    final outcome = find.byKey(const Key('outcome-input'));
    await tester.ensureVisible(outcome);
    await tester.enterText(outcome, '完成了十分钟，但二十分钟太长');
    final save = find.byKey(const Key('record-outcome'));
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
    expect(app.strategyController.hasPendingProposal, true);
    expect(app.strategyController.parentStrategyRef, isNotNull);
    expect(app.strategyController.executionId, isNull);
    expect(gateway.contexts.last, contains('二十分钟太长'));
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
final class _TestGateway implements AutomaticAgentGateway {
  final List<String> stages = <String>[], contexts = <String>[];
  final started = Completer<void>();
  Completer<String>? delayed;
  AgentGatewayException? failure;
  bool invalid = false;
  int cancellations = 0, revision = 0;
  List<Object?> events = <Object?>[];
  @override
  Uri get signInPage => Uri.parse('http://127.0.0.1:8787/connect');
  @override
  Future<Map<String, Object?>> status() async => <String, Object?>{
        'connected': true,
        'provider': 'test-agent',
        'account': null,
        'accounts': <Object?>[]
      };
  @override
  Future<List<Map<String, Object?>>> models() async => <Map<String, Object?>>[
        <String, Object?>{'id': 'test', 'name': 'Test model'}
      ];
  @override
  Future<String> request(
      {required String model,
      required String prompt,
      required String context,
      required String stage}) async {
    stages.add(stage);
    contexts.add(context);
    if (!started.isCompleted) started.complete();
    if (failure != null) throw failure!;
    if (delayed != null) return delayed!.future;
    if (invalid) return '{}';
    final value =
        jsonDecode(buildDemoAgentReply(context)) as Map<String, Object?>;
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
    if (body['revision'] != revision) {
      throw const AgentGatewayException('history_conflict');
    }
    events = body['events'] as List<Object?>;
    return <String, Object?>{'revision': ++revision};
  }

  @override
  void cancel() {
    cancellations++;
  }
}
