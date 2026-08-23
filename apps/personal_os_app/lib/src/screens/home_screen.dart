import 'package:flutter/material.dart';

import '../composition/app_composition.dart';
import '../controller/app_controller.dart';
import '../navigation/app_destination.dart';

/// Palette of chip colours keyed by [CompositionMode.chipColorId]. Keeping
/// them in one place means future design iterations or a light/dark mode
/// switch update a single source.
List<({Color background, Color foreground})> get _modeChipColors =>
    const <({Color background, Color foreground})>[
      (background: Color(0xfffff1c2), foreground: Color(0xff8a5d00)), // demo
      (background: Color(0xffc8f1e9), foreground: Color(0xff006a5c)), // dev
      (background: Color(0xffdce4ff), foreground: Color(0xff283593)), // encrypted
    ];

final class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.controller,
    required this.composition,
    super.key,
  });

  final AppController controller;
  final AppComposition composition;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final List<({Color background, Color foreground})> swatches = _modeChipColors;
    final int colorId = composition.mode.chipColorId.clamp(0, swatches.length - 1);
    final ({Color background, Color foreground}) chip = swatches[colorId];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '今天，从一个小改变开始',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: composition.modeDescription,
              child: InputChip(
                key: const Key('storage-mode-chip'),
                avatar: Icon(
                  composition.mode.storageEncrypted
                      ? Icons.enhanced_encryption
                      : composition.mode.restartsPreserveData
                          ? Icons.save_alt_rounded
                          : Icons.tips_and_updates_outlined,
                  size: 16,
                  color: chip.foreground,
                ),
                label: Text(
                  composition.modeLabel,
                  style: TextStyle(color: chip.foreground, fontWeight: FontWeight.w600),
                ),
                backgroundColor: chip.background,
                side: BorderSide(color: chip.foreground.withOpacity(0.15)),
                onDeleted: null, // non-interactive; only a visual indicator
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          composition.mode.restartsPreserveData
              ? 'MVP 使用合成示例生成建议，不调用真实 AI，也不会上传照片。'
              ' 关闭并重启应用后，任务和复盘记录仍会保留。'
              : 'MVP 使用合成示例生成建议，不调用真实 AI，也不会上传照片。'
                  ' 演示模式数据仅存在于内存，杀进程或冷启动后会清空。',
        ),
        if (composition.databasePath != null) ...<Widget>[
          const SizedBox(height: 8),
          SelectionArea(
            child: Text(
              '数据库位置：${composition.databasePath}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('外貌改善闭环 · 离线体验'),
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
}
