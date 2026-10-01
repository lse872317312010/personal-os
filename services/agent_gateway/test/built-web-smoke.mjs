// Production-build smoke test in a disposable CI browser/profile. It makes no
// model inference and has no user credentials. External hosts cannot resolve.
import { mkdtemp, readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import { ProtectedStore } from '../protected-store.mjs';
import { ChatGPTAuth } from '../chatgpt-auth.mjs';
import { AgentProviders } from '../providers.mjs';
import { createGateway } from '../server.mjs';

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const profile = await mkdtemp(join(tmpdir(), 'personal-os-browser-smoke-'));
const store = new ProtectedStore(join(profile, 'app'));
const auth = new ChatGPTAuth(store); await auth.init();
const gateway = createGateway({ store, auth, providers: new AgentProviders(auth), webRoot: resolve('apps/personal_os_app/build/web') });
const origin = await gateway.listen();
const browser = spawn(process.env.CHROME_EXECUTABLE || 'google-chrome', [
  '--headless=new', '--no-sandbox', '--disable-dev-shm-usage',
  '--disable-background-networking', '--no-first-run', '--no-default-browser-check',
  '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
  '--remote-debugging-port=0', `--user-data-dir=${join(profile, 'browser')}`, origin,
], { stdio: 'ignore' });
const browserExited = new Promise(resolve => browser.once('exit', resolve));
let socket;
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
  const call = (method, params = {}) => new Promise((resolve, reject) => { const id = ++next; pending.set(id, { resolve, reject }); socket.send(JSON.stringify({ id, method, params })); });
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
  console.log('Compiled automatic app starts at phone width with local fonts/renderer and no external requests. No account grant or inference was made.');
} finally {
  socket?.close();
  const forceExit = setTimeout(() => browser.kill('SIGKILL'), 5_000);
  browser.kill('SIGTERM');
  try { await browserExited; } finally { clearTimeout(forceExit); }
  await gateway.close();
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
