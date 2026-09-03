import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Stable failures for source-token ingestion.
final class SourceBlobIngestionException implements Exception {
  const SourceBlobIngestionException(this.code)
      : assert(
          code == 'source_expired' ||
              code == 'source_cancelled' ||
              code == 'source_unavailable' ||
              code == 'source_denied' ||
              code == 'source_consumed' ||
              code == 'd4_persistence_forbidden' ||
              code == 'consent_required' ||
              code == 'ingestion_failed',
          'unstable source blob ingestion error code',
        );

  final String code;

  @override
  String toString() => 'SourceBlobIngestionException($code)';
}

/// Source-to-encrypted-blob port. Native adapters own the source stream,
/// temporary storage, and encryption write. Dart receives only BlobRef.
abstract interface class SourceBlobIngestionContract {
  Future<BlobRef> ingestSource({
    required OpaqueSourceToken source,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  });
}
