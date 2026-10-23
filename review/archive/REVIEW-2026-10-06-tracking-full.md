

### Dropped checks (2026-10-23, user agreed)

BFA before/after headline numbers for CR-BUG-02, R2-BUG-04, R2-BUG-06, R2-BUG-07 (B4) and SP P0-8 are dropped. Each fix has a Decision log row with a synthetic check and a regression test that fails before and passes after. A clean "before" no longer exists: the batch pipeline arrived on 2026-10-19, after those commits, and reverting them on today's `dev` conflicts with DOC-10 and DOC-13 in the same code. The scoped Databricks bearer-token secret (CR-SEC-03) was confirmed on Connect by the user on 2026-10-23.

### CR-CQ-03 closed, CR-CQ-04 deferred (2026-10-23)

| CR-CQ-03 | L-M | M | ☐ | One `cachem` helper; `bindCache()` on run-pure outputs. Overlaps R2-PERF-03/04. |
| CR-CQ-04 | M | M | ☐ | Define outputs once at module level (58 are defined inside observers). |

Decision log, CR-CQ-03 and CR-CQ-04 (2026-10-23, user: as recommended). CR-CQ-03: of about 45 `new.env()` sites only the aggregation, preparation, suite, lasso and metadata caches are caches, and all but one were already bounded (`max_entries` with key order). The loose one, `ws$weighted_suite_cache` in `mod_2_02_results.R`, is now bounded at 32 entries with least-recently-used eviction (`get_suite()`, `assign_suite()`; test in `test-mod_2_02_results.R`). `cachem` was not adopted (not in `DESCRIPTION`, would refactor working caches, overlaps R2-PERF-03); `bindCache()` on run-pure outputs stays with R2-PERF-03. CR-CQ-04: a parse of `R/mod_*.R` finds 58 `output$... <-` inside observers (`mod_1_07_results` 22, `mod_1_05_weatherstats` 14, `mod_1_02_surveystats` 12, `mod_1_03_outcome` 9, `mod_3_08_diagnostics` 1 with dynamic ids). They bind to the fit-time snapshot by design (INT-05), hoisting them needs a reactive for each captured local, and no R test covers the real Step 1 flow. No user-visible bug, so deferred.

