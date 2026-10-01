import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/agent_interop/agent_handoff.dart';

void main() {
  test('online Agent bundle omits sensitive assets and raw observations', () {
    final bundle = <String, Object?>{
      'protocol_version': 'personal-os.mcp.v0',
      'bundle_id': 'bundle-1',
      'session_id': 'session-1',
      'created_at': DateTime.utc(2026, 9, 30).toIso8601String(),
      'scope': <String, Object?>{
        'purpose': 'personal strategy proposal',
        'object_types': <String>[
          'goal',
          'personal_asset',
          'observation',
          'strategy',
          'outcome',
        ],
      },
      'cursor': 'page-2',
      'has_more': true,
      'objects': <Object?>[
        <String, Object?>{
          'ref': <String, Object?>{'type': 'goal', 'id': 'goal-1', 'revision': 1},
          'data': <String, Object?>{'title': 'Finish the project'},
        },
        <String, Object?>{
          'ref': <String, Object?>{
            'type': 'personal_asset',
            'id': 'asset-1',
            'revision': 1,
          },
          'data': <String, Object?>{'private': 'omit me'},
        },
        <String, Object?>{
          'ref': <String, Object?>{
            'type': 'observation',
            'id': 'observation-1',
            'revision': 1,
          },
          'data': <String, Object?>{'private': 'omit me'},
        },
        <String, Object?>{
          'ref': <String, Object?>{
            'type': 'strategy',
            'id': 'strategy-1',
            'revision': 1,
          },
          'data': <String, Object?>{'title': 'Small daily action'},
        },
      ],
    };

    final sanitized = jsonDecode(
      buildExternalAgentContextBundle(jsonEncode(bundle)),
    ) as Map<String, Object?>;
    final records = sanitized['objects'] as List;
    final types = records
        .map((record) => (record as Map)['ref']['type'])
        .cast<String>()
        .toList();

    expect(types, <String>['goal', 'strategy']);
    expect(jsonEncode(sanitized), isNot(contains('private')));
    expect(sanitized.containsKey('cursor'), isFalse);
    expect(sanitized['has_more'], isFalse);
    expect(
      (sanitized['scope'] as Map)['object_types'],
      <String>['goal', 'strategy', 'outcome'],
    );
  });
  test('blocks likely API keys and password values from outbound context', () {
    final bundle = jsonEncode(<String, Object?>{
      'protocol_version': 'personal-os.mcp.v0',
      'session_id': 'session-1',
      'objects': <Object?>[
        <String, Object?>{
          'ref': <String, Object?>{
            'type': 'goal',
            'id': 'goal-1',
            'revision': 1,
          },
          'data': <String, Object?>{
            'title': 'API key: sk-proj-abcdefghijklmnopqr',
          },
        },
      ],
    });

    expect(
      () => buildExternalAgentContextBundle(bundle),
      throwsA(isA<ExternalAgentContextException>()),
    );
  });

}
