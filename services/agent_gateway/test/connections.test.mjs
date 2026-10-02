import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createServer } from 'node:http';
import { ProtectedStore } from '../protected-store.mjs';
import { ChatGPTAuth } from '../chatgpt-auth.mjs';
import { AgentConnections } from '../connections.mjs';
import { createGateway } from '../server.mjs';

async function setup(t) {
  const directory = await mkdtemp(join(tmpdir(), 'personal-os-connections-'));
  const store = new ProtectedStore(directory), auth = new ChatGPTAuth(store); await auth.init();
  const connections = await new AgentConnections(store, auth).init();
  t.after(() => rm(directory, { recursive: true, force: true }));
  return { directory, store, auth, connections };
}
async function fixtureServer(t, handler) {
  const server = createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    await handler(req, res, JSON.parse(Buffer.concat(chunks).toString('utf8')));
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); });
  return `http://127.0.0.1:${server.address().port}`;
}
const bundle = (session, title) => ({ protocol_version: 'personal-os.mcp.v0', session_id: session, strategy: { title } });

test('connection secrets stay encrypted, survive restart and never move to a changed endpoint', async t => {
  const { directory, store, auth, connections } = await setup(t);
  await connections.save({ label: '本机模型', kind: 'responses', base_url: 'http://localhost:11434/v1', model: 'local', api_key: 'secret-for-test' });
  const id = connections.state.active;
  assert.equal(connections.current.config.baseUrl, 'http://127.0.0.1:11434/v1');
  assert.equal(JSON.stringify(connections.summaries).includes('secret-for-test'), false);
  assert.equal((await readFile(join(directory, 'connections.private'), 'utf8')).includes('secret-for-test'), false);
  const restarted = await new AgentConnections(new ProtectedStore(directory), auth, { kind: 'agent-http', model: 'ignored', agentUrl: 'https://other.invalid/agent', apiKey: 'unwanted-override' }).init();
  assert.equal(restarted.state.active, id);
  assert.equal(restarted.current.config.apiKey, 'secret-for-test');
  await restarted.save({ id, label: '模型新名', kind: 'responses', base_url: 'http://127.0.0.1:11434/v1', model: 'other-model' });
  assert.equal(restarted.current.config.apiKey, 'secret-for-test');
  await restarted.save({ id, label: '另一地址', kind: 'responses', base_url: 'https://second.invalid/v1', model: 'other-model' });
  assert.equal(restarted.current.config.apiKey, undefined);
  for (const url of ['http://remote.invalid/v1', 'https://secret@remote.invalid/v1', 'https://remote.invalid/v1?key=secret', 'file:///private']) {
    await assert.rejects(restarted.save({ id, label: 'bad', kind: 'responses', base_url: url, model: 'm' }), { code: 'invalid_provider_endpoint' });
  }
  const before = JSON.stringify(restarted.summaries), active = restarted.state.active;
  const originalWrite = store.write;
  restarted.store.write = async () => { throw Error('storage unavailable'); };
  await assert.rejects(restarted.select('chatgpt'));
  assert.equal(restarted.state.active, active); assert.equal(JSON.stringify(restarted.summaries), before);
  restarted.store.write = originalWrite;
});

test('real HTTP connection settings switch Agents without losing history, secrets or stale-client guards', async t => {
  const { store, auth, connections } = await setup(t);
  const seen = [], started = Promise.withResolvers(), resume = Promise.withResolvers();
  let pause = false;
  const bridge = await fixtureServer(t, async (req, res, value) => {
    seen.push({ path: req.url, authorization: req.headers.authorization, value });
    if (pause) { started.resolve(); await resume.promise; }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ bundle: bundle(value.context.session_id, value.model) }));
  });
  const gateway = createGateway({ store, auth, connections, providers: connections.provider }), origin = await gateway.listen();
  t.after(() => gateway.close());
  const headers = { 'Content-Type': 'application/json', 'X-Personal-OS': '1' };
  const get = path => fetch(`${origin}${path}`, { headers });
  const post = (path, body) => fetch(`${origin}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
  headers['X-Personal-OS-CSRF'] = (await (await get('/api/agent/status')).json()).csrf;
  assert.equal((await fetch(`${origin}/api/agent/connections`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Personal-OS': '1' }, body: '{}' })).status, 403);
  const history = { revision: 0, events: [{ event_id: 'goal-1', sensitivity: 'd1', goal: '每天学习', result: '已完成十分钟' }] };
  assert.equal((await post('/api/history', history)).status, 200);
  const savedA = await post('/api/agent/connections', { label: 'Agent A', kind: 'agent-http', agent_url: `${bridge}/a`, model: 'a', api_key: 'secret-a-for-test' });
  assert.equal(savedA.status, 200); const a = (await savedA.json()).active;
  const request = (id, revision = connections.state.revision) => post('/api/agent/request', { connection_id: id, connection_revision: revision, model: id === a ? 'a' : 'b', stage: 'proposal', prompt: '使用目标与真实结果', context: JSON.stringify({ session_id: 'same-goal', goal: '每天学习', result: '已完成十分钟' }) });
  assert.equal((await request(a)).status, 200);
  assert.equal(seen[0].authorization, 'Bearer secret-a-for-test');
  const savedB = await post('/api/agent/connections', { label: 'Agent B', kind: 'agent-http', agent_url: `${bridge}/b`, model: 'b' });
  assert.equal(savedB.status, 200); const b = (await savedB.json()).active;
  assert.equal((await request(a)).status, 409);
  assert.equal((await get(`/api/agent/models?connection_id=${a}`)).status, 409);
  assert.equal(seen.length, 1);
  assert.equal((await request(b)).status, 200);
  assert.equal(seen[1].authorization, undefined);
  assert.deepEqual(seen[1].value.context, seen[0].value.context);
  assert.deepEqual((await (await get('/api/history')).json()).events, history.events);
  const status = await (await get('/api/agent/status')).json();
  assert.equal(JSON.stringify(status).includes('secret-a-for-test'), false);
  assert.equal(status.connections.find(c => c.id === a).has_api_key, true);
  // Editing a profile keeps its ID, but an older page must not send its context
  // to that profile's new endpoint/account without refreshing the connection.
  assert.equal((await post('/api/agent/connections', { id: b, label: 'Agent B updated', kind: 'agent-http', agent_url: `${bridge}/b-new`, model: 'b' })).status, 200);
  assert.equal((await request(b, status.connection_revision)).status, 409);
  assert.equal((await get(`/api/agent/models?connection_id=${b}&connection_revision=${status.connection_revision}`)).status, 409);
  assert.equal(seen.length, 2);
  pause = true;
  const pending = request(b); await started.promise;
  assert.equal((await post('/api/agent/connections/select', { connection_id: a })).status, 409);
  assert.equal((await post('/api/agent/connections/remove', { connection_id: b })).status, 409);
  assert.equal(connections.state.active, b);
  resume.resolve(); assert.equal((await pending).status, 200); pause = false;
  assert.equal((await post('/api/agent/connections/select', { connection_id: a })).status, 200);
  assert.equal((await request(a)).status, 200);
  assert.equal(seen.at(-1).authorization, 'Bearer secret-a-for-test');
  assert.equal((await post('/api/agent/connections/remove', { connection_id: a })).status, 200);
  assert.equal(connections.state.active, 'chatgpt');
  assert.deepEqual((await store.read('history')).events, history.events);
  assert.equal((await post('/api/agent/connections/remove', { connection_id: 'chatgpt' })).status, 400);
});

test('saved compatible APIs use actual streamed Responses and completed Chat Completions transports', async t => {
  const { store, auth, connections } = await setup(t), seen = [];
  const api = await fixtureServer(t, async (req, res, value) => {
    seen.push({ path: req.url, value, authorization: req.headers.authorization });
    const reply = JSON.stringify(bundle('same', value.model));
    if (req.url === '/v1/responses') {
      res.setHeader('Content-Type', 'text/event-stream');
      res.end(`data: ${JSON.stringify({ type: 'response.completed', response: { status: 'completed', output: [{ content: [{ type: 'output_text', text: reply }] }] } })}\n\n`);
    } else {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ choices: [{ finish_reason: 'stop', message: { content: reply } }] }));
    }
  });
  const gateway = createGateway({ store, auth, connections, providers: connections.provider }), origin = await gateway.listen();
  t.after(() => gateway.close());
  const headers = { 'Content-Type': 'application/json', 'X-Personal-OS': '1' };
  headers['X-Personal-OS-CSRF'] = (await (await fetch(`${origin}/api/agent/status`, { headers })).json()).csrf;
  const post = (path, body) => fetch(`${origin}${path}`, { method: 'POST', headers, body: JSON.stringify(body) });
  for (const kind of ['responses', 'chat-completions']) {
    const saved = await post('/api/agent/connections', { label: kind, kind, base_url: `${api}/v1`, model: 'test-model', api_key: 'test-api-key' });
    assert.equal(saved.status, 200); const id = (await saved.json()).active;
    const result = await post('/api/agent/request', { connection_id: id, connection_revision: connections.state.revision, model: 'test-model', prompt: '读取我的目标', stage: 'proposal', context: '{"session_id":"same"}' });
    assert.equal(result.status, 200);
    assert.equal(JSON.parse((await result.json()).reply).session_id, 'same');
    const checked = await post('/api/agent/check', { connection_id: id, connection_revision: connections.state.revision, model: 'test-model' });
    assert.equal(checked.status, 200);
    assert.deepEqual(await checked.json(), { ok: true, provider: kind, model: 'test-model' });
  }
  assert.deepEqual(seen.map(s => s.path), ['/v1/responses', '/v1/responses', '/v1/chat/completions', '/v1/chat/completions']);
  assert.equal(seen[0].value.stream, true); assert.equal(seen[0].value.store, false);
  assert.equal(seen[2].value.messages[0].content, '读取我的目标');
  assert.equal(seen[2].value.stream, false);
  assert.ok(seen[1].value.input[0].content.includes('No personal data'));
  assert.ok(seen[3].value.messages[0].content.includes('No personal data'));
  assert.ok(seen.every(s => s.authorization === 'Bearer test-api-key'));
});

test('HTTP Agent probe discards replies, preserves history and enforces CSRF, revision and request locks', async t => {
  const { store, auth, connections } = await setup(t);
  const seen = [], started = Promise.withResolvers(), resume = Promise.withResolvers();
  let pause = false, fail = false;
  const bridge = await fixtureServer(t, async (req, res, value) => {
    seen.push(value);
    if (pause) { started.resolve(); await resume.promise; }
    res.setHeader('Content-Type', 'application/json');
    res.statusCode = fail ? 401 : 200;
    res.end(JSON.stringify(fail ? { error: { code: 'invalid_api_key', message: 'never show raw secret' } } : { reply: 'fixture response that must never be returned or imported' }));
  });
  await connections.save({ label: 'Test bridge', kind: 'agent-http', agent_url: `${bridge}/agent`, model: 'test' });
  const history = { revision: 3, events: [{ event_id: 'goal', sensitivity: 'd1', goal: 'private-goal-only' }] };
  await store.write('history', history);
  const gateway = createGateway({ store, auth, connections, providers: connections.provider }), origin = await gateway.listen();
  t.after(() => gateway.close());
  const headers = { 'Content-Type': 'application/json', 'X-Personal-OS': '1' };
  const body = { model: 'test', connection_id: connections.state.active, connection_revision: connections.state.revision, prompt: 'private-client-prompt', context: 'private-client-context' };
  const post = (path, value = body) => fetch(`${origin}${path}`, { method: 'POST', headers, body: JSON.stringify(value) });
  assert.equal((await post('/api/agent/check')).status, 403);
  headers['X-Personal-OS-CSRF'] = (await (await fetch(`${origin}/api/agent/status`, { headers })).json()).csrf;
  const checked = await post('/api/agent/check');
  assert.equal(checked.status, 200);
  assert.deepEqual(await checked.json(), { ok: true, provider: 'agent-http', model: 'test' });
  assert.equal(JSON.stringify(seen).includes('private-'), false);
  assert.deepEqual(seen[0].context.objects, []);
  const schema = JSON.parse(await readFile(new URL('../../../schemas/personal-os-context-v0.schema.json', import.meta.url), 'utf8'));
  for (const field of schema.required) assert.ok(field in seen[0].context, `Probe context missing protocol field ${field}`);
  assert.deepEqual(seen[0].context.scope, { purpose: 'connection test', object_types: [] });
  assert.ok(Number.isFinite(Date.parse(seen[0].context.created_at)));
  assert.equal(seen[0].stage, 'proposal');
  assert.deepEqual(await store.read('history'), history);
  await connections.save({ id: body.connection_id, label: 'Updated', kind: 'agent-http', agent_url: `${bridge}/agent`, model: 'test' });
  assert.equal((await post('/api/agent/check')).status, 409);
  assert.equal(seen.length, 1);
  body.connection_revision = connections.state.revision;
  pause = true;
  const pending = post('/api/agent/check'); await started.promise;
  assert.equal((await post('/api/agent/check')).status, 409);
  assert.equal((await post('/api/agent/request')).status, 409);
  assert.equal((await post('/api/agent/connections/select', { connection_id: 'chatgpt' })).status, 409);
  assert.equal((await post('/api/auth/logout', {})).status, 409);
  resume.resolve(); assert.equal((await pending).status, 200); pause = false;
  fail = true;
  const failed = await post('/api/agent/check');
  assert.equal(failed.status, 502); assert.deepEqual(await failed.json(), { error: 'invalid_api_key' });
  assert.deepEqual(await store.read('history'), history);
});
