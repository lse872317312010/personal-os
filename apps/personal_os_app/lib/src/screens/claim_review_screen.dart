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
        Text('Claim 审阅', style: Theme.of(context).textTheme.headlineSmall),
        const Text('模型结论只是 proposed；接受、修订、拒绝动作将在后续端口接入。'),
        for (final claim in claims)
          Card(child: ListTile(title: Text(claim), subtitle: const Text('待人工审阅'))),
        if (claims.isEmpty) const Text('尚无分析结果。'),
      ],
    );
  }
}
