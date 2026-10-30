import 'dart:async';

import 'package:flutter/material.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:url_launcher/link.dart';

import '../controller/automatic_agent_controller.dart';
import '../controller/strategy_loop_controller.dart';
import 'strategy_action_card.dart';
import 'agent_connection_dialog.dart';

/// One working surface: goal -> suggested action -> result -> review -> next
/// action. No prompt export, clipboard, JSON editor or simulated model output.
final class AutomaticStrategyScreen extends StatefulWidget {
  const AutomaticStrategyScreen({required this.agent, super.key});
  final AutomaticAgentController agent;
  @override
  State<AutomaticStrategyScreen> createState() =>
      _AutomaticStrategyScreenState();
}

final class _AutomaticStrategyScreenState extends State<AutomaticStrategyScreen>
    with WidgetsBindingObserver {
  final _goal = TextEditingController();
  final _successCriteria = TextEditingController();
  final _conditions = TextEditingController();
  final _constraints = TextEditingController();
  final _result = TextEditingController();
  final _scroll = ScrollController();
  bool _contextEdited = false;
  bool _syncingContext = false;
  String? _contextNotice;
  AutomaticAgentController get agent => widget.agent;
  StrategyLoopController get strategy => agent.strategy;
  bool get busy => agent.busy || strategy.status == StrategyUiStatus.running;
  int get _optionalContextFieldCount => <String>[
        _successCriteria.text,
        _conditions.text,
        _constraints.text,
      ].where((value) => value.trim().isNotEmpty).length;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _goal.addListener(_editContext);
    _successCriteria.addListener(_editContext);
    _conditions.addListener(_editContext);
    _constraints.addListener(_editContext);
    unawaited(_load());
  }

  Future<void> _load() async {
    await strategy.bootstrap();
    if (!mounted) return;
    await agent.connect();
    if (!mounted) return;
    if (!strategy.hasSession) {
      await strategy.openOfflineSession(agentId: 'automatic-agent-gateway');
    }
    if (strategy.hasSession) await strategy.refreshContextForHandoff();
    _fillContext();
    await _resume();
  }

  Future<void> _resume() async {
    if (!mounted) return;
    if (await agent.resumePending()) {
      await _focusAction();
    }
  }

  Future<void> _reconnect({bool retryPending = false}) async {
    if (!mounted) return;
    if (await agent.reconnectAndResume(retryPending: retryPending)) {
      await _focusAction();
    }
  }

  Future<void> _chooseConnection(String id) async {
    if (await agent.selectConnection(id) && mounted) {
      await _resume();
    }
  }

  Future<void> _chooseAccount(String id) async {
    await agent.selectAccount(id);
    if (mounted && agent.error == null) {
      await _resume();
    }
  }

  Future<void> _editConnection({Map<String, Object?>? connection}) async {
    final changed = await showDialog<bool>(
        context: context,
        builder: (_) =>
            AgentConnectionDialog(agent: agent, connection: connection));
    if (mounted && changed == true) {
      await _resume();
    }
  }

  void _editContext() {
    if (_syncingContext || !mounted) return;
    setState(() {
      _contextEdited = true;
      _contextNotice = null;
    });
  }

  void _fillContext() {
    if (!mounted || _contextEdited) return;
    _syncingContext = true;
    _goal.text = strategy.personalGoal ?? '';
    _successCriteria.text = strategy.personalSuccessCriteria;
    _conditions.text = strategy.personalCurrentState;
    _constraints.text = strategy.personalConstraints;
    _syncingContext = false;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_reconnect());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goal.dispose();
    _successCriteria.dispose();
    _conditions.dispose();
    _constraints.dispose();
    _result.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    await agent.generate();
    await _focusAction();
  }

  Future<void> _focusAction() async {
    if (mounted && _scroll.hasClients) {
      await _scroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  Future<void> _saveGoal() async {
    if (busy || _goal.text.trim().isEmpty) return;
    final existing = strategy.personalGoalRecord != null;
    await strategy.updatePersonalContext(
      goal: _goal.text,
      successCriteria: _successCriteria.text,
      currentState: _conditions.text,
      constraints: _constraints.text,
    );
    if (!mounted) return;
    if (strategy.status != StrategyUiStatus.failed) {
      _contextEdited = false;
      _fillContext();
      if (mounted) {
        setState(() =>
            _contextNotice = existing ? '资料已保存，下次 AI 请求会使用更新后的内容。' : '目标已保存。');
      }
      if (!existing && agent.canGenerate) await _generate();
    }
  }

  Future<void> _start() async {
    if (busy) return;
    if (strategy.hasPendingProposal) {
      await strategy.decideProposal(ProposalDecision.accept);
    }
    if (strategy.canActivate) await strategy.activateStrategy();
  }

  Future<void> _feedback(ExecutionStatus status) async {
    if (busy) return;
    await agent.saveFeedback(status, note: _result.text);
    if (mounted && strategy.outcomeId != null) {
      _result.clear();
      await _focusAction();
    }
  }

  Future<void> _saveResult() async {
    if (_result.text.trim().isEmpty || busy) return;
    await agent.saveOutcome(_result.text);
    if (mounted && strategy.outcomeId != null) _result.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[agent, strategy]),
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Personal OS · 下一步')),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: <Widget>[
                      if (strategy.strategyId != null)
                        StrategyActionCard(
                          controller: strategy,
                          interactionBlocked: busy,
                          onStart: busy ? null : _start,
                          onReject: busy
                              ? null
                              : () => strategy
                                  .decideProposal(ProposalDecision.reject),
                          onFeedback: _feedback,
                          onSaveOutcome: busy ? null : _saveResult,
                          onAskAgent: agent.canGenerate ? _generate : null,
                          onReview: busy
                              ? null
                              : (decision) => agent.decideReview(decision),
                          outcome: _result,
                        )
                      else
                        Card(
                          color: const Color(0xff123c32),
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    const Text('把目标，变成你今天能做的一步',
                                        style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 26,
                                            fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 12),
                                    Text(
                                        strategy.personalGoal ??
                                            '连接 AI，告诉它你的目标。行动计划会直接出现在这里。',
                                        style: const TextStyle(
                                            color: Color(0xffc2f5d7),
                                            height: 1.6)),
                                    if (strategy.personalGoal !=
                                        null) ...<Widget>[
                                      const SizedBox(height: 18),
                                      FilledButton.icon(
                                          key: const Key('automatic-generate'),
                                          onPressed: agent.canGenerate
                                              ? _generate
                                              : null,
                                          icon: const Icon(Icons.auto_awesome),
                                          label: const Text('生成行动计划')),
                                    ],
                                  ])),
                        ),
                      if (agent.busy)
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(children: <Widget>[
                              const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(agent.checkingConnection
                                      ? '正在测试 AI 是否能够响应…'
                                      : agent.savingFeedback
                                          ? '正在保存你的行动反馈…'
                                          : 'AI 正在结合你的资料和行动历史思考…')),
                            ])),
                      if (agent.error != null ||
                          strategy.status == StrategyUiStatus.failed)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      Text(
                                          agent.error ??
                                              (strategy.errorCode ==
                                                      StrategyLoopFailureCode
                                                          .personalContextChanged
                                                  ? '资料已被更新，请刷新页面后再编辑。'
                                                  : '这次操作未能保存，请检查连接后重试。'),
                                          key: const Key(
                                              'automatic-agent-error')),
                                      if (agent.canGenerate)
                                        TextButton(
                                            onPressed: _generate,
                                            child: const Text('重试 AI 请求')),
                                    ]))),
                      _connection(),
                      Card(
                          child: ExpansionTile(
                        key: Key(
                            'automatic-personal-context-${strategy.personalGoal != null}'),
                        initiallyExpanded: strategy.personalGoal == null &&
                            strategy.strategyId == null,
                        title: Text(strategy.personalGoal == null
                            ? '你想达成什么？'
                            : '我的目标与资料'),
                        subtitle: strategy.personalGoal == null
                            ? const Text('先写一句话就够了')
                            : Text(strategy.personalGoal!),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: <Widget>[
                          TextField(
                              key: const Key('automatic-goal'),
                              controller: _goal,
                              enabled: !busy,
                              decoration: const InputDecoration(
                                  labelText: '目标', hintText: '例如：每天学习 20 分钟')),
                          const SizedBox(height: 12),
                          FilledButton(
                              key: const Key('automatic-save-goal'),
                              onPressed: busy || _goal.text.trim().isEmpty
                                  ? null
                                  : _saveGoal,
                              child: Text(strategy.personalGoalRecord != null
                                  ? '保存资料'
                                  : agent.connected
                                      ? '保存并生成行动计划'
                                      : '保存目标')),
                          if (_contextNotice != null)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(_contextNotice!)),
                          ExpansionTile(
                            key: const Key('automatic-profile-details'),
                            tilePadding: EdgeInsets.zero,
                            title: const Text('补充个人资料（可选）'),
                            subtitle: Text(_optionalContextFieldCount == 0
                                ? '成功标准、当前情况、执行限制'
                                : '已填写 $_optionalContextFieldCount 项'),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(0, 0, 0, 8),
                            children: <Widget>[
                              TextField(
                                  key: const Key('automatic-success-criteria'),
                                  controller: _successCriteria,
                                  enabled: !busy,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: '做到什么算完成',
                                      hintText: '例如：一周完成 3 次')),
                              const SizedBox(height: 12),
                              TextField(
                                  key: const Key('automatic-conditions'),
                                  controller: _conditions,
                                  enabled: !busy,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: '当前情况',
                                      hintText: '例如：工作日很累，晚上只有十分钟')),
                              const SizedBox(height: 12),
                              TextField(
                                  key: const Key('automatic-constraints'),
                                  controller: _constraints,
                                  enabled: !busy,
                                  maxLines: 2,
                                  decoration: const InputDecoration(
                                      labelText: '执行限制',
                                      hintText: '例如：不额外花钱，每天不超过 20 分钟')),
                            ],
                          ),
                        ],
                      )),
                      if (_additionalContextRecords.isNotEmpty)
                        _records(history: false),
                      if (strategy.contextRecords.any((e) => <String>[
                            'strategy',
                            'execution',
                            'outcome',
                            'review'
                          ].contains((e['ref'] as Map?)?['type'])))
                        _records(history: true),
                      const Padding(
                          padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
                          child: Text(
                              '你的资料和行动历史保存在本机。生成计划与复盘时，当前目标、成功标准、现状、执行限制和相关历史会发送给你连接的 AI。',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.black54))),
                    ],
                  ))),
        ),
      );
  Widget _connection() => Card(
      key: const Key('automatic-connection'),
      child: ExpansionTile(
        key: ValueKey('automatic-connection-${agent.connected}'),
        initiallyExpanded: !agent.connected,
        title: Text(agent.connected
            ? '使用 ${agent.connectionName ?? agent.provider}'
            : '连接你的 AI'),
        subtitle: Text(agent.hasPendingContinuation && !agent.connected
            ? '资料已保存，连接后会自动继续计划或复盘'
            : agent.connected
                ? agent.connectionCheckMessage ?? '已配置，可生成计划或测试 AI 响应'
                : agent.provider == 'chatgpt'
                    ? '首次登录一次，以后自动调用'
                    : '检查服务配置，保存后自动调用'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: <Widget>[
          if (agent.connections.length > 1)
            KeyedSubtree(
                key: ValueKey(agent.connectionId),
                child: DropdownButtonFormField<String>(
                  key: const Key('automatic-connection-picker'),
                  initialValue: agent.connectionId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '使用哪个 AI'),
                  items: agent.connections
                      .map((c) => DropdownMenuItem(
                          value: c['id'] as String,
                          child: Text(c['label'] as String,
                              maxLines: 1, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: busy
                      ? null
                      : (id) {
                          if (id != null) unawaited(_chooseConnection(id));
                        },
                )),
          if (!agent.connected && agent.provider == 'chatgpt')
            Link(
                uri: agent.gateway.signInPage,
                target: LinkTarget.blank,
                builder: (context, follow) => FilledButton.icon(
                    key: const Key('automatic-chatgpt-sign-in'),
                    onPressed: busy ? null : follow,
                    icon: const Icon(Icons.login),
                    label: const Text('Continue with ChatGPT'))),
          if (agent.models.isNotEmpty)
            KeyedSubtree(
                key: ValueKey('${agent.connectionId}:${agent.model}'),
                child: DropdownButtonFormField<String>(
                    key: const Key('automatic-model'),
                    initialValue: agent.model,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '模型'),
                    items: agent.models
                        .map((m) => DropdownMenuItem(
                            value: m['id'] as String,
                            child: Text(m['name'] as String,
                                maxLines: 1, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (value) {
                            agent.selectModel(value);
                            unawaited(_resume());
                          })),
          if (agent.provider == 'chatgpt' && agent.accounts.length > 1)
            DropdownButtonFormField<String>(
                initialValue: agent.account,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'ChatGPT 账号 / 工作区'),
                items: agent.accounts
                    .map((a) => DropdownMenuItem(
                        value: a['id'] as String,
                        child: Text(a['label'] as String,
                            maxLines: 1, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: busy
                    ? null
                    : (id) {
                        if (id != null) unawaited(_chooseAccount(id));
                      }),
          if (agent.connected && agent.model != null) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
                key: const Key('automatic-check-connection'),
                onPressed: busy ? null : agent.checkConnection,
                icon: const Icon(Icons.network_check),
                label: const Text('测试 AI 连接')),
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('发送固定测试内容，不读取你的个人资料。服务可能计入用量。',
                    style: TextStyle(fontSize: 12))),
          ],
          Wrap(spacing: 12, children: <Widget>[
            TextButton(
                key: const Key('add-agent-connection'),
                onPressed: busy ? null : () => _editConnection(),
                child: const Text('接入其他 AI')),
            if (agent.connectionId != null && agent.connectionId != 'chatgpt')
              TextButton(
                  onPressed: busy
                      ? null
                      : () => _editConnection(
                          connection: agent.connections.firstWhere(
                              (c) => c['id'] == agent.connectionId)),
                  child: const Text('编辑此连接')),
            TextButton(
                key: const Key('automatic-refresh-connection'),
                onPressed: busy ? null : () => _reconnect(retryPending: true),
                child: const Text('刷新连接')),
            if (agent.provider == 'chatgpt')
              Link(
                  uri: Uri.parse('https://chatgpt.com/#settings/Usage'),
                  target: LinkTarget.blank,
                  builder: (context, follow) => TextButton(
                      onPressed: follow, child: const Text('管理 ChatGPT 用量'))),
            if (agent.connected && agent.provider == 'chatgpt')
              TextButton(
                  onPressed: busy ? null : agent.logout,
                  child: const Text('退出 AI 账号')),
          ]),
        ],
      ));

  List<Map<String, Object?>> get _additionalContextRecords {
    final editableIds = <Object?>[
      strategy.personalGoalRecord,
      strategy.personalCurrentStateRecord,
      strategy.personalConstraintRecord,
    ]
        .whereType<Map<String, Object?>>()
        .map((record) => (record['ref'] as Map?)?['id'])
        .whereType<String>()
        .toSet();
    return strategy.contextRecords.where((record) {
      final ref = record['ref'] as Map?;
      return <String>['goal', 'personal_asset', 'constraint']
              .contains(ref?['type']) &&
          !editableIds.contains(ref?['id']);
    }).toList(growable: false);
  }

  Widget _records({required bool history}) {
    final labels = history
        ? <String, String>{
            'strategy': '行动计划',
            'execution': '执行记录',
            'outcome': '实际结果',
            'review': 'AI 复盘'
          }
        : <String, String>{
            'goal': '目标',
            'personal_asset': '个人情况',
            'constraint': '执行限制'
          };
    final records = history
        ? <Map<String, Object?>>[
            for (final type in labels.keys)
              ...strategy.contextRecords
                  .where((e) => (e['ref'] as Map?)?['type'] == type),
          ]
        : _additionalContextRecords;
    return Card(
        child: ExpansionTile(
      key: Key(history ? 'automatic-history' : 'automatic-saved-context'),
      title: Text(history ? '行动历史' : '其他个人资料'),
      subtitle: Text(history ? '计划、执行结果和 AI 复盘' : '共 ${records.length} 条补充资料'),
      children: records.map((record) {
        final type = (record['ref'] as Map)['type'] as String;
        final data = record['data'] as Map;
        final title = data['title'] as String?;
        final detail = data['observation'] ??
            data['summary'] ??
            data['content'] ??
            data['note'] ??
            data['rationale'] ??
            data['statement'];
        final criteria = data['success_criteria'] as List?;
        final state = <String, String>{
          'proposed': '待确认',
          'draft': '待确认',
          'accepted': '已接受',
          'rejected': '未接受',
          'active': '进行中',
          'completed': '已完成',
          'abandoned': '已结束',
          'archived': '已归档',
          'superseded': '已替代'
        }[data['state']];
        return ListTile(
          title: Text('${labels[type]}${state == null ? '' : ' · $state'}'),
          subtitle: Text(<String>[
            if (title != null) title,
            if (detail != null && detail != title) '$detail',
            if (criteria != null && criteria.isNotEmpty)
              '完成标准：${criteria.join('；')}',
          ].join('\n')),
        );
      }).toList(),
    ));
  }
}
