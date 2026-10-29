import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGateway } from '../server.mjs';

const event = { event_id: 'synthetic-event', sensitivity: 'd2', payload: { text: '中文原文', ref: { type: 'goal', id: 'g', revision: 2 } } };
async function fixture(t) {
  const state = { history: { revision: 0, events: [] }, writes: 0, fail: false, pause: null };
  let entered; state.entered = new Promise(resolve => { entered = resolve; });
  const forbidden = new Proxy({}, { get() { throw Error('Restore must not access AI or credentials'); } });
  const gateway = createGateway({ auth: forbidden, providers: forbidden, store: {
    async read(name, fallback) { assert.equal(name, 'history'); return structuredClone(state.history || fallback); },
    async write(name, value) {
      assert.equal(name, 'history');
      entered();
      if (state.pause) await state.pause;
      if (state.fail) throw Error('private-storage-error');
      state.history = structuredClone(value); state.writes++;
    },
  } });
  const origin = await gateway.listen(); t.after(() => gateway.close());
  const headers = { 'X-Personal-OS': '1', 'Content-Type': 'application/json' };
  const status = await (await fetch(origin + '/api/history/status', { headers })).json();
  assert.deepEqual({ ...status, csrf: 'redacted' }, { revision: 0, empty: true, csrf: 'redacted' });
  headers['X-Personal-OS-CSRF'] = status.csrf;
  const post = (body, extra = {}, path = '/api/history/restore') => fetch(origin + path,
    { method: 'POST', headers: { ...headers, ...extra }, body: JSON.stringify(body) });
  return { state, post, origin, headers };
}

test('restore preserves exact events in an empty store, increments destination revision and rejects repeats/stale tabs', async t => {
  const { state, post } = await fixture(t);
  const body = { revision: 0, events: [event] };
  assert.deepEqual(await (await post(body)).json(), { revision: 1 });
  assert.deepEqual(state.history, { revision: 1, events: [event] });
  assert.equal((await post(body)).status, 409);
  assert.equal((await post({ revision: 1, events: [event] })).status, 409);
  assert.equal((await post({ revision: 0, events: [] }, {}, '/api/history')).status, 409);
  assert.equal(state.writes, 1);
});

test('restore enforces CSRF, custom header, same-origin and independent payload limits without a write', async t => {
  const { state, post } = await fixture(t);
  const body = { revision: 0, events: [event] };
  for (const headers of [{ 'X-Personal-OS': '' }, { 'X-Personal-OS-CSRF': '' }, { Origin: 'https://foreign.invalid' }, { 'Sec-Fetch-Site': 'cross-site' }]) {
    assert.equal((await post(body, headers)).status, 403);
  }
  for (const invalid of [null, { ...body, connections: ['secret'] }, { revision: 0, events: null },
    { revision: 0, events: [event, event] }, { revision: 0, events: [{ ...event, sensitivity: 'D4' }] },
    { revision: 0, events: [{ ...event, event_id: ' ' }] }, { revision: 0, events: Array(20001).fill(event) }]) {
    assert.equal((await post(invalid)).status, 400);
  }
  assert.equal((await post({ revision: 0, events: [{ ...event, payload: 'x'.repeat(8000000) }] })).status, 413);
  assert.equal(state.writes, 0);
  assert.deepEqual(state.history, { revision: 0, events: [] });
});

test('shared write lock prevents competing restore or append, then permits normal append after restoration', async t => {
  const { state, post } = await fixture(t);
  let release;
  state.pause = new Promise(resolve => { release = resolve; });
  const first = post({ revision: 0, events: [event] });
  await state.entered;
  try {
    assert.equal((await post({ revision: 0, events: [] })).status, 409);
    assert.equal((await post({ revision: 0, events: [] }, {}, '/api/history')).status, 409);
  } finally { release(); }
  assert.equal((await first).status, 200);
  state.pause = null;
  const next = { ...event, event_id: 'next-synthetic-event' };
  assert.equal((await post({ revision: 1, events: [event, next] }, {}, '/api/history')).status, 200);
  assert.deepEqual(state.history, { revision: 2, events: [event, next] });
});

test('failed persistence does not publish partial history or expose storage errors; lock is released', async t => {
  const { state, post } = await fixture(t);
  state.fail = true;
  const response = await post({ revision: 0, events: [event] });
  assert.equal(response.status, 503);
  assert.doesNotMatch(await response.text(), /private-storage-error/);
  assert.deepEqual(state.history, { revision: 0, events: [] });
  state.fail = false;
  assert.equal((await post({ revision: 0, events: [event] })).status, 200);
});
