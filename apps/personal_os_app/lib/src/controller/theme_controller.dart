import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Volatile, process-lifetime theme preference (ADR-0009 in-memory demo mode).
///
/// Production builds will replace this with a persisted preference sourced
/// from the encrypted vault; widgets must continue to consume only the
/// [ThemeMode] value via [AnimatedBuilder] so the storage swap is invisible.
final class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.system})
      : _mode = initial;

  ThemeMode _mode;

  ThemeMode get mode => _mode;

  /// Updates the active [ThemeMode]. Calling with the current value is a
  /// no-op and does not notify listeners.
  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}
