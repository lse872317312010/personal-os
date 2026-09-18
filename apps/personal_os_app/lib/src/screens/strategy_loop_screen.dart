import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import '../controller/strategy_loop_controller.dart';

final class StrategyLoopScreen extends StatefulWidget {
  const StrategyLoopScreen({required this.controller, super.key});

  final StrategyLoopController controller;

  @override
  State<StrategyLoopScreen> createState() => _StrategyLoopScreenState();
}

final class _StrategyLoopScreenState extends State<StrategyLoopScreen> {
  final _agentId = TextEditingController(text: 'offline-harness');
  final _proposal = TextEditingController();
  final _actionId = TextEditingController(text: 'action-1');
  final _outcome = TextEditingController();

  @override
  void dispose() {
    _agentId.dispose();
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
              const Text(
                '手机保存资产、策略和真实反馈；外部 Agent 只提交建议，'
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
              ],
              if (controller.hasPendingProposal) ...<Widget>[
                const SizedBox(height: 20),
                Text(
                  '待你确认',
                  style: Theme.of(context).textTheme.titleMedium,
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
              if (controller.errorCode case final error?)
                Text(
                  error,
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
