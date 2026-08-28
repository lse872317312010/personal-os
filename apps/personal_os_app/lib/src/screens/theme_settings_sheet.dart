import 'package:flutter/material.dart';

import '../controller/theme_controller.dart';

class ThemeSettingsSheet extends StatelessWidget {
  const ThemeSettingsSheet({required this.controller, super.key});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '主题',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              RadioGroup<ThemeMode>(
                groupValue: controller.mode,
                onChanged: (value) {
                  if (value == null) return;
                  controller.setMode(value);
                  Navigator.of(context).maybePop();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final mode in ThemeMode.values)
                      RadioListTile<ThemeMode>(
                        key: Key('theme-option-${mode.name}'),
                        value: mode,
                        selected: mode == controller.mode,
                        title: Text(_labelFor(mode)),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  static String _labelFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => '跟随系统',
        ThemeMode.light => '浅色',
        ThemeMode.dark => '深色',
      };
}

Future<void> showThemeSettingsSheet(
  BuildContext context, {
  required ThemeController controller,
}) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ThemeSettingsSheet(controller: controller),
    );
