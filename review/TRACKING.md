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
| UR-02 | L | S | blocked | Measure seed variation with shock-responsive forecast and predicted-welfare layers enabled; the existing 20-seed check exercised targeting draws only. Blocked by SP-09 (the forecast layer is off in every run until it is fixed). Predicted-welfare layer already measured (2026-10-26, 8 seeds, Step 3 reseeded on one Step 2 run): coefficient of variation of the mean annual cost 0.75 to 0.97% (targeting only: about 0.6%), false-negative rate 4 to 7%, false-positive rate below 1%. After SP-09: rerun the forecast policies (POD 70, FAR 20, multiplier 1.5) over about 8 seeds by calling `wise_batch_policy()` with other `spec$seed` on the stored Step 2 run, then update `docs/43_shock_responsive_sp.md` and close. | `archive/uncertainty_residuals_review.md`; `docs/43_shock_responsive_sp.md` states the exclusion. Existing check: about 1.1% variation in cost/effect. |

## UX and Accessibility

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| CR-A11Y-09 | M | M | blocked | Confirm one successful GitHub run of the expanded 16-screen axe scan after an authorized push; run a real-data pass through Steps 1-3 and result tabs. | `tests/e2e/smoke.R`; `.github/workflows/e2e-smoke.yaml`; archive CR-A11Y-09. Green locally with `WISEAPP_AXE_FAIL=1`; four violation types fixed. Earlier green CI covered two screens only. Navbar upstream exception and transient-toast exclusion remain documented. `main` requires `e2e-smoke`; `dev` is unprotected by decision. |

## Engineering and Tests

| ID | Sev | Eff | Status | Issue / Next Action | Evidence / Source |
|---|---|---|---|---|---|
| CR-CQ-01 | M | L | ☐ | Move static builders out and split the three giant server functions. Delete dead code first; keep changes per file with characterization tests. | `archive/REVIEW-2026-10-06.md`, CR-CQ-01; `code_hygiene.md`. |
