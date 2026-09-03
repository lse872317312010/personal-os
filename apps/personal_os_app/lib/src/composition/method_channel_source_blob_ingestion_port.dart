import 'package:personal_os_application/application.dart';
import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

import 'method_channel_controlled_source_port.dart';

/// Composition adapter that keeps source bytes native and returns only BlobRef.
final class MethodChannelSourceBlobIngestionPort
    implements SourceBlobIngestionPort {
  const MethodChannelSourceBlobIngestionPort(this._source);

  final MethodChannelControlledSourcePort _source;

  @override
  Future<BlobRef> ingestSource({
    required OpaqueSourceToken source,
    required String mediaType,
    required Sensitivity sensitivity,
    required BlobAccessContext access,
  }) async {
    if (sensitivity == Sensitivity.d4) {
      throw const SourceBlobIngestionException('d4_persistence_forbidden');
    }
    if (access.consentRef == null) {
      throw const SourceBlobIngestionException('consent_required');
    }
    try {
      return BlobRef(await _source.ingestToBlob(source));
    } on ControlledSourceException catch (error) {
      throw SourceBlobIngestionException(_stableCode(error.code));
    } on Object {
      throw const SourceBlobIngestionException('ingestion_failed');
    }
  }

  @override
  Future<void> discard({
    required BlobRef ref,
    required BlobAccessContext access,
  }) =>
      _source.deleteBlob(ref.encode());

  String _stableCode(ControlledSourceFailureCode code) => switch (code) {
        ControlledSourceFailureCode.sourceExpired => 'source_expired',
        ControlledSourceFailureCode.sourceConsumed => 'source_consumed',
        ControlledSourceFailureCode.denied => 'source_denied',
        ControlledSourceFailureCode.sourceWriteFailed => 'ingestion_failed',
        ControlledSourceFailureCode.cancelled => 'source_cancelled',
        ControlledSourceFailureCode.unavailable => 'source_unavailable',
        ControlledSourceFailureCode.invalidResponse => 'ingestion_failed',
      };
}
