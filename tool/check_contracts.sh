#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

python3 tool/validate_local_dependencies.py
python3 adapters/sqlite_vault/tool/validate_schema.py
python3 tool/contract_audit/audit_recovery.py
python3 -m unittest discover -s tool/contract_audit/tests -p 'test_*.py'
python3 -m unittest discover -s tool/mvp_acceptance/tests -p 'test_*.py'
python3 evidence/android/tool/validate_evidence.py \
  evidence/android/records/synthetic.example.json
# ADR-0010 §4: validate the SHA-256 evidence ledger chain in the MVP
# status.json. The validator auto-dispatches by file shape; for the
# status.json ledger it walks records[] and recomputes each record_id.
python3 evidence/android/tool/validate_evidence.py \
  evidence/mvp/status.json
# Run the chain unit tests (record_id derivation, tamper detection, etc.).
python3 tool/test_evidence_chain.py

echo 'repository contracts: PASS'
