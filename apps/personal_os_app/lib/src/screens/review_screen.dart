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
          Text(controller.hasFinishedTask
              ? '行动已记录。现在用一次简短复盘结束闭环。'
              : '完成或跳过一个行动后，再回来复盘。'),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('create-review'),
            onPressed: controller.reviewId == null && controller.hasFinishedTask
                ? controller.createReview
                : null,
            child: const Text('生成本次复盘'),
          ),
          if (controller.reviewId != null) ...<Widget>[
            Text('本次复盘 · ${_reviewStateLabel(controller.reviewState)}'),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                FilledButton(
                  key: const Key('accept-review'),
                  onPressed: controller.reviewState == 'draft'
                      ? () => controller.decideReview(ReviewDecision.accept)
                      : null,
                  child: const Text('确认有效'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('reject-review'),
                  onPressed: controller.reviewState == 'draft'
                      ? () => controller.decideReview(ReviewDecision.reject)
                      : null,
                  child: const Text('标记无效'),
                ),
              ],
            ),
          ],
          if (controller.feedbackCode case final code?) ...<Widget>[
            Text('${controller.feedbackSubmission.name}: $code',
                key: const Key('review-feedback-code')),
            if (code == 'review_accepted' || code == 'review_rejected')
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('闭环完成。你的选择已记录在本地事件流中。'),
              ),
          ],
          if (!controller.hasFinishedTask)
            const Text('先完成或跳过一个行动，才能生成复盘。'),
        ],
      );
}

String _reviewStateLabel(String? state) => switch (state) {
      'accepted' => '有效',
      'rejected' => '无效',
      _ => '待确认',
    };
