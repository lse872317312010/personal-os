import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';

final class ObservationHistoryCard extends StatelessWidget {
  const ObservationHistoryCard({
    required this.controller,
    required this.mode,
    super.key,
  });

  final AppController controller;
  final AppExperienceMode mode;

  @override
  Widget build(BuildContext context) {
    final latest = controller.latestObservation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('最近观察', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('已记录 ${controller.observationCount} 条观察'),
            if (latest == null) ...<Widget>[
              const SizedBox(height: 4),
              const Text('暂无已恢复的观察 metadata。'),
            ] else ...<Widget>[
              const SizedBox(height: 4),
              Text('时间：${_formatTime(latest.occurredAt)}'),
              Text('媒体类型：${latest.mediaType}'),
            ],
            if (mode == AppExperienceMode.syntheticDemo) ...<Widget>[
              const SizedBox(height: 8),
              const Text('合成体验记录不表示真实照片已导入。'),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
