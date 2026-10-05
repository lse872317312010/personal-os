# Automatic Personal OS Agent loop

The automatic browser app uses the existing Personal OS strategy protocol,
fixed-version context references, reducers and user decisions. It does not ask
the user to copy prompts, paste replies, or import JSON. The model only proposes
plans and reviews; acceptance, real execution and outcome reports remain human
actions.

## Edit saved context

The goal and current situation fields are filled from saved context on reload.
First save still starts automatic planning when an AI is connected. Later saves
update the same goal and current fact by appending revisions, preserve the
accepted action and do not trigger an extra model request. The next request or
review uses the updated context. Unchanged saves append no events. Clearing the
optional situation archives it; earlier evidence remains available. Archived
facts are omitted from ordinary Agent context but remain readable by
their earlier pinned references. Existing fact-to-goal links are recovered from
their original events without rewriting history. These are
edits to these two fields, not general asset or constraint management. Upgrade
clients together: older readers cannot interpret the new revision event types.

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

Save a goal to generate a plan. Confirm the suggested plan to start. On the
action card, choose **完成了** or **这次没做**; the result/obstacle note is optional.
That explicit user choice saves an execution and an outcome in one atomic
append, then automatically requests the review. The outcome records only the
chosen status and any user-supplied note: valence stays neutral and no metrics,
feelings or effectiveness are inferred from completion. Accept the review:
the app automatically requests the next plan.
Repeated clicks do not create overlapping model requests. Failures preserve
existing state and provide a retry. Incomplete output is never adopted.

On reopening or reconnecting, the app automatically continues a saved goal
without a plan, saved feedback without a review, or an accepted review without
the next plan. Saving a connection closes setup before continuing; choosing a
different connection, account or model can also continue pending work. New
plans and reviews still await the user's decision. Drafts, rejected decisions,
accepted-but-not-started plans and actions without feedback are not advanced.
The resulting action or review is brought to the top of the page.

Each pending state and connection gets one automatic attempt in that app
instance. Switching away and back does not repeatedly request a failed model or
hide its error. **刷新连接** explicitly permits a retry; reopening also permits a
fresh attempt. Changed context or connection settings may permit a new attempt.
There is no background retry loop. History writes remain revision-checked, but
this is not an exactly-once guarantee for remote provider calls or billing.

A failed feedback write leaves both facts unwritten and preserves the note for
retry. A failed or unavailable AI request keeps the saved facts; reopening or
reconnecting continues the pending review without recording feedback again.
The action card also offers an explicit review retry. Saving feedback requires
the local service, but does not require an AI connection. No execution is
recorded when merely accepting or starting a plan. The atomic command checks
user authority, profile ownership, the active strategy revision and action ID.
It uses the existing execution/outcome event types. This shortcut is currently
for the automatic Web screen; other clients keep their existing input flow.

The AI card distinguishes saved configuration from a completed model response.
Choose **测试 AI 连接** to send one fixed test message to the selected model.
This explicit action may count toward the provider's usage. It does not read
personal history, accepts no client-supplied context or prompt, discards the raw
reply and creates no plan or event. The check uses a 30-second request deadline,
the same CSRF/connection revision guards and exclusive request lock as normal
inference. Success confirms a model response, not valid strategy generation;
formal plans still use the existing bundle validation and user decisions.
Changing the connection or model, refreshing it, or failing a later test clears
the previous response status. Check results are not persisted as personal data.

Saved personal facts and goals are shown in **已保存的个人资料**. Suggested plans,
execution reports, outcomes and reviews are shown separately in **行动历史**.
Both cards are collapsed by default so the current action stays prominent.

## Other model or Agent connections

Expand the AI connection card and choose **接入其他 AI**. Select OpenAI-compatible
Chat Completions, Responses API, or a custom HTTP Agent. Enter a display name,
service URL, model ID and, if required, an API key. Save once; plans and reviews
are then sent and received automatically. No environment variables or manual
prompt/reply handoff are needed.

Saved connections appear in a selector. Switching, editing or removing a
connection preserves the current goal, accepted plan, outcomes and history.
The next request carries that same structured context to the selected Agent.
Connections cannot change while a request is running; a stale browser's request
is rejected before it can send personal context to an unexpected connection.
Removing the active custom connection returns to ChatGPT. This removes only
the saved service configuration; ChatGPT sign-out remains a separate action.

Connection settings, including keys, are encrypted in the local runtime
profile. Editing shows whether a key exists, never the stored key. A blank key
keeps it only when the service type and destination stay the same; changing
either requires re-entering the key. There is also an explicit clear-key option.

For developer startup configuration, these variables seed a custom connection
on the **first launch of a new profile**. Later launches use saved connections;
changing environment variables does not overwrite them. Keep secrets out of
source control and browser storage.

| `PERSONAL_OS_PROVIDER` | Other configuration | Request contract |
| --- | --- | --- |
| `chatgpt` (default) | OAuth in the browser | Account catalog + streamed OpenAI Responses |
| `responses` | `PERSONAL_OS_BASE_URL`, `PERSONAL_OS_MODEL`, `PERSONAL_OS_API_KEY` | OpenAI-compatible streamed Responses |
| `chat-completions` | Same variables | OpenAI-compatible Chat Completions, terminal `finish_reason=stop` |
| `agent-http` | `PERSONAL_OS_AGENT_URL`, `PERSONAL_OS_MODEL`, optional `PERSONAL_OS_API_KEY` | JSON HTTP Agent bridge |

Remote provider endpoints must use HTTPS; local models may use HTTP on
`127.0.0.1`, `localhost` (normalized to `127.0.0.1`) or `[::1]`. Explicit settings
changes require the local app's same-origin and CSRF checks. URLs cannot contain
credentials, query strings or fragments, and redirects are not followed.
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
or replies. The web client cannot retrieve saved provider keys or OAuth tokens;
a user-entered key is submitted once from the setup form and is not persisted
in browser storage.
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
protected persistence, connection switching, all three generic transports and
late streaming failures. Flutter/Chrome tests cover the phone connection form,
switching Agent between action and review,
automatic proposal, user acceptance/action/outcome, automatic review and the
next proposal, plus persistence, automatic continuation, failed-attempt
deduplication, user-decision boundaries and stale-response cancellation. The
compiled browser smoke also reopens after a failed next-plan request and
verifies that the accepted review continues into a draft proposal while prior
execution/outcome evidence remains unchanged.

Model replies and JWTs in tests are explicitly test doubles. A production
ChatGPT inference run still requires a real eligible account's OAuth grant;
passing these tests is not evidence of a live paid-model inference.

Official references: [registration](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[sessions](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions),
[models and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).
