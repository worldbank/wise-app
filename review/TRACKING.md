# Maintenance Tracker

Open app/repo maintenance only. Use git for routine history; look up closure evidence, deferrals and numerical decisions by ID in `review/archive/REVIEW-2026-10-06-tracking-full.md`. Original findings: `review/archive/REVIEW-2026-10-06.md` (immutable).

## Working rules

- **Add:** check tracker/archive for duplicates. Use a stable existing ID or unused `<AREA>-NN`; one closable issue per row, with next action/acceptance condition and source. Never reuse IDs.
- **Group:** Data and Methods; UX and Accessibility; Engineering and Tests; Security and Deployment; Performance. Add a category and copy the table header when needed; no empty tables, placeholder rows, counts or separate waiting list. Sort by severity, then actionable before blocked.
- **Update:** retain only the open remainder; mark started work `◐`. For `blocked`, name the dependency and unblock action. Link long evidence rather than embedding it.
- **Close:** demonstrate the fix with regression tests or reproducible docs/config checks; run relevant tests (`wise-verify`). Archive the full row, dated outcome, commit/reference, evidence and unchecked paths, then remove it here. Code reading alone is not verification.
- **Defer/reopen:** user-approved deferrals need an archived reason, date and reopen trigger, not a claim of completion. Restore the same ID and link that decision when reopening. Procedure: `wise-close-finding`.
- **Gates:** numerical changes need archived BFA before/after and a Decision log (`wise-numeric-change`); speed claims need timing and peak memory (`wise-benchmark`). Follow `AGENTS.md` for Git/permissions and `wise-verify` for remaining checks. No rolling Log.

Status: `☐` todo, `◐` in progress, `blocked` awaiting a named dependency. Closed and deferred items belong only in the archive. Sev: C critical, H high, M medium, L low, I informational. Eff: S < 1 day, M 1-3 days, L > 3 days; `?` means untriaged.

## Data and Methods

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|

## UX and Accessibility

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| CR-A11Y-09 | M | M | blocked | Confirm one successful GitHub run of the expanded 16-screen axe scan after an authorized push; run a real-data pass through Steps 1-3 and result tabs. | `tests/e2e/smoke.R`; `.github/workflows/e2e-smoke.yaml`; archive CR-A11Y-09. Green locally with `WISEAPP_AXE_FAIL=1`; four violation types fixed. Earlier green CI covered two screens only. Navbar upstream exception and transient-toast exclusion remain documented. `main` requires `e2e-smoke`; `dev` is unprotected by decision. |

## Engineering and Tests

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| CR-CQ-01 | M | L | ◐ | Move static builders out and split the three giant server functions; keep changes per file with characterization tests. Dead-code sweep is done. Start where `fct_*` files call into `mod_*` files: pure helpers in `mod_3_09_decomposition.R` (compact-decomposition helpers) and `mod_3_08_diagnostics.R` (table and card builders) move to `fct_*`. Next: the nested pure closures in `mod_2_02_results.R` (aggregation builders, cache helpers, duplicate `build_for` and `tbl_of`), `effect_y_lab` in `mod_1_07_results.R`, the duplicate `with_grid_num` (`mod_3_01_sp.R`) and `step2_with_grid_num` (`mod_2_01_weathersim.R`), then the server bodies of `mod_3_01_sp.R` and `mod_3_06_policy_sim.R` (`run()`), which were not read in full. Open from the sweep, each a signature change: unused arguments of non-exported helpers whose tests or callers still pass them (for example `.s1_turning_point(snap)`, `.policy_reach_cards(analysis_unit)`, `.weather_reactable(pct_cols)`, `step3_metric_worker(artifact_dir)` in async code), and `eff_10`/`eff_50` in `step3_headline_cards`, whose removal cascades to `get_eff`. | `archive/REVIEW-2026-10-06.md`, CR-CQ-01; `code_hygiene.md`. Hygiene batches 1 to 4 on `dev`: `5cfac43`, `9e67645`, `063f8f9`, `5937f14` (ASCII comments, dead locals and helpers, unused arguments, unused module formals; full suite 1651 tests, 0 failures after each batch). Protected files changed by whitespace only, apart from two unused timers in `fct_run_simulation.R`. |
