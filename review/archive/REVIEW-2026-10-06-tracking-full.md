

### Dropped checks (2026-10-23, user agreed)

BFA before/after headline numbers for CR-BUG-02, R2-BUG-04, R2-BUG-06, R2-BUG-07 (B4) and SP P0-8 are dropped. Each fix has a Decision log row with a synthetic check and a regression test that fails before and passes after. A clean "before" no longer exists: the batch pipeline arrived on 2026-10-19, after those commits, and reverting them on today's `dev` conflicts with DOC-10 and DOC-13 in the same code. The scoped Databricks bearer-token secret (CR-SEC-03) was confirmed on Connect by the user on 2026-10-23.
