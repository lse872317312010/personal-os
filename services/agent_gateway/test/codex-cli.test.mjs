import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm, stat, access, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { CodexCli, cliEnvironment, cliFailure, completedCliReply } from '../codex-cli.mjs';

const events = reply => [
  { type: 'thread.started', thread_id: 'fixture' }, { type: 'turn.started' },
  { type: 'item.completed', item: { type: 'agent_message', text: JSON.stringify({ reply }) } },
  { type: 'turn.completed' },
].map(value => JSON.stringify(value)).join('\n');

test('CLI child environment excludes API keys and custom provider credentials', () => {
  const env = cliEnvironment({ PATH: '/bin', HOME: '/private/home', CODEX_HOME: '/private/codex', OPENAI_API_KEY: 'secret', CODEX_API_KEY: 'secret', PERSONAL_OS_API_KEY: 'secret', OPENAI_BASE_URL: 'https://other.invalid', HTTP_PROXY: 'secret' });
  assert.deepEqual(env, { PATH: '/bin', HOME: '/private/home', CODEX_HOME: '/private/codex' });
});

test('only complete, tool-free replies are accepted, including failure after useful output', () => {
  assert.equal(completedCliReply(events('complete-json-bundle')), 'complete-json-bundle');
  assert.throws(() => completedCliReply(events('useful') + '\n' + JSON.stringify({ type: 'turn.failed', error: { message: 'private-error' } })), { code: 'codex_cli_request_failed' });
  assert.throws(() => completedCliReply(events('useful').split('\n').slice(0, -1).join('\n')), { code: 'provider_response_interrupted' });
  assert.throws(() => completedCliReply(events('useful') + '\n{"type":"turn.started"}'), { code: 'provider_response_interrupted' });
  assert.throws(() => completedCliReply(events('useful') + '\n{"type":"item.completed","item":{"type":"agent_message","text":"late"}}'), { code: 'provider_response_interrupted' });
  assert.throws(() => completedCliReply('not-json'), { code: 'invalid_provider_response' });
  for (const type of ['command_execution', 'file_change', 'mcp_tool_call', 'web_search']) {
    assert.throws(() => completedCliReply(JSON.stringify({ type: 'item.completed', item: { type } }) + '\n' + events('answer')), { code: 'codex_cli_tools_not_allowed' });
  }
});

test('failure classification is bounded, redacted and does not inspect a successful model reply', () => {
  for (const [output, code] of [['usage_limit_reached: private-token', 'codex_usage_limit_reached'], ["You've hit your usage limit", 'codex_usage_limit_reached'], ['rate_limit_exceeded private-token', 'rate_limit_exceeded'], ['token_expired private-token', 'sign_in_required'], ['unknown private-token', 'codex_cli_request_failed']]) {
    const error = cliFailure(output); assert.equal(error.code, code); assert.equal(error.message.includes('private-token'), false);
  }
  assert.equal(completedCliReply(events('Discuss usage_limit_reached as a concept')), 'Discuss usage_limit_reached as a concept');
  assert.throws(() => completedCliReply(events('answer') + '\n' + JSON.stringify({ type: 'error', message: 'usage_limit_reached private-token' })), { code: 'codex_usage_limit_reached' });
});

test('API-key login is rejected before exec and no raw credentials escape', async () => {
  const calls = [];
  const cli = new CodexCli({ runner: async (_, args) => { calls.push(args); return { code: 0, stdout: 'Logged in using an API key: private-token', stderr: '' }; } });
  await assert.rejects(cli.request({ model: 'codex-default', prompt: 'private-context' }), { code: 'codex_chatgpt_login_required' });
  assert.deepEqual(calls, [['login', 'status']]);
  assert.equal(JSON.stringify(await cli.status()).includes('private-token'), false);
});

test('adapter enforces ChatGPT auth and disabled tools, private schema, default model and temp cleanup', async () => {
  let workingDirectory;
  const cli = new CodexCli({ runner: async (_, args, options) => {
    if (args[0] === 'login') return { code: 0, stdout: 'Logged in using ChatGPT', stderr: '' };
    workingDirectory = options.cwd;
    assert.deepEqual(await readdir(workingDirectory), ['reply.schema.json']);
    const schema = JSON.parse(await readFile(join(workingDirectory, 'reply.schema.json'), 'utf8'));
    assert.deepEqual(schema.required, ['reply']);
    if (process.platform !== 'win32') assert.equal((await stat(join(workingDirectory, 'reply.schema.json'))).mode & 0o777, 0o600);
    assert.ok(args.includes('forced_login_method="chatgpt"')); assert.ok(args.includes('--ignore-user-config')); assert.ok(args.includes('--ignore-rules')); assert.ok(args.includes('--ephemeral'));
    assert.ok(args.includes('read-only')); assert.ok(args.includes('web_search="disabled"'));
    assert.equal(args.includes('--model'), false);
    for (const feature of ['shell_tool', 'unified_exec', 'apps', 'plugins', 'hooks', 'multi_agent', 'browser_use', 'computer_use', 'view_image', 'skill_search', 'workspace_dependencies', 'daemon_auto_start']) assert.ok(args.some((value, i) => value === '--disable' && args[i + 1] === feature));
    assert.equal(args.some(value => value.includes('private-prompt')), false); assert.match(options.input, /private-prompt/);
    return { code: 0, stdout: events('bundle'), stderr: '' };
  } });
  assert.equal(await cli.request({ model: 'codex-default', prompt: 'private-prompt' }), 'bundle');
  await assert.rejects(access(workingDirectory), { code: 'ENOENT' });
});

test('real child receives stdin without a shell and is cancelled and cleaned up', { timeout: 10_000, skip: process.platform === 'win32' }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'personal-os-cli-child-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const binary = join(directory, 'fake-codex'), marker = join(directory, 'started.json');
  const script = `#!/usr/bin/env node
import { writeFileSync } from 'node:fs';
if (process.argv[2] === 'login') { console.log('Logged in using ChatGPT'); process.exit(0); }
let input = ''; for await (const chunk of process.stdin) input += chunk;
writeFileSync(${JSON.stringify(marker)}, JSON.stringify({ input, cwd: process.cwd() }));
setInterval(() => {}, 1000);
`;
  // .mjs determines module mode independently of directory/package settings.
  const modulePath = binary + '.mjs';
  await writeFile(modulePath, script, { mode: 0o700 });
  const cli = new CodexCli({ binary: modulePath }), controller = new AbortController();
  const pending = cli.request({ model: 'codex-default', prompt: 'literal $(do-not-run) `do-not-run`' }, controller.signal);
  const rejected = assert.rejects(pending, { code: 'provider_request_cancelled' });
  let markerValue;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { markerValue = JSON.parse(await readFile(marker, 'utf8')); break; } catch { await new Promise(resolve => setTimeout(resolve, 20)); }
  }
  controller.abort(); await rejected;
  assert.ok(markerValue); assert.match(markerValue.input, /literal \$\(do-not-run\) `do-not-run`/);
  await assert.rejects(access(markerValue.cwd), { code: 'ENOENT' });
});
