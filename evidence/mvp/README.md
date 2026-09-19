# MVP evidence ledger

`status.json` is the machine-audited, non-sensitive ledger for the five usability gates defined in `docs/MVP_USABILITY_GATE.md`.

The checked-in file is synthetic and intentionally proves nothing. Copy its structure when recording a real candidate, replace `kind` with `real`, and record only metadata and pass/fail assertions. Never store photos, appearance or fitness content, device identifiers, account identifiers, secrets, raw logs, or on-device paths here.

Schema version 2 makes the final gate match the product claim. A dogfood pass requires two executed strategy rounds, distinct Harness references, Strategy v2 lineage to v1, explicit evidence/feedback continuity checks, and the same APK digest at build and Redmi-device gates. A one-round demo cannot produce `DOGFOOD_READY`.

Run `python3 tool/mvp_acceptance/audit.py --status <path> --target dogfood` to audit a candidate. Evidence records may be reviewed and committed only after their referenced commands or manual procedures have actually run.
