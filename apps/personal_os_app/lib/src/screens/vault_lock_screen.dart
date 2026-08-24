import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';

final class VaultLockScreen extends StatelessWidget {
  const VaultLockScreen(
      {required this.controller, required this.mode, super.key});

  final AppController controller;
  final AppExperienceMode mode;

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
                    Text(
                      mode == AppExperienceMode.syntheticDemo
                          ? '当前为离线合成体验：数据只保存在本次运行的内存中，不上传云端。结果不代表真实 AI 分析。'
                          : '安全保险库当前已锁定。进入前需要可用的系统认证；应用不会使用明文或未加密存储。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      key: const Key('unlock-vault'),
                      onPressed: controller.unlockVault,
                      icon: const Icon(Icons.lock_open),
                      label: Text(
                        mode == AppExperienceMode.syntheticDemo
                            ? '进入合成体验'
                            : '解锁安全保险库',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
