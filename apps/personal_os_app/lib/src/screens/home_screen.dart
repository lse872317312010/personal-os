import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';
import '../navigation/app_destination.dart';
import 'observation_history_card.dart';

final class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.controller, required this.mode, super.key});

  final AppController controller;
  final AppExperienceMode mode;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('今天，从一个小改变开始',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            mode == AppExperienceMode.syntheticDemo
                ? 'MVP 使用合成示例生成建议，不调用真实 AI，也不会上传照片。'
                : '建议来自安全会话；UI 不接触原始资料，也不调用未接入的认证或存储实现。',
          ),
          const SizedBox(height: 16),
          ObservationHistoryCard(controller: controller, mode: mode),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mode == AppExperienceMode.syntheticDemo
                        ? '外貌改善闭环 · 合成离线体验'
                        : '外貌改善闭环 · 安全会话',
                  ),
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
