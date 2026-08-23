import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/composition/app_composition.dart';

/// Backwards-compatible demo launcher. Keep this as the default entry point
/// so `flutter run` with no explicit --target continues to work for quick
/// UI walkthroughs; use [main_dev.dart] or [main_prod.dart] for integration
/// and real-vault launches respectively.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PersonalOsApp(composition: AppComposition.demo()));
}
