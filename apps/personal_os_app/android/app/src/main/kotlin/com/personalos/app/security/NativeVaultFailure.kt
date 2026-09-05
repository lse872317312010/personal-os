package com.personalos.app.security

/** Stable failures that may cross the Flutter channel. No platform details belong here. */
internal enum class NativeVaultFailureCode(val wireValue: String, val safeMessage: String) {
    CANCELLED("security.unlock_cancelled", "Unlock was cancelled."),
    DENIED("security.unlock_denied", "Unlock was denied."),
    AUTHENTICATION_UNAVAILABLE("security.unlock_unavailable", "Secure authentication is unavailable."),
    AUTHENTICATION_EXPIRED("security.unlock_expired", "The unlock authorization has expired."),
    KEY_NOT_FOUND("security.key_not_found", "The secure key is unavailable."),
    PLAINTEXT_KEY_EXPORT_FORBIDDEN(
        "security.plaintext_key_export_forbidden",
        "Key material cannot be exported.",
    ),
    VAULT_LOCKED("security.vault_locked", "The vault is locked."),
    VAULT_SESSION_INVALID("security.vault_locked", "The vault session is invalid."),
    VAULT_EVENT_INVALID("security.vault_event_invalid", "The vault event is invalid."),
    VAULT_EVENT_CONFLICT(
        "security.vault_event_conflict",
        "The event conflicts with existing vault state.",
    ),
    TRANSACTION_FAILED("security.vault_transaction_failed", "The vault transaction failed."),
    SCHEMA_INVALID("security.vault_schema_invalid", "The vault schema is invalid."),
    SQLCIPHER_LIBRARY_UNAVAILABLE(
        "security.vault_library_unavailable",
        "The encrypted database library is unavailable.",
    ),
    VAULT_PATH_UNAVAILABLE(
        "security.vault_path_unavailable",
        "The private vault location is unavailable.",
    ),
    DATABASE_OPEN_FAILED(
        "security.vault_database_open_failed",
        "The encrypted database could not be opened.",
    ),
    CIPHER_VERIFICATION_FAILED(
        "security.vault_cipher_verification_failed",
        "The encrypted database provider could not be verified.",
    ),
    FOREIGN_KEYS_UNAVAILABLE(
        "security.vault_foreign_keys_unavailable",
        "Required database integrity enforcement is unavailable.",
    ),
    DATABASE_CONFIGURATION_FAILED(
        "security.vault_configuration_failed",
        "The encrypted database could not be configured.",
    ),
    JOURNAL_MODE_INVALID(
        "security.vault_journal_invalid",
        "The encrypted database journal mode is invalid.",
    ),
    UNAVAILABLE("security.provider_unavailable", "The secure vault is unavailable."),
}

internal class NativeVaultFailure(val failureCode: NativeVaultFailureCode) : Exception()
