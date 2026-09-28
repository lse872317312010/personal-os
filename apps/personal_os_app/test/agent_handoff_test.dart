import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:personal_os_app/src/agent_interop/agent_handoff.dart';

void main() {
  test('copies a provider-neutral prompt with the pinned session context', () {
    final contextBundle = jsonEncode(<String, Object?>{
      'protocol_version': 'personal-os.mcp.v0',
      'session_id': 'session-from-vault',
      'objects': <Object?>[],
    });

    final prompt = buildAgentHandoffPrompt(contextBundle);

    expect(prompt, contains('任何能处理文本的 AI 助手或 Harness'));
    expect(prompt, contains('"session_id" 必须严格使用 "session-from-vault"'));
    expect(prompt, contains('personal-os.mcp.v0'));
    expect(prompt, contains(contextBundle));
    expect(prompt, contains('不要编造个人事实'));
  });

  test('detects a raw proposal JSON object', () {
    const response = '''
{"protocol_version":"personal-os.mcp.v0","proposal_id":"p1","strategy":{"title":"Test"}}
''';

    final reply = parseAgentHandoffReply(response);

    expect(reply.kind, AgentReplyKind.proposal);
    expect(reply.bundleJson, contains('"proposal_id":"p1"'));
  });

  test('detects a fenced review inside a normal assistant reply', () {
    const response = '''
这是复盘结果：
\u0060\u0060\u0060json
{"protocol_version":"personal-os.mcp.v0","review_id":"r1","review":{"summary":"结果有限"}}
\u0060\u0060\u0060
''';

    final reply = parseAgentHandoffReply(response);

    expect(reply.kind, AgentReplyKind.review);
    expect(reply.bundleJson, contains('"review_id":"r1"'));
    expect(reply.bundleJson, isNot(contains('\u0060\u0060\u0060')));
  });

  test('asks for one bundle when the assistant returns multiple results', () {
    const response = '''
{"protocol_version":"personal-os.mcp.v0","proposal_id":"p1","strategy":{}}
{"protocol_version":"personal-os.mcp.v0","review_id":"r1","review":{}}
''';

    expect(
      () => parseAgentHandoffReply(response),
      throwsA(
        isA<AgentHandoffFormatException>().having(
          (error) => error.issue,
          'issue',
          AgentHandoffFormatIssue.multipleBundles,
        ),
      ),
    );
  });

  test('gives a friendly error when no bundle is present', () {
    expect(
      () => parseAgentHandoffReply('Here is my advice.'),
      throwsA(
        isA<AgentHandoffFormatException>().having(
          (error) => error.issue,
          'issue',
          AgentHandoffFormatIssue.noBundle,
        ),
      ),
    );
  });
}
