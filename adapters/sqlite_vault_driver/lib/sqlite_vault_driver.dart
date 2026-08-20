/// Driver-neutral lifecycle boundary for an encrypted local vault.
///
/// This package deliberately contains no SQLite, SQLCipher, Android Keystore,
/// or other platform implementation. In particular, it must not be treated as
/// evidence that encryption at rest is active.
library;

export 'src/vault_driver.dart';
