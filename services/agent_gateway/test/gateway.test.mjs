import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, stat, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { generateKeyPairSync, sign, createHash } from 'node:crypto';
import { ChatGPTAuth } from '../chatgpt-auth.mjs';
import { AgentProviders, completedResponse, endpoint } from '../providers.mjs';
import { ProtectedStore } from '../protected-store.mjs';
import { createGateway } from '../server.mjs';
import { request as httpRequest } from 'node:http';

const stream = events => new Response(events.map(event => `data: ${JSON.stringify(event)}\n\n`).join('')).body;
const json = value => new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } });
const memory = () => ({ value: null, async read(_name, fallback) { return this.value || fallback; }, async write(_name, value) { this.value = structuredClone(value); } });
const complete = text => ({ type: 'response.completed', response: { status: 'completed', output: [{ content: [{ type: 'output_text', text }] }] } });

test('stream consumes completed result and refuses late quota errors, incomplete/refused/interrupted output', async () => {
  assert.equal(await completedResponse(stream([{ type: 'response.output_text.delta', delta: 'partial' }, complete('whole')])), 'whole');
  for (const events of [
    [{ type: 'response.output_text.delta', delta: 'looks valid' }],
    [{ type: 'response.output_text.delta', delta: 'looks valid' }, { type: 'response.failed', response: { error: { code: 'subscription_sharing_usage_limit_exceeded' } } }],
    [{ type: 'response.incomplete' }], [{ type: 'response.refusal.done' }],
  ]) await assert.rejects(completedResponse(stream(events)));
});

test('SSE frames tolerate UTF-8 and CRLF split across network chunks', async () => {
  const text = `data: ${JSON.stringify(complete('行动'))}\r\n\r\n`, bytes = new TextEncoder().encode(text);
  const body = new ReadableStream({ start(controller) { for (const byte of bytes) controller.enqueue(Uint8Array.of(byte)); controller.close(); } });
  assert.equal(await completedResponse(body), '行动');
});

test('OAuth validates state, PKCE, issued client, JWT signature/nonce/identity and granted scope', async () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const key = { ...publicKey.export({ format: 'jwk' }), kid: 'test-key', alg: 'RS256', use: 'sig' };
  let attempt, nonceOverride, scope = 'openid chatgpt.tokens.use.direct offline_access', exchanges = 0;
  const auth = new ChatGPTAuth(memory(), async (url, options) => {
    if (url.includes('openid-configuration')) return json({ issuer: 'https://auth.openai.com', jwks_uri: 'https://auth.openai.com/jwks', revocation_endpoint: 'https://auth.openai.com/revoke' });
    if (url.endsWith('/jwks')) return json({ keys: [key] });
    if (url.endsWith('/oauth/token')) {
      exchanges++;
      assert.equal(options.body.get('client_id'), 'oaiapp_test');
      assert.equal(options.body.get('redirect_uri'), 'http://127.0.0.1:8787/auth/callback');
      assert.equal(createHash('sha256').update(options.body.get('code_verifier')).digest('base64url'), attempt.searchParams.get('code_challenge'));
      const h = Buffer.from(JSON.stringify({ alg: 'RS256', kid: key.kid })).toString('base64url');
      const b = Buffer.from(JSON.stringify({ iss: 'https://auth.openai.com', aud: 'oaiapp_test', sub: 'person', exp: Date.now() / 1000 + 3600, nonce: nonceOverride || attempt.searchParams.get('nonce'), email: 'test@example.invalid' })).toString('base64url');
      const signature = sign('sha256', Buffer.from(`${h}.${b}`), privateKey).toString('base64url');
      return json({ id_token: `${h}.${b}.${signature}`, access_token: 'access-test', refresh_token: 'refresh-test', token_type: 'Bearer', expires_in: 3600, scope });
    }
    throw Error('Unexpected endpoint');
  });
  await auth.init();
  const host = auth.state.hostId;
  attempt = new URL(await auth.begin('http://127.0.0.1:8787'));
  assert.equal(attempt.searchParams.get('client_id'), 'dynamic_agent_client');
  await assert.rejects(auth.callback(new URLSearchParams({ state: 'wrong', code: 'code', client_id: 'oaiapp_test' })), { code: 'invalid_authorization_state' });
  assert.equal(exchanges, 0);
  const callback = () => new URLSearchParams({ state: attempt.searchParams.get('state'), code: 'code', client_id: 'oaiapp_test', scope: 'untrusted_callback_scope' });
  await auth.callback(callback());
  assert.equal(auth.connected, true);
  assert.equal(await auth.accessToken(), 'access-test');
  await assert.rejects(auth.callback(callback()), { code: 'invalid_authorization_state' });
  attempt = new URL(await auth.begin('http://127.0.0.1:8787', 'oaiapp_test'));
  assert.equal(attempt.searchParams.get('ext_agent_host_id'), host);
  assert.equal(attempt.searchParams.has('agent_name_hint'), false);
  assert.ok(attempt.searchParams.get('id_token_hint'));
  nonceOverride = 'wrong'; await assert.rejects(auth.callback(callback()), { code: 'invalid_identity' });
  assert.equal(auth.account.access_token, 'access-test');
  nonceOverride = null; scope = 'openid';
  attempt = new URL(await auth.begin('http://127.0.0.1:8787', 'oaiapp_test'));
  await assert.rejects(auth.callback(callback()), { code: 'plan_permission_missing' });
  assert.equal(auth.account.access_token, 'access-test');
});

test('denied consent, changed returning client and missing issued ID never exchange a code', async () => {
  let exchanges = 0; const auth = new ChatGPTAuth(memory(), async () => { exchanges++; }); await auth.init();
  for (const extra of [{ error: 'access_denied' }, { code: 'code' }, { code: 'code', client_id: 'dynamic_agent_client' }]) {
    const url = new URL(await auth.begin('http://127.0.0.1:8787'));
    await assert.rejects(auth.callback(new URLSearchParams({ state: url.searchParams.get('state'), ...extra })));
  }
  auth.state.accounts.push({ client_id: 'oaiapp_old', subject: 'person' });
  const url = new URL(await auth.begin('http://127.0.0.1:8787', 'oaiapp_old'));
  await assert.rejects(auth.callback(new URLSearchParams({ state: url.searchParams.get('state'), code: 'code', client_id: 'oaiapp_different' })), { code: 'invalid_client' });
  assert.equal(exchanges, 0);
});

test('parallel requests serialize refresh, keep rotating token, preserve credentials on transient errors', async () => {
  let calls = 0, fail = false;
  const auth = new ChatGPTAuth(memory(), async (_url, options) => {
    calls++; assert.equal(options.body.get('scope'), null); assert.equal(options.body.get('client_id'), 'oaiapp_test');
    await new Promise(resolve => setTimeout(resolve, 10));
    if (fail) return new Response(JSON.stringify({ error: 'temporary' }), { status: 503 });
    return json({ access_token: 'new', refresh_token: 'rotated', expires_in: 3600, token_type: 'Bearer', scope: 'chatgpt.tokens.use.direct' });
  }); await auth.init();
  auth.state.accounts.push({ client_id: 'oaiapp_test', access_token: 'old', refresh_token: 'original', scopes: ['chatgpt.tokens.use.direct'], saved_at: 0, expires_in: 1 }); auth.state.active = 'oaiapp_test';
  assert.deepEqual(await Promise.all([auth.accessToken(), auth.accessToken(), auth.accessToken()]), ['new', 'new', 'new']); assert.equal(calls, 1); assert.equal(auth.account.refresh_token, 'rotated');
  auth.account.saved_at = 0; fail = true; await assert.rejects(auth.accessToken()); assert.equal(auth.account.refresh_token, 'rotated');
});

test('provider discovers eligible models, submits supported Responses fields and never leaks tokens', async () => {
  let payload;
  const auth = { connected: true, accessToken: async () => 'secret-for-test' };
  const providers = new AgentProviders(auth, {}, async (url, options) => {
    assert.equal(options.headers.Authorization, 'Bearer secret-for-test');
    if (url.endsWith('/models')) return json({ models: [{ slug: 'allowed', display_name: 'Allowed', visibility: 'list' }, { slug: 'hidden', visibility: 'hidden' }] });
    payload = JSON.parse(options.body); return new Response(stream([complete('{"strategy":{}}')]));
  });
  await assert.rejects(providers.request({ model: 'hidden', prompt: 'goal', context: '{}', stage: 'proposal' }));
  assert.equal(await providers.request({ model: 'allowed', prompt: 'goal', context: '{}', stage: 'proposal' }), '{"strategy":{}}');
  assert.deepEqual(Object.keys(payload).sort(), ['input', 'model', 'store', 'stream']); assert.equal(payload.store, false); assert.equal(payload.stream, true);
  assert.throws(() => endpoint('http://example.com/v1')); assert.throws(() => endpoint('https://key@example.com/v1'));
});

test('real loopback HTTP boundary enforces Host, origin, CSRF, bundle session and durable append-only history', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'personal-os-'));
  const store = new ProtectedStore(directory); const auth = new ChatGPTAuth(store); await auth.init();
  const providers = { id: 'test-agent', connected: true, models: async () => [{ id: 'test', name: 'Test' }], request: async body => JSON.stringify({ protocol_version: 'personal-os.mcp.v0', session_id: body.model === 'wrong' ? 'other' : 'session', strategy: { title: 'Action' } }) };
  const gateway = createGateway({ store, auth, providers }); const origin = await gateway.listen();
  t.after(async () => { await gateway.close(); await rm(directory, { recursive: true, force: true }); });
  const headers = { 'X-Personal-OS': '1', 'Content-Type': 'application/json' };
  assert.equal((await fetch(`${origin}/api/agent/status`)).status, 403);
  assert.equal((await fetch(`${origin}/api/agent/status`, { headers: { ...headers, Origin: 'https://evil.invalid' } })).status, 403);
  const callback = await fetch(`${origin}/auth/callback?state=wrong&code=code`, { headers: { 'Sec-Fetch-Site': 'cross-site' }, redirect: 'manual' });
  assert.equal(callback.status, 400);
  assert.equal((await callback.json()).error, 'invalid_authorization_state');
  const foreignHost = await new Promise((resolve, reject) => { const req = httpRequest(`${origin}/api/agent/status`, { headers: { ...headers, Host: 'evil.invalid' } }, res => { res.resume(); resolve(res.statusCode); }); req.on('error', reject); req.end(); });
  assert.equal(foreignHost, 403);
  const status = await (await fetch(`${origin}/api/agent/status`, { headers })).json();
  assert.ok(status.csrf); assert.equal(JSON.stringify(status).includes('access_token'), false);
  assert.equal((await fetch(`${origin}/api/agent/request`, { method: 'POST', headers, body: '{}' })).status, 403);
  headers['X-Personal-OS-CSRF'] = status.csrf;
  const post = (path, value) => fetch(`${origin}${path}`, { method: 'POST', headers, body: JSON.stringify(value) });
  assert.equal((await post('/api/agent/request', { context: '{"session_id":"session"}', model: 'wrong', stage: 'proposal' })).status, 502);
  assert.equal((await post('/api/agent/request', { context: '{"session_id":"session"}', model: 'test', stage: 'proposal' })).status, 200);
  assert.equal((await post('/api/history', { revision: 0, events: [{ event_id: '1', sensitivity: 'd1' }] })).status, 200);
  assert.equal((await post('/api/history', { revision: 0, events: [] })).status, 409);
  assert.equal((await post('/api/history', { revision: 1, events: [] })).status, 409);
  assert.equal((await post('/api/history', { revision: 1, events: [{ event_id: '1', sensitivity: 'd1' }, { event_id: '2', sensitivity: 'd4' }] })).status, 400);
  assert.equal((await store.read('history')).events.length, 1);
  if (process.platform !== 'win32') assert.equal((await stat(join(directory, 'history.private'))).mode & 0o777, 0o600);
});

test('personal records are encrypted, survive restart and reject tampering', async t => {
  const directory = await mkdtemp(join(tmpdir(), 'personal-os-encrypted-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const store = new ProtectedStore(directory);
  await store.write('history', { goal: '个人目标 · private-personal-goal' });
  const path = join(directory, 'history.private'), raw = await readFile(path, 'utf8');
  assert.equal(raw.includes('个人目标 · private-personal-goal'), false);
  assert.deepEqual(await new ProtectedStore(directory).read('history'), { goal: '个人目标 · private-personal-goal' });
  await writeFile(path, raw.slice(0, -10) + 'corrupted');
  await assert.rejects(store.read('history'), { message: 'protected_storage_unavailable' });
});
