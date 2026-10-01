import { AgentError } from './chatgpt-auth.mjs';

const allowedErrors = new Set(['subscription_sharing_usage_limit_exceeded', 'subscription_sharing_usage_unavailable', 'rate_limit_exceeded', 'insufficient_quota', 'invalid_api_key']);
function providerError(code) { return new AgentError(allowedErrors.has(code) ? code : 'provider_request_failed', 502); }
export function endpoint(value) {
  const url = new URL(value);
  if (url.protocol === 'http:' && url.hostname === 'localhost') url.hostname = '127.0.0.1';
  if ((url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(url.hostname))) || url.username || url.password || url.hash || url.search) throw new AgentError('invalid_provider_endpoint');
  return url.href.replace(/\/$/, '');
}

// Do not import deltas as a completed proposal. A quota failure may arrive
// after useful-looking output; interrupted, incomplete and refused results fail.
export async function completedResponse(body) {
  const decoder = new TextDecoder();
  let buffer = '', deltas = '', completed = null;
  for await (const chunk of body) {
    buffer = (buffer + decoder.decode(chunk, { stream: true })).replace(/\r\n/g, '\n');
    if (buffer.length + deltas.length > 2_000_000) throw new AgentError('provider_reply_too_large', 502);
    let position;
    while ((position = buffer.indexOf('\n\n')) >= 0) {
      const frame = buffer.slice(0, position); buffer = buffer.slice(position + 2);
      const data = frame.split('\n').filter(line => line.startsWith('data:')).map(line => line.slice(5).trimStart()).join('\n');
      if (!data || data === '[DONE]') continue;
      let event;
      try { event = JSON.parse(data); } catch { throw new AgentError('invalid_provider_response', 502); }
      if (event.type === 'response.output_text.delta') deltas += event.delta || '';
      if (['response.failed', 'error'].includes(event.type)) throw providerError(event.response?.error?.code || event.code);
      if (event.type === 'response.incomplete') throw new AgentError('provider_response_incomplete', 502);
      if (event.type?.includes('refusal')) throw new AgentError('provider_refused', 502);
      if (event.type === 'response.completed') {
        const response = event.response;
        if (response?.status !== 'completed') throw new AgentError('provider_response_incomplete', 502);
        const output = response.output?.flatMap(item => item.content || []) || [];
        if (output.some(part => part.type === 'refusal')) throw new AgentError('provider_refused', 502);
        completed = output.filter(part => part.type === 'output_text').map(part => part.text).join('') || deltas;
      }
    }
  }
  if (!completed?.trim() || buffer.trim()) throw new AgentError('provider_response_interrupted', 502);
  return completed;
}

export class AgentProviders {
  constructor(auth, config = {}, fetcher = fetch) {
    this.auth = auth; this.fetcher = fetcher; this.config = config;
    if (config.baseUrl) this.base = endpoint(config.baseUrl);
    if (config.agentUrl) this.agentUrl = endpoint(config.agentUrl);
    if ((['responses', 'chat-completions'].includes(this.id) && !this.base) || (this.id === 'agent-http' && !this.agentUrl) || !['chatgpt', 'responses', 'chat-completions', 'agent-http'].includes(this.id)) throw new AgentError('invalid_provider_configuration');
  }
  get id() { return this.config.kind || 'chatgpt'; }
  get connected() { return this.id === 'chatgpt' ? this.auth.connected : !!(this.config.model && (this.agentUrl || this.base)); }
  async credential() { return this.id === 'chatgpt' ? this.auth.accessToken() : this.config.apiKey; }
  async models() {
    if (this.id !== 'chatgpt') return this.connected ? [{ id: this.config.model, name: this.config.model }] : [];
    const response = await this.fetcher('https://api.openai.com/v1/models', { headers: { Authorization: `Bearer ${await this.credential()}` }, signal: AbortSignal.timeout(30_000), redirect: 'error' });
    if (!response.ok) throw providerError((await response.json()).error?.code);
    const value = await response.json();
    if (!Array.isArray(value.models)) throw new AgentError('invalid_model_catalog', 502);
    return value.models.filter(m => m.visibility === 'list' && typeof m.slug === 'string').map(m => ({ id: m.slug, name: m.display_name || m.slug }));
  }
  async request({ model, prompt, context, stage }, signal) {
    const models = await this.models();
    if (!models.some(m => m.id === model)) throw new AgentError('model_not_available');
    if (!['proposal', 'review', 'revision'].includes(stage) || typeof prompt !== 'string' || !prompt.trim() || typeof context !== 'string') throw new AgentError('invalid_agent_request');
    const headers = { 'Content-Type': 'application/json' };
    const credential = await this.credential();
    if (credential) headers.Authorization = `Bearer ${credential}`;
    let url, payload;
    if (this.id === 'agent-http') {
      url = this.agentUrl;
      payload = { protocol_version: 'personal-os.agent-gateway.v1', model, stage, prompt, context: JSON.parse(context) };
    } else if (this.id === 'chat-completions') {
      url = `${this.base}/chat/completions`;
      payload = { model, messages: [{ role: 'user', content: prompt }], stream: false };
    } else if (['chatgpt', 'responses'].includes(this.id)) {
      url = `${this.id === 'chatgpt' ? 'https://api.openai.com/v1' : this.base}/responses`;
      payload = { model, input: [{ role: 'user', content: prompt }], store: false, stream: true };
    } else throw new AgentError('provider_not_supported');
    const response = await this.fetcher(url, { method: 'POST', headers, body: JSON.stringify(payload), signal, redirect: 'error' });
    if (!response.ok) { let code; try { code = (await response.json()).error?.code; } catch { /* no raw response in diagnostics */ } throw providerError(code); }
    if (['chatgpt', 'responses'].includes(this.id)) return completedResponse(response.body);
    const value = await response.json();
    const reply = this.id === 'agent-http' ? (typeof value.reply === 'string' ? value.reply : value.bundle && JSON.stringify(value.bundle)) : value.choices?.[0]?.finish_reason === 'stop' && value.choices[0].message?.content;
    if (typeof reply !== 'string' || !reply.trim() || reply === undefined || reply.length > 2_000_000) throw new AgentError('invalid_provider_response', 502);
    return reply;
  }
}
