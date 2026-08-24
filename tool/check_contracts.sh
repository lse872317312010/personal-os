#!/usr/bin/env bash
set -Eeuo pipefail
readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"
python3 tool/validate_local_dependencies.py
python3 adapters/sqlite_vault/tool/validate_schema.py
python3 tool/contract_audit/audit_recovery.py
python3 -m unittest discover -s tool/contract_audit/tests -p 'test_*.py'
python3 -m unittest discover -s tool/mvp_acceptance/tests -p 'test_*.py'
python3 tool/tests/test_check_composition_root.py
python3 tool/check_composition_root.py
python3 tool/tests/test_check_persistence_boundary.py
python3 tool/check_persistence_boundary.py
python3 -m unittest discover -s tool/tests -p 'test_*.py'
python3 tool/validate_sync_envelope.py evidence/sync_envelope/synthetic.example.json
python3 evidence/android/tool/validate_evidence.py evidence/android/records/synthetic.example.json
echo 'repository contracts: PASS (sync signature verification remains unverified)'
