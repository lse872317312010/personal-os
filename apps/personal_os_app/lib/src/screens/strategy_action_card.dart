import 'package:flutter/material.dart';
import 'package:personal_os_application/application.dart';
import 'package:personal_os_domain/domain.dart';

import '../controller/strategy_loop_controller.dart';

/// The plan and its next user action stay together, ahead of handoff tools.
final class StrategyActionCard extends StatelessWidget {
  const StrategyActionCard({
    required this.controller,
    this.onOpen,
    this.onStart,
    this.onReject,
    this.onRecord,
    this.onFeedback,
    this.onSaveOutcome,
    this.onAskAgent,
    this.onReview,
    this.outcome,
    this.interactionBlocked = false,
    super.key,
  });

  final StrategyLoopController controller;
  final VoidCallback? onOpen;
  final VoidCallback? onStart;
  final VoidCallback? onReject;
  final VoidCallback? onRecord;
  final ValueChanged<ExecutionStatus>? onFeedback;
  final VoidCallback? onSaveOutcome;
  final VoidCallback? onAskAgent;
  final ValueChanged<ReviewDecision>? onReview;
  final TextEditingController? outcome;
  final bool interactionBlocked;

  static const _ink = Color(0xff123c32);
  static const _accent = Color(0xffc2f5d7);

  @override
  Widget build(BuildContext context) {
    final busy =
        interactionBlocked || controller.status == StrategyUiStatus.running;
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
                  controller.executionId == null &&
                  onFeedback != null) ...<Widget>[
                const Text('这一步做得怎么样？'),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('feedback-note'),
                  controller: outcome,
                  enabled: !busy,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 4000,
                  style: const TextStyle(color: _ink),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: '补充结果或困难（可选）',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                _button(
                  key: const Key('feedback-completed'),
                  label: '完成了',
                  onPressed: busy
                      ? null
                      : () => onFeedback?.call(ExecutionStatus.completed),
                ),
                TextButton(
                  key: const Key('feedback-skipped'),
                  onPressed: busy
                      ? null
                      : () => onFeedback?.call(ExecutionStatus.skipped),
                  child: const Text('这次没做', style: TextStyle(color: _accent)),
                ),
                const Text('点击即保存反馈，并让 AI 自动复盘。',
                    style: TextStyle(color: _accent, fontSize: 13)),
              ] else if (controller.canRecordExecution &&
                  controller.executionId == null)
                _button(
                  key: const Key('record-execution'),
                  label: '这一步做完了',
                  onPressed: busy || action == null ? null : onRecord,
                )
              else if (controller.canRecordOutcome && !hasResult) ...<Widget>[
                const Text('执行已记录。补充结果或困难，再交给 AI。'),
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
              if (!compact &&
                  !reviewing &&
                  controller.parentStrategyRef != null)
                StrategyRevisionEvidence(
                  parentRef: controller.parentStrategyRef!,
                  rationale: controller.proposalRationale,
                  records: controller.contextRecords,
                ),
              if (!compact &&
                  controller.proposalRationale != null &&
                  (controller.parentStrategyRef == null || reviewing))
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
        ),
        onPressed: onPressed,
        child: Text(label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}

/// Show only evidence linked to this revision's pinned parent strategy.
final class StrategyRevisionEvidence extends StatelessWidget {
  const StrategyRevisionEvidence({
    required this.parentRef,
    required this.rationale,
    required this.records,
    super.key,
  });

  final String parentRef;
  final String? rationale;
  final List<Map<String, Object?>> records;

  @override
  Widget build(BuildContext context) {
    final matches = records.where((record) {
      final data = record['data'] as Map?;
      return (record['ref'] as Map?)?['type'] == 'review' &&
          data?['state'] == 'accepted' &&
          _evidenceRef(data?['strategy_ref']) == parentRef;
    }).toList();
    final review = matches.length == 1 ? matches.single['data'] as Map : null;
    final changes = (review?['change'] as List? ?? const <Object?>[])
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty);
    final refs = (review?['outcome_refs'] as List? ?? const <Object?>[])
        .map(_evidenceRef)
        .whereType<String>()
        .toSet();
    final outcomes = records.where((record) =>
        (record['ref'] as Map?)?['type'] == 'outcome' &&
        refs.contains(_evidenceRef(record['ref'])));
    final observations = outcomes
        .map((record) => (record['data'] as Map?)?['observation'])
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('strategy-revision-evidence'),
        tilePadding: EdgeInsets.zero,
        textColor: Colors.white,
        collapsedTextColor: Colors.white,
        iconColor: Colors.white,
        collapsedIconColor: Colors.white,
        title: const Text('这轮为什么调整'),
        subtitle: Text(review == null ? '上一轮依据暂不可唯一定位' : '依据你已接受的上一轮复盘'),
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (rationale?.trim().isNotEmpty == true) ...<Widget>[
                  const Text('AI 给出的本轮理由'),
                  Text(rationale!),
                  const SizedBox(height: 12),
                ],
                if (review == null)
                  const Text('未找到唯一匹配的已接受复盘，暂不展示其他轮次的反馈。')
                else ...<Widget>[
                  const Text('上一轮已接受的 AI 复盘'),
                  if (review['summary'] is String)
                    Text(review['summary'] as String),
                  for (final change in changes) Text('建议调整：$change'),
                  const SizedBox(height: 12),
                  const Text('该复盘引用的实际反馈'),
                  for (final observation in observations) Text(observation),
                  if (observations.length != refs.length || refs.isEmpty)
                    const Text('部分结果证据暂不可读取；可在行动历史中核对。'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String? _evidenceRef(Object? value) {
  if (value is! Map ||
      value['type'] is! String ||
      value['id'] is! String ||
      value['revision'] is! int) {
    return null;
  }
  return '${value['type']}:${value['id']}@${value['revision']}';
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
