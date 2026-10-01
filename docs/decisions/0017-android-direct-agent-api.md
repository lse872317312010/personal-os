# 0017. Android direct Agent API round trip

Date: 2026-09-30

Status: Accepted
Supersedes: the manual-copy/paste-first transport priority in 0016 for the Android execution path

## Context

Decision 0016 made the Web walkthrough the fastest way to demonstrate the strategy loop and planned online adapters after the handoff flow. The action-first screen, validation pipeline, and Web synthetic walkthrough are now on main. The remaining product gap is that a real assistant still requires a user to copy a prompt out and paste a reply back.

The Android Vault is authoritative. Agent responses are suggestions; a user must accept them, activate a strategy, record execution, and record outcomes. Live MCP serving remains disabled until the existing security and physical-device gates pass.

## Decision

1. Add a provider-neutral outbound `AgentCompletionPort` to the application boundary. Ship OpenAI Responses as the first Android native adapter; later providers can implement the same contract.
2. Let the user enter the OpenAI API key in an Android secure native prompt. Keep it in process memory for the unlocked Vault session, never send it through Flutter, never persist it, and clear it on Vault lock or native activity teardown.
3. Require the OpenAI adapter build flag `personalOsOpenAiEnabled=true` and a configured `personalOsOpenAiModel`. The adapter remains unavailable by default when the build flag is off.
4. Before every model request, show the exact outgoing Context Bundle and ask for one-time confirmation. Send only text and set Responses `store=false`. Exclude `personal_asset` and `observation` records from this direct API path. Do not send D4 data or the API key in prompt/context.
5. Block common credential patterns (API keys, bearer tokens, password/secret values, recovery codes, and private-key headers) before provider I/O. This is a guardrail for untyped text, not a guarantee that every secret can be identified; show the complete outgoing Bundle so the user can inspect it.
6. Use the existing `personal-os.mcp.v0` prompt, codecs, protocol service, and acceptance flow. A completed response is imported as a pending proposal or review. No request runs automatically after an outcome, no proposal is auto-accepted, and no real-world action is triggered.
7. Keep copy/share support for other assistants. Keep the browser preview synthetic, memory-only, and free of real API requests. Do not open a local or public MCP listener as part of this decision.

OpenAI API usage can incur charges billed separately from ChatGPT subscriptions. Connecting the credential does not send personal context or invoke the model; the user chooses each request.

## Consequences

- Android can send and receive a complete strategy round trip without clipboard or system-share handoffs after the user configures the API key.
- Each send has a clear user action and per-request context preview. Data controls remain limited to the currently supported object categories; field-level D2/D3 authorization is still future work.
- The first provider is platform-specific, while UI/controller code depends on a provider-neutral Dart port.
- Web demonstrates the same accept/execute/result loop with synthetic replies until an equivalent secure online credential boundary is designed and reviewed.
- Redmi Turbo G3/G4 nine-scenario device verification remains mandatory before declaring device-ready; CI, emulator, and browser results do not satisfy it.
