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
            child: ListTile(
              title: Text(task),
              subtitle: Text('状态：${controller.taskState(task)}'),
              trailing: Wrap(
                children: <Widget>[
                  TextButton(
                    key: Key('skip-task-$task'),
                    onPressed: controller.taskState(task) == 'planned'
                        ? () => controller.skipTask(task)
                        : null,
                    child: const Text('跳过'),
                  ),
                  FilledButton(
                    key: Key('complete-task-$task'),
                    onPressed: controller.taskState(task) == 'planned'
                        ? () => controller.completeTask(task)
                        : null,
                    child: const Text('完成'),
                  ),
                ],
              ),
            ),
          ),
        if (tasks.isEmpty) const Text('尚无任务。'),
        if (controller.feedbackCode case final code?)
          Text(
            '${controller.feedbackSubmission.name}: $code',
            key: const Key('task-feedback-code'),
          ),
      ],
    );
  }
}
