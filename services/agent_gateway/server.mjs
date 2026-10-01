import { createServer } from 'node:http';
import { readFile, mkdir, open, unlink } from 'node:fs/promises';
import { resolve, join, extname, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { randomBytes } from 'node:crypto';
import { ProtectedStore } from './protected-store.mjs';
import { AgentError, ChatGPTAuth } from './chatgpt-auth.mjs';
import { AgentConnections } from './connections.mjs';

const root = dirname(fileURLToPath(import.meta.url));
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json', '.wasm': 'application/wasm', '.png': 'image/png', '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.woff2': 'font/woff2' };
const send = (response, status, value) => { response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); response.end(JSON.stringify(value)); };
async function jsonBody(request) {
  if (!request.headers['content-type']?.startsWith('application/json')) throw new AgentError('json_required', 415);
  const chunks = []; let size = 0;
  for await (const chunk of request) { size += chunk.length; if (size > 8_000_000) throw new AgentError('request_too_large', 413); chunks.push(chunk); }
  // A Chinese character may span TCP chunks. Decode only the complete body,
  // and reject malformed UTF-8 rather than persisting replacement characters.
  try { return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(chunks))); } catch { throw new AgentError('invalid_json'); }
}

export function createGateway({ auth, providers, connections = null, store, webRoot = join(root, 'web') }) {
  const csrf = randomBytes(32).toString('base64url');
  let origin, busy = null, authBusy = false, historyWriting = false, connectionWriting = false;
  const server = createServer(async (request, response) => {
    const controller = new AbortController();
    response.on('close', () => { if (!response.writableEnded) controller.abort(); });
    try {
      if (request.headers.host !== new URL(origin).host) throw new AgentError('invalid_host', 403);
      const url = new URL(request.url, origin);
      const provider = connections?.provider || providers;
      if (url.pathname === '/connect' && request.method === 'GET' && request.headers['sec-fetch-site'] !== 'cross-site' && (!request.headers.origin || request.headers.origin === origin)) {
        const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>连接 Personal OS</title><style>body{font:17px system-ui;max-width:480px;margin:12vh auto;padding:24px;background:#f3f7f3;color:#123c32}button,select{font:inherit;padding:12px;border-radius:10px;width:100%;margin:12px 0}button{background:#123c32;color:white;border:0}a{color:#315c4c}</style><h1>连接你的 ChatGPT</h1><p>登录后，Personal OS 会自动发送当前目标、现状及相关行动历史，并接收行动计划和复盘。凭据保存在本机。</p><select id="account"><option value="">添加 ChatGPT 账号 / 工作区</option></select><button id="start">Continue with ChatGPT</button><p id="message"></p><a href="/">返回应用</a><script>const accounts=${JSON.stringify(auth.accounts).replace(/</g, '\\u003c')};for(const a of accounts){const o=document.createElement('option');o.value=a.id;o.textContent=a.label;document.querySelector('select').append(o)}document.querySelector('select').value=${JSON.stringify(auth.state.active || '')};document.querySelector('button').onclick=async()=>{document.querySelector('button').disabled=true;try{const r=await fetch('/api/auth/start',{method:'POST',headers:{'Content-Type':'application/json','X-Personal-OS':'1','X-Personal-OS-CSRF':'${csrf}'},body:JSON.stringify({account_id:document.querySelector('select').value||null})});const v=await r.json();if(!r.ok)throw Error();location.assign(v.url)}catch{document.querySelector('#message').textContent='连接暂不可用，请返回应用重试。';document.querySelector('button').disabled=false}}</script>`;
        response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "frame-ancestors 'none'" }); response.end(html); return;
      }
      if (url.pathname === '/auth/callback' && request.method === 'GET') {
        if (authBusy || busy || connectionWriting) throw new AgentError('agent_busy', 409);
        authBusy = true;
        let account;
        try { account = await auth.callback(url.searchParams); } finally { authBusy = false; }
        if (!account.welcomed) {
          account.welcomed = true; await auth.save();
          response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' });
          response.end('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>ChatGPT 已连接</title><style>body{font:18px system-ui;max-width:480px;margin:15vh auto;padding:24px;color:#123c32}a{display:block;margin:24px 0;color:#315c4c}</style><h1>你正在使用 ChatGPT 订阅</h1><p>Personal OS 的 AI 请求会使用你的 ChatGPT 订阅或额度。计划、复盘和下一轮自动接收。</p><a href="https://chatgpt.com/#settings/Usage" target="_blank" rel="noopener">管理 ChatGPT 用量</a><a href="/">知道了，进入应用 →</a>'); return;
        }
        response.writeHead(303, { Location: '/', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer' }); response.end(); return;
      }
      // OAuth comes back from auth.openai.com as a cross-site navigation. It is
      // authorized by one-use state/PKCE/nonce, not by same-origin API rules.
      if (request.headers.origin && request.headers.origin !== origin) throw new AgentError('foreign_origin', 403);
      if (request.headers['sec-fetch-site'] === 'cross-site') throw new AgentError('foreign_origin', 403);
      if (url.pathname.startsWith('/api/')) {
        if (request.headers['x-personal-os'] !== '1') throw new AgentError('local_client_required', 403);
        if (request.method !== 'GET' && request.headers['x-personal-os-csrf'] !== csrf) throw new AgentError('invalid_csrf', 403);
        if (url.pathname === '/api/agent/status' && request.method === 'GET') {
          send(response, 200, { provider: provider.id, connected: provider.connected, csrf, account: auth.account?.client_id || null, accounts: auth.accounts, connection_id: connections?.state.active || null, connection_revision: connections?.state.revision || null, connection_name: connections?.current.label || null, connections: connections?.summaries || [] }); return;
        }
        if (url.pathname === '/api/agent/models' && request.method === 'GET') {
          if (connections && (url.searchParams.get('connection_id') !== connections.state.active || url.searchParams.get('connection_revision') !== connections.state.revision)) throw new AgentError('connection_changed', 409);
          send(response, 200, { models: await provider.models() }); return;
        }
        if (url.pathname === '/api/agent/connections' && request.method === 'GET') {
          if (!connections) throw new AgentError('connection_settings_unavailable', 503);
          send(response, 200, { active: connections.state.active, connections: connections.summaries }); return;
        }
        if (['/api/agent/connections', '/api/agent/connections/select', '/api/agent/connections/remove'].includes(url.pathname) && request.method === 'POST') {
          if (!connections) throw new AgentError('connection_settings_unavailable', 503);
          if (busy || authBusy || connectionWriting) throw new AgentError('agent_busy', 409);
          connectionWriting = true;
          try {
            const body = await jsonBody(request);
            if (url.pathname.endsWith('/select')) await connections.select(body.connection_id);
            else if (url.pathname.endsWith('/remove')) await connections.remove(body.connection_id);
            else await connections.save(body);
            send(response, 200, { active: connections.state.active, connections: connections.summaries });
          } finally { connectionWriting = false; }
          return;
        }
        if (url.pathname === '/api/auth/start' && request.method === 'POST') {
          if (busy || authBusy || connectionWriting) throw new AgentError('agent_busy', 409);
          const body = await jsonBody(request);
          send(response, 200, { url: await auth.begin(origin, body.account_id) }); return;
        }
        if (url.pathname === '/api/auth/select' && request.method === 'POST') {
          if (busy || authBusy || connectionWriting) throw new AgentError('agent_busy', 409);
          const body = await jsonBody(request); await auth.select(body.account_id); send(response, 200, { ok: true }); return;
        }
        if (url.pathname === '/api/auth/logout' && request.method === 'POST') {
          if (busy || authBusy || connectionWriting) throw new AgentError('agent_busy', 409);
          authBusy = true;
          try { send(response, 200, await auth.logout()); } finally { authBusy = false; } return;
        }
        if (url.pathname === '/api/history' && request.method === 'GET') { send(response, 200, await store.read('history', { revision: 0, events: [] })); return; }
        if (url.pathname === '/api/history' && request.method === 'POST') {
          if (historyWriting) throw new AgentError('history_conflict', 409);
          historyWriting = true;
          try {
            const body = await jsonBody(request), old = await store.read('history', { revision: 0, events: [] });
            if (body.revision !== old.revision) throw new AgentError('history_conflict', 409);
            if (!Array.isArray(body.events) || body.events.length > 20_000 || body.events.some(e => !e || typeof e.event_id !== 'string' || ['d4', 'D4'].includes(e.sensitivity))) throw new AgentError('invalid_history');
            // Append only: a stale or tampered client cannot erase old history.
            if (body.events.length < old.events.length || old.events.some((e, i) => JSON.stringify(e) !== JSON.stringify(body.events[i]))) throw new AgentError('history_conflict', 409);
            const next = { revision: old.revision + 1, events: body.events }; await store.write('history', next); send(response, 200, { revision: next.revision });
          } finally { historyWriting = false; } return;
        }
        if (url.pathname === '/api/agent/request' && request.method === 'POST') {
          if (busy || authBusy || connectionWriting) throw new AgentError('agent_busy', 409);
          if (!provider.connected) throw new AgentError('sign_in_required', 401);
          busy = controller;
          const timeout = setTimeout(() => controller.abort(), 180_000);
          try {
            const body = await jsonBody(request);
            if (connections && (body.connection_id !== connections.state.active || body.connection_revision !== connections.state.revision)) throw new AgentError('connection_changed', 409);
            const reply = await provider.request(body, controller.signal);
            let bundle, context;
            try { bundle = JSON.parse(reply); context = JSON.parse(body.context); } catch { throw new AgentError('invalid_agent_bundle', 502); }
            if (bundle.protocol_version !== 'personal-os.mcp.v0' || bundle.session_id !== context.session_id || (body.stage === 'review' ? !bundle.review || bundle.strategy : !bundle.strategy || bundle.review)) throw new AgentError('invalid_agent_bundle', 502);
            send(response, 200, { reply, provider: provider.id, model: body.model });
          } finally { clearTimeout(timeout); busy = null; } return;
        }
        throw new AgentError('not_found', 404);
      }
      if (!['GET', 'HEAD'].includes(request.method)) throw new AgentError('not_found', 404);
      const path = resolve(webRoot, `.${decodeURIComponent(url.pathname)}`);
      if (path !== resolve(webRoot) && !path.startsWith(`${resolve(webRoot)}/`) && !path.startsWith(`${resolve(webRoot)}\\`)) throw new AgentError('not_found', 404);
      let target = url.pathname === '/' ? join(webRoot, 'index.html') : path;
      let content;
      try { content = await readFile(target); } catch { throw new AgentError('web_build_missing', 404); }
      response.writeHead(200, { 'Content-Type': types[extname(target)] || 'application/octet-stream', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff', 'Content-Security-Policy': "frame-ancestors 'none'" });
      response.end(request.method === 'HEAD' ? undefined : content);
    } catch (error) {
      if (request.url?.startsWith('/auth/callback') && request.headers.accept?.includes('text/html') && !response.headersSent && !response.destroyed) {
        const message = error.code === 'authorization_denied' ? '你取消了授权。可以返回应用重新连接。' : error.code === 'plan_permission_missing' ? '本次授权没有启用 ChatGPT 订阅使用权限，请返回应用重新连接并确认权限。' : '本次登录未完成，请返回应用重新连接。';
        response.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "frame-ancestors 'none'" });
        response.end(`<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>连接未完成</title><style>body{font:18px system-ui;max-width:480px;margin:15vh auto;padding:24px;color:#123c32}a{color:#315c4c}</style><h1>ChatGPT 连接未完成</h1><p>${message}</p><a href="/">返回应用 →</a>`); return;
      }
      if (!response.headersSent && !response.destroyed) send(response, error instanceof AgentError ? error.status : 503, { error: error instanceof AgentError ? error.code : controller.signal.aborted ? 'provider_request_cancelled' : 'service_unavailable' });
    }
  });
  return {
    server,
    async listen(port = 0) { await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); }); origin = `http://127.0.0.1:${server.address().port}`; return origin; },
    close() { busy?.abort(); server.closeAllConnections(); return new Promise(resolve => server.close(resolve)); },
  };
}

async function main() {
  const directory = process.env.PERSONAL_OS_PROFILE || join(process.env.LOCALAPPDATA || homedir(), '.personal-os-agent');
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const lockPath = join(directory, 'runtime.lock');
  // One process per profile prevents refresh-token rotation and history races.
  let lock;
  try { lock = await open(lockPath, 'wx', 0o600); await lock.writeFile(String(process.pid)); }
  catch (error) {
    if (error.code !== 'EEXIST') throw error;
    const pid = Number(await readFile(lockPath, 'utf8'));
    try { process.kill(pid, 0); throw new AgentError('runtime_already_running'); }
    catch (probe) { if (probe.code !== 'ESRCH') throw probe; await unlink(lockPath); return main(); }
  }
  const cleanup = async () => { await lock.close(); await unlink(lockPath).catch(() => {}); };
  try {
    const store = new ProtectedStore(directory), auth = new ChatGPTAuth(store); await auth.init();
    const connections = await new AgentConnections(store, auth, { kind: process.env.PERSONAL_OS_PROVIDER || 'chatgpt', baseUrl: process.env.PERSONAL_OS_BASE_URL, agentUrl: process.env.PERSONAL_OS_AGENT_URL, apiKey: process.env.PERSONAL_OS_API_KEY, model: process.env.PERSONAL_OS_MODEL }).init();
    const gateway = createGateway({ auth, providers: connections.provider, connections, store, webRoot: process.env.PERSONAL_OS_WEB_ROOT || join(root, 'web') });
    const url = await gateway.listen(Number(process.env.PERSONAL_OS_PORT || 8787));
    console.log(`Personal OS: ${url}\nKeep this window open. No credentials or personal prompts are logged.`);
    if (process.env.PERSONAL_OS_OPEN_BROWSER === '1') {
      const { spawn } = await import('node:child_process');
      if (process.platform === 'win32') spawn('cmd.exe', ['/c', 'start', '', url], { windowsHide: true });
      else spawn(process.platform === 'darwin' ? 'open' : 'xdg-open', [url], { stdio: 'ignore' }).on('error', () => {});
    }
    for (const signal of ['SIGINT', 'SIGTERM']) process.once(signal, async () => { await gateway.close(); await cleanup(); process.exit(0); });
  } catch (error) { await cleanup(); throw error; }
}
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main().catch(error => { console.error(error instanceof AgentError ? error.code : 'Unable to start Personal OS local runtime.'); process.exitCode = 1; });
