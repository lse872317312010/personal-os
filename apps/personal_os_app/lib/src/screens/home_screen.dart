import 'package:flutter/material.dart';

import '../controller/app_controller.dart';
import '../navigation/app_destination.dart';

final class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('今天，从一个小改变开始',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('MVP 使用合成示例生成建议，不调用真实 AI，也不会上传照片。'),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('外貌改善闭环 · 离线体验'),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: controller.completedStep / 5),
                  const SizedBox(height: 8),
                  Text('进度 ${controller.completedStep}/5'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => controller.navigate(AppDestination.capture),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(controller.result == null ? '开始首次分析' : '重新分析'),
          ),
        ],
      );
}
