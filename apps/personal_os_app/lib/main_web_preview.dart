import 'package:flutter/widgets.dart';

import 'src/app.dart';
import 'src/composition/app_composition.dart';

/// Browser-only preview backed by ephemeral synthetic data.
///
/// The production entrypoint remains [AppComposition.forCurrentPlatform],
/// which fails closed outside Android until a trusted secure adapter exists.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PersonalOsApp(composition: AppComposition.inMemoryDemo()));
}
