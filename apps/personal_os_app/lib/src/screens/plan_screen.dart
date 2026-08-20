import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

final class PlanScreen extends StatelessWidget {
  const PlanScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('一个可执行的小行动',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Text('1')),
              title: const Text('拍一张标准对比照'),
              subtitle: Text(controller.result == null
                  ? '请先完成示例分析'
                  : '今天 · 约 2 分钟 · 使用相同光线和角度'),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('start-plan'),
            onPressed: controller.result == null ? null : controller.startPlan,
            child: const Text('选择这个行动'),
          ),
        ],
      );
}
