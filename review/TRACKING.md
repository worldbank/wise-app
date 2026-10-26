# Tracking: open work

The single list of open work in this repository. Every review feeds it: when a review or plan is finished, its remaining items are added here (with the source named in the section header) and the review moves to `review/archive/`. New findings from later reviews get a row here, not a new tracker. This file tracks **open work only**. Findings of the first review (batches B1 to B9) are described in `review/archive/REVIEW-2026-10-06.md` (immutable; reviewed commit `df37cdb`). The full record of finished, closed and deferred work (commits, verification, measurements, Decision log, dated Log, performance baselines, reopen triggers) is in `review/archive/REVIEW-2026-10-06-tracking-full.md`; read it only for the evidence behind a finished or closed item. Compacted 2026-10-24.

Status: `☐` todo · `◐` in progress (remainder listed) · `✗` won't fix / deferred (reason given). Sev: C critical · H high · M medium · L low. Effort: S < 1 day · M 1-3 days · L > 3 days.

## Where things stand (2026-10-26)

All Critical and High findings, the docs/ revision (DOC-01 to DOC-14) and UNC-01 are done or closed. Nothing is pushed; `dev` is the working branch. Closed, deferred and won't-fix items, with the trigger for reopening each, are listed in the archive ("Closed and deferred list").

| Batch | Scope | Open |
|---|---|---|
| B6 | Performance | 4 |
| B8 | Accessibility | 1 |
| B9 | Code quality and docs | 2 |
| B10 | Uncertainty and residuals | 2 |

B1, B2, B3, B4, B5, B7, B11, B12 and B13 have no open rows.

## Working rules

- One branch per batch off `dev`; within a batch, one commit per finding ID with the ID in the subject. Do not push or deploy without an explicit go-ahead.
- A finding is closed only when (a) a regression test fails before and passes after (or a reproducible command shows a config/docs fix), (b) the narrowest relevant `devtools::test(filter = ...)` passes, and (c) the Notes cell records the commit and what was verified. Then move it to the archive record (append the full row to the archive file's addendum), delete its row here and add a one-line entry to the Log.
- Numerical changes need a Decision log entry (in the archive file's table, or a new row here) with before/after BFA headline numbers, because outputs move.
- Performance changes follow `review/optimization_guidelines.md` section 9: authoritative payload choices and ceiling, Step 3 harness, numerical parity, before/after timing and peak RSS. Use skill `wise-benchmark` for the procedure.
- Run `devtools::document()` (roxygen2 as pinned in `DESCRIPTION`), `devtools::check()` and the full suite once per batch with the tree quiescent. Regenerate `manifest.json` (`dev/00_make_manifest.R`) at the end of any batch that changes dependencies or `R/` files.
- Code hygiene conventions: `review/code_hygiene.md`.

## Waiting on the user

- **CI first run:** the 16-screen axe scan (CR-A11Y-09) has run only locally; watch its first GitHub run (needs `arrow` and the DuckDB `h3` extension from the community repository). `main` requires `e2e-smoke`; `dev` is deliberately unprotected (user, 2026-10-24).
- **Step 3 worker memory (CR-PERF-13):** decided 2026-10-08, accept the lower peak, no `Max Processes` change. Unmeasured: Step 2's own 2x2 daemon peak, deployed cold start, 3x3.
- **R2-PERF-01 in-app check:** done 2026-10-24 for the Step 2 Results (aggregation, poverty line). Still unchecked: the scenario picker (needs two SSPs), any export after a release, RIF and ranger engines, memory on Linux. Revert path: `.step3_release_allowed()` returning FALSE.
- **Browser spot-check, still unchecked:** hover tooltips of columnar charts and `.wx-tip` legend markers (Escape), map pointer cursor, tab empty states, SPI/SPEI choices, the decile-movement card (needs a quantile-model run), survey-identification warnings at load (DOC-02), the weights and LCU notes, colour contrast of the changed palettes.
- **Before a deploy:** rerun `dev/00_make_manifest.R` after committing `R/`, `inst/` or dependency changes.

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

Source: `review/archive/uncertainty_residuals_review.md` (closed 2026-10-26). Open remainders:

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| UR-01 | L | S | ☐ | A failed `train_aug` precomputation inside `fct_run_simulation()` demotes the residual rule to "none" with a warning only; the run summary and provenance do not record it (the RIF demotion is recorded). `fct_run_simulation()` and the Step 2 result names are pinned by `test-step2-contract.R`, so the fix needs a contract change or a field on `sim_summary` set by the caller. Rare. |
| UR-02 | L | S | ☐ | The seed spread of the shock-responsive forecast hits and false alarms and of the predicted-welfare layer is unmeasured (the 20-seed check had only the seeded targeting draws active: about 1.1 per cent on cost and effect). `docs/43_shock_responsive_sp.md` says the bands exclude it. Measure with a spec that switches those layers on. |

## Decision log

Numerical changes get an entry here (formula before and after, BFA before/after, what was not checked). Entries for closed items move to the archive addendum (`review/archive/REVIEW-2026-10-06-tracking-full.md`, "Decision log moved from the tracker"); none are open.

## Log

Entries up to 2026-10-26 are in the archive ("Log moved from the tracker" and earlier addenda). Add new entries here.

- 2026-10-26 - CR-SEC-09 closed with CSP rollout deferred (user; B2 open count 1 to 0). App-owned inline-script guard passes; no Connect CSP deployment or enforcement verified. Full row, evidence and reopen trigger in the archive addendum.
- 2026-10-26 - SP-07 closed as superseded legacy bookkeeping (user; B11 open count 1 to 0). Historical before/after checks were already dropped on 2026-10-23; BFA shock-fixture benchmarks are recorded in the archived SP tasks. No new numerical validation claimed; full row and reopen trigger in the archive addendum.
- 2026-10-26 - MR-09 closed as a documented specification consideration (user; B12 open count 3 to 2). `docs/20_model_specification.md` highlights the area-by-round tradeoff; no estimator change, new specification test or empirical comparison. Full row and reopen trigger in the archive addendum.
- 2026-10-26 - BP-01 closed (user; B13 open count 1 to 0). `dev/batch_parity_bfa_policy.R` now checks that the Export bundle CSVs equal the module tables and that the app configuration gives the same stage ids as the batch run; fixture and BFA runs pass. Not driven: the browser download. Not committed yet. Full row, evidence and reopen trigger in the archive addendum.
- 2026-10-26 - MR-05 closed (`d449ec6`; B12 open count 2 to 1). Weather files are fingerprinted in the stage items (H3 files were already covered by the data item); a changed weather or H3 file reruns the branches that read it. Full row and evidence in the archive addendum.
- 2026-10-26 - MR-06 closed (B12 open count 1 to 0). Real-data check: no location with observed weather lacks a climate cell. Known data limitations documented in `docs/10_data.md` and `docs/31_climate_scenarios.md`: `loc_id` without H3 cells, H3 cells outside ERA5-Land, variables missing for some climate models, `mrsos` undefined at some coastal and island locations. Full row and evidence in the archive addendum.
