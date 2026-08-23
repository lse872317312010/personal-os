#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

python3 tool/validate_local_dependencies.py
python3 adapters/sqlite_vault/tool/validate_schema.py
python3 tool/contract_audit/audit_recovery.py
python3 -m unittest discover -s tool/contract_audit/tests -p 'test_*.py'
python3 -m unittest discover -s tool/mvp_acceptance/tests -p 'test_*.py'
python3 -m unittest discover -s evidence/android/tool/tests -p 'test_*.py'
# ADR-0010 v2: validator auto-dispatches by shape.
# - evidence/mvp/synthetic.example.json exercises the ledger chain +
#   cross-record cumulative_hash path.
# - evidence/mvp/status.json exercises the empty-ledger genesis path.
# - evidence/android/records/synthetic.example.json exercises the
#   Android device record schema.
python3 evidence/android/tool/validate_evidence.py \
  evidence/mvp/synthetic.example.json
python3 evidence/android/tool/validate_evidence.py \
  evidence/mvp/status.json
python3 evidence/android/tool/validate_evidence.py \
  evidence/android/records/synthetic.example.json

echo 'repository contracts: PASS'
