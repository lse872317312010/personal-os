# Policy/Application adapter

Production adapter for `AppearancePolicyPort`. It requires one exact-revision
Consent reference and evaluates the fixed appearance scope
`appearance_review / portrait / derive / D3` through `personal_os_policy`.

Missing, malformed, expired, revoked, mismatched, or unreadable Consent always
denies authorization. Test-only fixed/fake policy implementations must never be
used in a production composition root.
