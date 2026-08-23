import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';

/// Append-only persistence boundary. Implementations must append [events]
/// atomically and in list order or fail without a partial write.
abstract interface class EventStore {
  Future<void> appendAll(List<EventEnvelope> events);

  Future<List<EventEnvelope>> readBySubject(
    ObjectRef subject, {
    int? limit,
  });

  Future<EventEnvelope?> readById(String eventId);
}

final class EventAppendConflict implements Exception {
  const EventAppendConflict(this.message);

  final String message;

  @override
  String toString() => 'EventAppendConflict: $message';
}
