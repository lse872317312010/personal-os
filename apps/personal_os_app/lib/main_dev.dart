import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/app.dart';
import 'src/composition/app_composition.dart';

/// Launch with an unencrypted SQLite-backed vault.
///
/// Today the storage layer is InMemorySqlExecutor + SqliteVaultEventStore;
/// replace [DevSqliteInMemoryDriverFactory] with a sqflite-backed driver to
/// get restart durability. The entry point already resolves the real app
/// documents directory via path_provider so the hand-over to sqflite later
/// is a single-line swap.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final String docsDir = (await getApplicationDocumentsDirectory()).path;
  final String dbPath = '$docsDir/personal-os-vault.db';
  final AppComposition composition = AppComposition.withSqliteVault(
    driver: DevSqliteInMemoryDriverFactory(),
    databasePath: dbPath,
    mode: CompositionMode.devSqlite,
  );
  runApp(PersonalOsApp(composition: composition));
}
