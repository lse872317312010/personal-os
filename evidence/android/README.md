# Android device evidence

This directory defines the future Redmi Turbo device-validation procedure and
its non-sensitive evidence format. No real-device run has been performed or is
claimed by the files in this directory.

Evidence records must validate against `schema/evidence.schema.json`. They must
not contain device serials, Android IDs, account IDs, user content, filenames,
paths from the user's device, system fingerprints, authentication reasons,
exception messages, or log output. `records/synthetic.example.json` is test data
only and must never be presented as real evidence.

Scripts in `tool/` perform local build checks, schema validation, and a minimal
read-only ADB readiness check. They do not install packages, change device
state, inspect application data, or collect device output.
