import 'package:personal_os_events/events.dart';

/// Transport-neutral encrypted synchronization boundary.
abstract interface class SyncPort {
  Future<SyncPushReceipt> push({
    required String deviceId,
    required List<EventEnvelope> events,
    required String cursor,
  });

  Future<SyncPage> pull({
    required String deviceId,
    required String cursor,
    int limit = 100,
  });
}

final class SyncPushReceipt {
  const SyncPushReceipt({required this.acceptedEventIds, required this.cursor});

  final List<String> acceptedEventIds;
  final String cursor;
}

final class SyncPage {
  const SyncPage({
    required this.events,
    required this.cursor,
    required this.hasMore,
  });

  final List<EventEnvelope> events;
  final String cursor;
  final bool hasMore;
}

