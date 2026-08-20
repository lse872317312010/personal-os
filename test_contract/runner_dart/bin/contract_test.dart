import 'dart:io';

import 'package:personal_os_contract_runner/contract_runner.dart';

Future<void> main(List<String> arguments) async {
  final manifest = _manifestArgument(arguments);
  if (manifest == null) {
    stderr.writeln(
      'usage: dart run bin/contract_test.dart --manifest <manifest.json>',
    );
    exitCode = 64;
    return;
  }
  final report = await runManifest(manifest);
  stdout.write(encodeStableReport(report));
  if (report.hasFailures) exitCode = 1;
}

String? _manifestArgument(List<String> arguments) {
  final index = arguments.indexOf('--manifest');
  if (index < 0 || index + 1 >= arguments.length) return null;
  return arguments[index + 1];
}
