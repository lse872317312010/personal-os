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
  final _review = TextEditingController();
  final _proposal = TextEditingController();
  final _outcome = TextEditingController();
  final AgentTextSharePort _agentTextShare =
      const MethodChannelAgentTextShare();

  @override
  void initState() {
    super.initState();
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

  void _syncReplyFromInbox() {
    final inbox = widget.replyInbox;
    if (!mounted) return;
    if (inbox != null && !inbox.vaultOpen) {
      _agentReply.clear();
      return;
    }
    if (!widget.controller.hasSession) return;
    final reply = inbox?.pendingReply;
    if (reply == null || _agentReply.text.isNotEmpty) return;
    _agentReply.value = TextEditingValue(
      text: reply,
      selection: TextSelection.collapsed(offset: reply.length),
    );
  }

  Future<void> _importAgentReply() async {
    try {
      final reply = parseAgentHandoffReply(_agentReply.text);
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
      if (!imported) return;
      _agentReply.clear();
      widget.replyInbox?.clearPendingReply();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('建议已导入，请查看内容并决定是否接受。')),
      );
    } on AgentHandoffFormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.userMessage)),
      );
    }
  }

  Future<String?> _prepareHandoff(
    BuildContext context, {
    required bool useSystemShare,
  }) async {
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
    final prompt = buildAgentHandoffPrompt(bundle);
    if (widget.mode != AppExperienceMode.secureVault) return prompt;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(useSystemShare ? '确认发送个人上下文' : '确认复制个人上下文'),
        content: Text(
          useSystemShare
              ? '这会把当前导出的目标、资产、策略和历史记录交给系统分享菜单中你选择的应用。'
                  '对应应用和服务可能保存或处理这些信息。请确认你愿意分享。'
              : '这会把当前导出的目标、资产、策略和历史记录放入系统剪贴板。'
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

  Future<void> _closeAgentSession() async {
    await widget.controller.closeSession();
    if (!mounted || widget.controller.hasSession) return;
    _agentReply.clear();
    widget.replyInbox?.clearPendingReply();
    _review.clear();
    _proposal.clear();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final busy = controller.status == StrategyUiStatus.running;
          final selectedActionId = controller.selectedActionId;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              Text(
                '个人策略闭环',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                widget.mode == AppExperienceMode.syntheticDemo
                    ? '浏览器演示只在当前页面内存运行，刷新或关闭页面后清空。'
                        '外部 AI 助手只提交建议，接受、执行和结果始终由你确认。'
                    : '手机保存资产、策略和真实反馈；外部 AI 助手只提交建议，'
                        '接受、执行和结果始终由你确认。',
              ),
              const SizedBox(height: 16),
              _StatusCard(controller: controller),
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
                            onPressed:
                                widget.replyInbox!.clearPendingReply,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('丢弃回复'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
                label: const Text('开始协作并准备上下文'),
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
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (controller.contextBundle == null)
                          const Text('正在准备协作内容…')
                        else ...<Widget>[
                          const Text(
                            '每次发送或复制都会自动准备最新上下文。可选择系统分享，'
                            '或复制后粘贴到常用助手；助手回复可以直接分享回来，也可以粘贴到下方。',
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonalIcon(
                            key: const Key('copy-agent-handoff'),
                            onPressed:
                                busy ? null : () => _copyHandoff(context),
                            icon: const Icon(Icons.copy),
                            label: const Text('复制协作内容'),
                          ),
                          if (widget.mode == AppExperienceMode.secureVault)
                            OutlinedButton.icon(
                              key: const Key('share-agent-handoff'),
                              onPressed:
                                  busy ? null : () => _shareHandoff(context),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const Text(
                                    '已收到助手回复，并填入下方输入框。',
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    '内容仍在本机内存中。检查后手动导入；'
                                    '导入的建议仍需你单独接受。',
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton.icon(
                                      key: const Key(
                                        'discard-received-agent-reply',
                                      ),
                                      onPressed: () {
                                        widget.replyInbox
                                            ?.clearPendingReply();
                                        _agentReply.clear();
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('丢弃回复'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const Key('agent-reply-input'),
                          controller: _agentReply,
                          minLines: 4,
                          maxLines: 10,
                          decoration: InputDecoration(
                            labelText: 'AI 助手的回复',
                            hintText: '可从助手分享回来，也可粘贴完整回复',
                            helperText:
                                widget.replyInbox?.hasPendingReply ?? false
                                    ? '收到的内容已填入；检查后再手动导入。'
                                    : null,
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          key: const Key('import-agent-reply'),
                          onPressed: busy ? null : _importAgentReply,
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('识别并导入建议'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          key: const Key('close-agent-session'),
                          onPressed: busy || !controller.canCloseSession
                              ? null
                              : _closeAgentSession,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('结束协作并切换助手'),
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
                            color: Theme.of(context).colorScheme.outlineVariant,
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
                        onPressed: busy ? null : controller.exportContext,
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
                          : () => controller.importProposal(_proposal.text),
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
                      Text('Review ID: $id (${controller.reviewState})'),
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
              const SizedBox(height: 16),
              if (controller.reviewId != null) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  '策略复盘（${_reviewStateText(controller.reviewState)}）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(controller.reviewSummary ?? '无复盘摘要'),
                        if (controller.reviewConclusion case final conclusion?)
                          Text('结论：${_reviewConclusionText(conclusion)}'),
                      ],
                    ),
                  ),
                ),
                if (controller.hasPendingReview) ...<Widget>[
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton(
                          key: const Key('accept-review'),
                          onPressed: busy
                              ? null
                              : () => controller.decideReview(
                                    ReviewDecision.accept,
                                  ),
                          child: const Text('接受复盘'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('reject-review'),
                          onPressed: busy
                              ? null
                              : () => controller.decideReview(
                                    ReviewDecision.reject,
                                  ),
                          child: const Text('拒绝复盘'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
              if (controller.hasPendingProposal) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  '待你确认',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(controller.proposalTitle ?? '未命名策略'),
                        if (controller.proposalRationale case final rationale?)
                          Text('修改理由：$rationale'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        key: const Key('accept-proposal'),
                        onPressed: busy
                            ? null
                            : () => controller.decideProposal(
                                  ProposalDecision.accept,
                                ),
                        child: const Text('接受策略'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('reject-proposal'),
                        onPressed: busy
                            ? null
                            : () => controller.decideProposal(
                                  ProposalDecision.reject,
                                ),
                        child: const Text('拒绝'),
                      ),
                    ),
                  ],
                ),
              ],
              if (controller.canActivate) ...<Widget>[
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('activate-strategy'),
                  onPressed: busy ? null : controller.activateStrategy,
                  child: const Text('激活并开始执行'),
                ),
              ],
              if (controller.canRecordExecution) ...<Widget>[
                const SizedBox(height: 20),
                const Text('选择你实际完成的行动，再记录执行情况。'),
                const SizedBox(height: 8),
                if (controller.strategyActions.isEmpty)
                  const Text(
                    '当前策略没有可识别的行动，暂时无法安全记录执行。'
                    '请重新导入一份包含行动内容的策略建议。',
                  )
                else ...<Widget>[
                  if (controller.strategyActions.length == 1)
                    Text(
                      '本次记录：${controller.strategyActions.single.instruction}',
                      key: const Key('selected-execution-action'),
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: '你完成了哪一步？',
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: const Key('execution-action-picker'),
                          value: selectedActionId,
                          hint: const Text('请选择实际完成的行动'),
                          isExpanded: true,
                          items: controller.strategyActions
                              .map(
                                (action) => DropdownMenuItem<String>(
                                  value: action.id,
                                  child: Text(
                                    action.instruction,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: busy
                              ? null
                              : (actionId) {
                                  if (actionId != null) {
                                    controller.selectAction(actionId);
                                  }
                                },
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.tonal(
                    key: const Key('record-execution'),
                    onPressed: busy || selectedActionId == null
                        ? null
                        : () => controller.recordExecution(
                              actionId: selectedActionId,
                              executionStatus: ExecutionStatus.completed,
                            ),
                    child: const Text('记录行动已完成'),
                  ),
                ],
              ],
              if (controller.canRecordOutcome) ...<Widget>[
                const SizedBox(height: 20),
                TextField(
                  key: const Key('outcome-input'),
                  controller: _outcome,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '实际结果或观察',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('record-outcome'),
                  onPressed: busy
                      ? null
                      : () => controller.recordOutcome(
                            observation: _outcome.text,
                            valence: OutcomeValence.mixed,
                          ),
                  child: const Text('保存真实反馈'),
                ),
              ],
            ],
          );
        },
      );
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

String _reviewStateText(String? state) => switch (state) {
      'draft' => '等待你确认',
      'accepted' => '已接受',
      'rejected' => '已拒绝',
      _ => '处理中',
    };

String _reviewConclusionText(String conclusion) => switch (conclusion) {
      'effective' => '有效',
      'ineffective' => '效果不佳',
      'inconclusive' => '暂时无法判断',
      'executionInsufficient' => '执行证据不足',
      _ => conclusion,
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
      _ => '操作未完成，请检查当前步骤后重试。',
    };
