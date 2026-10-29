import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:personal_os_app/src/agent_interop/automatic_agent_gateway.dart';
import 'package:personal_os_app/src/agent_interop/web_history_restore.dart';
import 'package:personal_os_app/src/agent_interop/local_agent_event_store.dart';
import 'package:personal_os_app/src/screens/history_restore_screen.dart';
import 'package:personal_os_events/events.dart';

void main() {
  test(
      'normal append preserves the exact imported prefix, including null fields and field order',
      () async {
    final h = _Harness();
    final restore = WebHistoryRestore(h.gateway);
    await restore.restore(await restore.prepare(_file()));
    final store = LocalAgentEventStore(h.gateway);
    await store.load();
    final next = Map<String, Object?>.from(_event)
      ..['event_id'] = 'fixture-next-plan'
      ..['event_type'] = 'strategy.proposed'
      ..['subject_refs'] = [
        {'type': 'strategy', 'id': 'fixture-plan', 'revision': 1}
      ];
    await store.appendAll([EventEnvelopeJsonCodec.decode(next)]);
    expect(h.history['revision'], 2);
    expect((h.history['events']! as List).length, 2);
    expect(
        jsonEncode((h.history['events']! as List).first), jsonEncode(_event));
  });
  test(
      'preparation is read-only; restore preserves raw event fields and uses destination revision without AI status',
      () async {
    final h = _Harness();
    final restore = WebHistoryRestore(h.gateway);
    final prepared = await restore.prepare(_file());
    expect(prepared.preview.sourceRevision, 42);
    expect(prepared.destinationRevision, 0);
    expect(h.writes, 0);
    expect(h.paths, ['/api/history/status']);
    await restore.restore(prepared);
    expect(h.history['events'], [_event]);
    expect(h.history['revision'], 1);
    expect(h.paths,
        ['/api/history/status', '/api/history/status', '/api/history/restore']);
    await expectLater(
        restore.restore(prepared), throwsA(isA<AgentGatewayException>()));
  });

  test(
      'invalid file never contacts the gateway; nonempty and changed destinations refuse before POST',
      () async {
    final h = _Harness();
    final restore = WebHistoryRestore(h.gateway);
    await expectLater(
        restore.prepare('bad'), throwsA(isA<WebHistoryException>()));
    expect(h.paths, isEmpty);
    final service = WebHistoryRestore(h.gateway);
    final prepared = await service.prepare(_file());
    h.history = {
      'revision': 1,
      'events': [_event]
    };
    await expectLater(
        service.restore(prepared), throwsA(isA<AgentGatewayException>()));
    await expectLater(
        service.prepare(_file()), throwsA(isA<AgentGatewayException>()));
    expect(h.writes, 0);
    expect(h.paths, everyElement('/api/history/status'));
  });

  testWidgets(
      'selection previews without writing; confirmation restores and waits for explicit entry',
      (tester) async {
    final h = _Harness();
    var entered = 0;
    await tester.pumpWidget(MaterialApp(
        home: HistoryRestoreScreen(
      gateway: h.gateway,
      pickFile: () async => _file(),
      onContinue: () async {
        entered++;
      },
    )));
    await tester.pumpAndSettle();
    expect(h.writes, 0);
    expect(entered, 0);
    await tester.tap(find.byKey(const Key('history-restore-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-restore-preview')), findsOneWidget);
    expect(h.writes, 0);
    await tester
        .ensureVisible(find.byKey(const Key('history-restore-confirm')));
    await tester.tap(find.byKey(const Key('history-restore-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('历史已恢复'), findsOneWidget);
    expect(h.writes, 1);
    expect(entered, 0);
    expect(h.history['events'], [_event]);
    await tester.tap(find.byKey(const Key('history-restore-continue')));
    await tester.pumpAndSettle();
    expect(entered, 1);
  });

  testWidgets(
      'cancel and invalid file keep history empty and allow another selection',
      (tester) async {
    final h = _Harness();
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: HistoryRestoreScreen(
      gateway: h.gateway,
      pickFile: () async =>
          selected++ == 0 ? null : 'private malformed content',
      onContinue: () async {},
    )));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('history-restore-select')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history-restore-confirm')), findsNothing);
    }
    expect(h.writes, 0);
    expect(find.textContaining('private malformed'), findsNothing);
    expect(find.textContaining('历史未写入'), findsOneWidget);
  });

  testWidgets(
      'a concurrent writer blocks confirmation without replacing history',
      (tester) async {
    final h = _Harness();
    await tester.pumpWidget(MaterialApp(
        home: HistoryRestoreScreen(
      gateway: h.gateway,
      pickFile: () async => _file(),
      onContinue: () async {},
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-restore-select')));
    await tester.pumpAndSettle();
    h.history = {
      'revision': 8,
      'events': [_event]
    };
    await tester
        .ensureVisible(find.byKey(const Key('history-restore-confirm')));
    await tester.tap(find.byKey(const Key('history-restore-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('恢复已拒绝'), findsOneWidget);
    expect(find.byKey(const Key('history-restore-select')), findsNothing);
    expect(h.history['revision'], 8);
    expect(h.writes, 0);
  });

  testWidgets(
      'an uncertain response never retries or opens the app automatically',
      (tester) async {
    final h = _Harness()..uncertain = true;
    var entered = 0;
    await tester.pumpWidget(MaterialApp(
        home: HistoryRestoreScreen(
      gateway: h.gateway,
      pickFile: () async => _file(),
      onContinue: () async {
        entered++;
      },
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-restore-select')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const Key('history-restore-confirm')));
    await tester.tap(find.byKey(const Key('history-restore-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不要重复导入'), findsOneWidget);
    expect(find.byKey(const Key('history-restore-confirm')), findsNothing);
    expect(h.writes, 1);
    expect(entered, 0);
  });
}

final class _Harness {
  Map<String, Object?> history = {'revision': 0, 'events': <Object?>[]};
  int writes = 0;
  bool uncertain = false;
  final paths = <String>[];
  late final gateway = LocalAutomaticAgentGateway(
      origin: Uri.parse('http://127.0.0.1:8787'),
      client: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.headers['X-Personal-OS'], '1');
        if (request.url.path == '/api/history/status') {
          return http.Response(
              jsonEncode({
                'revision': history['revision'],
                'empty': (history['events']! as List).isEmpty,
                'csrf': 'fixture-nonce'
              }),
              200);
        }
        if (request.url.path == '/api/history' && request.method == 'GET') {
          return http.Response(jsonEncode(history), 200);
        }
        if (request.url.path == '/api/history' && request.method == 'POST') {
          expect(request.headers['X-Personal-OS-CSRF'], 'fixture-nonce');
          final body = jsonDecode(request.body) as Map;
          final old = history['events']! as List, next = body['events'] as List;
          if (body['revision'] != history['revision'] ||
              next.length < old.length ||
              List.generate(old.length, (i) => i)
                  .any((i) => jsonEncode(old[i]) != jsonEncode(next[i]))) {
            return http.Response('{"error":"history_conflict"}', 409);
          }
          history = {
            'revision': (history['revision']! as int) + 1,
            'events': next
          };
          writes++;
          return http.Response(
              jsonEncode({'revision': history['revision']}), 200);
        }
        expect(request.url.path, '/api/history/restore');
        expect(request.headers['X-Personal-OS-CSRF'], 'fixture-nonce');
        final body = jsonDecode(request.body) as Map;
        if (body['revision'] != history['revision'] ||
            (history['events']! as List).isNotEmpty) {
          return http.Response('{"error":"history_conflict"}', 409);
        }
        history = {
          'revision': (history['revision']! as int) + 1,
          'events': body['events']
        };
        writes++;
        return uncertain
            ? http.Response('{"error":"service_unavailable"}', 503)
            : http.Response(jsonEncode({'revision': history['revision']}), 200);
      }));
}

String _file() => jsonEncode({
      'format': 'personal-os.web-history.v1',
      'exported_at': '2026-10-30T00:00:00.000Z',
      'source_revision': 42,
      'events': [_event]
    });
const _event = <String, Object?>{
  'schema_version': 1,
  'event_version': 1,
  'event_id': 'fixture-goal-created',
  'event_type': 'goal.created',
  'occurred_at': '2026-10-29T00:00:00.000Z',
  'recorded_at': '2026-10-29T00:00:00.000Z',
  'actor': {
    'actor_id': 'fixture-user',
    'actor_type': 'user',
    'authority_source': 'explicit_user_action',
    'capability_refs': <Object?>[]
  },
  'subject_refs': [
    {'type': 'goal', 'id': 'fixture-goal', 'revision': 1}
  ],
  'correlation_id': 'fixture-round',
  'causation_id': null,
  'source_refs': <Object?>[],
  'consent_refs': <Object?>[],
  'sensitivity': 'd2',
  'payload': {'expected_revision': 0, 'text': '中文反馈 </script> 原样保留'},
  'integrity': <String, Object?>{},
  'extensions': <String, Object?>{},
};
