import { createHash, randomBytes, randomUUID, createPublicKey, verify, timingSafeEqual } from 'node:crypto';

const issuer = 'https://auth.openai.com';
const resource = 'https://api.openai.com/v1';
const tokenEndpoint = `${issuer}/api/accounts/oauth/token`;
const random = () => randomBytes(32).toString('base64url');
const same = (a, b) => typeof a === 'string' && typeof b === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const scopes = token => typeof token.scope === 'string' ? token.scope.split(/\s+/).filter(Boolean) : [];

export class AgentError extends Error {
  constructor(code, status = 400) { super(code); this.code = code; this.status = status; }
}

export class ChatGPTAuth {
  constructor(store, fetcher = fetch) { this.store = store; this.fetcher = fetcher; this.pending = new Map(); this.refreshing = null; }
  async init() {
    this.state = await this.store.read('chatgpt', { hostId: `urn:uuid:${randomUUID()}`, accounts: [], active: null });
    await this.save();
  }
  save() { return this.store.write('chatgpt', this.state); }
  get account() { return this.state.accounts.find(a => a.client_id === this.state.active); }
  get connected() { return !!this.account?.refresh_token && this.account.scopes?.includes('chatgpt.tokens.use.direct'); }
  get accounts() { return this.state.accounts.map(a => ({ id: a.client_id, label: `${a.email || 'ChatGPT'} · ${a.client_id.slice(-6)}`, connected: !!a.refresh_token })); }
  async begin(origin, accountId) {
    const account = accountId ? this.state.accounts.find(a => a.client_id === accountId) : null;
    if (accountId && !account) throw new AgentError('account_not_found');
    const attempt = { state: random(), nonce: random(), verifier: random(), redirect: `${origin}/auth/callback`, account, expires: Date.now() + 10 * 60_000 };
    this.pending.clear();
    this.pending.set(attempt.state, attempt);
    const url = new URL(`${issuer}/api/accounts/authorize`);
    const params = {
      client_id: account?.client_id || 'dynamic_agent_client', ext_agent_host_id: this.state.hostId,
      response_type: 'code', redirect_uri: attempt.redirect,
      scope: 'openid profile email offline_access resource.invoke chatgpt.tokens.use.direct', resource,
      state: attempt.state, nonce: attempt.nonce, code_challenge_method: 'S256',
      code_challenge: createHash('sha256').update(attempt.verifier).digest('base64url'),
    };
    if (account?.id_token) params.id_token_hint = account.id_token;
    if (!account) params.agent_name_hint = 'Personal OS';
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value));
    return url.href;
  }
  async form(url, body) {
    const response = await this.fetcher(url, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams(body), signal: AbortSignal.timeout(30_000), redirect: 'error' });
    const value = await response.json();
    if (!response.ok) throw new AgentError(['invalid_grant', 'invalid_client', 'access_denied'].includes(value.error) ? value.error : 'authorization_unavailable', response.status >= 500 ? 503 : 401);
    return value;
  }
  async discovery() {
    const response = await this.fetcher(`${issuer}/.well-known/openid-configuration`, { signal: AbortSignal.timeout(30_000), redirect: 'error' });
    if (!response.ok) throw new AgentError('authorization_unavailable', 503);
    const document = await response.json();
    if (document.issuer !== issuer) throw new AgentError('invalid_identity');
    for (const field of ['jwks_uri', 'revocation_endpoint']) {
      const endpoint = new URL(document[field]);
      if (endpoint.origin !== issuer) throw new AgentError('invalid_identity');
    }
    return document;
  }
  async validate(token, clientId, nonce) {
    try {
      const [header, body, signature, extra] = token.split('.');
      if (!signature || extra) throw new Error();
      const h = JSON.parse(Buffer.from(header, 'base64url'));
      const claims = JSON.parse(Buffer.from(body, 'base64url'));
      if (!['RS256', 'ES256'].includes(h.alg)) throw new Error();
      const config = await this.discovery();
      const response = await this.fetcher(config.jwks_uri, { signal: AbortSignal.timeout(30_000), redirect: 'error' });
      if (!response.ok) throw new Error();
      const keys = (await response.json()).keys;
      const key = keys.find(k => k.kid === h.kid && (!k.alg || k.alg === h.alg) && (!k.use || k.use === 'sig') && k.kty === (h.alg === 'RS256' ? 'RSA' : 'EC'));
      if (!key) throw new Error();
      const publicKey = createPublicKey({ key, format: 'jwk' });
      if (!verify('sha256', Buffer.from(`${header}.${body}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url'))) throw new Error();
      const now = Date.now() / 1000;
      if (claims.iss !== issuer || !(Array.isArray(claims.aud) ? claims.aud.includes(clientId) : claims.aud === clientId) || (Array.isArray(claims.aud) && claims.aud.length > 1 && claims.azp !== clientId) || !Number.isFinite(claims.exp) || claims.exp <= now || (claims.nbf && claims.nbf > now + 30) || !same(claims.nonce, nonce) || typeof claims.sub !== 'string' || !claims.sub) throw new Error();
      return claims;
    } catch { throw new AgentError('invalid_identity'); }
  }
  async callback(params) {
    if (this.refreshing) await this.refreshing;
    const state = params.get('state');
    const attempt = this.pending.get(state);
    if (!attempt || !same(state, attempt.state) || attempt.expires < Date.now()) throw new AgentError('invalid_authorization_state');
    this.pending.delete(state);
    if (params.has('error')) throw new AgentError('authorization_denied');
    const issued = params.get('client_id') || attempt.account?.client_id;
    if (!issued || issued === 'dynamic_agent_client' || !issued.startsWith('oaiapp_') || (attempt.account && issued !== attempt.account.client_id) || !params.get('code')) throw new AgentError('invalid_client');
    let account = attempt.account || this.state.accounts.find(a => a.client_id === issued);
    if (!account) { account = { client_id: issued }; this.state.accounts.push(account); }
    // Keep the issued registration even if exchange fails; never exchange with
    // dynamic_agent_client. It must not become active before identity validation.
    await this.save();
    const tokens = await this.form(tokenEndpoint, { grant_type: 'authorization_code', client_id: issued, code: params.get('code'), code_verifier: attempt.verifier, redirect_uri: attempt.redirect, resource });
    const identity = await this.validate(tokens.id_token, issued, attempt.nonce);
    if (account.subject && (identity.sub !== account.subject || identity.iss !== account.issuer)) throw new AgentError('account_identity_changed');
    if (!scopes(tokens).includes('chatgpt.tokens.use.direct')) throw new AgentError('plan_permission_missing');
    this.checkTokens(tokens);
    Object.assign(account, tokens, { issuer: identity.iss, subject: identity.sub, email: identity.email, scopes: scopes(tokens), saved_at: Date.now() });
    this.state.active = issued;
    await this.save();
    return account;
  }
  checkTokens(tokens) {
    if (typeof tokens.access_token !== 'string' || !tokens.access_token || typeof tokens.refresh_token !== 'string' || !tokens.refresh_token || tokens.token_type?.toLowerCase() !== 'bearer' || !Number.isFinite(tokens.expires_in) || tokens.expires_in <= 0) throw new AgentError('invalid_token_response');
  }
  async select(id) {
    if (this.refreshing) await this.refreshing;
    const account = this.state.accounts.find(a => a.client_id === id && a.subject);
    if (!account) throw new AgentError('account_not_found');
    this.state.active = id;
    await this.save();
  }
  async accessToken() {
    if (!this.connected) throw new AgentError('sign_in_required', 401);
    const account = this.account;
    if (account.saved_at + account.expires_in * 1000 > Date.now() + 60_000) return account.access_token;
    if (this.refreshing) { await this.refreshing; return this.accessToken(); }
    this.refreshing = (async () => {
      try {
        const tokens = await this.form(tokenEndpoint, { grant_type: 'refresh_token', client_id: account.client_id, refresh_token: account.refresh_token, resource });
        this.checkTokens({ ...tokens, refresh_token: tokens.refresh_token || account.refresh_token });
        const granted = typeof tokens.scope === 'string' ? scopes(tokens) : account.scopes;
        if (!granted.includes('chatgpt.tokens.use.direct')) throw new AgentError('plan_permission_missing', 401);
        Object.assign(account, tokens, { refresh_token: tokens.refresh_token || account.refresh_token, scopes: granted, saved_at: Date.now() });
        await this.save();
      } catch (error) {
        if (['invalid_grant', 'invalid_client', 'plan_permission_missing'].includes(error.code)) { this.clearTokens(account); await this.save(); }
        throw error;
      }
    })();
    try { await this.refreshing; } finally { this.refreshing = null; }
    return this.accessToken();
  }
  clearTokens(account) { for (const key of ['access_token', 'refresh_token', 'id_token', 'scope', 'scopes', 'expires_in', 'saved_at']) delete account[key]; }
  async logout() {
    if (this.refreshing) { try { await this.refreshing; } catch { /* still clear the local session */ } }
    const account = this.account;
    let revoked = !account?.refresh_token;
    if (account?.refresh_token) {
      try {
        const config = await this.discovery();
        const response = await this.fetcher(config.revocation_endpoint, { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ token: account.refresh_token, token_type_hint: 'refresh_token', client_id: account.client_id }), signal: AbortSignal.timeout(30_000), redirect: 'error' });
        revoked = response.status === 200;
      } catch { revoked = false; }
    }
    if (account) this.clearTokens(account);
    await this.save();
    return { revoked };
  }
}
