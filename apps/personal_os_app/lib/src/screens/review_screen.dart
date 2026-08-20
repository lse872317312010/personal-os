import 'package:flutter/material.dart';
import 'package:personal_os_application/application.dart';

import '../controller/app_controller.dart';

final class ReviewScreen extends StatelessWidget {
  const ReviewScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('反馈与复盘', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('记录执行反馈、复测证据和计划修订，形成闭环。'),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('create-review'),
            onPressed:
                controller.reviewId == null ? controller.createReview : null,
            child: const Text('新增复盘'),
          ),
          if (controller.reviewId case final id?) ...<Widget>[
            Text('复盘：$id；状态：${controller.reviewState}'),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton(
                  key: const Key('accept-review'),
                  onPressed: controller.reviewState == 'draft'
                      ? () => controller.decideReview(ReviewDecision.accept)
                      : null,
                  child: const Text('接受'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('reject-review'),
                  onPressed: controller.reviewState == 'draft'
                      ? () => controller.decideReview(ReviewDecision.reject)
                      : null,
                  child: const Text('拒绝'),
                ),
              ],
            ),
          ],
          if (controller.feedbackCode case final code?)
            Text(
              '${controller.feedbackSubmission.name}: $code',
              key: const Key('review-feedback-code'),
            ),
        ],
      );
}
