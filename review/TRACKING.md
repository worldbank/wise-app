# Tracking: open work

The single list of open work in this repository. Every review feeds it: when a review or plan is finished, its remaining items are added here (with the source named in the section header) and the review moves to `review/archive/`. New findings from later reviews get a row here, not a new tracker. This file tracks **open work only**. Findings of the first review (batches B1 to B9) are described in `review/archive/REVIEW-2026-10-06.md` (immutable; reviewed commit `df37cdb`). The full record of finished, closed and deferred work (commits, verification, measurements, Decision log, dated Log, performance baselines, reopen triggers) is in `review/archive/REVIEW-2026-10-06-tracking-full.md`; read it only for the evidence behind a finished or closed item. Compacted 2026-10-24.

Status: `☐` todo · `◐` in progress (remainder listed) · `✗` won't fix / deferred (reason given). Sev: C critical · H high · M medium · L low. Effort: S < 1 day · M 1-3 days · L > 3 days.

## Where things stand (2026-10-24)

All Critical and High findings, the docs/ revision (DOC-01 to DOC-14) and UNC-01 are done or closed. Nothing is pushed; `dev` is the working branch. Closed, deferred and won't-fix items, with the trigger for reopening each, are listed in the archive ("Closed and deferred list").

| Batch | Scope | Open |
|---|---|---|
| B2 | Security | 1 |
| B6 | Performance | 4 |
| B8 | Accessibility | 1 |
| B9 | Code quality and docs | 2 |
| B10 | Uncertainty and residuals | 2 |
| B11 | Social protection (deferred) | 8 |

B1, B3, B4, B5, B7 have no open rows (B4: Step 3 lever numbers are owed, see Waiting on the user).

## Working rules

- One branch per batch off `dev`; within a batch, one commit per finding ID with the ID in the subject. Do not push or deploy without an explicit go-ahead.
- A finding is closed only when (a) a regression test fails before and passes after (or a reproducible command shows a config/docs fix), (b) the narrowest relevant `devtools::test(filter = ...)` passes, and (c) the Notes cell records the commit and what was verified. Then move it to the archive record (append the full row to the archive file's addendum), delete its row here and add a one-line entry to the Log.
- Numerical changes need a Decision log entry (in the archive file's table, or a new row here) with before/after BFA headline numbers, because outputs move.
- Performance changes follow `review/optimization_guidelines.md` section 9: authoritative payload choices and ceiling, Step 3 harness, numerical parity, before/after timing and peak RSS. Use skill `wise-benchmark` for the procedure.
- Run `devtools::document()` (roxygen2 as pinned in `DESCRIPTION`), `devtools::check()` and the full suite once per batch with the tree quiescent. Regenerate `manifest.json` (`dev/00_make_manifest.R`) at the end of any batch that changes dependencies or `R/` files.
- Code hygiene conventions: `review/code_hygiene.md`.

## Waiting on the user

- **CR-SEC-09 step 2, staging:** needs a go-ahead before any deployment (see the row).
- **CI first run:** the 16-screen axe scan (CR-A11Y-09) has run only locally; watch its first GitHub run (needs `arrow` and the DuckDB `h3` extension from the community repository). `main` requires `e2e-smoke`; `dev` is deliberately unprotected (user, 2026-10-24).
- **Step 3 worker memory (CR-PERF-13):** decided 2026-10-08, accept the lower peak, no `Max Processes` change. Unmeasured: Step 2's own 2x2 daemon peak, deployed cold start, 3x3.
- **R2-PERF-01 in-app check:** done 2026-10-24 for the Step 2 Results (aggregation, poverty line). Still unchecked: the scenario picker (needs two SSPs), any export after a release, RIF and ranger engines, memory on Linux. Revert path: `.step3_release_allowed()` returning FALSE.
- **Browser spot-check, still unchecked:** hover tooltips of columnar charts and `.wx-tip` legend markers (Escape), map pointer cursor, tab empty states, SPI/SPEI choices, the decile-movement card (needs a quantile-model run), survey-identification warnings at load (DOC-02), the weights and LCU notes, colour contrast of the changed palettes.
- **Before a deploy:** rerun `dev/00_make_manifest.R` after committing `R/`, `inst/` or dependency changes.

## B2 - Security

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-SEC-09 (rest) | L | S | ◐ | Steps 1 (no inline script or handler in the app's code) and 2 (report-only policy designed; zero violations over the fixture flow Step 1 to 3 in headless Chrome) are done. Open: set the report-only header on a staging Connect instance and read real traffic (`CustomHeader` in the `[Server]` section of `rstudio-connect.gcfg`; it applies to all content on that server, so check other apps first), then decide on enforcing. Header: `Content-Security-Policy-Report-Only: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' https://tiles.basemaps.cartocdn.com; worker-src 'self' blob:; object-src 'none'; base-uri 'self'; form-action 'self'`. It pins connections, images, workers, plugins, base and form targets, but gives no injected-script protection (`script-src` needs `'unsafe-inline'` for bslib/Shiny initialisers and `'unsafe-eval'` for `htmlwidgets::JS()`); a strict `script-src` would need nonces, which Shiny lacks. Not covered locally: real downloads, hover tooltips, real-data tile traffic. Evidence in the archive. |

## B6 - Performance

Work stopped by decision 2026-10-24 (user agreed): the rows below have no measured pain behind them. Baselines and measurements are in the archive. Rejected experiments not to reopen (section 11): Arrow fetch path, `csw()` stepwise fits, SQL `ORDER BY` for survey sort, `bw.SJ` subsampling, batched gemm (1.8x regression with reference BLAS), `shared_period` plan, reference weather as default, shared SSP monthly cache, sort-once materialisation of the period relation (no gain: 3.35 s against 3.23 s for 16 members), unsorted per-member collect with a key-order check (DuckDB does not return key order, so it collects twice: 2x2 40.0 s to 43.1 s), R-side rounding rewrite (identical, saves only 4 ms per member).

| Rank | ID | Eff | Status | Open task | Gate |
|---:|---|---|---|---|---|
| 3 | R2-PERF-01 | M | ◐ | Shrink the Step 2 result. Done: household-constant vectors shared once; Step 3 policy arm linked to the baseline; member `weather_raw` released at adoption (`.step3_release_member_weather()`; BFA 2x2 live heap -294 MB, max RSS unchanged because the peak is the adoption read). Open: a peak reduction needs the Step 2 worker to write member frames to a second file (artifact contract change, not started); drop `hist_sim_result$svy` (4.3 MB); slimmer `F_loading` (3.4 MB per pipeline, uncertainty on only). | Bit-identical |
| OPT-02 | - | - | ☐ | Startup and Step 3 backend. Measured 2026-10-24: Step 3 is linear in pipeline count, no stage justifies a change. Reopen only on a reported slow Step 3 run or metric switch, or a Linux/Connect measurement showing the Shiny process is memory-bound. | - |
| OPT-03 | - | - | ☐ | Hex engine lazy-load. mod_1_02/03 map containers are static, so deferral needs container restructuring. | - |
| OPT-06 | - | - | ☐ | Deferred 2026-10-08 (no measured pain). Step 2 batching tuning (never implemented). XGBoost support deferred by the user. DuckDB 2.0 / Parquet v2 is in `review/duckdb_parquet_plan.md`. | - |

## B8 - Accessibility (WCAG 2.2 AA, section 9)

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-A11Y-09 | M | M | ◐ | Done 2026-10-24: axe-core scans 16 screens (Overview, Steps 1 to 3 and every result tab) in the smoke job on a generated fixture data folder; four real violation types fixed in `custom.js`; green locally with `WISEAPP_AXE_FAIL=1`. Open: the first GitHub run, and a real-data pass (the scan sees fixture table sizes only). Known and filtered: bslib's navbar `role="tablist"` also holds plain links and a dropdown (`aria-required-children` on `.navbar-nav`; upstream). Shiny toasts are outside the scan (transient contrast). |

## B9 - Code quality and docs

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-CQ-01 | M | L | ☐ | Move static builders out; split the three giant server functions. |
| CR-CQ-02 | M | L | ☐ | Shared Results-pane module for Steps 2 and 3. |

Ordering note from the report: delete dead code before splitting files; one PR per file with characterisation tests.

## B10 - Uncertainty and residuals

Source: `review/archive/uncertainty_residuals_review.md` (closed 2026-10-26; findings F0 to F10 and the removal of the "normal" residual rule are done). Open remainders:

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| UR-01 | L | S | ☐ | A failed `train_aug` precomputation inside `fct_run_simulation()` demotes the residual rule to "none" with a warning only; the run summary and provenance do not record it (the RIF demotion is recorded). `fct_run_simulation()` and the Step 2 result names are pinned by `test-step2-contract.R`, so the fix needs a contract change or a field on `sim_summary` set by the caller. Rare. |
| UR-02 | L | S | ☐ | The seed spread of the shock-responsive forecast hits and false alarms and of the predicted-welfare layer is unmeasured (the 20-seed check had only the seeded targeting draws active: about 1.1 per cent on cost and effect). `docs/43_shock_responsive_sp.md` says the bands exclude it. Measure with a spec that switches those layers on. |

Not done and not planned (closed decisions): a cluster-block or stratified resample rule (F4), a bootstrap of the return-period tail (F10).

## B11 - Social protection (all deferred or owed)

Sources: `review/archive/sp_shock_responsive_plan.md`, `review/archive/sp_shock_responsive_tasks.md`, `review/archive/step3_cost_effectiveness_plan.md` (archived 2026-10-26; Phases 0 to 2 and the cost-effectiveness tab are built). Nothing here is scheduled.

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| SP-01 | L | M | ✗ | P0-9 admin and error presets: a literature pass on cost-transfer ratios and PMT error rates, then a preset dropdown. The 10 % / 10 % defaults and zero admin share stay. |
| SP-02 | L | M | ✗ | PR-13: the shock state plus transfer is re-evaluated per metric-decomposition job (1.7 s base to 3.5 s with anticipatory and layers, BFA, 17 pipelines). Cache it in the retained Step 3 artifact if a slow metric switch is reported. |
| SP-03 | L | S-M | ✗ | Phase 3 presets and amount rules (P3-1 named presets, P3-4 gap-filling and tiered amounts). |
| SP-04 | L | M | ✗ | Phase 3 design sweep (P3-2: cost against poverty-reduction frontier over a bounded grid) and reserve dynamics (P3-3: needs an ordered-year rule first, years are draws today). |
| SP-05 | L | M | ✗ | P3-5 further budget rules (AAL sizing, premium-equivalent cost, budgets tied to the rise in the number of poor, envelope per activation). Needs P2-5. |
| SP-06 | L | M | ✗ | Cost-effectiveness for non-cash levers (`mod_3_02` to `mod_3_05`) and the cost-effectiveness summary card: need unit costs from the policy team. |
| SP-07 | M | S | ☐ | Owed numbers: BFA before/after headline figures for P0-8 (synthetic check already recorded: realised weighted inclusion 15.8 % / exclusion 12.2 % before, 15.0 % / 10.0 % after, for 15 % / 10 % sliders), BFA Step 3 benchmark figures with the shock fixtures, and the BFA LCU re-run entry for R2-BUG-04 / CR-BUG-02. |
| SP-08 | L | S | ✗ | Targeting errors are one seeded draw; the draw-to-draw variation of coverage and leakage, and of the shock forecast layers, is not shown (see UR-02). |

## Decision log (uncertainty and residuals, 2026-10-26)

Numerical changes, BFA unless stated, "original" rule unless stated. Evidence and tables are in the archived review.

- F0 (residual key): BEN 2018 + 2021, historical average mean / poverty rate / Gini 5.4948 / 0.2916 / 0.3782 before, 5.2755 / 0.2685 / 0.3410 after (observed 5.2510 / 0.2729 / 0.3432). BFA unchanged to every printed digit (4.3606 / 0.4358 / 0.3725).
- F8 (logistic loading): agriculture employment, first historical year, coefficient SD 0.5036 before, 0.1140 after (Monte Carlo 0.107); band at 10/90 [-0.194, 1.097] before, [0.314, 0.598] after.
- F1 (median reference under "resample"): the reference year's residual variance is added to the contrast; the mean reference, same-year and year-averaged contrasts are unchanged.
- F2 (own residual bar): "resample", level, coefficient bar 0.5461 before (residual inside), 0.5429 after, residual bar 0.0588.
- F9 (poverty-rate residual variance): residual SD under "resample" 0.00967 before, 0.00758 after (Monte Carlo 0.00778).
- Normal rule removed: point estimates under "original" and "resample" identical to every printed digit (mean 4.36060483590172 and 4.77585348505506).

## Log

Entries up to 2026-10-24 are in the archive ("Log 2026-10-23 to 2026-10-24 (moved)" and earlier addenda). Add new entries here.

- 2026-10-24 - Tracker compacted to open work; closed list, known gaps, baselines and the Log moved to the archive verbatim.
- 2026-10-24 - CR-SEC-03 and CR-A11Y-08 closed as won't fix (user decision; B2 open count 2 to 1, B8 2 to 1). Rows and reopen triggers in the archive addendum.
- 2026-10-24 - RED-06 and R2-OPS-09 closed as won't fix (B5 open count 1 to 0); DOC-11 severity raised L to M (the log-outcome transfer is worth 8% to 18% more than T with a residual term, so policy gains are overstated). Rows in the archive addendum.
- 2026-10-24 - DOC-11 closed (B9 open count 3 to 2): for a log outcome the cash transfer is now added after the residual, so the policy arm gains T and not T * exp(e); regular and shock-responsive SP, aggregation mean and its gradient, and the metric states. Outputs move (policy gains shrink by up to 8% at SD 0.4); Decision log entry, real-BFA before/after (policy mean gain 0.70 and 1.30 of the transfer before, 1.00 after, for original and resample residuals) and the row in the archive addendum. The Step 3 pane was not driven in the browser.
- 2026-10-25 - DOC-11 follow-up: the quantile model (RIF) now adds the transfer after repositioning (`E * exp(c + rho) + T`) and the level channels add it once with another lever active. RIF outputs move when a transfer combines with another lever or repositioning. Decision log in the archive addendum; real-BFA RIF before/after (transfer alone +1.8% gain, transfer plus electricity -0.7%) and the Decomposition tab driven in the browser, both in the archive. Also: `test-bench-step3.R` timing assertion made `expect_gte` (1 ms clock resolution made it flaky).
- 2026-10-26 - Uncertainty and residuals review closed and archived (B10 opened with 2 low-severity rows): residual key (F0), logistic loading (F8), own residual bar and median reference (F2, F1), poverty-rate residual variance (F9), the all-covariates control removed (F3), the applied residual rule recorded in the run summary, Step 2 provenance and batch provenance, the "normal" rule removed, docs 30, 32, 33, 40, 43, 50. Commits `c5ccb9e`, `1ecc93e`, `f84b9e3`, `235bce2`. Decision log rows above.
- 2026-10-26 - `REVIEW-2026-10-06.md`, the shock-responsive SP plan and tasks and the cost-effectiveness plan moved to `review/archive/` (code comments, tests, `ARCHITECTURE.md` and the `wise-close-finding` skill re-pointed). Their open or deferred items are B11 (8 rows, none scheduled).
