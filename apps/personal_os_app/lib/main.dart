import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/composition/app_composition.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(PersonalOsApp(composition: AppComposition.forCurrentPlatform()));
}
