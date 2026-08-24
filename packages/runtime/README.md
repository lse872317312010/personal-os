# Personal OS runtime

Pure Dart composition and lifecycle policy. It coordinates opaque ports and
does not depend on Flutter, SQLite/SQLCipher, a particular sync transport, or a
model provider.

The runtime starts fail-closed. Unlock order is vault, event-store availability,
model access, then sync. Lock and failure cleanup use the reverse dependency
order. Background mode stops sync and model access while retaining the local
vault; foreground mode restores them. Any foreground/background startup failure
falls back to a locked state. Public failures contain stable codes only.
Lifecycle calls are serialized, so concurrent app/platform callbacks cannot
observe or bypass an in-progress transition or close boundary.
