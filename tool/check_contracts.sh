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
python3 -m unittest tool/tests/test_evidence_ledger.py
python3 -m unittest tool/tests/test_audit_remote_branches.py
python3 tool/evidence_ledger.py --ledger evidence/mvp/status.json
python3 tool/check_external_provider_boundary.py

echo 'repository contracts: PASS'
