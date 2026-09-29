# External Agent and Harness compatibility

Personal OS keeps one vendor-neutral contract for external reasoning: `personal-os.mcp.v0`. The user can give the same context and receive the same proposal or review from any assistant or Harness that can handle text and return the contract.

## Ways to connect

- On Android, use the system share chooser to send the prepared handoff to any installed app that accepts text. Personal OS refreshes the Context Bundle first and asks before sharing real Vault context.
- In an assistant that supports sharing a text reply, share the reply to Personal OS. After Vault unlock, Personal OS places it in the reply box; review it and choose “识别并导入建议” yourself. Raw JSON and Markdown-fenced JSON replies are both recognized.
- Use copy/paste as a fallback or when the target app is not listed.
- The MCP JSON-RPC adapter is ready for Harnesses, but the Android live transport remains unavailable until its security and device acceptance gates pass.

The assistant name is a free-form session label. Adding a provider-specific name does not require a provider SDK, a new protocol, or changes to the core. A future transport adapter should map to the existing application API and capabilities.

## Authority and privacy

The Android Vault remains the authoritative store. External assistants can suggest strategies and reviews; the user accepts or rejects those suggestions in Personal OS. Only the user records real execution outcomes. On secure Vault devices, sending context through the system share chooser or copying it to the clipboard requires explicit confirmation because it can contain goals, assets, strategies, and history. The selected app may send that content to its service.

Incoming Android shares accept only bounded plain text. While the Vault is locked, Dart does not read replies; up to eight replies (with a 1 MiB aggregate text limit) wait in a volatile native FIFO so the user can unlock and review them in order. New replies never overwrite queued replies. If the queue fills, Personal OS reports how many new replies were not retained and asks the user to share them again. Dart peeks at the FIFO head only while unlocked. The native reply stays queued until the user imports or discards it, so locking or switching away before deciding does not silently lose it; the temporary Flutter copy is cleared when the Vault locks. Replies are never persisted and queued replies are lost if the Activity is destroyed. If Personal OS is already running, Android sends only a body-free availability signal, and Dart pulls reply text only after its Vault-unlocked check. Importing creates a pending suggestion, and accepting it remains a separate user action.

The browser preview uses synthetic in-memory data and is not a production Vault or an MCP listener.

## Handoff contract

Before each share or copy, Personal OS refreshes the Context Bundle so newly recorded strategies, executions, and outcomes are included without a manual refresh. The copy prompt pins the current session ID and protocol version, asks the assistant to use only pinned references in the Context Bundle, and requests exactly one proposal or review. Personal OS accepts one raw or fenced Bundle reply at a time, whether shared into the app or pasted. Incoming text is not imported automatically: the user checks it and starts import, then accepts or rejects the resulting suggestion separately. A review must be accepted by the user before a revised strategy can be imported.

Execution uses the action IDs and instructions in the imported strategy or restored event history. The normal flow displays the actual step; when a strategy has multiple steps, the user selects the step they completed before recording it. The app rejects IDs that do not belong to the active strategy.

Tests for provider-neutral prompt generation, reply recognition, and single-Bundle handling live in `apps/personal_os_app/test/agent_handoff_test.dart`. The native share-channel boundary is covered by `agent_text_share_test.dart`, and background lock/revocation by `app_composition_test.dart`. Action validation and cold-start restoration are covered by `strategy_loop_controller_test.dart` and `strategy_cold_start_restore_test.dart`. Keep vendor names out of the protocol and core domain.
