import 'package:personal_os_blob_engine/blob_engine.dart';
import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_source_api/source_api.dart';
import 'package:personal_os_storage_api/storage_api.dart';

/// Narrow fail-closed boundary expected from the policy package.
abstract interface class AppearancePolicyPort {
  Future<PolicyVerdict> authorizeAnalysis({
    required ActorRef actor,
    required EntityId profileId,
    required List<ObjectRef> consentRefs,
    required Sensitivity sensitivity,
  });
}

final class PolicyVerdict {
  const PolicyVerdict._({required this.allowed, required this.reasonCode});

  const PolicyVerdict.allow() : this._(allowed: true, reasonCode: null);

  const PolicyVerdict.deny(String reasonCode)
      : this._(allowed: false, reasonCode: reasonCode);

  final bool allowed;
  final String? reasonCode;
}

/// Application port for native source-to-encrypted-blob composition.
///
/// Implementations must stream from the native source directly into the
/// encrypted BlobStore. No bytes, path, URI, provider metadata, or raw error
/// may cross this boundary.
abstract interface class SourceBlobIngestionPort
    implements SourceBlobIngestionContract, BlobIngestionRollback {}

abstract interface class IdGenerator {
  String nextId(String namespace);
}

abstract interface class Clock {
  DateTime now();
}
