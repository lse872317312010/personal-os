PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

CREATE TABLE schema_metadata (
  singleton_id INTEGER PRIMARY KEY CHECK (singleton_id = 1),
  schema_version INTEGER NOT NULL CHECK (schema_version >= 1),
  migration_id TEXT NOT NULL,
  applied_at TEXT NOT NULL,
  application_build TEXT
);

INSERT INTO schema_metadata (
  singleton_id, schema_version, migration_id, applied_at
) VALUES (
  1, 1, '0001_vault_schema', strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
);

CREATE TABLE event_log (
  sequence_no INTEGER PRIMARY KEY AUTOINCREMENT,
  event_id TEXT NOT NULL UNIQUE CHECK (length(trim(event_id)) > 0),
  event_type TEXT NOT NULL CHECK (length(trim(event_type)) > 0),
  event_version INTEGER NOT NULL CHECK (event_version > 0),
  occurred_at TEXT NOT NULL,
  recorded_at TEXT NOT NULL,
  actor_json TEXT NOT NULL CHECK (json_valid(actor_json)),
  correlation_id TEXT NOT NULL CHECK (length(trim(correlation_id)) > 0),
  causation_id TEXT,
  source_refs_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(source_refs_json)),
  consent_refs_json TEXT NOT NULL DEFAULT '[]' CHECK (json_valid(consent_refs_json)),
  sensitivity TEXT NOT NULL CHECK (sensitivity IN ('D0', 'D1', 'D2', 'D3')),
  payload_json TEXT NOT NULL CHECK (json_valid(payload_json)),
  integrity_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(integrity_json)),
  extensions_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(extensions_json))
);

CREATE INDEX event_log_recorded_order_idx
  ON event_log(recorded_at, sequence_no);
CREATE INDEX event_log_correlation_idx ON event_log(correlation_id);
CREATE INDEX event_log_causation_idx ON event_log(causation_id)
  WHERE causation_id IS NOT NULL;

CREATE TABLE event_subjects (
  event_id TEXT NOT NULL REFERENCES event_log(event_id) ON DELETE RESTRICT,
  subject_type TEXT NOT NULL CHECK (length(trim(subject_type)) > 0),
  subject_id TEXT NOT NULL CHECK (length(trim(subject_id)) > 0),
  subject_revision INTEGER CHECK (subject_revision IS NULL OR subject_revision >= 0),
  subject_ordinal INTEGER NOT NULL CHECK (subject_ordinal >= 0),
  PRIMARY KEY (event_id, subject_type, subject_id)
);

CREATE INDEX event_subjects_subject_idx
  ON event_subjects(subject_type, subject_id, event_id);

CREATE TABLE projections (
  projection_type TEXT NOT NULL,
  subject_type TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision >= 0),
  last_event_id TEXT NOT NULL REFERENCES event_log(event_id) ON DELETE RESTRICT,
  state_json TEXT NOT NULL CHECK (json_valid(state_json)),
  sensitivity TEXT NOT NULL CHECK (sensitivity IN ('D0', 'D1', 'D2', 'D3')),
  updated_at TEXT NOT NULL,
  PRIMARY KEY (projection_type, subject_type, subject_id)
);

CREATE INDEX projections_subject_idx
  ON projections(subject_type, subject_id, projection_type);

CREATE TABLE outbox (
  outbox_id TEXT PRIMARY KEY CHECK (length(trim(outbox_id)) > 0),
  event_id TEXT NOT NULL UNIQUE REFERENCES event_log(event_id) ON DELETE RESTRICT,
  destination TEXT NOT NULL CHECK (length(trim(destination)) > 0),
  envelope_json TEXT NOT NULL CHECK (json_valid(envelope_json)),
  sensitivity TEXT NOT NULL CHECK (sensitivity IN ('D0', 'D1', 'D2', 'D3')),
  state TEXT NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'leased', 'delivered', 'failed', 'cancelled')),
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  next_attempt_at TEXT,
  lease_expires_at TEXT,
  created_at TEXT NOT NULL,
  delivered_at TEXT,
  last_error_code TEXT
);

CREATE INDEX outbox_dispatch_idx
  ON outbox(state, next_attempt_at, created_at);

CREATE TABLE blob_metadata (
  blob_id TEXT PRIMARY KEY CHECK (length(trim(blob_id)) > 0),
  owner_subject_type TEXT NOT NULL,
  owner_subject_id TEXT NOT NULL,
  media_type TEXT NOT NULL,
  byte_length INTEGER NOT NULL CHECK (byte_length >= 0),
  ciphertext_digest TEXT NOT NULL CHECK (length(trim(ciphertext_digest)) > 0),
  storage_locator TEXT NOT NULL UNIQUE CHECK (length(trim(storage_locator)) > 0),
  encryption_format TEXT NOT NULL,
  key_reference TEXT NOT NULL,
  sensitivity TEXT NOT NULL CHECK (sensitivity IN ('D0', 'D1', 'D2', 'D3')),
  created_at TEXT NOT NULL,
  deleted_at TEXT
);

CREATE INDEX blob_metadata_owner_idx
  ON blob_metadata(owner_subject_type, owner_subject_id, created_at);

CREATE TABLE consent_revisions (
  consent_id TEXT NOT NULL,
  revision INTEGER NOT NULL CHECK (revision > 0),
  subject_id TEXT NOT NULL,
  authorized_actor_id TEXT NOT NULL,
  purposes_json TEXT NOT NULL CHECK (json_valid(purposes_json)),
  resources_json TEXT NOT NULL CHECK (json_valid(resources_json)),
  actions_json TEXT NOT NULL CHECK (json_valid(actions_json)),
  maximum_sensitivity TEXT NOT NULL
    CHECK (maximum_sensitivity IN ('D0', 'D1', 'D2', 'D3')),
  valid_from TEXT NOT NULL,
  valid_until TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('active', 'revoked', 'superseded')),
  source_event_id TEXT NOT NULL REFERENCES event_log(event_id) ON DELETE RESTRICT,
  recorded_at TEXT NOT NULL,
  PRIMARY KEY (consent_id, revision),
  CHECK (valid_until > valid_from)
);

CREATE INDEX consent_revisions_subject_idx
  ON consent_revisions(subject_id, authorized_actor_id, status);

CREATE TABLE deletion_tombstones (
  tombstone_id TEXT PRIMARY KEY CHECK (length(trim(tombstone_id)) > 0),
  target_type TEXT NOT NULL,
  target_token TEXT NOT NULL UNIQUE CHECK (length(trim(target_token)) >= 22),
  scope TEXT NOT NULL CHECK (scope IN ('logical', 'content', 'cryptographic', 'full')),
  requested_event_id TEXT REFERENCES event_log(event_id) ON DELETE RESTRICT,
  completed_event_id TEXT REFERENCES event_log(event_id) ON DELETE RESTRICT,
  deleted_at TEXT NOT NULL,
  audit_json TEXT NOT NULL DEFAULT '{}' CHECK (json_valid(audit_json)),
  UNIQUE (target_type, target_token, scope)
);

CREATE TABLE deletion_propagation_log (
  propagation_id TEXT PRIMARY KEY CHECK (length(trim(propagation_id)) > 0),
  tombstone_id TEXT NOT NULL
    REFERENCES deletion_tombstones(tombstone_id) ON DELETE RESTRICT,
  destination TEXT NOT NULL CHECK (length(trim(destination)) > 0),
  state TEXT NOT NULL
    CHECK (state IN ('pending', 'acknowledged', 'failed', 'unreachable')),
  attempt_no INTEGER NOT NULL CHECK (attempt_no > 0),
  recorded_at TEXT NOT NULL,
  error_code TEXT,
  source_event_id TEXT REFERENCES event_log(event_id) ON DELETE RESTRICT,
  UNIQUE (tombstone_id, destination, attempt_no)
);

CREATE INDEX deletion_propagation_lookup_idx
  ON deletion_propagation_log(tombstone_id, destination, attempt_no DESC);

CREATE TRIGGER event_log_no_update
BEFORE UPDATE ON event_log
BEGIN
  SELECT RAISE(ABORT, 'event_log is append-only');
END;

CREATE TRIGGER event_log_no_delete
BEFORE DELETE ON event_log
BEGIN
  SELECT RAISE(ABORT, 'event_log is append-only');
END;

CREATE TRIGGER consent_revisions_no_update
BEFORE UPDATE ON consent_revisions
BEGIN
  SELECT RAISE(ABORT, 'consent revisions are append-only');
END;

CREATE TRIGGER consent_revisions_no_delete
BEFORE DELETE ON consent_revisions
BEGIN
  SELECT RAISE(ABORT, 'consent revisions are append-only');
END;

CREATE TRIGGER deletion_tombstones_no_update
BEFORE UPDATE ON deletion_tombstones
BEGIN
  SELECT RAISE(ABORT, 'deletion tombstones are immutable');
END;

CREATE TRIGGER deletion_tombstones_no_delete
BEFORE DELETE ON deletion_tombstones
BEGIN
  SELECT RAISE(ABORT, 'deletion tombstones are immutable');
END;

CREATE TRIGGER deletion_propagation_log_no_update
BEFORE UPDATE ON deletion_propagation_log
BEGIN
  SELECT RAISE(ABORT, 'deletion propagation log is append-only');
END;

CREATE TRIGGER deletion_propagation_log_no_delete
BEFORE DELETE ON deletion_propagation_log
BEGIN
  SELECT RAISE(ABORT, 'deletion propagation log is append-only');
END;

COMMIT;
