import { test } from 'node:test';
import assert from 'node:assert/strict';
import { historyExport } from '../history-export.mjs';
import { createGateway } from '../server.mjs';

const fixture = () => ({ revision: 7, events: [{ event_id: 'synthetic-event', sensitivity: 'd1', payload: { observation: '中文反馈 </script> 保留原文', refs: [{ type: 'goal', id: 'one', revision: 2 }] } }] });

test('export preserves event contents and versions but not other namespaces or outer fields', () => {
  const source = { ...fixture(), access_token: 'private-token', installation_key: 'private-key', connections: ['private-connection'] };
  const result = historyExport(source, new Date('2026-10-30T00:00:00Z'));
  assert.deepEqual(result, { format: 'personal-os.web-history.v1', exported_at: '2026-10-30T00:00:00.000Z', source_revision: 7, events: source.events });
  assert.doesNotMatch(JSON.stringify(result), /private-token|private-key|private-connection/);
  result.events[0].payload.observation = 'changed copy';
  assert.equal(source.events[0].payload.observation, '中文反馈 </script> 保留原文');
});

test('empty history exports; corrupt history and D4 are refused without repairing or changing it', () => {
  assert.deepEqual(historyExport({ revision: 0, events: [] }).events, []);
  for (const value of [{ revision: -1, events: [] }, { revision: 1, events: null }, { revision: 1, events: [null] }, { revision: 1, events: [{ event_id: 'one', sensitivity: 'D4' }] }]) {
    const before = structuredClone(value);
    assert.throws(() => historyExport(value), { code: 'invalid_history' });
    assert.deepEqual(value, before);
  }
});

async function setup(t) {
  const source = fixture(), reads = [];
  const forbidden = new Proxy({}, { get() { throw Error('Export must not access auth or AI'); } });
  const gateway = createGateway({ auth: forbidden, providers: forbidden, store: {
    async read(name) { reads.push(name); assert.equal(name, 'history'); return source; },
    async write() { throw Error('Export must not write'); },
  } });
  const origin = await gateway.listen();
  t.after(() => gateway.close());
  return { origin, reads, source };
}

test('real HTTP export retains same-origin and custom-header boundaries and never touches auth or AI', async t => {
  const { origin, reads, source } = await setup(t);
  for (const headers of [{}, { 'X-Personal-OS': '1', Origin: 'https://foreign.invalid' }, { 'X-Personal-OS': '1', 'Sec-Fetch-Site': 'cross-site' }]) {
    assert.equal((await fetch(origin + '/api/history/export', { headers })).status, 403);
  }
  assert.deepEqual(reads, []);
  const response = await fetch(origin + '/api/history/export', { headers: { 'X-Personal-OS': '1' } });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('cache-control'), 'no-store');
  assert.match(response.headers.get('content-disposition'), /attachment/);
  assert.deepEqual((await response.json()).events, source.events);
  assert.deepEqual(reads, ['history']);
  assert.equal(source.revision, 7);
});

test('download page embeds no history and refuses cross-site access', async t => {
  const { origin, reads } = await setup(t);
  const response = await fetch(origin + '/history-export');
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-security-policy'), /frame-ancestors 'none'/);
  const html = await response.text();
  assert.match(html, /下载历史 JSON/);
  assert.doesNotMatch(html, /synthetic-event|中文反馈/);
  assert.deepEqual(reads, []);
  assert.equal((await fetch(origin + '/history-export', { headers: { 'Sec-Fetch-Site': 'cross-site' } })).status, 403);
});
