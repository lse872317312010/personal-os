# Android device evidence

This directory is the single source of truth for the Redmi Turbo G3
device-validation gate. No real-device run has been performed or is claimed by
the checked-in files.

- `REDMI_TURBO_RUNBOOK.md` defines the exact nine scenarios used by the MVP
  audit.
- `schema/evidence.schema.json` defines schema version 2.
- `records/synthetic.example.json` is a blocked template and test fixture,
  never real evidence.
- `tool/validate_evidence.py` validates the privacy-bounded record.
- `tool/adb_readiness.sh` reports only ready/not-ready and suppresses device
  identifiers.

Records must bind the exact candidate commit and APK SHA-256. They must not
contain device serials, Android IDs, account IDs, user content, filenames,
device paths, build fingerprints, biometric details, exception messages, raw
logs, or screenshots. Repository tests and APK builds remain G0-G2 evidence;
only a completed real-device record can satisfy G3.
