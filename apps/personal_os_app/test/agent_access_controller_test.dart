import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:personal_os_app/src/controller/agent_access_controller.dart';

void main() {
  test('locked Vault cannot start Agent access', () {
    var revocations = 0;
    const unlocked = false;
    final controller = AgentAccessController(
      handleRequest: (request) async => request,
      revokeAll: () => revocations++,
      vaultUnlocked: () => unlocked,
    );

    expect(controller.start(), isFalse);
    expect(controller.active, isFalse);
    expect(revocations, 0);
  });

  test('explicit start enables requests and stop revokes synchronously', () async {
    var revocations = 0;
    const unlocked = true;
    final controller = AgentAccessController(
      handleRequest: (request) async => <String, Object?>{
        'jsonrpc': '2.0',
        'id': request['id'],
        'result': <String, Object?>{'accepted': true},
      },
      revokeAll: () => revocations++,
      vaultUnlocked: () => unlocked,
    );

    expect(controller.start(), isTrue);
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

  test('Vault state is checked for every request', () async {
    var unlocked = true;
    var calls = 0;
    final controller = AgentAccessController(
      handleRequest: (request) async {
        calls++;
        return request;
      },
      revokeAll: () {},
      vaultUnlocked: () => unlocked,
    );
    expect(controller.start(), isTrue);
    unlocked = false;
    final denied = await controller.handle(
      <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
    );
    expect(
      (denied?['error'] as Map<String, Object?>)['message'],
      'access_denied',
    );
    expect(calls, 0);
  });

  test('pending response is discarded after stop and restart', () async {
    const unlocked = true;
    final pending = Completer<Map<String, Object?>?>();
    final controller = AgentAccessController(
      handleRequest: (request) => pending.future,
      revokeAll: () {},
      vaultUnlocked: () => unlocked,
    );
    expect(controller.start(), isTrue);
    final response = controller.handle(
      <String, Object?>{'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'},
    );
    controller.stop();
    expect(controller.start(), isTrue);
    pending.complete(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'result': <String, Object?>{},
    });
    expect(await response, isNull);
  });

  test('notifications are dropped while access is stopped', () async {
    final controller = AgentAccessController(
      handleRequest: (request) async => request,
      revokeAll: () {},
      vaultUnlocked: () => true,
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
