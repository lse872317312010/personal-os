PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

CREATE INDEX event_log_type_recorded_idx
  ON event_log(event_type, recorded_at, sequence_no);

CREATE INDEX projections_type_updated_idx
  ON projections(subject_type, updated_at DESC, subject_id);

CREATE INDEX projections_state_idx
  ON projections(
    subject_type,
    json_extract(state_json, '$.state'),
    updated_at DESC
  );

UPDATE schema_metadata
SET
  schema_version = 2,
  migration_id = '0002_strategy_loop_queries',
  applied_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE singleton_id = 1 AND schema_version = 1;

SELECT CASE
  WHEN changes() != 1
  THEN RAISE(ABORT, 'unexpected source schema version')
END;

COMMIT;
