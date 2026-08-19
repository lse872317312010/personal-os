import 'package:personal_os_domain/domain.dart';
import 'package:personal_os_events/events.dart';
import 'package:personal_os_storage_api/storage_api.dart';

final class GetAppearanceHistoryQuery {
  const GetAppearanceHistoryQuery({required this.profileId, this.limit = 50})
      : assert(limit > 0);

  final EntityId profileId;
  final int limit;
}

final class AppearanceHistory {
  const AppearanceHistory(this.events);

  final List<EventEnvelope> events;
}

final class AppearanceHistoryQueryHandler {
  const AppearanceHistoryQueryHandler(this._eventStore);

  final EventStore _eventStore;

  Future<AppearanceHistory> execute(GetAppearanceHistoryQuery query) async {
    final events = await _eventStore.readBySubject(
      ObjectRef(type: 'profile', id: query.profileId),
      limit: query.limit,
    );
    return AppearanceHistory(List<EventEnvelope>.unmodifiable(events));
  }
}

