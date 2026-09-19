import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';
import '../controller/encrypted_event_backup_controller.dart';
import '../navigation/app_destination.dart';
import 'observation_history_card.dart';

final class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.controller,
    required this.backupController,
    required this.mode,
    super.key,
  });

  final AppController controller;
  final EncryptedEventBackupController backupController;
  final AppExperienceMode mode;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('今天，从一个小改变开始', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            mode == AppExperienceMode.syntheticDemo
                ? 'MVP 使用合成示例生成建议，不调用真实 AI，也不会上传照片。'
                : '建议来自安全会话；UI 不接触原始资料，也不调用未接入的认证或存储实现。',
          ),
          const SizedBox(height: 16),
          ObservationHistoryCard(controller: controller, mode: mode),
          if (mode == AppExperienceMode.secureVault) ...<Widget>[
            const SizedBox(height: 16),
            _EncryptedBackupCard(controller: backupController),
          ],
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    mode == AppExperienceMode.syntheticDemo
                        ? '外貌改善闭环 · 合成离线体验'
                        : '外貌改善闭环 · 安全会话',
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: controller.completedStep / 5),
                  const SizedBox(height: 8),
                  Text('进度 ${controller.completedStep}/5'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => controller.navigate(AppDestination.capture),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: Text(controller.result == null ? '开始首次分析' : '重新分析'),
          ),
        ],
      );
}

final class _EncryptedBackupCard extends StatelessWidget {
  const _EncryptedBackupCard({required this.controller});

  final EncryptedEventBackupController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '加密备份与恢复',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  '事件历史先在原生层用口令加密，再交给系统文件选择器。口令不会进入 Flutter，也不会写入磁盘。',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: <Widget>[
                    OutlinedButton.icon(
                      key: const Key('export-encrypted-backup'),
                      onPressed: controller.running || !controller.available
                          ? null
                          : controller.exportBackup,
                      icon: const Icon(Icons.save_alt),
                      label: const Text('导出加密备份'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('restore-encrypted-backup'),
                      onPressed: controller.running || !controller.available
                          ? null
                          : controller.restoreBackup,
                      icon: const Icon(Icons.restore),
                      label: const Text('恢复备份'),
                    ),
                  ],
                ),
                if (controller.status != EncryptedBackupStatus.idle) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    _backupStatusText(controller),
                    key: const Key('encrypted-backup-status'),
                    style: TextStyle(
                      color: controller.status == EncryptedBackupStatus.failed
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  '恢复会先验证密文和归档，再以单个事务写入；冲突时不会留下部分数据。恢复完成后需重新解锁。',
                ),
              ],
            ),
          ),
        ),
      );
}

String _backupStatusText(EncryptedEventBackupController controller) {
  final count = controller.lastEventCount;
  return switch (controller.status) {
    EncryptedBackupStatus.running =>
      controller.action == EncryptedBackupAction.export
          ? '正在准备加密备份…'
          : '正在验证并恢复备份…',
    EncryptedBackupStatus.succeeded =>
      controller.action == EncryptedBackupAction.export
          ? '已导出 ${count ?? 0} 条事件。'
          : '已恢复 ${count ?? 0} 条事件。',
    EncryptedBackupStatus.cancelled => '操作已取消。',
    EncryptedBackupStatus.failed => _backupErrorText(controller.errorCode),
    EncryptedBackupStatus.idle => '',
  };
}

String _backupErrorText(String? code) => switch (code) {
      'backup.empty' => '当前没有可备份的事件。',
      'backup.authentication_failed' => '口令错误或备份已损坏。',
      'backup.unsupported_format' => '不支持此备份格式。',
      'backup.too_large' => '备份文件超出当前大小限制。',
      'backup.export_denied' => '事件策略不允许导出此历史。',
      'backup.restore_conflict' => '备份与现有历史冲突，未写入任何数据。',
      'backup.archive_invalid' => '备份归档校验失败，未写入任何数据。',
      'backup.vault_locked' => 'Vault 已锁定，请重新解锁后再试。',
      'backup.busy' => '另一项备份操作正在进行。',
      'backup.io_failed' => '系统文件读写失败。',
      _ => '当前无法完成加密备份操作。',
    };
