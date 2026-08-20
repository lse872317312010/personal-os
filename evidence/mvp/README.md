# MVP evidence ledger

`status.json` is the machine-audited, non-sensitive ledger for the five usability gates defined in `docs/MVP_USABILITY_GATE.md`.

The checked-in file is synthetic and intentionally proves nothing. Copy its structure when recording a real candidate, replace `kind` with `real`, and record only metadata and pass/fail assertions. Never store photos, appearance text, device identifiers, account identifiers, secrets, raw logs, or on-device paths here.

Run `python3 tool/mvp_acceptance/audit.py --status <path> --target dogfood` to audit a candidate. Evidence records may be reviewed and committed only after their referenced commands or manual procedures have actually run.
