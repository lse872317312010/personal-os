import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

final class VaultLockScreen extends StatelessWidget {
  const VaultLockScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.shield_outlined, size: 72),
                    const SizedBox(height: 20),
                    Text('我的 Personal OS',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    const Text(
                      '当前为离线 MVP：数据只保存在本次运行的本地内存中，不上传云端。尚未接入系统生物识别和硬件密钥。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('unlock-vault'),
                      onPressed: controller.unlockVault,
                      icon: const Icon(Icons.lock_open),
                      label: const Text('进入离线体验'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
