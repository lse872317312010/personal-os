import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/composition/app_composition.dart';

/// Launch with the production encrypted vault.
///
/// The composition API is identical to [main_dev.dart] – only the driver
/// and mode change. Before the native SQLCipher + Keystore MethodChannel
/// lands this entry point is intentionally left thin; Wave 15+ will swap
/// the driver factory placeholder for the real sqflite_sqlcipher-backed
/// one and plug the key provider into it.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final String docsDir = (await getApplicationDocumentsDirectory()).path;
  final String dbPath = '$docsDir/personal-os-vault.enc.db';
  final AppComposition composition = AppComposition.withSqliteVault(
    driver: DevSqliteInMemoryDriverFactory(), // TODO(Wave 15): swap for SQLCipher driver
    databasePath: dbPath,
    mode: CompositionMode.prodEncrypted,
  );
  runApp(PersonalOsApp(composition: composition));
}
