#!/usr/bin/env python3
"""SQLite schema smoke test; does not claim SQLCipher encryption coverage."""

from pathlib import Path
import sqlite3


ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "migrations" / "0001_vault_schema.sql"
REQUIRED_TABLES = {
    "schema_metadata",
    "event_log",
    "event_subjects",
    "projections",
    "outbox",
    "blob_metadata",
    "consent_revisions",
    "deletion_tombstones",
    "deletion_propagation_log",
}
FORBIDDEN_COLUMNS = {
    "raw_key",
    "database_key",
    "encryption_key",
    "private_key",
    "recovery_code",
    "password",
    "api_key",
    "access_token",
    "refresh_token",
    "target_id_digest",
    "target_id_hash",
    "target_digest",
    "target_hash",
    "object_id_digest",
    "object_id_hash",
    "deleted_identifier_digest",
    "deleted_identifier_hash",
    "content_digest",
    "content_hash",
    "plaintext_digest",
    "plaintext_hash",
    "subject_hash",
    "subject_digest",
}


def event_values(event_id: str, sensitivity: str = "D2") -> tuple[object, ...]:
    return (
        event_id,
        "claim.proposed",
        1,
        "2026-08-20T00:00:00.000Z",
        "2026-08-20T00:00:01.000Z",
        '{"actor_id":"user-1"}',
        "correlation-1",
        sensitivity,
        '{"claim_id":"claim-1"}',
    )


def main() -> None:
    db = sqlite3.connect(":memory:", isolation_level=None)
    db.executescript(MIGRATION.read_text(encoding="utf-8"))

    tables = {
        row[0]
        for row in db.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )
    }
    assert REQUIRED_TABLES <= tables, REQUIRED_TABLES - tables

    for table in REQUIRED_TABLES:
        columns = {row[1] for row in db.execute(f"PRAGMA table_info({table})")}
        assert not (columns & FORBIDDEN_COLUMNS), (table, columns & FORBIDDEN_COLUMNS)

    indexes = {
        row[0]
        for row in db.execute(
            "SELECT name FROM sqlite_master WHERE type='index'"
        )
    }
    assert "event_subjects_subject_idx" in indexes
    blob_columns = {
        row[1] for row in db.execute("PRAGMA table_info(blob_metadata)")
    }
    assert "ciphertext_digest" in blob_columns
    tombstone_columns = {
        row[1] for row in db.execute("PRAGMA table_info(deletion_tombstones)")
    }
    assert "target_token" in tombstone_columns
    assert "propagation_state" not in tombstone_columns
    subject_columns = {
        row[1] for row in db.execute("PRAGMA table_info(event_subjects)")
    }
    assert "subject_revision" in subject_columns
    assert "subject_ordinal" in subject_columns

    insert_event = """
        INSERT INTO event_log (
          event_id, event_type, event_version, occurred_at, recorded_at,
          actor_json, correlation_id, sensitivity, payload_json
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    """

    # D4 is denied by the database even if an application validator is bypassed.
    try:
        db.execute(insert_event, event_values("event-d4", "D4"))
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("D4 unexpectedly persisted")

    # Duplicate IDs are idempotency conflicts, never duplicate state changes.
    db.execute(insert_event, event_values("event-1"))
    try:
        db.execute(insert_event, event_values("event-1"))
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("duplicate event_id unexpectedly persisted")

    # A failed projection write rolls the event and outbox back together.
    db.execute("BEGIN IMMEDIATE")
    try:
        db.execute(insert_event, event_values("event-atomic"))
        db.execute(
            "INSERT INTO event_subjects VALUES (?, ?, ?, ?, ?)",
            ("event-atomic", "claim", "claim-1", 3, 0),
        )
        db.execute(
            """INSERT INTO projections VALUES
               (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "claim",
                "claim",
                "claim-1",
                -1,
                "event-atomic",
                "{}",
                "D2",
                "2026-08-20T00:00:01.000Z",
            ),
        )
        db.execute("COMMIT")
    except sqlite3.IntegrityError:
        db.execute("ROLLBACK")
    else:
        raise AssertionError("invalid projection unexpectedly committed")

    assert db.execute(
        "SELECT count(*) FROM event_log WHERE event_id='event-atomic'"
    ).fetchone()[0] == 0

    # Happy path commits event, subject index, projection, and outbox together.
    db.execute("BEGIN IMMEDIATE")
    db.execute(insert_event, event_values("event-committed"))
    db.execute(
        "INSERT INTO event_subjects VALUES (?, ?, ?, ?, ?)",
        ("event-committed", "claim", "claim-2", 7, 0),
    )
    db.execute(
        """INSERT INTO projections VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            "claim",
            "claim",
            "claim-2",
            1,
            "event-committed",
            "{}",
            "D2",
            "2026-08-20T00:00:01.000Z",
        ),
    )
    db.execute(
        """INSERT INTO outbox (
             outbox_id, event_id, destination, envelope_json, sensitivity,
             created_at
           ) VALUES (?, ?, ?, ?, ?, ?)""",
        (
            "outbox-1",
            "event-committed",
            "trusted-device",
            "{}",
            "D2",
            "2026-08-20T00:00:01.000Z",
        ),
    )
    db.execute("COMMIT")
    for table in ("event_log", "event_subjects", "projections", "outbox"):
        assert db.execute(f"SELECT count(*) FROM {table}").fetchone()[0] >= 1
    assert db.execute(
        "SELECT subject_revision FROM event_subjects WHERE event_id=?",
        ("event-committed",),
    ).fetchone()[0] == 7

    # Deletion identity is an opaque random token; propagation evolves by append.
    db.execute(
        """INSERT INTO deletion_tombstones (
             tombstone_id, target_type, target_token, scope, deleted_at
           ) VALUES (?, ?, ?, ?, ?)""",
        (
            "tombstone-1",
            "blob",
            "J7vVh4nPk2sQ8mWx9Lc3Za",
            "cryptographic",
            "2026-08-20T00:00:02.000Z",
        ),
    )
    db.execute(
        """INSERT INTO deletion_propagation_log VALUES
           (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            "propagation-1",
            "tombstone-1",
            "trusted-device",
            "pending",
            1,
            "2026-08-20T00:00:03.000Z",
            None,
            None,
        ),
    )
    db.execute(
        """INSERT INTO deletion_propagation_log VALUES
           (?, ?, ?, ?, ?, ?, ?, ?)""",
        (
            "propagation-2",
            "tombstone-1",
            "trusted-device",
            "acknowledged",
            2,
            "2026-08-20T00:00:04.000Z",
            None,
            None,
        ),
    )
    assert db.execute(
        "SELECT count(*) FROM deletion_propagation_log WHERE tombstone_id=?",
        ("tombstone-1",),
    ).fetchone()[0] == 2
    try:
        db.execute(
            "UPDATE deletion_propagation_log SET state='failed' "
            "WHERE propagation_id='propagation-1'"
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("propagation log update unexpectedly succeeded")

    # Append-only enforcement is active.
    try:
        db.execute(
            "UPDATE event_log SET event_type='changed' WHERE event_id='event-1'"
        )
    except sqlite3.IntegrityError:
        pass
    else:
        raise AssertionError("event_log update unexpectedly succeeded")

    print("sqlite_vault schema v1: PASS (SQLite only; SQLCipher not exercised)")


if __name__ == "__main__":
    main()
