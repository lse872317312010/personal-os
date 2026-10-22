import { test } from 'node:test';
import assert from 'node:assert/strict';
import { deploymentDiagnostics } from '../diagnostics.mjs';
import { createGateway } from '../server.mjs';

test('liveness never invokes auth, model or history dependencies', async t => {
  const fail = () => { throw Error('must not call'); };
  const gateway = createGateway({ auth: {}, providers: { status: fail }, store: { read: fail, write: fail } });
  const origin = await gateway.listen(); t.after(() => gateway.close());
  assert.deepEqual(await (await fetch(`${origin}/api/health`, { headers: { 'X-Personal-OS': '1' } })).json(), { ok: true });
});

test('diagnostics only probe allowed paths and redact status secrets without inference', async () => {
  const paths = [];
  const result = await deploymentDiagnostics({ storage: async () => true, cli: async () => true, fetcher: async (url, options) => {
    const path = new URL(url).pathname; paths.push([path, options.method || 'GET']);
    if (path === '/api/health') return Response.json({ ok: true });
    if (path === '/api/agent/status') return Response.json({ provider: 'codex-cli', connected: true, csrf: 'private-token', accounts: ['private-account'], error: 'private-error' });
    return new Response(null, { status: 200 });
  } });
  assert.equal(result.ready, true); assert.equal(result.inference_tested, false);
  assert.deepEqual(paths, [['/api/health', 'GET'], ['/', 'HEAD'], ['/flutter_bootstrap.js', 'HEAD'], ['/main.dart.js', 'HEAD'], ['/fonts/NotoSansSC.ttf', 'HEAD'], ['/api/agent/status', 'GET']]);
  assert.doesNotMatch(JSON.stringify(result), /private-/);
});

test('diagnostic exceptions never leak raw storage, CLI or HTTP details', async () => {
  const fail = async () => { throw Error('private-token'); };
  const result = await deploymentDiagnostics({ storage: fail, cli: fail, fetcher: fail });
  assert.equal(result.ready, false); assert.equal(result.checks.every(check => !check.ok), true);
  assert.equal(JSON.stringify(result).includes('private-token'), false);
});
