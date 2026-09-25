import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import '../composition/app_composition.dart';
import '../controller/strategy_loop_controller.dart';

final class StrategyLoopScreen extends StatefulWidget {
  const StrategyLoopScreen({
    required this.controller,
    required this.mode,
    super.key,
  });

  final StrategyLoopController controller;
  final AppExperienceMode mode;

  @override
  State<StrategyLoopScreen> createState() => _StrategyLoopScreenState();
}

final class _StrategyLoopScreenState extends State<StrategyLoopScreen> {
  final _agentId = TextEditingController(text: 'offline-harness');
  final _review = TextEditingController();
  final _proposal = TextEditingController();
  final _actionId = TextEditingController(text: 'action-1');
  final _outcome = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(widget.controller.bootstrap());
  }

  @override
  void dispose() {
    _agentId.dispose();
    _review.dispose();
    _proposal.dispose();
    _actionId.dispose();
    _outcome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final busy = controller.status == StrategyUiStatus.running;
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
                        '外部 Agent 只提交建议，接受、执行和结果始终由你确认。'
                    : '手机保存资产、策略和真实反馈；外部 Agent 只提交建议，'
                        '接受、执行和结果始终由你确认。',
              ),
              const SizedBox(height: 16),
              _StatusCard(controller: controller),
              const SizedBox(height: 16),
              TextField(
                key: const Key('agent-id-input'),
                controller: _agentId,
                enabled: !busy && !controller.hasSession,
                decoration: const InputDecoration(
                  labelText: 'Agent / Harness ID',
                  hintText: '例如 codex-cli、claude-code 或 my-harness',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                key: const Key('open-agent-session'),
                onPressed: busy || controller.hasSession
                    ? null
                    : () => controller.openOfflineSession(
                          agentId: _agentId.text,
                        ),
                icon: const Icon(Icons.link),
                label: const Text('创建离线 Agent 会话'),
              ),
              if (controller.sessionId case final sessionId?) ...<Widget>[
                const SizedBox(height: 8),
                SelectableText('Session ID: $sessionId'),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  key: const Key('export-context'),
                  onPressed: busy ? null : controller.exportContext,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('导出 Context Bundle'),
                ),
                if (controller.contextBundle case final bundle?) ...<Widget>[
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      key: const Key('copy-context-bundle'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: bundle));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Context Bundle 已复制')),
                        );
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('复制给外部 Agent'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                TextField(
                  key: const Key('review-bundle-input'),
                  controller: _review,
                  minLines: 5,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Review Bundle JSON（可选）',
                    hintText: '粘贴 Agent 对已有策略、执行和结果的结构化复盘',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  key: const Key('import-review'),
                  onPressed: busy
                      ? null
                      : () => controller.importReview(_review.text),
                  child: const Text('验证并导入待确认复盘'),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const Key('proposal-bundle-input'),
                  controller: _proposal,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(
                    labelText: 'Proposal Bundle JSON',
                    hintText: '粘贴外部 Agent 返回的 personal-os.mcp.v0 提案',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  key: const Key('import-proposal'),
                  onPressed: busy
                      ? null
                      : () => controller.importProposal(_proposal.text),
                  child: const Text('验证并导入待确认策略'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('close-agent-session'),
                  onPressed:
                      busy || !controller.canCloseSession
                          ? null
                          : controller.closeSession,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('结束会话并交给下一个 Harness'),
                ),
                if (!controller.canCloseSession &&
                    controller.strategyId != null)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('完成结果记录或拒绝策略后，才能切换 Harness。'),
                  ),
              ],

              if (controller.reviewId != null) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  '策略复盘（${controller.reviewState}）',
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
                          Text('结论：$conclusion'),
                        if (controller.reviewEvidenceRefs.isNotEmpty)
                          Text(
                            '证据：${controller.reviewEvidenceRefs.join(', ')}',
                          ),
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
                        if (controller.parentStrategyRef case final parent?)
                          Text('父策略：$parent'),
                        if (controller.proposalEvidenceRefs.isNotEmpty)
                          Text(
                            '引用：${controller.proposalEvidenceRefs.join(', ')}',
                          ),
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
                TextField(
                  key: const Key('action-id-input'),
                  controller: _actionId,
                  decoration: const InputDecoration(labelText: 'Action ID'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  key: const Key('record-execution'),
                  onPressed: busy
                      ? null
                      : () => controller.recordExecution(
                            actionId: _actionId.text,
                            executionStatus: ExecutionStatus.completed,
                          ),
                  child: const Text('记录为已完成'),
                ),
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
              Text('状态：${controller.strategyState ?? '尚未导入策略'}'),
              Text('Harness：${controller.agentId}'),
              if (controller.strategyId case final id?) Text('Strategy: $id'),
              if (controller.executionId case final id?) Text('Execution: $id'),
              if (controller.outcomeId case final id?) Text('Outcome: $id'),
              if (controller.reviewId case final id?)
                Text('Review: $id (${controller.reviewState})'),
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

String _strategyErrorText(String code) => switch (code) {
      'strategy.session_already_open' => '当前已有会话，请先结束当前会话。',
      'strategy.agent_id_invalid' => 'Agent / Harness ID 必须为 1–100 个字符。',
      'strategy.session_required' => '请先创建离线 Agent 会话。',
      'strategy.loop_must_finish_before_handoff' =>
        '请先记录本次行动的实际结果，再切换到其他 Harness。',
      'strategy.session_or_review_bundle_required' =>
        '请先创建会话，再粘贴 Review Bundle。',
      'strategy.pending_review_required' => '当前没有等待确认的复盘。',
      'strategy.session_or_bundle_required' =>
        '请先创建会话，再粘贴 Proposal Bundle。',
      'strategy.pending_proposal_required' => '当前没有等待确认的策略。',
      'strategy.accepted_strategy_required' => '请先确认策略，再激活执行。',
      'strategy.active_strategy_required' => '请先激活策略，再记录执行。',
      'strategy.action_required' => '请输入有效的 Action ID。',
      'strategy.execution_or_observation_required' =>
        '请先记录执行，并填写实际结果或观察。',
      'strategy.restore_ambiguous_open_sessions' =>
        '发现多个未完成的策略会话，无法安全恢复。',
      'strategy.restore_malformed_state' => '策略历史无法恢复，请检查本地记录。',
      'strategy.unexpected_failure' => '策略操作暂时无法完成，请稍后重试。',
      'invalid_request' || 'validation_failed' =>
        'Bundle 内容无效，请检查 JSON 格式和必填字段。',
      'unsupported_version' =>
        'Bundle 版本不受支持，请使用 personal-os.mcp.v0 格式。',
      'unpinned_reference' || 'strategy_loop.pinned_reference_required' =>
        'Bundle 引用缺少固定版本信息，请重新导出 Context Bundle。',
      'session_closed' => '会话已结束，请新建会话后再继续。',
      'access_denied' => '当前会话权限不足，请重新创建会话后重试。',
      'not_found' => 'Bundle 引用的数据不存在，请重新导出 Context Bundle。',
      'stale_reference' => 'Bundle 引用的状态已过期，请重新导出后再试。',
      'internal_error' => '策略服务暂时不可用，请稍后重试。',
      'strategy_loop.invalid_command' => '当前策略状态不允许此操作，请检查步骤顺序。',
      'strategy_loop.user_authority_required' => '此操作需要用户本人确认。',
      'strategy_loop.agent_authority_required' =>
        '请使用本次离线 Agent 会话提交建议。',
      'strategy_loop.outcome_authority_denied' => '实际结果只能由用户本人记录。',
      'strategy_loop.d4_forbidden' || 'feedback.d4_forbidden' =>
        '当前闭环不支持 D4 级敏感资料。',
      _ => '操作未完成，请检查当前步骤后重试。',
    };
