import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

final class TaskScreen extends StatelessWidget {
  const TaskScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final tasks = controller.result?.taskIds ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        for (final task in tasks)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('拍一张标准对比照'),
                  const SizedBox(height: 4),
                  Text('状态：${_taskStateLabel(controller.taskState(task))}'),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton(
                          key: Key('skip-task-$task'),
                          onPressed: controller.planStarted &&
                                  controller.taskState(task) == 'planned'
                              ? () => controller.skipTask(task)
                              : null,
                          child: const Text('跳过'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          key: Key('complete-task-$task'),
                          onPressed: controller.planStarted &&
                                  controller.taskState(task) == 'planned'
                              ? () => controller.completeTask(task)
                              : null,
                          child: const Text('完成'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (tasks.isEmpty) const Text('尚无任务。'),
        if (tasks.isNotEmpty && !controller.planStarted)
          const Text('请先在分析流程中确认并选择行动计划。'),
        if (controller.feedbackCode case final code?) ...<Widget>[
          Text(_feedbackLabel(code),
              key: const Key('task-feedback-message')),
        ],
      ],
    );
  }
}

String _taskStateLabel(String state) => switch (state) {
      'completed' => '已完成',
      'skipped' => '已跳过',
      _ => '待行动',
    };

String _feedbackLabel(String code) => switch (code) {
      'task_completed' => '已记录完成，即将进入复盘。',
      'task_skipped' => '已记录跳过，即将进入复盘。',
      'plan_not_started' => '请先确认行动计划。',
      _ => '操作未完成，请稍后重试。',
    };
