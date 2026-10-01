# External Agent and Harness compatibility

Personal OS keeps one vendor-neutral contract for external reasoning: `personal-os.mcp.v0`. The user can give the same context and receive the same proposal or review from any assistant or Harness that can handle text and return the contract.

## Ways to connect

- Start from “开始个人策略闭环” on the home screen. Save a goal, completion criteria, current conditions and constraints without first running the legacy appearance analysis.
- On Android, connect the optional OpenAI API adapter once per unlocked Vault session, then use “向 OpenAI 请求并读取建议” for an automatic request and reply. Each request shows the exact Context Bundle and asks for one-time confirmation. PersonalAsset and Observation records are removed before sending; the returned Bundle goes through the existing protocol validation and remains a pending suggestion until the user accepts it.
- On Android, use the system share chooser to send the prepared handoff to any installed app that accepts text. Personal OS refreshes the Context Bundle first and asks before sharing real Vault context.
- In an assistant that supports sharing a text reply, share the reply to Personal OS. After Vault unlock, Personal OS places it in the reply box; review it and choose “识别并导入建议” yourself. Raw JSON and Markdown-fenced JSON replies are both recognized.
- Copy/paste remains available for other assistants and as a fallback when the OpenAI API adapter is unavailable.
- The MCP JSON-RPC adapter is ready for Harnesses, but the Android live transport remains unavailable until its security and device acceptance gates pass.

The assistant name is a free-form session label. Adding a provider-specific name does not require a provider SDK, a new protocol, or changes to the core. A future transport adapter should map to the existing application API and capabilities.

## Authority and privacy

The Android Vault remains the authoritative store. External assistants can suggest strategies and reviews; the user accepts or rejects those suggestions in Personal OS. Only the user records real execution outcomes. On secure Vault devices, every system share, clipboard handoff, or OpenAI API request requires explicit confirmation. Direct API requests omit PersonalAsset and Observation records, block common credential patterns such as API keys and private-key headers, and use only the session context previewed to the user. Pattern checks are a guardrail, not a replacement for checking the preview. The API key is entered in a native secure prompt, held in Android process memory, never crosses the Flutter channel, and is cleared when the Vault locks or the native activity is destroyed. OpenAI API usage may be billed separately from a ChatGPT subscription.

Incoming Android shares accept only bounded plain text. While the Vault is locked, Dart does not read replies; up to eight replies (with a 1 MiB aggregate text limit) wait in an app-private FIFO so the user can unlock and review them in order. The queue file is encrypted with an Android Keystore AES-GCM key, excluded from Android backup, and deleted as replies are imported or explicitly discarded. New replies never overwrite queued replies. If the queue fills, Personal OS reports how many new replies were not retained and asks the user to share them again. Dart peeks at the FIFO head only while unlocked. Locking or switching away before deciding does not remove a reply; the temporary Flutter copy is cleared when the Vault locks. An unreadable or unwritable encrypted queue fails closed and is reported in the UI without replacing the stored ciphertext. If Personal OS is already running, Android sends only a body-free availability signal, and Dart pulls reply text only after its Vault-unlocked check. Importing creates a pending suggestion, and accepting it remains a separate user action.

The browser preview uses synthetic in-memory data and is not a production Vault or an MCP listener.

## Web walkthrough first

The Web preview is the first surface for demonstrating the entire interaction, following decision 0016. “填入演示资料” and “填入演示回复” are optional synthetic helpers; they use the same application commands and manual decisions as an external reply. They never invoke a model, accept a proposal, or record an execution automatically. Refreshing the page clears all demonstration data.

After recording an outcome, request a review through OpenAI or use another assistant. Accept that review, then request a revised strategy from the same assistant or end the session and choose another assistant. The Web preview stays synthetic and memory-only; it does not call OpenAI. The application checks accepted reviews against the exact parent strategy across sessions. New strategies receive separate execution and outcome records; prior history remains in the context. Context handoffs collect all query pages and fail visibly if they cannot export the complete bounded history.

`test/web_agent_loop_test.dart` runs the two-assistant walkthrough in Flutter and Chrome. It also checks exact-parent review matching, restoration without prior-round UI leakage, and context histories longer than one page. These are engineering checks, not G3 or G4 evidence.

## Handoff contract

Before each automatic request, share, or copy, Personal OS refreshes the Context Bundle so newly recorded strategies, executions, and outcomes are included without a manual refresh. Direct OpenAI requests remove PersonalAsset and Observation records, then preview the resulting exact Bundle before asking the user to send it. The copy prompt pins the current session ID and protocol version, asks the assistant to use only pinned references in the Context Bundle, and requests exactly one proposal or review. Personal OS accepts one raw or fenced Bundle reply at a time, whether shared into the app or pasted. Incoming text is not imported automatically: the user checks it and starts import, then accepts or rejects the resulting suggestion separately. A review must be accepted by the user before a revised strategy can be imported.

Execution uses the action IDs and instructions in the imported strategy or restored event history. The normal flow displays the actual step; when a strategy has multiple steps, the user selects the step they completed before recording it. The app rejects IDs that do not belong to the active strategy.

Tests for provider-neutral prompt generation, reply recognition, and single-Bundle handling live in `apps/personal_os_app/test/agent_handoff_test.dart`. The native share-channel boundary is covered by `agent_text_share_test.dart`, and background lock/revocation by `app_composition_test.dart`. Action validation and cold-start restoration are covered by `strategy_loop_controller_test.dart` and `strategy_cold_start_restore_test.dart`. Keep vendor names out of the protocol and core domain.
