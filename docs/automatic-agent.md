# Automatic Personal OS Agent loop

The automatic browser app uses the existing Personal OS strategy protocol,
fixed-version context references, reducers and user decisions. It does not ask
the user to copy prompts, paste replies, or import JSON. The model only proposes
plans and reviews; acceptance, real execution and outcome reports remain human
actions.

## Run

Download `personal-os-automatic-windows.zip` from the `automatic-agent-web`
release, extract it, and double-click `Start-Personal-OS.cmd`. Node is bundled;
no Flutter SDK, npm installation, API key or developer console is required for
the ChatGPT connection. Keep the service window open. The app opens at
`http://127.0.0.1:8787`.

The Linux archive similarly includes Node. Run `bash start-personal-os.sh`.
For source development, use Node 22+, build the Flutter web app with base href
`/`, and copy `build/web/` into `services/agent_gateway/web/`:

```sh
cd apps/personal_os_app
flutter pub get
python3 ../../tool/prepare_local_web_font.py
flutter build web --release --base-href / --target lib/main_web_agent.dart
cd ../..
cp -R apps/personal_os_app/build/web services/agent_gateway/web
node services/agent_gateway/server.mjs
```

The first connection uses **Continue with ChatGPT** and OpenAI's system-browser
OAuth authorization. Eligible plan access is granted by OpenAI, not inferred
from an identity token. No existing ChatGPT browser session is extracted.
Choose an account/workspace once; later launches reuse the registered client
and automatically refresh its credentials. Available models come from that
account's current catalog. Sign-out revokes the renewable session and keeps
the host/account registration for later sign-in. If revocation cannot be
confirmed, the app says so and links to ChatGPT settings.

Save a goal to generate a plan. Confirm the suggested plan to start. After doing
an action, report its result: the app automatically requests and receives the
review. Accept that review: the app automatically requests the next plan.
Repeated clicks do not create overlapping model requests. Failures preserve
existing state and provide a retry. Incomplete output is never adopted.

## Other model or Agent connections

The same automatic service supports four adapters. Configure these variables
in the local runtime environment **before launching**, not in source control
or browser storage. Provider configuration is a one-time setup, not a daily
prompt/reply handoff.

| `PERSONAL_OS_PROVIDER` | Other configuration | Request contract |
| --- | --- | --- |
| `chatgpt` (default) | OAuth in the browser | Account catalog + streamed OpenAI Responses |
| `responses` | `PERSONAL_OS_BASE_URL`, `PERSONAL_OS_MODEL`, `PERSONAL_OS_API_KEY` | OpenAI-compatible streamed Responses |
| `chat-completions` | Same variables | OpenAI-compatible Chat Completions, terminal `finish_reason=stop` |
| `agent-http` | `PERSONAL_OS_AGENT_URL`, `PERSONAL_OS_MODEL`, optional `PERSONAL_OS_API_KEY` | JSON HTTP Agent bridge |

Remote provider endpoints must use HTTPS; local models may use HTTP on
`127.0.0.1` or `[::1]`. The browser cannot supply arbitrary endpoints or keys.
The custom HTTP bridge accepts:

```json
{
  "protocol_version": "personal-os.agent-gateway.v1",
  "model": "my-agent",
  "stage": "proposal",
  "prompt": "Protocol instructions and the complete context",
  "context": { "protocol_version": "personal-os.mcp.v0", "session_id": "...", "objects": [] }
}
```

Return either `{ "reply": "<one complete Bundle JSON>" }` or
`{ "bundle": { "protocol_version": "personal-os.mcp.v0", "session_id": "...", "strategy": {} } }`.
The stage is `proposal`, `review` or `revision`. The full protocol instructions
and current, fixed-version references are supplied automatically in `prompt`.
Transport success does not bypass the core bundle/reference/state validation.

## Runtime and data boundary

Credentials and append-only personal event history live in the user's private
runtime profile, outside the project. Windows uses current-user DPAPI; Unix
uses AES-256-GCM records and a local installation key in owner-only files (0600
in a 0700 directory). **The Unix key is protected by account/file permissions,
not hardware or an OS keychain. This store is not the Android SQLCipher Vault.** The local browser
entrypoint is explicit and leaves the Android production composition intact.
It does not run the synthetic appearance provider.

The server binds only to `127.0.0.1`, validates Host/Origin and CSRF, rejects
cross-site requests, serializes rotating-token refresh, prevents two runtimes
from sharing a profile, and never logs credentials, authorization URLs, prompts
or replies. The web client receives neither provider keys nor OAuth tokens.
History updates use revision checks and cannot erase prior events; the Dart
reducer validates the complete append transaction before it is persisted.

When AI is requested, the current structured goal, conditions and related
history are sent to the connected provider. The UI states this next to the
connection and goal controls. Requests use `store=false`; this does not imply
that the remote provider has no other retention policy.

The public GitHub Pages site distributes the local app. It cannot itself hold
personal OAuth tokens or run a private callback service. Do not describe the
public download page as a live model inference demo.

CanvasKit and the pinned OFL-licensed Noto Sans SC font are included in the
package and loaded from the same app origin. Startup does not request these
resources from Google CDNs. The font's unmodified license is included in the
web build; its exact upstream commit/blob is verified during packaging.

## Verification scope

`node --test services/agent_gateway/test/*.test.mjs` covers real loopback HTTP,
OAuth state/PKCE/signed ID tokens, permission validation, rotating refresh,
protected persistence and late streaming failures. Flutter/Chrome tests cover
automatic proposal, user acceptance/action/outcome, automatic review and the
next proposal, plus persistence and stale-response cancellation.

Model replies and JWTs in tests are explicitly test doubles. A production
ChatGPT inference run still requires a real eligible account's OAuth grant;
passing these tests is not evidence of a live paid-model inference.

Official references: [registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
[models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).
