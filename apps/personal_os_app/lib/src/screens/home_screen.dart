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
          Text('今天从一次观察开始',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text('照片仅通过 Vault blob reference 传递；界面层不接触原始字节。'),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => controller.navigate(AppDestination.capture),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('记录外貌观察'),
          ),
        ],
      );
}
