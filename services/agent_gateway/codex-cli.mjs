import { spawn } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AgentError } from './chatgpt-auth.mjs';

// Deliberately omit API keys, custom providers, and application credentials.
export function cliEnvironment(source = process.env) {
  const env = {};
  for (const name of ['PATH', 'HOME', 'USERPROFILE', 'SYSTEMROOT', 'CODEX_HOME', 'SSL_CERT_FILE', 'CODEX_CA_CERTIFICATE']) {
    if (source[name]) env[name] = source[name];
  }
  return env;
}

function runCli(binary, args, { input = '', signal, cwd, limit = 2_000_000, timeout = 180_000 } = {}) {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) return reject(new AgentError('provider_request_cancelled', 499));
    const child = spawn(binary, args, { cwd, env: cliEnvironment(), shell: false, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '', stderr = '', size = 0, failure;
    const stop = error => {
      failure ||= error;
      child.kill('SIGTERM');
      killTimer ||= setTimeout(() => child.kill('SIGKILL'), 1000);
      killTimer.unref();
    };
    let killTimer;
    const abort = () => stop(new AgentError('provider_request_cancelled', 499));
    signal?.addEventListener('abort', abort, { once: true });
    const timer = setTimeout(() => stop(new AgentError('codex_cli_timeout', 504)), timeout);
    for (const [stream, target] of [[child.stdout, 'stdout'], [child.stderr, 'stderr']]) {
      stream.setEncoding('utf8');
      stream.on('data', chunk => {
        size += Buffer.byteLength(chunk);
        if (size > limit) return stop(new AgentError('provider_reply_too_large', 502));
        if (target === 'stdout') stdout += chunk; else stderr += chunk;
      });
    }
    child.stdin.on('error', () => {}); // Early CLI exit can close stdin.
    child.on('error', error => { failure ||= new AgentError(error.code === 'ENOENT' ? 'codex_cli_not_installed' : 'codex_cli_unavailable', 503); });
    child.on('close', code => {
      clearTimeout(timer); clearTimeout(killTimer); signal?.removeEventListener('abort', abort);
      if (failure) reject(failure); else resolve({ code, stdout, stderr });
    });
    child.stdin.end(input);
  });
}

// Classify only failures. Raw CLI output may contain credentials or prompts;
// return fixed codes and never echo that output to the browser or reports.
export function cliFailure(...outputs) {
  const text = outputs.filter(value => typeof value === 'string').join('\n');
  if (/\b(?:usage_limit_reached|usage_limit_exceeded|insufficient_quota)\b|you['’]ve hit your usage limit|usage limit (?:has been )?reached/i.test(text)) return new AgentError('codex_usage_limit_reached', 429);
  if (/\brate_limit_exceeded\b|too many requests/i.test(text)) return new AgentError('rate_limit_exceeded', 429);
  if (/\b(?:token_expired|invalid_grant|reauthentication_required)\b|please (?:run )?[`"']?codex login/i.test(text)) return new AgentError('sign_in_required', 401);
  return new AgentError('codex_cli_request_failed', 502);
}

export function completedCliReply(output) {
  let reply, completed = false;
  for (const line of output.split('\n').filter(line => line.trim())) {
    let event;
    try { event = JSON.parse(line); } catch { throw new AgentError('invalid_provider_response', 502); }
    if (['error', 'turn.failed'].includes(event.type)) throw cliFailure(JSON.stringify(event));
    if (event.type === 'turn.started') { completed = false; reply = undefined; }
    if (['command_execution', 'file_change', 'mcp_tool_call', 'web_search'].includes(event.item?.type)) throw new AgentError('codex_cli_tools_not_allowed', 502);
    // No intermediate agent message or failed turn is accepted as a proposal.
    if (event.type === 'item.completed' && event.item?.type === 'agent_message') {
      if (completed) throw new AgentError('provider_response_interrupted', 502);
      reply = event.item.text;
    }
    if (event.type === 'turn.completed') completed = true;
  }
  if (!completed || typeof reply !== 'string') throw new AgentError('provider_response_interrupted', 502);
  let envelope;
  try { envelope = JSON.parse(reply); } catch { throw new AgentError('invalid_provider_response', 502); }
  if (typeof envelope.reply !== 'string' || !envelope.reply.trim()) throw new AgentError('invalid_provider_response', 502);
  return envelope.reply;
}

export class CodexCli {
  constructor({ binary = process.env.PERSONAL_OS_CODEX_BIN || 'codex', runner = runCli } = {}) {
    this.binary = binary; this.runner = runner; this.connected = false; this.error = null;
  }
  async status(signal) {
    this.connected = false; this.error = null;
    try {
      const result = await this.runner(this.binary, ['login', 'status'], { signal, timeout: 10_000, limit: 16_000 });
      // Fail closed on API-key auth or an unknown login mode. Never expose output.
      this.connected = result.code === 0 && /Logged in using ChatGPT/i.test(result.stdout + result.stderr);
      if (!this.connected) this.error = /API key/i.test(result.stdout + result.stderr) ? 'codex_chatgpt_login_required' : 'sign_in_required';
    } catch (error) { this.error = error instanceof AgentError ? error.code : 'codex_cli_unavailable'; }
    return { connected: this.connected, error: this.error };
  }
  async request({ model, prompt }, signal) {
    await this.status(signal);
    if (!this.connected) throw new AgentError(this.error || 'sign_in_required', 401);
    const directory = await mkdtemp(join(tmpdir(), 'personal-os-codex-'));
    try {
      const schema = join(directory, 'reply.schema.json');
      await writeFile(schema, JSON.stringify({ type: 'object', properties: { reply: { type: 'string' } }, required: ['reply'], additionalProperties: false }), { mode: 0o600 });
      const args = ['exec', '--json', '--ephemeral', '--ignore-user-config', '--ignore-rules', '--skip-git-repo-check', '--sandbox', 'read-only', '-c', 'approval_policy="never"', '-c', 'forced_login_method="chatgpt"', '-c', 'web_search="disabled"', '--output-schema', schema];
      // Names verified with the pinned CLI's `features list`. Personal OS only
      // needs a text reply, not shell/file/browser/MCP or delegated operations.
      for (const feature of ['shell_tool', 'unified_exec', 'code_mode_host', 'apps', 'plugins', 'hooks', 'multi_agent', 'browser_use', 'computer_use', 'view_image', 'skill_search', 'workspace_dependencies', 'daemon_auto_start']) args.push('--disable', feature);
      if (model !== 'codex-default') args.push('--model', model);
      args.push('-');
      const input = 'Respond only from the supplied task and context. Do not use tools or read files. Return an object with a single string field "reply". That string must contain the complete response requested below (a JSON bundle for a strategy task).\n\n' + prompt;
      const result = await this.runner(this.binary, args, { input, signal, cwd: directory });
      if (result.code !== 0) throw cliFailure(result.stdout, result.stderr);
      return completedCliReply(result.stdout);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
}
