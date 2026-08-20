import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

final class ClaimReviewScreen extends StatelessWidget {
  const ClaimReviewScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final claims = controller.result?.claimIds ?? const <String>[];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('你的示例建议', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('以下内容来自固定合成样例，不是对你的真实外貌判断。请由你决定是否采用。'),
        const SizedBox(height: 12),
        for (var index = 0; index < claims.length; index++)
          Card(
            child: ListTile(
              leading: const Icon(Icons.lightbulb_outline),
              title: Text(index == 0 ? '先改善拍摄与观察条件' : '可选改善建议'),
              subtitle: const Text('保持自然光、正面视角和无滤镜，再进行周期性对比。'),
            ),
          ),
        if (claims.isEmpty) const Text('尚无结果，请先完成一次离线示例分析。'),
        if (claims.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('accept-suggestions'),
            onPressed: controller.continueFromClaims,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('采用建议，查看行动计划'),
          ),
        ],
      ],
    );
  }
}
