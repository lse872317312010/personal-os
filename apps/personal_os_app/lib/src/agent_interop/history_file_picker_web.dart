// This build targets JavaScript; keep the browser API behind a conditional
// import so native widget tests never depend on it.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:personal_os_events/events.dart';

Future<String?> pickHistoryFile() async {
  final input = html.FileUploadInputElement()
    ..accept = '.json,application/json';
  final result = Completer<String?>();
  late StreamSubscription<html.Event> changed, cancelled;
  changed = input.onChange.listen((_) async {
    try {
      final files = input.files;
      if (files == null || files.isEmpty) {
        if (!result.isCompleted) result.complete(null);
        return;
      }
      final file = files.single;
      if (file.size > WebHistoryCodec.maxSourceBytes) {
        throw const WebHistoryException('history.file_too_large');
      }
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoadEnd.first;
      if (reader.error != null || reader.result is! ByteBuffer) {
        throw const WebHistoryException('history.file_unavailable');
      }
      if (!result.isCompleted) {
        result.complete(
            utf8.decode((reader.result! as ByteBuffer).asUint8List()));
      }
    } on Object {
      if (!result.isCompleted) {
        result.completeError(const WebHistoryException('history.file_invalid'));
      }
    }
  });
  cancelled = input.on['cancel'].listen((_) {
    if (!result.isCompleted) result.complete(null);
  });
  // A DOM node also lets browser automation exercise a real file selection.
  input.id = 'personal-os-history-file';
  input.style.display = 'none';
  html.document.body!.append(input);
  input.click();
  try {
    return await result.future;
  } finally {
    await changed.cancel();
    await cancelled.cancel();
    input.remove();
  }
}
