# Tracking: open work

The single list of open work in this repository. Every review feeds it: when a review or plan is finished, its remaining items are added here (with the source named in the section header) and the review moves to `review/archive/`. New findings from later reviews get a row here, not a new tracker. This file tracks **open work only**. Findings of the first review (batches B1 to B9) are described in `review/archive/REVIEW-2026-10-06.md` (immutable; reviewed commit `df37cdb`). The full record of finished, closed and deferred work (commits, verification, measurements, Decision log, dated Log, performance baselines, reopen triggers) is in `review/archive/REVIEW-2026-10-06-tracking-full.md`; read it only for the evidence behind a finished or closed item. Compacted 2026-10-24.

Status: `☐` todo · `◐` in progress (remainder listed) · `✗` won't fix / deferred (reason given). Sev: C critical · H high · M medium · L low. Effort: S < 1 day · M 1-3 days · L > 3 days.

## Where things stand (2026-10-26)

All Critical and High findings, the docs/ revision (DOC-01 to DOC-14) and UNC-01 are done or closed. Nothing is pushed; `dev` is the working branch. Closed, deferred and won't-fix items, with the trigger for reopening each, are listed in the archive ("Closed and deferred list").

| Batch | Scope | Open |
|---|---|---|
| B2 | Security | 1 |
| B6 | Performance | 4 |
| B8 | Accessibility | 1 |
| B9 | Code quality and docs | 2 |
| B10 | Uncertainty and residuals | 2 |
| B11 | Social protection (deferred) | 8 |
| B12 | Methodology review follow-ups | 3 |
| B13 | Batch pipeline follow-ups | 3 |

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

Source: `review/archive/uncertainty_residuals_review.md` (closed 2026-10-26). Open remainders:

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| UR-01 | L | S | ☐ | A failed `train_aug` precomputation inside `fct_run_simulation()` demotes the residual rule to "none" with a warning only; the run summary and provenance do not record it (the RIF demotion is recorded). `fct_run_simulation()` and the Step 2 result names are pinned by `test-step2-contract.R`, so the fix needs a contract change or a field on `sim_summary` set by the caller. Rare. |
| UR-02 | L | S | ☐ | The seed spread of the shock-responsive forecast hits and false alarms and of the predicted-welfare layer is unmeasured (the 20-seed check had only the seeded targeting draws active: about 1.1 per cent on cost and effect). `docs/43_shock_responsive_sp.md` says the bands exclude it. Measure with a spec that switches those layers on. |

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

## B12 - Methodology review follow-ups

Source: `review/archive/methodology_review_2026-10-26.md` (closed 2026-10-26; its closed items and their evidence are in the archive addendum). Open remainders:

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| MR-05 | L | S | ☐ | The batch data work item fingerprints the survey files only. H3 and weather files do not enter any stage identifier (stated in `docs/52_batch_runs.md`). Add their fingerprints and a two-run integration test that changes one input file and checks the affected branches rerun. |
| MR-06 | L | S | ☐ | Real-data check of the climate grid rule (expected location-months from the requested locations, independent of members): a location with no climate cell excludes every member. The five BFA members excluded on 2026-10-26 (all 7152 location-months missing) are known and expected; what is left is to confirm that no requested location lacks a climate cell. |
| MR-09 | M | M | ☐ | Finding 1 follow-up: add a specification test that distinguishes additive from interacted fixed effects, and assess an area-by-round specification as a separate methodological decision (identification and support diagnostics, numerical parity). Do not change the estimator silently. |

## B13 - Batch pipeline follow-ups

Source: `review/archive/batch_pipeline_plan.md` (archived 2026-10-26). Phases 1 to 4, the reproducibility template/checker, early-stage artifact stamps and local survey fingerprints are implemented. Broader source-input fingerprints remain MR-05; do not duplicate that task here.

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| BP-01 | L | M | ☐ | Per-release parity against a downloaded headless-app Export bundle. Existing `dev/batch_parity_bfa*.R` checks compare module-server tables with batch, not the downloaded bundle. Compare the same spec and seed through Steps 1 to 3, including policy tables. |
| BP-02 | L | S | ✗ | Separate policy-stage crew controller; policy currently shares the bounded `sim` controller. Defer until a measured batch workload needs different Step 2/3 concurrency or memory limits. |
| BP-03 | L | M | ✗ | A frame key independent of descriptive-statistics options, which currently enter `data_id` and invalidate downstream fits. Defer until changing statistics causes material rerun cost; preserve table identity and cache correctness if split. |

## Decision log

Numerical changes get an entry here (formula before and after, BFA before/after, what was not checked). Entries for closed items move to the archive addendum (`review/archive/REVIEW-2026-10-06-tracking-full.md`, "Decision log moved from the tracker"); none are open.

## Log

Entries up to 2026-10-26 are in the archive ("Log moved from the tracker" and earlier addenda). Add new entries here.
