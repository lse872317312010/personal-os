// Production-build smoke test in a disposable CI browser/profile. It makes no
// model inference and has no user credentials. External hosts cannot resolve.
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
    checks.push(JSON.parse(Buffer.concat(chunks).toString('utf8')));
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify({ reply: 'CI fixture acknowledgement, not real model inference.' }));
  });
  await new Promise(resolve => fixture.listen(0, '127.0.0.1', resolve));
  await connections.save({ label: 'CI 测试模型', kind: 'agent-http', model: `ci-test-${'long-model-name-'.repeat(8)}`, agent_url: `http://127.0.0.1:${fixture.address().port}/agent` });
  const historyBefore = await store.read('history');
  await call('Page.reload', { ignoreCache: true });
  const clickButton = async label => {
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
          // Activate the actual accessible DOM button. Flutter's semantic box
          // can differ from its canvas hit area during an expansion animation.
          const { object } = await call('DOM.resolveNode', { backendNodeId: node.backendDOMNodeId });
          await call('Runtime.callFunctionOn', { objectId: object.objectId, functionDeclaration: 'function() { this.click(); }' });
          await call('Runtime.releaseObject', { objectId: object.objectId });
          return;
        }
      }
      if (attempt > 5) await call('Input.dispatchMouseEvent', { type: 'mouseWheel', x: 195, y: 600, deltaX: 0, deltaY: 300 });
      await delay(150);
    }
    throw Error(`Compiled app button unavailable: ${label}`);
  };
  await clickButton('使用 CI 测试模型');
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
