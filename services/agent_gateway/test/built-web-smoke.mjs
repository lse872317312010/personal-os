// Production-build smoke test in a disposable CI browser/profile. It makes no
// real model inference and has no user credentials. External hosts cannot resolve.
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import assert from 'node:assert/strict';
import { ProtectedStore } from '../protected-store.mjs';
import { ChatGPTAuth } from '../chatgpt-auth.mjs';
import { AgentConnections } from '../connections.mjs';
import { createGateway } from '../server.mjs';

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const profile = await mkdtemp(join(tmpdir(), 'personal-os-browser-smoke-'));
const store = new ProtectedStore(join(profile, 'app'));
const auth = new ChatGPTAuth(store); await auth.init();
const connections = await new AgentConnections(store, auth).init();
const gateway = createGateway({ store, auth, connections, providers: connections.provider, webRoot: resolve('apps/personal_os_app/build/web') });
const origin = await gateway.listen();
const browser = spawn(process.env.CHROME_EXECUTABLE || 'google-chrome', [
  '--headless=new', '--no-sandbox', '--disable-dev-shm-usage',
  '--disable-background-networking', '--no-first-run', '--no-default-browser-check',
  '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
  '--remote-debugging-port=0', `--user-data-dir=${join(profile, 'browser')}`, origin,
], { stdio: 'ignore' });
const browserExited = new Promise(resolve => browser.once('exit', resolve));
let socket, fixture, call;
try {
  let port;
  const deadline = Date.now() + 45_000;
  while (Date.now() < deadline && !port) {
    try { port = Number((await readFile(join(profile, 'browser', 'DevToolsActivePort'), 'utf8')).split('\n')[0]); }
    catch { await delay(100); }
  }
  assert.ok(port, 'Disposable Chrome did not start');
  const tabs = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const tab = tabs.find(t => t.type === 'page' && t.url.startsWith(origin));
  assert.ok(tab, 'Compiled app tab was not found');
  socket = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { socket.addEventListener('open', resolve, { once: true }); socket.addEventListener('error', reject, { once: true }); });
  let next = 0;
  const pending = new Map(), requests = [];
  socket.addEventListener('message', message => {
    const value = JSON.parse(message.data);
    if (value.method === 'Network.requestWillBeSent') requests.push(value.params.request.url);
    if (value.id) { const item = pending.get(value.id); if (item) { pending.delete(value.id); value.error ? item.reject(new Error(value.error.message)) : item.resolve(value.result); } }
  });
  call = (method, params = {}) => new Promise((resolve, reject) => { const id = ++next; pending.set(id, { resolve, reject }); socket.send(JSON.stringify({ id, method, params })); });
  await call('Network.enable');
  await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await call('Page.reload', { ignoreCache: true });
  let ready = false;
  while (Date.now() < deadline && !ready) {
    const value = await call('Runtime.evaluate', { expression: "document.querySelector('flt-semantics-placeholder')?.click(); document.body.outerHTML", returnByValue: true });
    const html = value.result.value || '';
    if (html.includes('Continue with ChatGPT') && html.includes('你想达成什么')) {
      const ax = await call('Accessibility.getFullAXTree');
      ready = ax.nodes.some(n => ['button', 'link'].includes(n.role?.value)
        && n.name?.value?.includes('Continue with ChatGPT')
        && !(n.properties || []).some(p => p.name === 'disabled' && p.value?.value === true));
    }
    if (!ready) await delay(200);
  }
  assert.ok(ready, 'Actual compiled app did not show connection and goal controls');
  assert.ok(requests.some(u => u.includes('/fonts/NotoSansSC.ttf')), 'Chinese font was not loaded from the bundle');
  assert.ok(requests.some(u => u.includes('/canvaskit/')), 'Local renderer was not loaded');
  assert.deepEqual(requests.filter(u => !u.startsWith(origin) && !u.startsWith('data:') && !u.startsWith('blob:')), [], 'App startup requested an external host');
  // Let the enabled-control transition finish before visual QA.
  await delay(250);
  const screenshot = await call('Page.captureScreenshot', { format: 'png' });
  await mkdir('build', { recursive: true });
  await writeFile('build/automatic-agent-start.png', Buffer.from(screenshot.data, 'base64'));
  const tree = await call('Accessibility.getFullAXTree');
  const add = tree.nodes.find(n => n.role?.value === 'button' && n.name?.value?.includes('接入其他 AI'));
  assert.ok(add?.backendDOMNodeId, 'Connection setup is not accessible from the app');
  await call('DOM.scrollIntoViewIfNeeded', { backendNodeId: add.backendDOMNodeId });
  const { model } = await call('DOM.getBoxModel', { backendNodeId: add.backendDOMNodeId });
  const x = (model.content[0] + model.content[2]) / 2, y = (model.content[1] + model.content[5]) / 2;
  await call('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
  await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
  let dialogReady = false;
  while (Date.now() < deadline && !dialogReady) {
    const dialog = await call('Accessibility.getFullAXTree');
    dialogReady = dialog.nodes.some(n => n.name?.value?.includes('连接名称'))
      && dialog.nodes.some(n => n.role?.value === 'button' && n.name?.value?.includes('保存并使用'));
    if (!dialogReady) await delay(100);
  }
  assert.ok(dialogReady, 'Connection setup dialog did not open at phone width');
  await delay(250);
  const setupScreenshot = await call('Page.captureScreenshot', { format: 'png' });
  await writeFile('build/automatic-agent-connection.png', Buffer.from(setupScreenshot.data, 'base64'));
  // A second production-browser pass uses an explicit disposable model fixture.
  // It exercises the actual Web -> gateway -> HTTP Agent probe, never OAuth.
  const checks = [];
  fixture = createServer(async (req, res) => {
    const chunks = []; for await (const chunk of req) chunks.push(chunk);
    const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    checks.push(body);
    res.setHeader('Content-Type', 'application/json');
    const refs = type => body.context.objects.filter(o => o.ref.type === type).map(o => o.ref);
    let reply = 'CI fixture acknowledgement, not real model inference.';
    if (refs('goal').length) {
      const bundle = { protocol_version: 'personal-os.mcp.v0', session_id: body.context.session_id, created_at: new Date().toISOString() };
      if (body.stage === 'review') {
        Object.assign(bundle, { review_id: 'ci-quick-feedback-review', review: {
          strategy_ref: refs('strategy').at(-1), summary: 'CI 复盘：只验证用户反馈进入闭环，不判断真实效果。',
          conclusion: 'inconclusive', execution_refs: refs('execution'), outcome_refs: refs('outcome'),
          feedback_refs: [], keep: [], change: [], unknowns: ['CI fixture, not real inference'],
        } });
      } else {
        Object.assign(bundle, { proposal_id: 'ci-quick-feedback-plan', strategy: {
          title: 'CI 行动计划', rationale: 'CI fixture, not real inference', goal_refs: refs('goal'), asset_refs: refs('personal_asset'),
          actions: [{ id: 'ci-action', instruction: '用十分钟复习一个知识点。', success_measure: '记录完成情况。' }],
          assumptions: ['Disposable fixture; no real human action is claimed'],
        } });
      }
      reply = JSON.stringify(bundle);
    }
    res.end(JSON.stringify({ reply }));
  });
  await new Promise(resolve => fixture.listen(0, '127.0.0.1', resolve));
  await connections.save({ label: 'CI 测试模型', kind: 'agent-http', model: `ci-test-${'long-model-name-'.repeat(8)}`, agent_url: `http://127.0.0.1:${fixture.address().port}/agent` });
  const historyBefore = await store.read('history');
  await call('Page.reload', { ignoreCache: true });
  const clickButton = async (label, { expand = false } = {}) => {
    for (let attempt = 0; attempt < 40; attempt++) {
      await call('Runtime.evaluate', { expression: "document.querySelector('flt-semantics-placeholder')?.click()" });
      const ax = await call('Accessibility.getFullAXTree');
      const node = ax.nodes.find(n => n.role?.value === 'button' && n.name?.value?.includes(label)
        && !(n.properties || []).some(p => p.name === 'disabled' && p.value?.value === true));
      if (node?.backendDOMNodeId) {
        let box;
        try { box = await call('DOM.getBoxModel', { backendNodeId: node.backendDOMNodeId }); }
        catch { await delay(150); continue; }
        const x = (box.model.content[0] + box.model.content[2]) / 2, y = (box.model.content[1] + box.model.content[5]) / 2;
        if (y > 40 && y < 790) {
          if (expand) {
            // The connection panel can remain open while startup discovers the
            // saved profile. Do not toggle an already-expanded panel closed.
            const { object } = await call('DOM.resolveNode', { backendNodeId: node.backendDOMNodeId });
            const state = await call('Runtime.callFunctionOn', { objectId: object.objectId, functionDeclaration: 'function() { return this.getAttribute("aria-description"); }', returnByValue: true });
            await call('Runtime.releaseObject', { objectId: object.objectId });
            if (state.result.value === 'Expanded') return;
          }
          await call('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
          await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
          return;
        }
      }
      if (attempt > 5) await call('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 195, y: 600, deltaX: 0, deltaY: 300 });
      await delay(150);
    }
    const unavailable = await call('Accessibility.getFullAXTree');
    console.log('Fixture controls after failed activation:', JSON.stringify(unavailable.nodes.filter(n => n.role?.value === 'button').map(n => ({ name: n.name?.value, properties: n.properties }))));
    throw Error(`Compiled app button unavailable: ${label}`);
  };
  await clickButton('使用 CI 测试模型', { expand: true });
  await delay(250);
  await clickButton('测试 AI 连接');
  let checked = false;
  for (let attempt = 0; attempt < 50 && !checked; attempt++) {
    const ax = await call('Accessibility.getFullAXTree');
    checked = ax.nodes.some(n => n.name?.value?.includes('AI 服务已响应。'));
    if (!checked) await delay(100);
  }
  assert.ok(checked, 'Actual compiled app did not confirm the fixture response');
  assert.equal(checks.length, 1);
  assert.deepEqual(checks[0].context.objects, []);
  assert.deepEqual(await store.read('history'), historyBefore, 'Connection test changed personal history');
  await delay(250);
  const checkScreenshot = await call('Page.captureScreenshot', { format: 'png' });
  await writeFile('build/automatic-agent-check.png', Buffer.from(checkScreenshot.data, 'base64'));
  console.log('Actual compiled app completed a fixture Agent response check without sharing personal context or changing history.');
  // Complete the new feedback interaction in the compiled app itself. Input is
  // disposable CI data; choosing "没做" explicitly avoids claiming execution.
  await call('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 195, y: 500, deltaX: 0, deltaY: -1600 });
  await delay(300);
  const goalDeadline = Date.now() + 15_000;
  let filledGoal = false;
  while (Date.now() < goalDeadline && !filledGoal) {
    const ax = await call('Accessibility.getFullAXTree');
    const goal = ax.nodes.find(n => n.role?.value === 'textbox' && n.name?.value?.startsWith('目标'));
    if (goal?.backendDOMNodeId) {
      const { model } = await call('DOM.getBoxModel', { backendNodeId: goal.backendDOMNodeId });
      const x = (model.content[0] + model.content[2]) / 2, y = (model.content[1] + model.content[5]) / 2;
      if (y > 40 && y < 790) {
        await call('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
        await call('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
        await call('Input.insertText', { text: 'CI 目标：验证一键反馈' });
        filledGoal = true;
      }
    }
    if (!filledGoal) await delay(150);
  }
  assert.ok(filledGoal, 'Compiled app goal input was unavailable');
  await clickButton('保存并生成行动计划');
  await clickButton('就按这个计划开始');
  await delay(250);
  const feedbackScreenshot = await call('Page.captureScreenshot', { format: 'png' });
  await writeFile('build/automatic-agent-feedback.png', Buffer.from(feedbackScreenshot.data, 'base64'));
  await clickButton('这次没做');
  let reviewed = false;
  for (let attempt = 0; attempt < 80 && !reviewed; attempt++) {
    const ax = await call('Accessibility.getFullAXTree');
    reviewed = ax.nodes.some(n => n.role?.value === 'button' && n.name?.value?.includes('确认复盘，准备下一轮'));
    if (!reviewed) await delay(100);
  }
  assert.ok(reviewed, 'Compiled app did not automatically review quick feedback');
  assert.deepEqual(checks.map(c => c.stage), ['proposal', 'proposal', 'review']);
  const historyAfter = await store.read('history');
  const executions = historyAfter.events.filter(e => e.event_type === 'execution.recorded');
  const outcomes = historyAfter.events.filter(e => e.event_type === 'outcome.recorded');
  assert.equal(executions.length, 1);
  assert.equal(executions[0].payload.status, 'skipped');
  assert.equal(outcomes.length, 1);
  assert.equal(outcomes[0].payload.valence, 'neutral');
  assert.equal(outcomes[0].payload.observation, '用户反馈：这次没有执行这一步。');
  assert.equal(outcomes[0].payload.execution_ref.id, executions[0].subject_refs[0].id);
  assert.equal(checks.at(-1).context.objects.filter(o => o.ref.type === 'execution').length, 1);
  await delay(250);
  const reviewScreenshot = await call('Page.captureScreenshot', { format: 'png' });
  await writeFile('build/automatic-agent-feedback-review.png', Buffer.from(reviewScreenshot.data, 'base64'));
  console.log('Compiled Web -> real local gateway -> fixture Agent quick-feedback review passed with one skipped execution and one neutral outcome.');
  console.log('Compiled automatic app starts and opens connection setup at phone width with local fonts/renderer and no external startup requests. No account grant or real model inference was made.');
} catch (error) {
  if (call) {
    try {
      const screenshot = await call('Page.captureScreenshot', { format: 'png' });
      await mkdir('build', { recursive: true });
      await writeFile('build/automatic-agent-check-failure.png', Buffer.from(screenshot.data, 'base64'));
    } catch { /* Preserve the original failure if the disposable browser exited. */ }
  }
  throw error;
} finally {
  socket?.close();
  const forceExit = setTimeout(() => browser.kill('SIGKILL'), 5_000);
  browser.kill('SIGTERM');
  try { await browserExited; } finally { clearTimeout(forceExit); }
  await gateway.close();
  if (fixture) { fixture.closeAllConnections(); await new Promise(resolve => fixture.close(resolve)); }
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
