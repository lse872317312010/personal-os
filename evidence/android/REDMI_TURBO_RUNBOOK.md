# Redmi Turbo MVP device-validation runbook

Status: **not run**. This is the canonical G3 procedure. Repository tests,
Actions results, emulators, and synthetic records cannot mark a scenario as
passed.

## Safety and evidence boundary

- Use only a dedicated test profile and synthetic records.
- Bind the record to the exact candidate commit and APK SHA-256 from verified
  release provenance.
- Never record a serial number, Android ID, account ID, build fingerprint,
  biometric detail, filename, device path, photo, raw log, exception text, or
  notification content.
- Do not run `adb logcat`, pull app storage, copy the SQLCipher database, or
  upload screenshots containing user content.
- The only accepted record shape is schema version 2 in
  `schema/evidence.schema.json`.

## Preparation

1. Verify the APK, checksum sidecar, and provenance:

   ```sh
   python3 tool/android_mvp/verify_release_candidate.py \
     --apk personal-os-latest-debug.apk \
     --checksum personal-os-latest-debug.apk.sha256 \
     --provenance personal-os-latest-debug.provenance.json
   ```

2. Run workstation and ADB readiness checks:

   ```sh
   bash evidence/android/tool/build_check.sh
   bash evidence/android/tool/adb_readiness.sh
   ```

3. Copy `records/synthetic.example.json` outside the repository. Change
   `recordKind` to `real_device`, fill the verified commit and APK digest,
   use real UTC start/end times, and leave every scenario blocked until it has
   actually been executed.
4. Install the exact verified APK. Do not rebuild between scenarios.

## Result rules

A scenario is `pass` only when every numbered check passes. It is `fail`
when an observed result violates a check, using the closest allowlisted stable
failure code. It remains `blocked` when a prerequisite is missing or it has
not been run. Overall is `pass` only when all nine scenarios pass, `fail`
when any scenario fails, and otherwise `blocked`.

## Canonical nine scenarios

### 1. Install and launch (`install_launch`, 3 checks)

1. Android installs the verified APK without requesting undeclared access.
2. The first launch displays the locked Vault gate.
3. No protected history, Blob reference, analysis result, or real content is
   visible before authentication.

Failure codes: `install_failed`, `launch_failed`, `lock_bypass`.

### 2. Offline strategy loop (`offline_loop`, 4 checks)

1. Enable airplane mode before opening the Vault.
2. Create a synthetic Agent/strategy session and reach at least one execution
   and deterministic outcome.
3. Confirm the UI remains functional without a server response or embedded
   model dependency.
4. Lock and unlock; the committed synthetic state remains readable.

Failure codes: `network_dependency`, `state_not_restored`.

### 3. Process death (`process_death`, 4 checks)

1. Leave one open synthetic strategy session with a current execution outcome.
2. Run `adb shell am force-stop com.personalos.app`, then relaunch with
   `adb shell monkey -p com.personalos.app -c android.intent.category.LAUNCHER 1`.
3. Confirm the app returns to the locked gate and exposes no protected state.
4. Authenticate and confirm the same session identity, execution, outcome, and
   review state are reconstructed without duplicate events.

Failure codes: `lock_bypass`, `state_not_restored`.

### 4. Device reboot (`device_reboot`, 4 checks)

1. Reboot manually with only synthetic data stored.
2. Launch before authentication and confirm the Vault stays locked.
3. Authenticate and confirm committed appearance and strategy history restore.
4. Continue the restored strategy once and confirm the new event persists.

Failure codes: `lock_bypass`, `state_not_restored`.

### 5. Lock and unlock (`lock_unlock`, 4 checks)

1. Open the Vault through the normal system authentication gate.
2. Lock from the app and confirm all protected projections disappear.
3. Cancel the next authentication attempt; the Vault remains locked.
4. Authenticate again and confirm projections are rebuilt from durable events.

Failure codes: `lock_bypass`, `state_not_restored`.

### 6. Permission denial (`permission_denied`, 3 checks)

1. Open Photo Picker and cancel; confirm no Blob, observation, or model call is
   created. Photo Picker itself should not request shared-storage permission.
2. Start camera capture, deny the runtime camera permission, and confirm the
   operation fails closed with stable UI behavior.
3. Reopen the app and confirm denial did not corrupt or mutate prior history.

Failure codes: `permission_behavior_invalid`, `unexpected_result`.

### 7. HyperOS battery restriction (`battery_restriction`, 3 checks)

1. Set the app to the restrictive HyperOS battery mode.
2. Leave the app, allow the OS to stop it, and relaunch normally.
3. Confirm no background service is required and committed state restores only
   after Vault authentication.

Failure codes: `battery_behavior_invalid`, `state_not_restored`.

### 8. Export and local deletion (`export_delete`, 5 checks)

1. With synthetic history present, export an encrypted `.posb` backup.
2. Cancel one export attempt and confirm no success state is reported.
3. Lock the Vault, then clear the app's local storage through Android Settings.
4. Relaunch and authenticate into a fresh Vault; old local history must be
   absent.
5. Confirm the external encrypted backup remains the only recovery capability
   and that deleting local storage did not expose plaintext.

Failure codes: `export_failed`, `delete_failed`, `lock_bypass`.

### 9. Encrypted recovery drill (`recovery_drill`, 8 checks)

1. Start from a fresh Vault after the deletion scenario.
2. Select the previously exported encrypted backup.
3. Enter a deliberately wrong test passphrase; confirm
   `backup.authentication_failed` and zero restored events.
4. Modify one byte in a disposable copy of the backup outside the phone; import
   it and confirm authentication failure with zero restored events.
5. Import the original backup with the correct passphrase.
6. Confirm the app locks immediately after the atomic restore.
7. Authenticate and compare only non-sensitive event counts and workflow state
   with the pre-export baseline.
8. Force-stop and relaunch once more; after authentication the restored state
   must remain identical and usable.

Failure codes: `backup_authentication_failed`,
`backup_tamper_accepted`, `backup_failed`, `recovery_failed`,
`state_not_restored`.

## Finalization

Validate the completed record:

```sh
bash evidence/android/tool/check_evidence.sh /path/to/record.json
python3 tool/android_mvp/validate_redmi_evidence.py \
  /path/to/record.json --require-ready
```

Review the JSON manually for prohibited identifiers or free text before
retaining it. A successful structural check means only that the record is
well-formed; `DEVICE_VERIFIED` requires a real-device record with all nine
scenarios passed.
