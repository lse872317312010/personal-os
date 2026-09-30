import 'dart:convert';

import 'package:http/http.dart' as http;

abstract interface class AutomaticAgentGateway {
  Uri get signInPage;
  Future<Map<String, Object?>> status();
  Future<List<Map<String, Object?>>> models();
  Future<String> request(
      {required String model,
      required String prompt,
      required String context,
      required String stage});
  Future<Map<String, Object?>> post(String path, Map<String, Object?> body);
  Future<Map<String, Object?>> get(String path);
  void cancel();
}

final class AgentGatewayException implements Exception {
  const AgentGatewayException(this.code);
  final String code;
}

/// Same-origin local runtime. OAuth and provider credentials never cross this
/// boundary; the CSRF nonce stays in memory rather than browser storage.
final class LocalAutomaticAgentGateway implements AutomaticAgentGateway {
  LocalAutomaticAgentGateway({required this.origin, http.Client? client})
      : _client = client ?? http.Client();
  final Uri origin;
  http.Client _client;
  String? _csrf;
  @override
  Uri get signInPage => origin.resolve('/connect');
  @override
  Future<Map<String, Object?>> status() async {
    final value = await get('/api/agent/status');
    _csrf = value['csrf'] as String?;
    return value;
  }

  @override
  Future<Map<String, Object?>> get(String path) => _send(path);
  @override
  Future<Map<String, Object?>> post(
      String path, Map<String, Object?> body) async {
    if (_csrf == null) await status();
    return _send(path, body: body);
  }

  Future<Map<String, Object?>> _send(String path,
      {Map<String, Object?>? body}) async {
    try {
      final headers = <String, String>{
        'X-Personal-OS': '1',
        if (body != null) 'Content-Type': 'application/json',
        if (_csrf != null) 'X-Personal-OS-CSRF': _csrf!
      };
      final url = origin.resolve(path);
      final response = await (body == null
              ? _client.get(url, headers: headers)
              : _client.post(url, headers: headers, body: jsonEncode(body)))
          .timeout(const Duration(seconds: 190));
      final value = jsonDecode(response.body) as Map<String, Object?>;
      if (response.statusCode != 200)
        throw AgentGatewayException(
            value['error'] as String? ?? 'service_unavailable');
      return value;
    } on AgentGatewayException {
      rethrow;
    } on Object {
      throw const AgentGatewayException('local_service_unavailable');
    }
  }

  @override
  Future<List<Map<String, Object?>>> models() async =>
      ((await get('/api/agent/models'))['models'] as List)
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList(growable: false);
  @override
  Future<String> request(
          {required String model,
          required String prompt,
          required String context,
          required String stage}) async =>
      (await post('/api/agent/request', <String, Object?>{
        'model': model,
        'prompt': prompt,
        'context': context,
        'stage': stage
      }))['reply'] as String;
  @override
  void cancel() {
    _client.close();
    _client = http.Client();
  }
}
