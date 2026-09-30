import 'package:flutter/material.dart';
import 'package:personal_os_application/application.dart';

import '../controller/strategy_loop_controller.dart';

/// The plan and its next user action stay together, ahead of handoff tools.
final class StrategyActionCard extends StatelessWidget {
  const StrategyActionCard({
    required this.controller,
    this.onOpen,
    this.onStart,
    this.onReject,
    this.onRecord,
    this.onSaveOutcome,
    this.onAskAgent,
    this.onReview,
    this.outcome,
    super.key,
  });

  final StrategyLoopController controller;
  final VoidCallback? onOpen;
  final VoidCallback? onStart;
  final VoidCallback? onReject;
  final VoidCallback? onRecord;
  final VoidCallback? onSaveOutcome;
  final VoidCallback? onAskAgent;
  final ValueChanged<ReviewDecision>? onReview;
  final TextEditingController? outcome;

  static const _ink = Color(0xff123c32);
  static const _accent = Color(0xffc2f5d7);

  @override
  Widget build(BuildContext context) {
    final busy = controller.status == StrategyUiStatus.running;
    final actions = controller.strategyActions;
    final action =
        controller.selectedAction ?? (actions.isEmpty ? null : actions.first);
    final compact = onOpen != null;
    final reviewing = controller.hasPendingReview && !compact;
    final hasResult = controller.outcomeId != null;
    final label = controller.hasPendingProposal
        ? 'AI 行动计划 · 等你确认'
        : reviewing
            ? 'AI 复盘 · 等你确认'
            : hasResult
                ? '本轮结果已记录'
                : '你现在要做的事';
    return Card(
      key: const Key('strategy-action-focus'),
      color: _ink,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                color: Colors.white,
                height: 1.5,
              ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.auto_awesome, color: _accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label, style: const TextStyle(color: _accent)),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                controller.proposalTitle ?? '你的行动计划',
                key: const Key('strategy-focus-title'),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 20),
              if (reviewing) ...<Widget>[
                Text(
                  controller.reviewSummary ?? '请查看这次复盘。',
                  style: const TextStyle(fontSize: 19),
                ),
                const SizedBox(height: 8),
                Text(
                  '判断：${_conclusion(controller.reviewConclusion)}',
                  style: const TextStyle(color: _accent),
                ),
              ] else if (action != null) ...<Widget>[
                if (actions.length > 1)
                  Text(
                    '当前行动 ${actions.indexOf(action) + 1} / ${actions.length}',
                    style: const TextStyle(color: _accent, fontSize: 13),
                  ),
                Text(
                  action.instruction,
                  key: const Key('strategy-focus-instruction'),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (action.successMeasure case final measure?) ...<Widget>[
                  const SizedBox(height: 10),
                  Text('做到什么算完成：$measure'),
                ],
                if (action.dueAt case final due?) ...<Widget>[
                  const SizedBox(height: 6),
                  Text('计划截止：${_date(due)}'),
                ],
              ] else
                const Text('这份计划没有可执行的行动，请让 AI 补充具体步骤。'),
              if (!compact && !reviewing && actions.length > 1) ...<Widget>[
                const SizedBox(height: 12),
                Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    key: const Key('strategy-all-actions'),
                    tilePadding: EdgeInsets.zero,
                    iconColor: _accent,
                    collapsedIconColor: _accent,
                    textColor: Colors.white,
                    collapsedTextColor: Colors.white,
                    title: Text('查看全部 ${actions.length} 个行动'),
                    children: <Widget>[
                      for (final step in actions)
                        ListTile(
                          key: Key('choose-strategy-action-${step.id}'),
                          contentPadding: EdgeInsets.zero,
                          textColor: Colors.white,
                          leading: CircleAvatar(
                            backgroundColor: _accent,
                            foregroundColor: _ink,
                            child: Text('${actions.indexOf(step) + 1}'),
                          ),
                          title: Text(step.instruction),
                          subtitle: step.successMeasure == null
                              ? null
                              : Text(
                                  step.successMeasure!,
                                  style: const TextStyle(color: _accent),
                                ),
                          trailing: step == action
                              ? const Icon(Icons.check_circle, color: _accent)
                              : null,
                          onTap: busy ||
                                  !controller.canRecordExecution ||
                                  controller.executionId != null
                              ? null
                              : () => controller.selectAction(step.id),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (compact)
                _button(
                  key: const Key('open-current-agent-action'),
                  label: controller.hasPendingProposal ? '查看并开始这个计划' : '继续我的行动',
                  onPressed: busy ? null : onOpen,
                )
              else if (reviewing) ...<Widget>[
                _button(
                  key: const Key('accept-review'),
                  label: '确认复盘，准备下一轮',
                  onPressed:
                      busy ? null : () => onReview?.call(ReviewDecision.accept),
                ),
                TextButton(
                  key: const Key('reject-review'),
                  onPressed:
                      busy ? null : () => onReview?.call(ReviewDecision.reject),
                  child:
                      const Text('这份复盘不合适', style: TextStyle(color: _accent)),
                ),
              ] else if (controller.hasPendingProposal) ...<Widget>[
                _button(
                  key: const Key('accept-proposal'),
                  label: '就按这个计划开始',
                  onPressed: busy || action == null ? null : onStart,
                ),
                TextButton(
                  key: const Key('reject-proposal'),
                  onPressed: busy ? null : onReject,
                  child: const Text('暂不采用', style: TextStyle(color: _accent)),
                ),
              ] else if (controller.canActivate)
                _button(
                  key: const Key('activate-strategy'),
                  label: '继续开始行动',
                  onPressed: busy ? null : onStart,
                )
              else if (controller.canRecordExecution &&
                  controller.executionId == null)
                _button(
                  key: const Key('record-execution'),
                  label: '这一步做完了',
                  onPressed: busy || action == null ? null : onRecord,
                )
              else if (controller.canRecordOutcome && !hasResult) ...<Widget>[
                const Text('已经记下完成。实际感觉如何？'),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('outcome-input'),
                  controller: outcome,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 4,
                  style: const TextStyle(color: _ink),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: '一句话记录结果、感受或困难',
                  ),
                ),
                const SizedBox(height: 12),
                _button(
                  key: const Key('record-outcome'),
                  label: '保存这次结果',
                  onPressed: busy ? null : onSaveOutcome,
                ),
              ] else if (hasResult) ...<Widget>[
                const Text('执行和结果已保存，可以交给 AI 复盘或调整下一轮。'),
                const SizedBox(height: 12),
                _button(
                  key: const Key('ask-agent-next'),
                  label: controller.reviewState == 'accepted'
                      ? '让 AI 调整下一轮'
                      : '让 AI 复盘这次行动',
                  onPressed: busy ? null : onAskAgent,
                ),
              ],
              if (!compact && controller.proposalRationale != null)
                Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    iconColor: _accent,
                    collapsedIconColor: _accent,
                    textColor: _accent,
                    collapsedTextColor: _accent,
                    title: const Text('为什么这样安排'),
                    children: <Widget>[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(controller.proposalRationale!),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button({
    required Key key,
    required String label,
    required VoidCallback? onPressed,
  }) =>
      FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          foregroundColor: _ink,
          backgroundColor: _accent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        onPressed: onPressed,
        child: Text(label),
      );
}

String _date(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  return date == null ? value : '${date.year}/${date.month}/${date.day}';
}

String _conclusion(String? value) => switch (value) {
      'effective' => '有效',
      'ineffective' => '需要调整',
      'executionInsufficient' => '还需要更多执行记录',
      _ => '还需要继续观察',
    };
