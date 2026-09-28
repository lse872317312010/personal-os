# External Agent and Harness compatibility

Personal OS keeps one vendor-neutral contract for external reasoning: `personal-os.mcp.v0`. The user can give the same context and receive the same proposal or review from any assistant or Harness that can handle text and return the contract.

## Ways to connect

- On Android, use the system share chooser to send the prepared handoff to any installed app that accepts text. Personal OS refreshes the Context Bundle first and asks before sharing real Vault context.
- Use copy/paste as a fallback or when the target app is not listed. Raw JSON and Markdown-fenced JSON replies are both recognized.
- The MCP JSON-RPC adapter is ready for Harnesses, but the Android live transport remains unavailable until its security and device acceptance gates pass.

The assistant name is a free-form session label. Adding a provider-specific name does not require a provider SDK, a new protocol, or changes to the core. A future transport adapter should map to the existing application API and capabilities.

## Authority and privacy

The Android Vault remains the authoritative store. External assistants can suggest strategies and reviews; the user accepts or rejects those suggestions in Personal OS. Only the user records real execution outcomes. On secure Vault devices, sending context through the system share chooser or copying it to the clipboard requires explicit confirmation because it can contain goals, assets, strategies, and history. The selected app may send that content to its service.

The browser preview uses synthetic in-memory data and is not a production Vault or an MCP listener.

## Handoff contract

Before each share or copy, Personal OS refreshes the Context Bundle so newly recorded strategies, executions, and outcomes are included without a manual refresh. The copy prompt pins the current session ID and protocol version, asks the assistant to use only pinned references in the Context Bundle, and requests exactly one proposal or review. Personal OS accepts one raw or fenced Bundle reply at a time. A review must be accepted by the user before a revised strategy can be imported.

Execution uses the action IDs and instructions in the imported strategy or restored event history. The normal flow displays the actual step; when a strategy has multiple steps, the user selects the step they completed before recording it. The app rejects IDs that do not belong to the active strategy.

Tests for provider-neutral prompt generation, reply recognition, and single-Bundle handling live in `apps/personal_os_app/test/agent_handoff_test.dart`. The native share-channel boundary is covered by `agent_text_share_test.dart`, and background lock/revocation by `app_composition_test.dart`. Action validation and cold-start restoration are covered by `strategy_loop_controller_test.dart` and `strategy_cold_start_restore_test.dart`. Keep vendor names out of the protocol and core domain.
