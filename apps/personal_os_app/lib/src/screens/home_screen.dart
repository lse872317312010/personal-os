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

/// HomeScreen surfaces the ADR-0009 §2 "易失 · 演示" banner whenever the
/// active [CompositionMode] is process-bound (i.e. `demo`), and gates the
/// analysis CTA behind a one-time confirmation dialog the first time the
/// user tries to capture data in that mode.
///
/// The acknowledgement bit lives on [AppController] (`volatileDemoAcknowledged`)
/// rather than in `State` so that it survives HomeScreen ↔ CaptureScreen
/// reconciliation. AppController is constructed once per process via
/// AppComposition, which exactly matches the "session-scoped" requirement
/// of ADR-0009: cold start resets the bit because the process is gone.
class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.controller,
    required this.composition,
    super.key,
  });

  final AppController controller;
  final AppComposition composition;

  bool get _isVolatile => !composition.mode.restartsPreserveData;
  bool get _requiresAcknowledgement =>
      _isVolatile && !controller.volatileDemoAcknowledged;

  Future<void> _onStartAnalysis(BuildContext context) async {
    if (_requiresAcknowledgement) {
      final bool accepted = await _showVolatileDemoDialog(context);
      if (!accepted) return;
      controller.markVolatileDemoAcknowledged();
    }
    controller.navigate(AppDestination.capture);
  }

  Future<bool> _showVolatileDemoDialog(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const Key('volatile-demo-dialog'),
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('演示模式：数据易失'),
        content: const Text(
          '你正在演示模式下运行。'
          '关闭应用或杀进程后，所有照片、分析结果与任务都会消失。'
          '此模式仅用于 UI 走查，不应保存任何真实数据。\n\n'
          '是否继续？',
        ),
        actions: <Widget>[
          TextButton(
            key: const Key('volatile-demo-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('返回'),
          ),
          FilledButton(
            key: const Key('volatile-demo-accept'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续演示'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

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
        if (_isVolatile) ...<Widget>[
          const SizedBox(height: 12),
          _VolatileDemoBanner(acknowledged: controller.volatileDemoAcknowledged),
        ],
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
          key: const Key('start-analysis-cta'),
          onPressed: controller.vaultUnlocked
              ? () => _onStartAnalysis(context)
              : null,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: Text(controller.result == null ? '开始首次分析' : '重新分析'),
        ),
      ],
    );
  }
}

/// Inline banner surfacing ADR-0009 §2's "易失 · 演示" tag. The banner
/// stays visible even after acknowledgement — only its tone changes from
/// "warn" to "acknowledged" — so users never forget they are inside the
/// volatile mode for the rest of the session.
class _VolatileDemoBanner extends StatelessWidget {
  const _VolatileDemoBanner({required this.acknowledged});

  final bool acknowledged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final Color background = acknowledged
        ? colors.surfaceContainerHighest
        : colors.errorContainer;
    final Color foreground = acknowledged
        ? colors.onSurface
        : colors.onErrorContainer;
    final IconData icon = acknowledged
        ? Icons.check_circle_outline
        : Icons.warning_amber_rounded;
    final String label = acknowledged
        ? '易失 · 演示（已确认）'
        : '易失 · 演示';

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
