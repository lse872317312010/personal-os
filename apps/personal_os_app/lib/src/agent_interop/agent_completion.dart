import 'package:flutter/services.dart';

const int maximumAgentPromptLength = 120000;
const int maximumAgentReplyLength = 65536;

/// Provider-neutral outbound text completion boundary for a user-approved turn.
///
/// Implementations must keep provider credentials outside Dart and must not
/// persist requests or responses unless a separate user-visible feature does so.
abstract interface class AgentCompletionPort {
  Future<bool> configureCredential();

  Future<String> complete(String prompt);

  Future<void> clearCredential();
}

final class AgentCompletionFailure implements Exception {
  const AgentCompletionFailure(this.code);

  final String code;

  @override
  String toString() => 'AgentCompletionFailure($code)';
}

/// Android-backed OpenAI Responses adapter. Only the request prompt and
/// response cross the platform channel; the API key never does.
final class MethodChannelAgentCompletionPort implements AgentCompletionPort {
  const MethodChannelAgentCompletionPort({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('personal_os/internal/agent_completion');

  final MethodChannel _channel;

  @override
  Future<bool> configureCredential() async {
    try {
      final configured =
          await _channel.invokeMethod<Object?>('configureCredential');
      if (configured is bool) return configured;
      throw const AgentCompletionFailure('agent.invalid_response');
    } on PlatformException catch (error) {
      throw AgentCompletionFailure(_stableCode(error.code));
    } on AgentCompletionFailure {
      rethrow;
    } on Object {
      throw const AgentCompletionFailure('agent.adapter_unavailable');
    }
  }

  @override
  Future<String> complete(String prompt) async {
    if (prompt.trim().isEmpty || prompt.length > maximumAgentPromptLength) {
      throw const AgentCompletionFailure('agent.invalid_request');
    }
    try {
      final reply = await _channel.invokeMethod<Object?>(
        'complete',
        <String, Object?>{'prompt': prompt},
      );
      if (reply is! String ||
          reply.trim().isEmpty ||
          reply.length > maximumAgentReplyLength) {
        throw const AgentCompletionFailure('agent.invalid_response');
      }
      return reply;
    } on PlatformException catch (error) {
      throw AgentCompletionFailure(_stableCode(error.code));
    } on AgentCompletionFailure {
      rethrow;
    } on Object {
      throw const AgentCompletionFailure('agent.adapter_unavailable');
    }
  }

  @override
  Future<void> clearCredential() async {
    try {
      await _channel.invokeMethod<void>('clearCredential');
    } on PlatformException catch (error) {
      throw AgentCompletionFailure(_stableCode(error.code));
    } on Object {
      throw const AgentCompletionFailure('agent.adapter_unavailable');
    }
  }
}

final class UnavailableAgentCompletionPort implements AgentCompletionPort {
  const UnavailableAgentCompletionPort();

  @override
  Future<bool> configureCredential() async => false;

  @override
  Future<String> complete(String prompt) async {
    throw const AgentCompletionFailure('agent.adapter_unavailable');
  }

  @override
  Future<void> clearCredential() async {}
}

String _stableCode(String code) => switch (code) {
      'agent.adapter_unavailable' ||
      'agent.credential_required' ||
      'agent.invalid_request' ||
      'agent.invalid_response' ||
      'agent.request_failed' =>
        code,
      _ => 'agent.adapter_unavailable',
    };
