import 'dart:typed_data';

import 'package:personal_os_domain/domain.dart';

/// Opaque encrypted/blob storage boundary. The application layer never sees
/// file paths, database handles, or platform URIs.
abstract interface class BlobStore {
  Future<BlobRef> put({
    required Stream<List<int>> bytes,
    required String mediaType,
    required Sensitivity sensitivity,
  });

  Future<Uint8List> read(BlobRef ref);
}

final class BlobRef {
  BlobRef(String value) : value = _nonBlank(value, 'value');

  final String value;
}

String _nonBlank(String value, String label) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, label, 'must not be blank');
  }
  return value;
}
