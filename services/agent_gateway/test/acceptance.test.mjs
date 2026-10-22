import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { inferenceAcceptance } from '../acceptance.mjs';
import { createGateway } from '../server.mjs';
import { AgentConnections } from '../connections.mjs';
import { ChatGPTAuth } from '../chatgpt-auth.mjs';
import { ProtectedStore } from '../protected-store.mjs';

const replyEvents = text => [
  { type: 'turn.started' },
  { type: 'item.completed', item: { type: 'agent_message', text: JSON.stringify({ reply: text }) } },
  { type: 'turn.completed' },
].map(value => JSON.stringify(value)).join('\n');

async function setup(t, { login = 'Logged in using ChatGPT', failure = null } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'personal-os-acceptance-'));
  const store = new ProtectedStore(directory), auth = new ChatGPTAuth(store);
  await auth.init();
  const connections = await new AgentConnections(store, auth, { kind: 'codex-cli' }).init();
  const calls = [];
  connections.provider.cli.runner = async (binary, args, options) => {
    calls.push({ args, input: options?.input });
    if (args[0] === 'login') return { code: 0, stdout: login, stderr: '' };
    return failure || { code: 0, stdout: replyEvents('private-model-reply'), stderr: '' };
  };
  const gateway = createGateway({ auth, connections, providers: connections.provider, store: {
    read() { throw Error('Acceptance must not read history'); },
    write() { throw Error('Acceptance must not write history'); },
  } });
  const origin = await gateway.listen();
  t.after(async () => { await gateway.close(); await rm(directory, { recursive: true, force: true }); });
  return { origin, calls, connections };
}

test('default does not contact gateway or infer; non-loopback destinations are rejected', async () => {
  const fetcher = () => { throw Error('must not fetch'); };
  assert.equal((await inferenceAcceptance({ fetcher })).code, 'not_requested');
  for (const origin of ['https://example.invalid', 'http://localhost:8787', 'http://user@127.0.0.1:8787', 'http://127.0.0.1:8787/private', 'file:///tmp']) {
    const result = await inferenceAcceptance({ runInference: true, origin, fetcher });
    assert.equal(result.code, 'gateway_unavailable'); assert.equal(result.inference_attempted, false);
  }
});

test('real HTTP probe uses only fixed contents, no history, no model text or credentials in report', async t => {
  const { origin, calls } = await setup(t);
  const report = await inferenceAcceptance({ runInference: true, origin });
  assert.equal(report.inference_passed, true); assert.equal(report.inference_attempted, true);
  assert.equal(report.strategy_loop_tested, false); assert.equal(report.history_tested, false);
  const inference = calls.filter(call => call.args[0] === 'exec');
  assert.equal(inference.length, 1);
  assert.match(inference[0].input, /No personal data is supplied/);
  assert.equal(JSON.stringify(report).includes('private-model-reply'), false);
  assert.deepEqual(Object.keys(report).sort(), ['acceptance_version', 'code', 'history_tested', 'inference_attempted', 'inference_passed', 'inference_requested', 'message', 'strategy_loop_tested'].sort());
});

test('API-key and signed-out sessions fail before inference without changing the selected connection', async t => {
  for (const login of ['Logged in using an API key: secret-account-value', 'Not logged in']) {
    const { origin, calls, connections } = await setup(t, { login });
    const active = connections.state.active;
    const result = await inferenceAcceptance({ runInference: true, origin });
    assert.equal(result.inference_passed, false); assert.equal(result.inference_attempted, false);
    assert.equal(result.code, login.includes('API key') ? 'codex_chatgpt_login_required' : 'sign_in_required');
    assert.equal(calls.some(call => call.args[0] === 'exec'), false);
    assert.equal(connections.state.active, active);
    assert.equal(JSON.stringify(result).includes('secret-account-value'), false);
  }
});

test('usage exhaustion is classified and never retried or replaced by a paid provider', async t => {
  const { origin, calls, connections } = await setup(t, { failure: { code: 1, stdout: JSON.stringify({ type: 'turn.failed', error: { message: "You've hit your usage limit. secret-account-value" } }), stderr: 'private-diagnostic' } });
  const active = connections.state.active;
  const report = await inferenceAcceptance({ runInference: true, origin });
  assert.equal(report.code, 'codex_usage_limit_reached'); assert.equal(report.inference_passed, false);
  assert.equal(calls.filter(call => call.args[0] === 'exec').length, 1);
  assert.equal(connections.state.active, active);
  assert.doesNotMatch(JSON.stringify(report), /secret-account-value|private-diagnostic/);
});

function fakeFetch({ status = {}, models = [{ id: 'codex-default' }], check, modelsError, fail } = {}) {
  const seen = [];
  const fetcher = async (url, options) => {
    seen.push({ url, options });
    if (fail) throw fail;
    if (url.endsWith('/status')) return Response.json({ provider: 'codex-cli', connected: true, csrf: 'private-csrf', connection_id: 'cli', connection_revision: 'revision', ...status });
    if (url.includes('/models?')) return Response.json(modelsError || { models }, { status: modelsError ? 409 : 200 });
    return check || Response.json({ ok: true, provider: 'codex-cli', model: 'codex-default' });
  };
  return { fetcher, seen };
}

test('non-Codex provider and stale model catalogue stop before any inference', async () => {
  for (const [options, expected] of [[{ status: { provider: 'responses' } }, 'codex_connection_required'], [{ modelsError: { error: 'connection_changed' } }, 'connection_changed'], [{ models: [] }, 'model_not_available']]) {
    const { fetcher, seen } = fakeFetch(options);
    const report = await inferenceAcceptance({ runInference: true, fetcher });
    assert.equal(report.code, expected); assert.equal(report.inference_attempted, false);
    assert.equal(seen.some(call => call.options.method === 'POST'), false);
  }
});

test('success requires matching provider and model; arbitrary upstream errors are never echoed', async () => {
  for (const check of [Response.json({ ok: true, provider: 'responses', model: 'codex-default' }), Response.json({ ok: true, provider: 'codex-cli', model: 'other' }), Response.json({ error: 'secret-upstream-message', token: 'private-token' }, { status: 502 })]) {
    const { fetcher } = fakeFetch({ check });
    const report = await inferenceAcceptance({ runInference: true, fetcher });
    assert.equal(report.inference_passed, false);
    assert.doesNotMatch(JSON.stringify(report), /private-token|private-csrf|secret-upstream-message/);
  }
});

test('timeouts produce a bounded failure without retrying', async () => {
  const { fetcher, seen } = fakeFetch();
  const report = await inferenceAcceptance({ runInference: true, fetcher: async (url, options) => {
    if (options.method === 'POST') { seen.push({ url, options }); throw new DOMException('private-timeout-details', 'TimeoutError'); }
    return fetcher(url, options);
  } });
  assert.equal(report.code, 'connection_check_timeout'); assert.equal(report.inference_passed, false);
  assert.equal(seen.filter(call => call.options.method === 'POST').length, 1);
  assert.equal(JSON.stringify(report).includes('private-timeout-details'), false);
});

test('Codex proposal, review and revision use the normal HTTP path and reject stale or mismatched bundles', async t => {
  const { origin, calls, connections } = await setup(t);
  let review = false, wrongSession = false;
  const originalRunner = connections.provider.cli.runner;
  connections.provider.cli.runner = async (binary, args, options) => {
    if (args[0] !== 'exec') return originalRunner(binary, args, options);
    calls.push({ args, input: options.input });
    const bundle = { protocol_version: 'personal-os.mcp.v0', session_id: wrongSession ? 'wrong' : 'synthetic-session', ...(review ? { review: { summary: 'Synthetic review' } } : { strategy: { title: 'Synthetic action' } }) };
    return { code: 0, stdout: replyEvents(JSON.stringify(bundle)), stderr: '' };
  };
  const status = await (await fetch(`${origin}/api/agent/status`, { headers: { 'X-Personal-OS': '1' } })).json();
  const request = (stage, revision = status.connection_revision) => fetch(`${origin}/api/agent/request`, {
    method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Personal-OS': '1', 'X-Personal-OS-CSRF': status.csrf },
    body: JSON.stringify({ connection_id: status.connection_id, connection_revision: revision, model: 'codex-default', stage, prompt: `Synthetic ${stage} task; session synthetic-session`, context: '{"session_id":"synthetic-session"}' }),
  });
  for (const stage of ['proposal', 'review', 'revision']) {
    review = stage === 'review';
    const response = await request(stage); assert.equal(response.status, 200);
    const bundle = JSON.parse((await response.json()).reply);
    assert.equal(Boolean(bundle.review), review);
  }
  const count = calls.filter(call => call.args[0] === 'exec').length;
  assert.equal((await request('proposal', 'stale')).status, 409);
  assert.equal(calls.filter(call => call.args[0] === 'exec').length, count);
  wrongSession = true;
  assert.equal((await request('proposal')).status, 502);
});

test('installing Codex preserves an existing active connection and history and does not duplicate it', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'personal-os-migration-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const store = new ProtectedStore(directory), auth = new ChatGPTAuth(store); await auth.init();
  const original = await new AgentConnections(store, auth).init();
  await store.write('history', { revision: 1, events: [{ event_id: 'sentinel' }] });
  const migrated = await new AgentConnections(store, auth, { kind: 'codex-cli' }).init();
  assert.equal(migrated.state.active, original.state.active);
  assert.equal(migrated.summaries.filter(value => value.kind === 'codex-cli').length, 1);
  const restarted = await new AgentConnections(store, auth, { kind: 'codex-cli' }).init();
  assert.equal(restarted.summaries.filter(value => value.kind === 'codex-cli').length, 1);
  assert.deepEqual(await store.read('history'), { revision: 1, events: [{ event_id: 'sentinel' }] });
});

test('a slow catalogue from a previous provider cannot become the current model list', async t => {
  const { origin, connections } = await setup(t);
  const started = Promise.withResolvers(), resume = Promise.withResolvers();
  connections.provider.models = async () => { started.resolve(); await resume.promise; return [{ id: 'stale' }]; };
  const query = new URLSearchParams({ connection_id: connections.state.active, connection_revision: connections.state.revision });
  const pending = fetch(`${origin}/api/agent/models?${query}`, { headers: { 'X-Personal-OS': '1' } });
  await started.promise;
  connections.provider = { id: 'replacement' };
  resume.resolve();
  assert.equal((await pending).status, 409);
});
