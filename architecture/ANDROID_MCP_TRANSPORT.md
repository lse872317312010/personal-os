# Android foreground MCP transport security contract

Status: **JSON-RPC adapter implemented; network listener not enabled**

This contract is the gate between the vendor-neutral Agent Protocol and any
Android network transport. It does not claim that a socket, HTTP endpoint, or
real external Harness is currently available.

## Scope

The MVP transport exists only to let one user-controlled external Harness talk
to the unlocked Redmi Primary Vault. It is not a background service, LAN API,
cloud endpoint, browser API, synchronization channel, or general remote-access
feature.

The pure Dart `PersonalOsMcpJsonRpcAdapter` may parse MCP initialization,
`tools/list`, and `tools/call` requests. It opens no socket and grants no
Android permission by itself.

## Mandatory deployment boundary

A future Android HTTP wrapper must satisfy all of these conditions:

1. Bind only to `127.0.0.1`; never bind `0.0.0.0`, a Wi-Fi address, IPv6
   wildcard, or a public interface.
2. Be reachable from a workstation only through an explicit
   `adb forward tcp:<host> tcp:<device>` session over a user-authorized USB
   debugging connection.
3. Start only while the Vault is unlocked, the app is foreground, and the user
   presses an explicit start control.
4. Stop and revoke all volatile bindings on Vault lock, app background, process
   death, user stop, authentication cancellation, or idle timeout.
5. Accept only `POST /mcp` with an exact JSON content type and a bounded body.
   The initial limit is 1 MiB; oversized, chunk-abusive, malformed, or batched
   requests fail closed.
6. Require a memory-only, cryptographically random bearer secret with at least
   128 bits of entropy. It expires after at most 10 minutes or when the
   transport stops, whichever happens first.
7. Never persist, log, export, back up, screenshot, or place the bearer secret
   on the clipboard by default.
8. Reject browser origins and emit no permissive CORS headers. A session ID is
   not an authentication credential.
9. Allow one active transport client and one profile only. The caller cannot
   choose a profile identifier.
10. Keep Android `allowBackup=false`, cleartext client traffic disabled, and
    the existing zero-sensitive-log policy.

LAN binding, TLS certificate management, background availability, Wi-Fi
pairing, cloud relay, and multiple simultaneous clients are outside the MVP.

## Authority checks

Transport authentication and Agent authorization are separate:

- the bearer secret admits a request to the local MCP endpoint;
- `personal_os.open_session` records the Harness identity, purpose, and the
  granted subset of capabilities;
- every later operation rechecks that the durable session is still open;
- every read/write rechecks the exact stored capability;
- proposal and review writes recheck Harness identity and profile ownership;
- Android remains authoritative and Agent writes remain proposals or review
  drafts until user confirmation.

A missing capability returns `access_denied`. A closed/failed session returns
`session_closed`. Unknown sessions, revoked volatile bindings, malformed
requests, and internal adapter failures return only stable redacted errors.

## MCP surface

The adapter supports MCP transport version `2025-06-18` and:

- `initialize`;
- `notifications/initialized`;
- `tools/list`;
- `tools/call`.

The only tools are the six names frozen in `docs/contracts/MCP_V0.md`.
Resources, prompts, sampling, elicitation, server-initiated notifications, SSE,
resumption, and batch JSON-RPC are not enabled in this MVP slice.

## Request and response rules

- JSON-RPC must be exactly `2.0`.
- Request IDs are strings, numbers, or null; notifications receive no response.
- Tool input is parsed into typed domain values; profile, authority source,
  Session revision, and user identity are server-owned.
- The adapter tracks Session revision after proposal submission instead of
  trusting a caller-provided revision.
- Tool failures return a stable code and `retryable` flag without raw
  exception text, database paths, user content, keys, or native error detail.
- `revokeAll()` clears initialization state and every volatile Session
  binding. The future Android lifecycle wrapper must call it synchronously
  during shutdown.

## Required evidence before enabling a listener

1. Unit tests for handshake ordering, exact tool list, capability denial,
   revision ownership, revocation, unsupported versions, and error redaction.
2. Application tests proving Vault lock/background/timeout call transport stop
   and `revokeAll()`.
3. Android tests proving loopback-only binding, bearer enforcement, request-size
   bounds, single-client behavior, and zero network availability while locked.
4. A Redmi test using an exact verified APK and `adb forward`, followed by
   lock, background, timeout, force-stop, and reboot denial checks.
5. Manual inspection that no token, payload, path, device identifier, or raw
   error enters logs or evidence.

Until all five exist, documentation and release notes must say
`MCP JSON-RPC adapter available; Android live transport unavailable`.
