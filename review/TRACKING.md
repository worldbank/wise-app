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
| CR-CQ-01 | M | L | ◐ | Split the three giant server functions; keep changes per file with characterization tests. Pure helpers already moved to `fct_*`/`utils_*` (steps a to c on branch `cr-cq-01`): compact-decomposition helpers (`fct_compact_decomp.R`), diagnostics table and card builders (`fct_policy_diagnostics.R`), aggregation workspace, cache and builder helpers (`fct_aggregation_workspace.R`), `.effect_y_lab` (`fct_results.R`) and `with_grid_num` (`utils_ui.R`). Open: (1) split the server bodies of `mod_3_01_sp.R` (about 1800 lines: the trigger `renderUI`, budget and timing UIs, the reach preview) and `mod_3_06_policy_sim.R` `run()` (the `publish` step and the async submit); a plan is awaiting review. (2) `mod_2_02_results.R` keeps two non-identical `tbl_of` closures (`results_source`, `.seed_aggregation_cache`) and two `build_for` closures inside the builders, which differ in shared-cache use and model ids; merging them is a behaviour change. (3) Each a signature change, from the sweep: unused arguments of non-exported helpers whose tests or callers still pass them (for example `.s1_turning_point(snap)`, `.policy_reach_cards(analysis_unit)`, `.weather_reactable(pct_cols)`, `step3_metric_worker(artifact_dir)` in async code), and `eff_10`/`eff_50` in `step3_headline_cards`, whose removal cascades to `get_eff`. | `archive/REVIEW-2026-10-06.md`, CR-CQ-01; `code_hygiene.md`. Hygiene batches 1 to 4 on `dev`: `5cfac43`, `9e67645`, `063f8f9`, `5937f14` (ASCII comments, dead locals and helpers, unused arguments, unused module formals; full suite 1651 tests, 0 failures after each batch). Protected files changed by whitespace only, apart from two unused timers in `fct_run_simulation.R`. Steps a to c: `e54626b`, `fd88ab4`, `795df92`; manifest regenerated in `0565227`, `d1a59b0`. Full suite after step c: 12458 tests, 0 failures apart from the manifest listing fixed by `d1a59b0`. |
