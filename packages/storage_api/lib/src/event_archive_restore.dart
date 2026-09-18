import 'package:personal_os_events/events.dart';

import 'event_store.dart';

final class EventArchiveRestoreResult {
  const EventArchiveRestoreResult({
    required this.eventCount,
    required this.checksum,
  });

  final int eventCount;
  final String checksum;
}

/// Verifies the complete archive before performing one atomic append.
///
/// Callers must decrypt and authenticate the opaque platform backup before
/// invoking this service. The target store remains responsible for rejecting
/// conflicts with any existing history.
final class EventArchiveRestoreService {
  const EventArchiveRestoreService({required EventStore eventStore})
      : _eventStore = eventStore;

  final EventStore _eventStore;

  Future<EventArchiveRestoreResult> restore(String archiveJson) async {
    final archive = EventArchiveCodec.decode(archiveJson);
    if (archive.events.isNotEmpty) {
      await _eventStore.appendAll(archive.events);
    }
    return EventArchiveRestoreResult(
      eventCount: archive.events.length,
      checksum: archive.checksum,
    );
  }
}
