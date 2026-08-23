import 'package:flutter/material.dart';

import '../controller/theme_controller.dart';

/// Modal bottom sheet exposing the three supported [ThemeMode] options.
///
/// The sheet is intentionally small and self-contained so it can ship on
/// `main` without waiting for the full Settings screen (PR #18). When that
/// screen merges, this sheet can be embedded as a row or replaced by a
/// dedicated settings tile.
class ThemeSettingsSheet extends StatelessWidget {
  const ThemeSettingsSheet({required this.controller, super.key});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text(
                _title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final mode in const <ThemeMode>[
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ])
              RadioListTile<ThemeMode>(
                key: Key('theme-option-${mode.name}'),
                value: mode,
                groupValue: controller.mode,
                onChanged: (value) {
                  if (value == null) return;
                  controller.setMode(value);
                  Navigator.of(context).maybePop();
                },
                title: Text(_labelFor(mode)),
                subtitle: Text(_hintFor(mode)),
              ),
          ],
        ),
      ),
    );
  }

  static const String _title = '主题';
  static const Map<ThemeMode, String> _labels = <ThemeMode, String>{
    ThemeMode.system: '跟随系统',
    ThemeMode.light: '浅色',
    ThemeMode.dark: '深色',
  };
  static const Map<ThemeMode, String> _hints = <ThemeMode, String>{
    ThemeMode.system: '使用操作系统的浅色或深色设置',
    ThemeMode.light: '始终使用浅色主题',
    ThemeMode.dark: '始终使用深色主题',
  };

  static String _labelFor(ThemeMode mode) => _labels[mode]!;
  static String _hintFor(ThemeMode mode) => _hints[mode]!;
}

/// Opens [ThemeSettingsSheet] as a modal bottom sheet.
Future<void> showThemeSettingsSheet(
  BuildContext context, {
  required ThemeController controller,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ThemeSettingsSheet(controller: controller),
    );
