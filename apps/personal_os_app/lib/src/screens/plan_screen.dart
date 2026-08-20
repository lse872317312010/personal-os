import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

final class PlanScreen extends StatelessWidget {
  const PlanScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: ListTile(
          leading: const Icon(Icons.route_outlined),
          title: const Text('外貌改善行动计划'),
          subtitle: Text(controller.result == null
              ? '先完成一次分析并审阅 Claim'
              : '计划 ${controller.result!.planId} · 待确认'),
        ),
      );
}
