import 'package:flutter/material.dart';

import '../controller/app_controller.dart';

/// SettingsScreen stub (Wave 20e D).
///
/// This is a deliberately *static* UI — no actions are wired yet. It
/// surfaces:
/// - the current composition mode + vault state (read-only)
/// - the ADR-0009 §2 volatile-demo warning (mirrors home_screen banner)
/// - a roadmap of pending settings (theme, language, export, delete)
///   so the user knows what is coming in subsequent waves.
///
/// Action wiring is deferred to Wave 21 (theme/language) and Wave 19b/19c
/// (export/delete — already shipped but not yet surfaced here).
final class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('设置', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          _CompositionCard(controller: controller),
          const SizedBox(height: 16),
          _VolatileDemoCard(),
          const SizedBox(height: 16),
          _PendingFeaturesCard(),
          const SizedBox(height: 16),
          _AboutCard(),
        ],
      );
}

final class _CompositionCard extends StatelessWidget {
  const _CompositionCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.memory_outlined),
                  const SizedBox(width: 8),
                  Text('运行模式',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Composition Mode: inMemoryDemo (ADR-0008)'),
              const SizedBox(height: 4),
              Text('Vault 状态: ${controller.vaultUnlocked ? "已解锁" : "已锁定"}'),
              const SizedBox(height: 4),
              const Text('数据存储: 进程内存（重启即丢失）'),
            ],
          ),
        ),
      );
}

final class _VolatileDemoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.warning_amber_outlined,
                      color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('易失·演示数据 (ADR-0009 §2)',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                '当前所有数据仅存在于本次 App 运行的内存中。重启 App 或清除'
                '应用数据后，所有照片、观察、计划、任务、复盘都将永久丢失。'
                '请勿在此版本存放真实数据。',
              ),
            ],
          ),
        ),
      );
}

final class _PendingFeaturesCard extends StatelessWidget {
  static const _pending = <_PendingFeature>[
    _PendingFeature(
      icon: Icons.palette_outlined,
      title: '主题切换',
      wave: 'Wave 21a',
      status: _PendingStatus.planned,
    ),
    _PendingFeature(
      icon: Icons.language_outlined,
      title: '语言切换',
      wave: 'Wave 21b',
      status: _PendingStatus.planned,
    ),
    _PendingFeature(
      icon: Icons.file_download_outlined,
      title: '导出 Vault',
      wave: 'Wave 19b',
      status: _PendingStatus.shipped,
    ),
    _PendingFeature(
      icon: Icons.delete_outline,
      title: '删除 Vault',
      wave: 'Wave 19c',
      status: _PendingStatus.shipped,
    ),
    _PendingFeature(
      icon: Icons.sync_outlined,
      title: '跨设备同步',
      wave: 'ADR-0012',
      status: _PendingStatus.draft,
    ),
  ];

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.build_outlined),
                  const SizedBox(width: 8),
                  Text('功能路线图',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _pending.length; i++) ...<Widget>[
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_pending[i].icon),
                  title: Text(_pending[i].title),
                  subtitle: Text(
                      '${_pending[i].wave} · ${_pending[i].status.label}'),
                  trailing: _PendingStatusChip(status: _pending[i].status),
                ),
                if (i < _pending.length - 1)
                  const Divider(height: 1, indent: 16),
              ],
            ],
          ),
        ),
      );
}

final class _PendingFeature {
  const _PendingFeature({
    required this.icon,
    required this.title,
    required this.wave,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String wave;
  final _PendingStatus status;
}

enum _PendingStatus { planned, draft, shipped }

extension _PendingStatusLabel on _PendingStatus {
  String get label => switch (this) {
        _PendingStatus.planned => '规划中',
        _PendingStatus.draft => '草案',
        _PendingStatus.shipped => '已上线（其他入口）',
      };
}

final class _PendingStatusChip extends StatelessWidget {
  const _PendingStatusChip({required this.status});

  final _PendingStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      _PendingStatus.planned => (Colors.grey, Icons.hourglass_top_outlined),
      _PendingStatus.draft => (Colors.blueGrey, Icons.edit_note_outlined),
      _PendingStatus.shipped => (Colors.green, Icons.check_circle_outline),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide.none,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(status.label,
              style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}

final class _AboutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 8),
                  Text('关于', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Personal OS · Android-first MVP'),
              const SizedBox(height: 4),
              const Text('Version: 0.1.0 (stub)'),
              const SizedBox(height: 4),
              const Text('Build: debug'),
              const SizedBox(height: 8),
              const Text(
                '面向个人的隐私优先 OS。当前版本仅用于演示外观改善闭环，'
                '不调用真实 AI，不上传云端，不持久化数据。',
              ),
            ],
          ),
        ),
      );
}
