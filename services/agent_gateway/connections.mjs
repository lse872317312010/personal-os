import { randomUUID } from 'node:crypto';
import { AgentError } from './chatgpt-auth.mjs';
import { AgentProviders, endpoint } from './providers.mjs';

const kinds = new Set(['responses', 'chat-completions', 'agent-http']);
const defaultConnection = () => ({ id: 'chatgpt', label: 'ChatGPT', config: { kind: 'chatgpt' } });
function text(value, limit, optional = false) {
  if (value == null && optional) return '';
  if (typeof value !== 'string' || value.length > limit || /[\u0000-\u001f\u007f]/.test(value)) throw new AgentError('invalid_connection');
  return value.trim();
}

// Only this service reads credentials back. Public summaries are built field by
// field, never by spreading a stored connection or provider configuration.
export class AgentConnections {
  constructor(store, auth, initial = {}, fetcher = fetch) {
    this.store = store; this.auth = auth; this.initial = initial; this.fetcher = fetcher;
  }
  async init() {
    const saved = await this.store.read('connections');
    if (saved) {
      if (saved.version !== 1 || typeof saved.revision !== 'string' || !Array.isArray(saved.entries) || !saved.entries.some(e => e.id === saved.active) || !saved.entries.some(e => e.id === 'chatgpt')) throw new AgentError('invalid_connection_store', 503);
      this.state = saved;
    } else {
      this.state = { version: 1, revision: randomUUID(), active: 'chatgpt', entries: [defaultConnection()] };
      if (this.initial.kind && this.initial.kind !== 'chatgpt') {
        const entry = { id: randomUUID(), label: '启动配置', config: this.normalize({ kind: this.initial.kind, base_url: this.initial.baseUrl, agent_url: this.initial.agentUrl, model: this.initial.model, api_key: this.initial.apiKey }) };
        this.state.entries.push(entry); this.state.active = entry.id;
      }
      await this.store.write('connections', this.state);
    }
    this.provider = new AgentProviders(this.auth, this.current.config, this.fetcher);
    return this;
  }
  get current() { return this.state.entries.find(e => e.id === this.state.active); }
  get summaries() {
    return this.state.entries.map(e => ({ id: e.id, label: e.label, kind: e.config.kind, base_url: e.config.baseUrl || '', agent_url: e.config.agentUrl || '', model: e.config.model || '', has_api_key: !!e.config.apiKey }));
  }
  normalize(body, previous) {
    if (!kinds.has(body.kind)) throw new AgentError('invalid_connection');
    const model = text(body.model, 256);
    if (!model) throw new AgentError('connection_model_required');
    let url;
    try { url = endpoint(text(body.kind === 'agent-http' ? body.agent_url : body.base_url, 2048)); }
    catch { throw new AgentError('invalid_provider_endpoint'); }
    const config = { kind: body.kind, model, ...(body.kind === 'agent-http' ? { agentUrl: url } : { baseUrl: url }) };
    const key = text(body.api_key, 8192, true);
    // Never reuse a service's secret at a different endpoint or protocol.
    const sameDestination = previous?.kind === config.kind && (previous.agentUrl || previous.baseUrl) === url;
    if (key) config.apiKey = key;
    else if (sameDestination && body.clear_api_key !== true && previous.apiKey) config.apiKey = previous.apiKey;
    return config;
  }
  async commit(next) {
    next = { ...next, revision: randomUUID() };
    const current = next.entries.find(e => e.id === next.active);
    const provider = new AgentProviders(this.auth, current.config, this.fetcher);
    await this.store.write('connections', next);
    this.state = next; this.provider = provider;
  }
  async save(body) {
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new AgentError('invalid_connection');
    const old = body.id ? this.state.entries.find(e => e.id === body.id) : null;
    if (body.id && (!old || old.id === 'chatgpt')) throw new AgentError('invalid_connection');
    if (!old && this.state.entries.length >= 20) throw new AgentError('connection_limit');
    const label = text(body.label, 80);
    if (!label) throw new AgentError('connection_name_required');
    const entry = { id: old?.id || randomUUID(), label, config: this.normalize(body, old?.config) };
    const entries = old ? this.state.entries.map(e => e.id === old.id ? entry : e) : [...this.state.entries, entry];
    await this.commit({ version: 1, active: entry.id, entries });
  }
  async select(id) {
    if (!this.state.entries.some(e => e.id === id)) throw new AgentError('connection_not_found');
    await this.commit({ ...this.state, active: id });
  }
  async remove(id) {
    if (id === 'chatgpt' || !this.state.entries.some(e => e.id === id)) throw new AgentError('connection_not_found');
    await this.commit({ version: 1, active: this.state.active === id ? 'chatgpt' : this.state.active, entries: this.state.entries.filter(e => e.id !== id) });
  }
}
