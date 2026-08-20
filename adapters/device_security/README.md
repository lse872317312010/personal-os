# Device security adapter

Cross-platform Dart adapter between `security_api` and a replaceable native
bridge. Android is the first target; Apple and desktop bridges can implement the
same contract without changing domain or application code.

This package does **not** implement Android Keystore, StrongBox, biometric
prompts, Keychain, Secure Enclave, TPM, or Windows Hello. Hardware properties
are runtime reports from a future native implementation and must not be inferred
from a Redmi model name or Android version.

Security boundaries:

- key material is represented only by opaque handles;
- authentication grants are short-lived opaque capabilities;
- wrapped ciphertext is defensively copied;
- device revocation and account-epoch rotation are one bridge operation;
- logs use an allowlisted event with no arbitrary text or metadata;
- native exception messages never cross into domain errors or logs.

A production bridge must validate grant expiry and binding inside the native
security boundary. Dart-side expiry checks are useful lifecycle controls but are
not a substitute for platform enforcement.
