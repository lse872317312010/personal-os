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
                      onPressed: controller.vaultUnlocking
                          ? null
                          : controller.unlockVault,
                      icon: controller.vaultUnlocking
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open),
                      label: Text(
                        controller.vaultUnlocking
                            ? '正在打开安全保险库…'
                            : mode == AppExperienceMode.syntheticDemo
                                ? '进入合成体验'
                                : '解锁安全保险库',
                      ),
                    ),
                    if (controller.errorCode != null) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        _unlockErrorText(controller.errorCode!),
                        key: const Key('unlock-error'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

String _unlockErrorText(String code) => switch (code) {
      'security.unlock_cancelled' => '已取消解锁。',
      'security.unlock_denied' => '系统未授权解锁，请重试。',
      'security.unlock_unavailable' => '当前无法使用系统解锁。',
      'security.unlock_expired' => '解锁授权已过期，请重试。',
      'security.provider_unavailable' => '当前平台的安全服务尚未配置。',
      'security.vault_locked' => '安全保险库会话无效，请重试。',
      'security.vault_library_unavailable' => '加密数据库原生库加载失败（vault_library）。',
      'security.vault_path_unavailable' => '应用私有数据库目录不可用（vault_path）。',
      'security.vault_database_open_failed' => '加密数据库打开失败（vault_open）。',
      'security.vault_cipher_verification_failed' =>
        'SQLCipher 提供程序校验失败（vault_cipher）。',
      'security.vault_foreign_keys_unavailable' =>
        '数据库完整性约束启用失败（vault_foreign_keys）。',
      'security.vault_configuration_failed' => '数据库安全配置失败（vault_config）。',
      'security.vault_journal_invalid' => '数据库事务日志校验失败（vault_journal）。',
      _ => '安全保险库打开失败（$code）。',
    };
