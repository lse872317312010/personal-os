/// Allowlisted structured telemetry. No message, metadata map, handle, ticket,
/// device ID, ciphertext, reason, or native exception can be attached.
enum SecurityOperation { capabilities, authenticate, createKey, wrapKey, unwrapKey, rotateEpoch, revokeDevice, authorizeNewData, destroyKey }

enum SecurityOperationOutcome { succeeded, failed }

final class SafeSecurityEvent {
  const SafeSecurityEvent({required this.operation, required this.outcome, this.errorCode});

  final SecurityOperation operation;
  final SecurityOperationOutcome outcome;
  final String? errorCode;
}

abstract interface class SafeSecurityLogSink {
  void record(SafeSecurityEvent event);
}

final class NoopSafeSecurityLogSink implements SafeSecurityLogSink {
  const NoopSafeSecurityLogSink();

  @override
  void record(SafeSecurityEvent event) {}
}
