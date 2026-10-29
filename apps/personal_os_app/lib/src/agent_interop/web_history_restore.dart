import 'dart:convert';

import 'package:personal_os_events/events.dart';

import 'automatic_agent_gateway.dart';

/// Holds the original validated event JSON; encoding decoded envelopes could
/// silently normalize optional fields in an otherwise valid imported file.
final class PreparedHistoryRestore {
  PreparedHistoryRestore._(
      this.preview, this.destinationRevision, this._events);
  final WebHistoryPreview preview;
  final int destinationRevision;
  final String _events;
}

final class WebHistoryRestore {
  WebHistoryRestore(this.gateway);
  final AutomaticAgentGateway gateway;

  Future<Map<String, Object?>> status() => gateway.get('/api/history/status');

  Future<PreparedHistoryRestore> prepare(String source) async {
    final preview = WebHistoryCodec.preview(source);
    final destination = await status();
    final revision = destination['revision'];
    if (destination['empty'] != true || revision is! int || revision < 0) {
      throw const AgentGatewayException('history_conflict');
    }
    return PreparedHistoryRestore._(
        preview, revision, jsonEncode((jsonDecode(source) as Map)['events']));
  }

  Future<void> restore(PreparedHistoryRestore prepared) async {
    // Re-check status to refresh CSRF without reading AI login/config. The
    // server repeats this check while holding the shared history write lock.
    final destination = await status();
    if (destination['empty'] != true ||
        destination['revision'] != prepared.destinationRevision) {
      throw const AgentGatewayException('history_conflict');
    }
    await gateway.post('/api/history/restore', <String, Object?>{
      'revision': prepared.destinationRevision,
      'events': jsonDecode(prepared._events),
    });
  }
}
