# Contract audit

Standard-library-only static checks that keep Recovery Protocol v1 and its
language-neutral JSON fixtures aligned.

From the repository root:

```sh
python3 tool/contract_audit/audit_recovery.py
python3 -m unittest discover -s tool/contract_audit/tests -v
```
