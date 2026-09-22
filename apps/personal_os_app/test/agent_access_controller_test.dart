import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/controller/agent_access_controller.dart';

void main() {
  test('locked Vault cannot start Agent access', () {
    var revocations = 0;
    final controller = AgentAccessController(
      handleRequest: (request) async => request,
      revokeAll: () => revocations++,
    );

    expect(controller.start(vaultUnlocked: false), isFalse);
    expect(controller.active, isFalse);
    expect(revocations, 0);
  });

  test('explicit start enables requests and stop revokes synchronously', () async {
    var revocations = 0;
    final controller = AgentAccessController(
      handleRequest: (request) async => <String, Object?>{
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': <String, Object?>{'accepted': true},
      },
      revokeAll: () => revocations++,
    );

    expect(controller.start(vaultUnlocked: true), isTrue);
    expect(controller.active, isTrue);
    expect(revocations, 1);

    final accepted = await controller.handle(
      <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
    );
    expect(accepted?['result'], <String, Object?>{'accepted': true});

    controller.stop();
    expect(controller.active, isFalse);
    expect(revocations, 2);

    final denied = await controller.handle(
      <String, Object?>{'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    );
    final error = denied?['error']! as Map<String, Object?>;
    final data = error['data']! as Map<String, Object?>;
    expect(data['code'], 'access_denied');
    expect(data['retryable'], isFalse);
  });

  test('notifications are dropped while access is stopped', () async {
    final controller = AgentAccessController(
      handleRequest: (request) async => request,
      revokeAll: () {},
    );

    final response = await controller.handle(
      <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'notifications/initialized',
      },
    );
    expect(response, isNull);
  });
}
