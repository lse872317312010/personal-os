import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import '../agent_interop/agent_handoff.dart';
import '../agent_interop/agent_reply_inbox.dart';
import '../agent_interop/agent_text_share.dart';
import '../composition/app_composition.dart';
import '../controller/strategy_loop_controller.dart';
import 'strategy_action_card.dart';

final class StrategyLoopScreen extends StatefulWidget {
  const StrategyLoopScreen({
    required this.controller,
    required this.mode,
    this.replyInbox,
    super.key,
  });

  final StrategyLoopController controller;
  final AppExperienceMode mode;
  final AgentReplyInboxController? replyInbox;

  @override
  State<StrategyLoopScreen> createState() => _StrategyLoopScreenState();
}

final class _StrategyLoopScreenState extends State<StrategyLoopScreen> {
  final _assistantName = TextEditingController(text: '通用 AI 助手');
  final _agentReply = TextEditingController();
  String? _loadedInboxReply;
  bool _showFormatRepairActions = false;
  final _review = TextEditingController();
  final _proposal = TextEditingController();
  final _outcome = TextEditingController();
  final _goal = TextEditingController();
  final _successCriteria = TextEditingController();
  final _currentState = TextEditingController();
  final _constraints = TextEditingController();
  final _scroll = ScrollController();
  final _collaborationKey = GlobalKey();
  bool _agentPanelOpen = true;
  final AgentTextSharePort _agentTextShare =
      const MethodChannelAgentTextShare();

  bool get _canUseSystemShare => widget.mode == AppExperienceMode.secureVault;

  @override
  void initState() {
    super.initState();
    _agentPanelOpen = widget.controller.strategyId == null;
    widget.replyInbox?.addListener(_syncReplyFromInbox);
    unawaited(_prepareRestoredSession());
  }

  @override
  void dispose() {
    widget.replyInbox?.removeListener(_syncReplyFromInbox);
    _assistantName.dispose();
    _agentReply.dispose();
    _review.dispose();
    _proposal.dispose();
    _outcome.dispose();
    _goal.dispose();
    _successCriteria.dispose();
    _currentState.dispose();
    _constraints.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _prepareRestoredSession() async {
    await widget.controller.bootstrap();
    if (!mounted) return;
    _syncReplyFromInbox();
    if (!widget.controller.hasSession) return;
    if (widget.controller.contextBundle == null) {
      await widget.controller.exportContext();
    }
  }

  Future<void> _startAgentSession() async {
    final name = _assistantName.text.trim().isEmpty
        ? '通用 AI 助手'
        : _assistantName.text.trim();
    await widget.controller.openOfflineSession(agentId: name);
    if (!mounted || !widget.controller.hasSession) return;
    await widget.controller.exportContext();
  }

  Future<void> _savePersonalContext() async {
    await widget.controller.savePersonalContext(
      goal: _goal.text,
      successCriteria: _successCriteria.text,
      currentState: _currentState.text,
      constraints: _constraints.text,
    );
  }

  void _loadDemoContext() {
    _goal.text = '一周内建立稳定的学习习惯';
    _successCriteria.text = '一周完成 3 次学习，并记录每次耗时和困难';
    _currentState.text = '演示资料：工作日晚上有 30 分钟空闲';
    _constraints.text = '演示约束：每天投入不超过 20 分钟，不额外花钱';
  }

  Future<void> _fillDemoReply() async {
    final bundle = await widget.controller.refreshContextForHandoff();
    if (!mounted || bundle == null) return;
    _agentReply.text = buildDemoAgentReply(
      bundle,
      strategyId: widget.controller.strategyId,
    );
    await _importAgentReply();
  }

  Future<void> _pasteAgentReply() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || data?.text == null) return;
      _agentReply.text = data!.text!;
      await _importAgentReply();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请在回复框中长按或使用 Ctrl+V 粘贴。')),
      );
    }
  }

  Future<void> _decideReview(ReviewDecision decision) async {
    await widget.controller.decideReview(decision);
    if (!mounted || widget.controller.status != StrategyUiStatus.ready) return;
    await widget.controller.exportContext();
    _returnToAction();
  }

  Future<void> _startPlan() async {
    if (widget.controller.status == StrategyUiStatus.running) return;
    FocusScope.of(context).unfocus();
    final controller = widget.controller;
    if (controller.hasPendingProposal) {
      await controller.decideProposal(ProposalDecision.accept);
    }
    if (!mounted ||
        controller.status != StrategyUiStatus.ready ||
        !controller.canActivate) {
      return;
    }
    await controller.activateStrategy();
  }

  Future<void> _recordExecution() async {
    final controller = widget.controller;
    if (controller.status == StrategyUiStatus.running) return;
    final actions = controller.strategyActions;
    if (actions.isEmpty) return;
    final action = controller.selectedAction ?? actions.first;
    controller.selectAction(action.id);
    await controller.recordExecution(
      actionId: action.id,
      executionStatus: ExecutionStatus.completed,
    );
  }

  void _returnToAction() {
    if (!mounted) return;
    setState(() => _agentPanelOpen = false);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _showAgentPanel() async {
    setState(() => _agentPanelOpen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final panel = _collaborationKey.currentContext;
    if (panel != null && panel.mounted) {
      await Scrollable.ensureVisible(panel, alignment: 0.05);
    }
  }

  Future<void> _recordOutcome() async {
    await widget.controller.recordOutcome(
      observation: _outcome.text,
      valence: OutcomeValence.mixed,
    );
    if (!mounted || widget.controller.status != StrategyUiStatus.ready) return;
    _outcome.clear();
    await widget.controller.exportContext();
  }

  void _syncReplyFromInbox() {
    final inbox = widget.replyInbox;
    if (!mounted) return;
    if (inbox != null && !inbox.vaultOpen) {
      _loadedInboxReply = null;
      _agentReply.clear();
      return;
    }
    if (!widget.controller.hasSession) return;
    final reply = inbox?.pendingReply;
    if (reply == null) {
      _loadedInboxReply = null;
      return;
    }
    if (_agentReply.text.isNotEmpty) return;
    _loadedInboxReply = reply;
    _agentReply.value = TextEditingValue(
      text: reply,
      selection: TextSelection.collapsed(offset: reply.length),
    );
  }

  Future<void> _loadReceivedAgentReply(BuildContext context) async {
    final reply = widget.replyInbox?.pendingReply;
    if (reply == null) return;

    final hasDifferentDraft =
        _agentReply.text.isNotEmpty && _agentReply.text != reply;
    if (hasDifferentDraft) {
      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('替换当前输入？'),
          content: const Text('当前输入内容将被收到的 AI 助手回复替换。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('保留当前输入'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('替换输入'),
            ),
          ],
        ),
      );
      if (!mounted || shouldReplace != true) return;
    }

    _loadedInboxReply = reply;
    _agentReply.value = TextEditingValue(
      text: reply,
      selection: TextSelection.collapsed(offset: reply.length),
    );
  }

  Future<void> _importAgentReply() async {
    try {
      final replyText = _agentReply.text;
      final pendingInboxReply = widget.replyInbox?.pendingReply;
      final importedInboxReply =
          pendingInboxReply != null && _loadedInboxReply == pendingInboxReply;
      final reply = parseAgentHandoffReply(replyText);
      final controller = widget.controller;
      if (reply.kind == AgentReplyKind.review) {
        await controller.importReview(reply.bundleJson);
      } else {
        await controller.importProposal(reply.bundleJson);
      }
      if (!mounted) return;
      final imported = controller.status == StrategyUiStatus.ready &&
          (reply.kind == AgentReplyKind.proposal
              ? controller.hasPendingProposal
              : controller.hasPendingReview);
      if (!imported) {
        const repairableErrors = <String>{
          'invalid_request',
          'validation_failed',
          'unsupported_version',
          'unpinned_reference',
          'access_denied',
          'not_found',
          'stale_reference',
        };
        if (controller.status == StrategyUiStatus.failed &&
            repairableErrors.contains(controller.errorCode)) {
          setState(() => _showFormatRepairActions = true);
        }
        if (controller.errorCode case final code?) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_strategyErrorText(code))),
          );
        }
        return;
      }
      setState(() => _showFormatRepairActions = false);
      _agentReply.clear();
      await controller.exportContext();
      if (!mounted) return;
      var inboxAcknowledged = true;
      if (importedInboxReply) {
        _loadedInboxReply = null;
        inboxAcknowledged =
            await widget.replyInbox?.clearPendingReply() ?? false;
      } else {
        _syncReplyFromInbox();
      }
      if (!mounted) return;
      _returnToAction();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            inboxAcknowledged
                ? '建议已导入，请查看内容并决定是否接受。'
                : '建议已导入，但收件箱未能确认移除原回复；请勿重复导入，'
                    '待加密收件箱恢复后再明确丢弃原回复。',
          ),
        ),
      );
    } on AgentHandoffFormatException catch (error) {
      if (!mounted) return;
      if (error.issue != AgentHandoffFormatIssue.empty) {
        setState(() => _showFormatRepairActions = true);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.userMessage)),
      );
    }
  }

  Future<String?> _prepareHandoff(
    BuildContext context, {
    required bool useSystemShare,
    String? rejectedReply,
  }) async {
    if (rejectedReply != null && rejectedReply.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先保留 AI 助手的原回复，再生成修正请求。')),
      );
      return null;
    }
    final bundle = await widget.controller.refreshContextForHandoff();
    if (!context.mounted) return null;
    if (bundle == null) {
      final errorCode = widget.controller.errorCode;
      final message = errorCode == null
          ? '无法准备最新协作内容，请稍后重试。'
          : _strategyErrorText(errorCode);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return null;
    }
    final prompt = rejectedReply == null
        ? buildAgentHandoffPrompt(
            bundle,
            strategyId: widget.controller.strategyId,
          )
        : buildAgentHandoffRepairPrompt(
            contextBundle: bundle,
            rejectedReply: rejectedReply,
            strategyId: widget.controller.strategyId,
          );
    if (widget.mode != AppExperienceMode.secureVault) return prompt;

    final sharedData = rejectedReply == null
        ? '当前导出的目标、资产、策略和历史记录'
        : '当前导出的目标、资产、策略和历史记录，以及上一条未能识别的回复文本';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(useSystemShare ? '确认发送个人上下文' : '确认复制个人上下文'),
        content: Text(
          useSystemShare
              ? '这会把$sharedData交给系统分享菜单中你选择的应用。'
                  '对应应用和服务可能保存或处理这些信息。请确认你愿意分享。'
              : '这会把$sharedData放入系统剪贴板。'
                  '设备或输入法可能同步或暂存剪贴板内容；粘贴到外部 AI 助手后，'
                  '对应服务也会收到这些信息。请确认你愿意分享。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(useSystemShare ? '继续发送' : '继续复制'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return null;
    return prompt;
  }

  Future<void> _configureAutomaticAgent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('连接 OpenAI API'),
        content: const Text(
          '接下来会在 Android 原生安全输入框中输入 API 密钥。'
          '此步骤不会发送个人资料；密钥只留在当前 Vault 解锁期间的内存中，'
          '锁定 Vault 时清除。发送请求时会逐次征求确认，API 用量可能产生独立费用。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('输入 API 密钥'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final configured = await widget.controller.configureAutomaticAgent();
    if (!mounted) return;
    if (configured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OpenAI API 已连接。发送个人上下文前仍会再次确认。')),
      );
    } else if (widget.controller.errorCode case final code?) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_strategyErrorText(code))),
      );
    }
  }

  Future<String?> _prepareAutomaticAgentRequest(BuildContext context) async {
    final bundle = await widget.controller.refreshContextForHandoff();
    if (!context.mounted) return null;
    if (bundle == null) {
      final errorCode = widget.controller.errorCode;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorCode == null
              ? '无法准备最新协作内容，请稍后重试。'
              : _strategyErrorText(errorCode)),
        ),
      );
      return null;
    }
    late final String externalBundle;
    late final String prompt;
    try {
      externalBundle = buildExternalAgentContextBundle(bundle);
      prompt = buildAgentHandoffPrompt(
        externalBundle,
        strategyId: widget.controller.strategyId,
      );
    } on ExternalAgentContextException catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.userMessage)),
      );
      return null;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: const Text('发送本轮上下文到 OpenAI？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '本次只发送当前协作中的目标、约束、策略、行动、执行、结果和复盘。'
              'Personal Asset 与 Observation 记录会先从内容中剔除。',
            ),
            const SizedBox(height: 8),
            Text(
              'OpenAI API 会收到下面这份数据。请检查其中是否包含你不想发送的内容。'
              'API 用量可能产生独立费用，与 ChatGPT 订阅分开。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('查看本次发送的数据'),
              children: <Widget>[
                SizedBox(
                  height: 220,
                  child: SingleChildScrollView(
                    child: SelectableText(externalBundle),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('仅发送这一次'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return null;
    return prompt;
  }

  Future<void> _requestAutomaticAgent(BuildContext context) async {
    final prompt = await _prepareAutomaticAgentRequest(context);
    if (prompt == null || !context.mounted) return;
    final reply = await widget.controller.requestAutomaticAgent(prompt: prompt);
    if (!mounted) return;
    if (reply == null) {
      if (widget.controller.errorCode case final code?) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_strategyErrorText(code))),
        );
      }
      return;
    }
    _agentReply.value = TextEditingValue(
      text: reply,
      selection: TextSelection.collapsed(offset: reply.length),
    );
    await _importAgentReply();
  }

  Future<void> _disconnectAutomaticAgent() async {
    await widget.controller.disconnectAutomaticAgent();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已从当前解锁会话断开 OpenAI API。')),
    );
  }

  Future<void> _copyHandoff(BuildContext context) async {
    final prompt = await _prepareHandoff(context, useSystemShare: false);
    if (prompt == null || !context.mounted) return;

    try {
      await Clipboard.setData(ClipboardData(text: prompt));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制失败，请检查设备剪贴板权限后重试。')),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('协作内容已复制。粘贴到任意 AI 助手，再把回复粘贴回来。'),
      ),
    );
  }

  Future<void> _shareHandoff(BuildContext context) async {
    final prompt = await _prepareHandoff(context, useSystemShare: true);
    if (prompt == null || !context.mounted) return;

    try {
      await _agentTextShare.share(prompt);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法打开系统分享菜单，请改用“复制协作内容”。'),
        ),
      );
    }
  }

  Future<void> _copyFormatRepairRequest(BuildContext context) async {
    final prompt = await _prepareHandoff(
      context,
      useSystemShare: false,
      rejectedReply: _agentReply.text,
    );
    if (prompt == null || !context.mounted) return;

    try {
      await Clipboard.setData(ClipboardData(text: prompt));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制失败，请检查设备剪贴板权限后重试。')),
      );
      return;
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('修正请求已复制。粘贴回原助手会话，再把新回复分享或粘贴回来。'),
      ),
    );
  }

  Future<void> _shareFormatRepairRequest(BuildContext context) async {
    final prompt = await _prepareHandoff(
      context,
      useSystemShare: true,
      rejectedReply: _agentReply.text,
    );
    if (prompt == null || !context.mounted) return;

    try {
      await _agentTextShare.share(prompt);
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('无法打开系统分享菜单，请改用“复制格式修正请求”。'),
        ),
      );
    }
  }

  Future<void> _closeAgentSession() async {
    await widget.controller.closeSession();
    if (!mounted || widget.controller.hasSession) return;
    _loadedInboxReply = null;
    _agentReply.clear();
    setState(() => _showFormatRepairActions = false);
    // Switching sessions is not an explicit decision to discard a reply.
    _review.clear();
    _proposal.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final busy = controller.status == StrategyUiStatus.running;
          return ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              if (controller.errorCode != null || busy)
                _StatusCard(controller: controller),
              if (controller.strategyId != null)
                StrategyActionCard(
                  controller: controller,
                  onStart: _startPlan,
                  onReject: () => controller.decideProposal(
                    ProposalDecision.reject,
                  ),
                  onRecord: _recordExecution,
                  onSaveOutcome: _recordOutcome,
                  onAskAgent: _showAgentPanel,
                  onReview: _decideReview,
                  outcome: _outcome,
                )
              else ...<Widget>[
                Text(
                  '把目标变成下一步行动',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.mode == AppExperienceMode.syntheticDemo
                      ? '浏览器演示只在当前页面内存运行。先写一个目标，再让常用 AI 帮你安排。'
                      : '先写一个目标，再让常用 AI 帮你安排。',
                ),
              ],
              const SizedBox(height: 12),
              Card(
                key: const Key('personal-context-form'),
                child: ExpansionTile(
                  key: ValueKey<String>(
                    '${controller.hasSession}:${controller.personalGoal != null}',
                  ),
                  initiallyExpanded: controller.personalGoal == null &&
                      controller.strategyId == null &&
                      !controller.hasSession,
                  title: Text(
                    controller.personalGoal == null ? '目标和个人条件' : '个人资料与历史',
                  ),
                  subtitle: controller.personalGoal == null
                      ? null
                      : Text(controller.personalGoal!),
                  children: <Widget>[
                    if (controller.personalGoal != null)
                      _PersonalContextCard(controller: controller),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            controller.personalGoal == null
                                ? '先保存这轮目标和个人条件'
                                : '补充新的目标和个人条件',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('personal-goal-input'),
                            controller: _goal,
                            enabled: !busy,
                            maxLength: 4000,
                            decoration: const InputDecoration(
                                labelText: '这轮目标', counterText: ''),
                          ),
                          ExpansionTile(
                            key: const Key('personal-context-options'),
                            tilePadding: EdgeInsets.zero,
                            title: const Text('补充个人条件（可选）'),
                            children: <Widget>[
                              TextField(
                                key: const Key('personal-success-input'),
                                controller: _successCriteria,
                                enabled: !busy,
                                maxLength: 4000,
                                decoration: const InputDecoration(
                                  labelText: '怎样算完成（可选）',
                                ),
                              ),
                              TextField(
                                key: const Key('personal-state-input'),
                                controller: _currentState,
                                enabled: !busy,
                                maxLength: 4000,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: '已有条件或当前情况（可选）',
                                ),
                              ),
                              TextField(
                                key: const Key('personal-constraints-input'),
                                controller: _constraints,
                                enabled: !busy,
                                maxLength: 4000,
                                maxLines: 3,
                                decoration: const InputDecoration(
                                  labelText: '时间、预算和其他约束（可选）',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (widget.mode == AppExperienceMode.syntheticDemo)
                            TextButton.icon(
                              key: const Key('load-demo-personal-context'),
                              onPressed: busy ? null : _loadDemoContext,
                              icon: const Icon(Icons.science_outlined),
                              label: const Text('填入演示资料'),
                            ),
                          FilledButton.icon(
                            key: const Key('save-personal-context'),
                            onPressed: busy ? null : _savePersonalContext,
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('保存我的目标'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.replyInbox?.replyQueueStorageUnavailable ?? false)
                const Card(
                  key: Key('agent-reply-storage-warning'),
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '本机加密收件箱暂不可用。已有回复不会被自动删除；'
                      '新回复可能无法保存，请先处理当前可见回复，必要时回到助手重新分享。',
                    ),
                  ),
                ),
              if (!(widget.replyInbox?.hasPendingReply ?? false) &&
                  (widget.replyInbox?.droppedReplyCount ?? 0) > 0)
                Card(
                  key: const Key('agent-reply-overflow-note'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '收件箱容量不足或保存失败，${widget.replyInbox!.droppedReplyCount} 条新回复未保留，'
                          '请回到发送回复的助手重新分享。',
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed:
                                widget.replyInbox!.clearDroppedReplyNotice,
                            child: const Text('知道了'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!controller.hasSession &&
                  (widget.replyInbox?.hasPendingReply ?? false))
                Card(
                  key: const Key('orphaned-agent-reply'),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '收到了一条助手回复，但没有找到原协作会话。',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '为避免把回复放进错误会话，请先丢弃这条回复，再重新开始协作并发送最新上下文。',
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const Key('discard-orphaned-agent-reply'),
                            onPressed: () => unawaited(
                              widget.replyInbox!.clearPendingReply(),
                            ),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('丢弃回复'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: const Key('agent-collaboration-panel'),
                child: Container(
                  key: _collaborationKey,
                  child: ExpansionTile(
                    key: ValueKey<String>(
                      '${controller.strategyId}:$_agentPanelOpen:'
                      '${widget.replyInbox?.hasPendingReply}',
                    ),
                    initiallyExpanded: _agentPanelOpen ||
                        (widget.replyInbox?.hasPendingReply ?? false),
                    maintainState: true,
                    title: const Text('与 AI 协作'),
                    subtitle: Text(controller.hasSession
                        ? '直接请求 OpenAI，或用其他助手协作'
                        : '用你常用的 ChatGPT、Codex 或其他助手'),
                    onExpansionChanged: (open) {
                      _agentPanelOpen = open;
                    },
                    children: <Widget>[
                      const SizedBox(height: 16),
                      TextField(
                        key: const Key('assistant-name-input'),
                        controller: _assistantName,
                        enabled: !busy && !controller.hasSession,
                        decoration: const InputDecoration(
                          labelText: 'AI 助手名称（可选）',
                          hintText: '例如：ChatGPT、Codex、Claude 或本地助手',
                          helperText: '可填写任何助手或 Harness 名称；无需专门适配。',
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const Key('open-agent-session'),
                        onPressed: busy ||
                                controller.hasSession ||
                                (widget.replyInbox?.hasPendingReply ?? false)
                            ? null
                            : _startAgentSession,
                        icon: const Icon(Icons.link),
                        label: const Text('准备给 AI 的请求'),
                      ),
                      if (controller.hasSession) ...<Widget>[
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '协作会话：${controller.agentId}',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                if (controller.contextBundle == null)
                                  const Text('正在准备协作内容…')
                                else ...<Widget>[
                                  const Text(
                                    '每次发送都会自动准备最新上下文。可直接向 OpenAI API 请求并读取回复，'
                                    '也可用系统分享或复制给其他助手。',
                                  ),
                                  const SizedBox(height: 12),
                                  if (widget.mode ==
                                      AppExperienceMode.secureVault)
                                    if (controller.automaticAgentConfigured)
                                      FilledButton.icon(
                                        key: const Key('request-openai-agent'),
                                        onPressed: busy ||
                                                !controller.canRequestAgent
                                            ? null
                                            : () =>
                                                _requestAutomaticAgent(context),
                                        icon: const Icon(Icons.auto_awesome),
                                        label: const Text('向 OpenAI 请求并读取建议'),
                                      )
                                    else
                                      OutlinedButton.icon(
                                        key: const Key('connect-openai-agent'),
                                        onPressed: busy
                                            ? null
                                            : _configureAutomaticAgent,
                                        icon: const Icon(Icons.link),
                                        label: const Text('连接 OpenAI API'),
                                      ),
                                  if (controller.automaticAgentConfigured)
                                    TextButton.icon(
                                      key: const Key('disconnect-openai-agent'),
                                      onPressed: busy
                                          ? null
                                          : _disconnectAutomaticAgent,
                                      icon: const Icon(Icons.link_off),
                                      label: const Text('断开连接'),
                                    ),
                                  FilledButton.tonalIcon(
                                    key: const Key('copy-agent-handoff'),
                                    onPressed:
                                        busy || !controller.canRequestAgent
                                            ? null
                                            : () => _copyHandoff(context),
                                    icon: const Icon(Icons.copy),
                                    label: const Text('复制请求，发给常用 AI'),
                                  ),
                                  if (widget.mode ==
                                      AppExperienceMode.secureVault)
                                    OutlinedButton.icon(
                                      key: const Key('share-agent-handoff'),
                                      onPressed:
                                          busy || !controller.canRequestAgent
                                              ? null
                                              : () => _shareHandoff(context),
                                      icon: const Icon(Icons.ios_share),
                                      label: const Text('选择 AI 助手发送'),
                                    ),
                                ],
                                if (widget.replyInbox?.hasPendingReply ?? false)
                                  Card(
                                    key: const Key('received-agent-reply-note'),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            <String>[
                                              '收到的回复暂存在本机加密收件箱中，不会自动导入。'
                                                  '检查后再手动导入；导入的建议仍需你单独接受。',
                                              if ((widget.replyInbox
                                                          ?.queuedReplyCount ??
                                                      0) >
                                                  0)
                                                '另有 ${widget.replyInbox!.queuedReplyCount} 条回复等待处理。',
                                              if ((widget.replyInbox
                                                          ?.droppedReplyCount ??
                                                      0) >
                                                  0)
                                                '收件箱容量不足或保存失败，${widget.replyInbox!.droppedReplyCount} 条新回复未保留，请回到发送回复的助手重新分享。',
                                            ].join(' '),
                                          ),
                                          if ((widget.replyInbox
                                                      ?.droppedReplyCount ??
                                                  0) >
                                              0)
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: TextButton(
                                                onPressed: widget.replyInbox!
                                                    .clearDroppedReplyNotice,
                                                child: const Text('知道了'),
                                              ),
                                            ),
                                          ValueListenableBuilder<
                                              TextEditingValue>(
                                            valueListenable: _agentReply,
                                            builder: (context, value, _) {
                                              final reply = widget
                                                  .replyInbox?.pendingReply;
                                              if (reply == null ||
                                                  value.text == reply) {
                                                return const SizedBox.shrink();
                                              }
                                              return Align(
                                                alignment: Alignment.centerLeft,
                                                child: TextButton.icon(
                                                  key: const Key(
                                                    'load-received-agent-reply',
                                                  ),
                                                  onPressed: () =>
                                                      _loadReceivedAgentReply(
                                                          context),
                                                  icon: const Icon(
                                                      Icons.content_paste),
                                                  label: Text(
                                                    value.text.isEmpty
                                                        ? '放入输入框'
                                                        : '用收到的回复替换当前输入',
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: TextButton.icon(
                                              key: const Key(
                                                'discard-received-agent-reply',
                                              ),
                                              onPressed: () async {
                                                final reply = widget
                                                    .replyInbox?.pendingReply;
                                                _loadedInboxReply = null;
                                                if (_agentReply.text == reply) {
                                                  _agentReply.clear();
                                                }
                                                await widget.replyInbox
                                                    ?.clearPendingReply();
                                              },
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              label: const Text('丢弃回复'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: <Widget>[
                                    TextButton.icon(
                                      key: const Key('paste-agent-reply'),
                                      onPressed: busy ? null : _pasteAgentReply,
                                      icon: const Icon(Icons.content_paste),
                                      label: const Text('粘贴并读取回复'),
                                    ),
                                    if (widget.mode ==
                                        AppExperienceMode.syntheticDemo)
                                      TextButton.icon(
                                        key: const Key('fill-demo-agent-reply'),
                                        onPressed:
                                            busy || !controller.canRequestAgent
                                                ? null
                                                : _fillDemoReply,
                                        icon:
                                            const Icon(Icons.science_outlined),
                                        label: const Text('用演示回复体验'),
                                      ),
                                  ],
                                ),
                                TextField(
                                  key: const Key('agent-reply-input'),
                                  controller: _agentReply,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: InputDecoration(
                                    labelText: 'AI 助手的回复',
                                    hintText: '可从助手分享回来，也可粘贴完整回复',
                                    helperText:
                                        widget.replyInbox?.hasPendingReply ??
                                                false
                                            ? '收到了一条回复；检查后再手动导入。'
                                            : null,
                                    alignLabelWithHint: true,
                                  ),
                                ),
                                if (_showFormatRepairActions) ...<Widget>[
                                  const SizedBox(height: 12),
                                  Card(
                                    key: const Key('agent-reply-format-repair'),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .tertiaryContainer,
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(
                                            '不用手动修改 JSON',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            '让原助手基于最新上下文重新生成，'
                                            '应用会保留这条回复并说明需要修正的格式。',
                                          ),
                                          const SizedBox(height: 8),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: <Widget>[
                                              FilledButton.tonalIcon(
                                                key: const Key(
                                                  'copy-agent-repair-request',
                                                ),
                                                onPressed: busy
                                                    ? null
                                                    : () =>
                                                        _copyFormatRepairRequest(
                                                          context,
                                                        ),
                                                icon: const Icon(Icons.copy),
                                                label: const Text('复制格式修正请求'),
                                              ),
                                              if (_canUseSystemShare)
                                                OutlinedButton.icon(
                                                  key: const Key(
                                                    'share-agent-repair-request',
                                                  ),
                                                  onPressed: busy
                                                      ? null
                                                      : () =>
                                                          _shareFormatRepairRequest(
                                                            context,
                                                          ),
                                                  icon: const Icon(
                                                      Icons.ios_share),
                                                  label: const Text('发送给助手修正'),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                FilledButton.icon(
                                  key: const Key('import-agent-reply'),
                                  onPressed: busy ? null : _importAgentReply,
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('读取这份回复'),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  key: const Key('close-agent-session'),
                                  onPressed: busy || !controller.canCloseSession
                                      ? null
                                      : _closeAgentSession,
                                  icon: const Icon(Icons.swap_horiz),
                                  label: const Text('更换 AI 助手'),
                                ),
                                if (!controller.canCloseSession &&
                                    controller.strategyId != null)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      '先记录实际结果或拒绝当前策略，就能切换助手。',
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        ExpansionTile(
                          key: const Key('advanced-agent-options'),
                          title: const Text('高级 / 兼容模式'),
                          subtitle: const Text('手动导入 Bundle、查看原始上下文或技术信息'),
                          children: <Widget>[
                            if (controller.contextBundle
                                case final bundle?) ...<Widget>[
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Context Bundle',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: SelectableText(
                                    bundle,
                                    key: const Key('context-bundle-output'),
                                    maxLines: 10,
                                  ),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                key: const Key('export-context'),
                                onPressed:
                                    busy ? null : controller.exportContext,
                                icon: const Icon(Icons.refresh),
                                label: const Text('重新准备协作上下文'),
                              ),
                            ],
                            TextField(
                              key: const Key('review-bundle-input'),
                              controller: _review,
                              minLines: 4,
                              maxLines: 10,
                              decoration: const InputDecoration(
                                labelText: '手动导入 Review Bundle',
                                hintText: '粘贴结构化复盘 JSON',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              key: const Key('import-review'),
                              onPressed: busy
                                  ? null
                                  : () => controller.importReview(_review.text),
                              child: const Text('验证并导入复盘'),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              key: const Key('proposal-bundle-input'),
                              controller: _proposal,
                              minLines: 4,
                              maxLines: 10,
                              decoration: const InputDecoration(
                                labelText: '手动导入 Proposal Bundle',
                                hintText: '粘贴结构化策略 JSON',
                                alignLabelWithHint: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              key: const Key('import-proposal'),
                              onPressed: busy
                                  ? null
                                  : () =>
                                      controller.importProposal(_proposal.text),
                              child: const Text('验证并导入策略'),
                            ),
                            const SizedBox(height: 12),
                            SelectableText(
                              'Session ID: ${controller.sessionId}',
                              key: const Key('advanced-session-id'),
                            ),
                            if (controller.strategyId case final id?)
                              Text('Strategy ID: $id'),
                            if (controller.executionId case final id?)
                              Text('Execution ID: $id'),
                            if (controller.outcomeId case final id?)
                              Text('Outcome ID: $id'),
                            if (controller.reviewId case final id?)
                              Text(
                                  'Review ID: $id (${controller.reviewState})'),
                            if (controller.proposalEvidenceRefs.isNotEmpty)
                              Text(
                                '引用：${controller.proposalEvidenceRefs.join(', ')}',
                              ),
                            if (controller.reviewEvidenceRefs.isNotEmpty)
                              Text(
                                '复盘证据：${controller.reviewEvidenceRefs.join(', ')}',
                              ),
                          ],
                        ),
                        if (!controller.canCloseSession &&
                            controller.strategyId != null)
                          const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
}

final class _PersonalContextCard extends StatelessWidget {
  const _PersonalContextCard({required this.controller});

  final StrategyLoopController controller;

  @override
  Widget build(BuildContext context) {
    final records = controller.contextRecords;
    int count(String type) => records
        .where((record) => (record['ref'] as Map)['type'] == type)
        .length;
    return Card(
      key: const Key('structured-personal-context'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '应用替你保留的个人上下文',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('目标：${controller.personalGoal}'),
            for (final record in records)
              if (<String>{'personal_asset', 'constraint'}
                  .contains((record['ref'] as Map)['type']))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${(record['data'] as Map)['title']}：'
                    '${(record['data'] as Map)['content']}',
                  ),
                ),
            const SizedBox(height: 8),
            Text(
              '策略版本 ${count('strategy')} · 执行记录 ${count('execution')} · '
              '结果 ${count('outcome')} · 复盘 ${count('review')}',
              key: const Key('strategy-history-summary'),
            ),
            const SizedBox(height: 4),
            const Text('更换助手后仍会带上这些历史；助手建议与实际执行分开保存。'),
          ],
        ),
      ),
    );
  }
}

final class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final StrategyLoopController controller;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('当前状态：${_strategyStateText(controller.strategyState)}'),
              if (controller.errorCode case final error?)
                Text(
                  _strategyErrorText(error),
                  key: const Key('strategy-error-message'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (controller.status == StrategyUiStatus.running) ...<Widget>[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      );
}

String _strategyStateText(String? state) => switch (state) {
      'proposed' => '等待你确认建议',
      'accepted' => '策略已确认',
      'active' => '正在执行',
      'completed' => '已完成',
      'abandoned' => '已停止',
      _ => '尚未导入策略',
    };

String _strategyErrorText(String code) => switch (code) {
      'strategy.session_already_open' => '当前已有会话，请先结束当前会话。',
      'strategy.agent_id_invalid' => '助手名称需为 1–100 个字符，请缩短后重试。',
      'strategy.session_required' => '请先开始与 AI 助手协作。',
      'strategy.loop_must_finish_before_handoff' =>
        '先完成当前策略并记录实际结果，或拒绝待确认的建议，之后才能切换助手。',
      'strategy.session_or_review_bundle_required' => '请先开始协作，再粘贴 AI 助手的回复。',
      'strategy.pending_review_required' => '当前没有等待确认的复盘。',
      'strategy.accepted_review_required' => '修订策略前请先导入并接受一份复盘。',
      'strategy.session_or_bundle_required' => '请先开始协作，再粘贴 AI 助手的回复。',
      'strategy.pending_proposal_required' => '当前没有等待确认的策略。',
      'strategy.accepted_strategy_required' => '请先确认策略，再激活执行。',
      'strategy.active_strategy_required' => '请先激活策略，再记录执行。',
      'strategy.action_required' => '当前没有可记录的行动，请检查策略后重试。',
      'strategy.action_selection_required' => '请先选择你实际完成的行动。',
      'strategy.action_not_in_strategy' => '该行动不属于当前策略，请从策略步骤中重新选择。',
      'strategy.action_selection_mismatch' => '行动选择已变化，请重新选择后再记录。',
      'strategy.execution_or_observation_required' => '请先记录执行，并填写实际结果或观察。',
      'strategy.restore_ambiguous_open_sessions' => '发现多个未完成的策略会话，无法安全恢复。',
      'strategy.restore_malformed_state' => '策略历史无法恢复，请检查本地记录。',
      'strategy.unexpected_failure' => '策略操作暂时无法完成，请稍后重试。',
      'strategy.context_too_large' => '个人历史过大，暂时无法完整准备上下文；请勿使用不完整的内容继续协作。',
      'invalid_request' ||
      'validation_failed' =>
        '这份建议暂时无法导入。请重新复制完整回复，让助手再生成一次。',
      'unsupported_version' => '这份建议与当前版本不兼容。请重新复制协作内容，再让助手生成。',
      'unpinned_reference' ||
      'strategy_loop.pinned_reference_required' =>
        '建议引用的资料版本不完整。请重新准备协作内容，再试一次。',
      'session_closed' => '这轮协作已结束，请开始新一轮。',
      'access_denied' => '助手回复与当前协作不匹配。请复制最新协作内容，再让助手生成。',
      'not_found' => '建议引用了当前资料中不存在的内容。请让助手只使用提供的上下文。',
      'stale_reference' => '资料刚刚有更新。请重新准备协作内容，再让助手生成。',
      'internal_error' => '策略服务暂时不可用，请稍后重试。',
      'strategy_loop.invalid_command' => '当前策略状态不允许此操作，请检查步骤顺序。',
      'strategy_loop.user_authority_required' => '此操作需要用户本人确认。',
      'strategy_loop.agent_authority_required' => '请使用当前 AI 助手协作会话提交建议。',
      'strategy_loop.outcome_authority_denied' => '实际结果只能由用户本人记录。',
      'strategy_loop.d4_forbidden' ||
      'feedback.d4_forbidden' =>
        '当前闭环不支持 D4 级敏感资料。',
      'agent.adapter_unavailable' => '当前版本尚未启用 OpenAI 自动接入，或原生服务暂时不可用。',
      'agent.credential_required' => '请先连接 OpenAI API。',
      'agent.credential_cancelled' => '已取消 OpenAI API 密钥输入。',
      'agent.invalid_request' => '本次协作内容过长、无效或含疑似凭据，已阻止发送。',
      'agent.invalid_response' => 'OpenAI 返回格式暂不支持，请重试或改用手动助手。',
      'agent.request_failed' => 'OpenAI 请求未完成，请检查网络和 API 密钥后重试。',
      _ => '操作未完成，请检查当前步骤后重试。',
    };
