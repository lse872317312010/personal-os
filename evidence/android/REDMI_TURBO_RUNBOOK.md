# Redmi Turbo device validation runbook

Status: **not run**. This is a future manual procedure, not test evidence.

## Safety rules

- Use a dedicated test profile and synthetic records only.
- Disable log capture, screenshots containing personal data, crash uploads, and
  screen recording. Never run `adb logcat`, inspect app storage, or copy device
  databases.
- Do not record serial number, Android ID, account ID, build fingerprint, Wi-Fi
  details, filenames, notification text, biometric details, or exception text.
- Record only the schema fields. A native capability report is a runtime claim,
  not proof of StrongBox attestation.
- Run destructive recovery and revocation tests only against disposable test
  keys and synthetic vault data.

## Preparation

1. Run `tool/build_check.sh` on the workstation. Stop on any failure.
2. Connect the Redmi Turbo with USB debugging explicitly enabled for this test.
3. Run `tool/adb_readiness.sh`. It reports only ready/not-ready and never emits
   the device identifier.
4. Build the app from the reviewed commit. Install it manually using the normal
   Android development workflow; the helper scripts intentionally do not
   install or mutate the device.
5. Create a fresh JSON record from the synthetic example, change
   `recordKind` to `real_device`, reset all scenario results to `blocked`, and
   keep all test data synthetic.

## Result rules

A scenario is `pass` only when every listed check passes. It is `fail` when an
observed result violates any check, with the closest allowlisted failure code.
It is `blocked` when the scenario cannot be completed; use `not_run` or the
closest allowlisted environmental code. Overall is `pass` only when all nine
scenarios pass, `fail` if any fails, otherwise `blocked`.

## Scenarios

### 1. Install and launch (`install_launch`, 3 checks)

1. Android accepts the reviewed build without requesting undeclared access.
2. The app launches to its expected locked or onboarding state.
3. No real user content is needed to proceed.

Pass: all three. Fail: installation or launch fails, or real content is
required (`install_failed`, `launch_failed`, or `unexpected_result`).

### 2. Offline operation (`offline_operation`, 3 checks)

1. Enable airplane mode manually after creating one synthetic local record.
2. Relaunch and read/update that synthetic record.
3. Verify the change is queued locally without requiring a server response.

Pass: all three. Fail if core use becomes network-dependent
(`network_dependency`).

### 3. Screen lock (`screen_lock`, 4 checks)

1. Open the synthetic vault through the normal authentication gate.
2. Lock the screen, wait beyond the configured grant lifetime, and unlock it.
3. Return to the app; protected data must be gated.
4. Cancel authentication; protected data must remain unavailable.

Pass: all four. Fail if protected state is exposed (`lock_bypass`).

### 4. Device reboot (`device_reboot`, 4 checks)

1. With only synthetic data stored, reboot manually.
2. Launch before authenticating; the vault must remain locked.
3. Authenticate; committed synthetic state must be restored.
4. Pending encrypted work must be recoverable without plaintext leakage.

Pass: all four. Fail on bypass or lost committed state (`lock_bypass` or
`state_not_restored`).

### 5. Capability report (`capability_report`, 4 checks)

1. Read only the app's structured capability UI/export; do not use system logs.
2. Confirm authentication and device-credential booleans match observed gates.
3. Confirm non-exportability and atomic-revocation values are not hard-coded.
4. Record the exact protection enum. Do not upgrade `trusted_environment` to
   `strongbox` without a future attestation design.

Pass: all four. Fail on contradiction (`capability_mismatch`).

### 6. Vault wrong-key rejection (`vault_wrong_key`, 3 checks)

1. Use a deliberately unrelated disposable test key handle.
2. Attempt to open a copied synthetic encrypted fixture.
3. Confirm access fails closed and no partial plaintext becomes visible.

Pass: rejection with no plaintext. Fail if accepted (`wrong_key_accepted`).

### 7. Trusted-device recovery (`trusted_device_recovery`, 5 checks)

1. Use two dedicated test devices or an approved simulator as the trusted peer.
2. Start migration with synthetic data and authenticate both endpoints.
3. Confirm encrypted transfer requires explicit approval.
4. Confirm the recovered vault matches synthetic fixture counts.
5. Confirm the old transfer capability cannot be reused.

Pass: all five. Fail on mismatch, bypass, or replay (`recovery_failed`).

### 8. Offline-package recovery (`offline_package_recovery`, 5 checks)

1. Create a disposable encrypted recovery package from synthetic data.
2. Move it through an approved test-only path without recording filenames.
3. Enter a dedicated high-entropy test recovery code.
4. Confirm a wrong code reveals no data; then recover with the correct code.
5. Confirm the recovery capability is rotated or invalidated as designed.

Pass: all five. Fail on disclosure, wrong-code acceptance, or unusable correct
recovery (`recovery_failed` or `wrong_key_accepted`).

### 9. Device revocation (`device_revocation`, 5 checks)

1. Provision two disposable device identities with synthetic data.
2. Revoke one through the approved test flow.
3. Confirm revocation and account-epoch rotation complete as one operation.
4. Confirm the revoked device cannot authorize new data, online or offline.
5. Confirm the retained device can create and later synchronize new data.

Pass: all five. Fail if the revoked device authorizes future data
(`revoked_device_authorized`) or rotation is incomplete (`unexpected_result`).

## Finalization

1. Set counts, allowlisted codes, scenario results, and overall result only.
2. Run `tool/check_evidence.sh path/to/record.json`.
3. Review the JSON manually for prohibited identifiers or free text.
4. Remove disposable app data and test keys using normal UI/platform controls.
   Do not use helper scripts to delete device data.
