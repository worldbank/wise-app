# Maintenance Tracker

The single list of actionable app and repository work. Group by maintenance area, not review date or batch. Keep existing IDs stable; use git history for routine progress, not a rolling log here. Finished work, deferred decisions, numerical Decision log entries and detailed evidence live in `review/archive/REVIEW-2026-10-06-tracking-full.md` (look up by ID). Original review findings are in `review/archive/REVIEW-2026-10-06.md` (immutable).

## Working rules

- **Add:** check this file and the archive for duplicates or a reopen trigger. Add one independently closable row under the relevant category, with an observable problem, next action or acceptance condition, and a source or code/test reference. Use an existing finding ID; for new work use `<AREA>-NN` (for example `CI-01`, `DATA-01`, `UX-01`), choosing an unused number across tracker and archive. Never reuse or renumber an ID.
- **Organize:** use Data and Methods; UX and Accessibility; Engineering and Tests; Security and Deployment; Performance, as needed. Omit empty categories. Order by severity, then actionable work before blocked work. Do not maintain counts or duplicate an issue in a separate waiting list.
- **Update:** keep only the current remainder. Mark work in progress when started; for blocked work name the dependency and concrete unblock action in the row. Put long evidence in the archive or linked review, not in the task cell.
- **Close a fix:** show a regression test failing before and passing after, or a reproducible docs/config check; run the narrowest relevant tests. Append the full row and dated outcome to the archive with commit/reference, verification and unchecked paths, then remove the active row. Do not close from code reading alone.
- **Defer or drop:** obtain the user's scope decision; archive the full row with reason, date, decision and a concrete reopen trigger, then remove it here. Do not describe deferred work or waived checks as implemented or verified. On reopening, restore the same ID and link the decision.
- **Verification:** numerical changes require a Decision log entry with BFA before/after (`wise-numeric-change`); speed claims require timing and peak memory (`wise-benchmark`). Follow `wise-verify` for tests, browser checks, documentation, full-suite/check and manifest follow-ups. Keep numerical decisions in the archive, not in this file.
- **Git:** work on `dev` or a branch off it; keep changes scoped and put the issue ID in the commit subject where applicable. Commit, push, deploy or upload only when requested. No tracker Log entry is required; git records routine edits.

Status: `☐` todo, `◐` in progress, `blocked` awaiting a named dependency. Closed and deferred items belong only in the archive. Sev: C critical, H high, M medium, L low, I informational. Eff: S < 1 day, M 1-3 days, L > 3 days; `?` means untriaged.

## Data and Methods

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| SP-09 | H | S | ☐ | `wise_sp_config()` hard-codes `is_regular <- TRUE`, so a shock program always gets `transfer_timing = NA`, `timeliness_weeks = NA` and `transfer_frequency = "regular"`. Anticipatory payments (forecast hits, false alarms, effect multiplier) and the ex-post delay never reach `.sp_timing_plan()` through the Step 3 module or a batch spec (the run falls back to ex post). Fix: derive `is_regular` from `sp_type`, then regression tests through `wise_sp_config()` and `wise_policy_configs()` (the module-versus-spec comparison in `test-fct_step3_input.R` compares NA with NA), check the app's Step 3 timing controls, and handle as a numeric change (`wise-numeric-change`: BFA before/after, Decision log, docs 42/43). | `R/fct_step3_input.R` (`wise_sp_config()`); `R/fct_sp_shock.R` (`.sp_timing_plan()`); found 2026-10-26 in the UR-02 run: forecast policy output identical to the base policy. Present since the scaffolding commit; not yet checked in the running app. |
| UR-02 | L | S | blocked | Measure seed variation with shock-responsive forecast and predicted-welfare layers enabled; the existing 20-seed check exercised targeting draws only. Blocked by SP-09 (the forecast layer is off in every run until it is fixed). Predicted-welfare layer already measured (2026-10-26, 8 seeds, Step 3 reseeded on one Step 2 run): coefficient of variation of the mean annual cost 0.75 to 0.97% (targeting only: about 0.6%), false-negative rate 4 to 7%, false-positive rate below 1%. After SP-09: rerun the forecast policies (POD 70, FAR 20, multiplier 1.5) over about 8 seeds by calling `wise_batch_policy()` with other `spec$seed` on the stored Step 2 run, then update `docs/43_shock_responsive_sp.md` and close. | `archive/uncertainty_residuals_review.md`; `docs/43_shock_responsive_sp.md` states the exclusion. Existing check: about 1.1% variation in cost/effect. |

## UX and Accessibility

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| CR-A11Y-09 | M | M | blocked | Confirm one successful GitHub run of the expanded 16-screen axe scan after an authorized push; run a real-data pass through Steps 1-3 and result tabs. | `tests/e2e/smoke.R`; `.github/workflows/e2e-smoke.yaml`; archive CR-A11Y-09. Green locally with `WISEAPP_AXE_FAIL=1`; four violation types fixed. Earlier green CI covered two screens only. Navbar upstream exception and transient-toast exclusion remain documented. `main` requires `e2e-smoke`; `dev` is unprotected by decision. |
| UX-01 | L | S | ☐ | Complete remaining browser spot-checks: column-chart hover tips and `.wx-tip` Escape; map pointer cursor; empty tabs; SPI/SPEI choices; quantile decile-movement card; DOC-02 survey-identification warnings; weights/LCU notes; changed-palette contrast. Record which checks pass and which remain. | Carried from the former "Waiting on the user" checklist, 2026-10-26; earlier browser evidence in the archive. Decile card needs a quantile-model run. |

## Engineering and Tests

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| CR-CQ-01 | M | L | ☐ | Move static builders out and split the three giant server functions. Delete dead code first; keep changes per file with characterization tests. | `archive/REVIEW-2026-10-06.md`, CR-CQ-01; `code_hygiene.md`. |
