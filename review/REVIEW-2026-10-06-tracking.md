# Review remediation tracking (REVIEW-2026-10-06)

Source of truth for findings: `review/REVIEW-2026-10-06.md` (immutable; reviewed commit `df37cdb`). This file tracks **open work only**. Finding text, evidence and remediation advice stay in the report; `§` numbers refer to it. The full per-finding record of finished and closed work (commits, verification, measurements, Decision log, dated Log) is in `review/archive/REVIEW-2026-10-06-tracking-full.md` (snapshot of 2026-10-07 plus an addendum of 2026-10-08); read it only for the evidence behind a finished or closed item.

Status: `☐` todo · `◐` in progress (remainder listed) · `✗` won't fix / deferred (reason given). Sev: C critical · H high · M medium · L low. Effort: S < 1 day · M 1-3 days · L > 3 days.

## Where things stand (2026-10-08)

All Critical and High findings are done in code, except where noted below. Done: B3 (headline numerics) and B4 (Step 3 levers) in code; B1, B7 and the B2, B5, B8 quick wins; the B6 weather and aggregation wins (PERF-W1 `5bb1ffc`, PERF-W2 `21a9e7c`, R2-PERF-04 table construction `ac62773`). What is left is below, grouped by what kind of work it needs. Nothing is pushed. The `dev` branch is the working branch.

| Batch | Scope | Open |
|---|---|---|
| B1 | Deployment and dependencies | 0 |
| B2 | Security | 3 |
| B3 | Headline numerics | 0 |
| B4 | Step 3 levers | 0 (numbers owed, see Waiting on the user) |
| B5 | Robustness, CI, tests | 6 |
| B6 | Performance | 9 |
| B7 | Medium/Low bugs | 0 |
| B8 | Accessibility | 6 |
| B9 | Code quality and docs | 5 |

Closed as won't fix or deferred (full rows in the archive addendum; reopen only on the stated trigger): R2-OPS-05 (stay on DuckDB 1.5.6), CR-SEC-02 (no further DuckDB lockdown), R2-SEC-07 (persistent prepared-weather cache off), CR-PERF-15 (keep `load_all()` in `app.R`), R2-PERF-10 / CR-PERF-02 (weather cache keys; reopen if remote slice reads dominate), CR-PERF-03 (prediction speedup), OPT-05 (aggregation remainders), R2-PERF-13 / R2-PERF-09 / CR-PERF-05, CR-PERF-07 (model_fit size; reopen if a large-country session shows high RSS), CR-CQ-07 (one integer `year` type; needs an engine parity gate).

## Working rules

- One branch per batch off `dev`; within a batch, one commit per finding ID with the ID in the subject. Do not push or deploy without an explicit go-ahead.
- A finding is closed only when (a) a regression test fails before and passes after (or a reproducible command shows a config/docs fix), (b) the narrowest relevant `devtools::test(filter = ...)` passes, and (c) the Notes cell records the commit and what was verified. Then move it to the archive record (append the full row to the archive file's addendum), delete its row here and add a one-line entry to the Log.
- Numerical changes need a Decision log entry (in the archive file's table, or a new row here) with before/after BFA headline numbers, because outputs move.
- Performance changes follow `review/optimization_guidelines.md` section 9 (equivalence gate, before/after timing and peak RSS). Benchmarks: BFA 1x1 OLS (`WISEAPP_STEP2_WORKLOADS=one_ssp_one_period`, `WISEAPP_STEP2_MODELS=ols`) unless a larger payload is needed (user instruction 2026-10-07); 2x2 (`two_ssps_two_periods`) is the maximum for benchmarks and profiling, because 3x3 is an uncommon payload (user instruction 2026-10-08). The Step 3 harness is `dev/bench_step2.R` with `WISEAPP_STEP2_INCLUDE_STEP3=1 WISEAPP_STEP3_POLICIES=targeted_sp`; the `covariate` fixture needs an electricity column in the fitted model. Report timings are from a 4-vCPU container, so re-measure locally.
- Run `devtools::document()` (roxygen2 as pinned in `DESCRIPTION`), `devtools::check()` and the full suite once per batch with the tree quiescent. Regenerate `manifest.json` (`dev/00_make_manifest.R`) at the end of any batch that changes dependencies or `R/` files.
- Code hygiene conventions: `review/code_hygiene.md`.

## Waiting on the user

- **BFA before/after numbers (B4):** CR-BUG-02, R2-BUG-04, R2-BUG-06 and R2-BUG-07 move Step 3 outputs. Their Decision log rows (archive file) hold synthetic checks only; the BFA values need a manual Step 3 run in the app (BFA's outcome is not confirmed to be LCU, so the CR-BUG-02 and R2-BUG-04 LCU effects also need an LCU-outcome run).
- **BFA before/after numbers (SP P0-8):** SP targeting errors now hit the weighted share the sliders describe (surveys without weights or with constant weights are unchanged). Synthetic check: realised weighted inclusion / exclusion 15.8% / 12.2% before, 15.0% / 10.0% after for 15% / 10% sliders. The BFA headline numbers (reach, cost, Step 3 effect with the SP lever on) need a manual run before and after the change (use the previous commit for "before"); add the Decision log row then.
- **Browser spot-check of recent UI changes:** columnar chart tooltips, map without pointer cursor, tab empty state, data-check notice, Step 1 diagnostics, a11y changes not yet seen in a browser.
- **Live Databricks check** of the scoped bearer-token secret on the first Connect load after the next deploy (CR-SEC-03).
- **Connect memory limit** (CR-PERF-13): pick `WISEAPP_DUCKDB_MEMORY_LIMIT` for the shared host (try 4GB; check a 3x3 run first). Weather threads are decided: they stay at 1 in production (user, 2026-10-08).
- **Manifest:** regenerate before deployment. `R/` changed since the last regeneration (`91f599c` predates comment-only changes to 13 files in `3666d97`, plus `fct_aggregation.R`, `fct_simulations.R` and `fct_get_weather.R`), and `R/fct_sp_shock.R` is missing from `manifest.json`, so `test-deploy-contract.R:76` fails until it is regenerated.

## Known gaps in finished items

Closed with a documented remainder; reopen only if the area is touched again.

- R2-BUG-14: the seed is not in the fit signature, so a ranger/xgboost seed-only refit is not caught (needs `.fit_sig_from_live` in mod_1_07).
- R2-BUG-13: checked on the decomposition path only, not an end-to-end NA-welfare Step 3 run.
- R2-BUG-08: BFA default-spec LASSO selection not re-run; selection may shift.
- CR-BUG-06: not checked on BFA how many real CMIP6 members are partial rather than wholly missing (7 of 22 SSP3-7.0 members are excluded with t + spei6).
- CR-BUG-17: the CMIP6 path still falls back silently to the target H3 resolution on error.
- R2-BUG-19: `echart_weather_effect_plot` RIF polynomial curve uses `x_mean` 0 and misses the `I(I(temp^2))` term (linear only).
- R2-BUG-06: no parity test against `predict_rif` itself; the legacy `decompose_policy_effect()` path still uses absolute period-mean hazards.
- R2-BUG-07: the legacy non-annual decomposition keeps the observed baseline.
- R2-BUG-28 / UI notice: `n_bad_loading` approximates `n_coef_dropped` (misses overflowing gradients).
- CR-SEC-02: DuckDB `lock_configuration` / `enable_external_access` not applied (the weather code changes `threads` at run time); the path passed to `load_data` as a full URI is not allowlisted (it comes from metadata).
- CR-SEC-04: h3 mappings still on disk.
- CR-BUG-16: CPI/PPP and panel-id joins now report dropped records (BFA 407 of 14,186) but still drop them.
- PERF-W1: real-data test of a multiplicative weather variable deferred by the user (unit tests only); the fast roll falls back to the window query for gaps, duplicate months, incomplete delta calendars, Median and lags above 12 (`WISEAPP_WEATHER_ROLL=window` forces the legacy path).

## B2 - Security

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-SEC-03 | H | M | ◐ | Per-session secret names and a per-session connection. Two sessions in one process using different credentials for the same bucket still share one secret. Low priority: Connect uses one service principal and UI credentials are a local-use path. Confirm the scoped Databricks secret after the next deploy. |
| CR-SEC-07 | M | L | ☐ | Per-run size limits from config; cap the Step 2 queue by bytes; small profile for metadata. Folds into CR-PERF-04. |
| CR-SEC-09 (rest) | L | S | ☐ | Move inline JS/CSS to `custom.js`/`custom.css` (enables a CSP). Deferred (decisions 2026-10-07 and 2026-10-08): do last, in two steps. (1) Move our inline code to files (low risk). (2) Run the CSP in report-only mode on a staging Connect instance to list violations from Shiny, htmlwidgets, echarts4r, reactable and bslib; enforce only if the list is short, with a script-only target (strict `script-src`, lenient `style-src`) as the realistic goal. Connect or a proxy has to set the header. Not needed before the next deploy. |

## B5 - Robustness, CI and test hygiene

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-OPS-01 | M | M | ◐ | Decided 2026-10-08: add a `shinytest2`/axe smoke job to CI (shared with CR-A11Y-09). Scope: one app-boot smoke, one `conditionalPanel` check and one axe run on the first screens; start as a non-blocking job, make it required once it is stable. Investigate why the headless-Chrome PNG test skips on some CI runs. CI is otherwise green (Tests step about 340 s, 0 failed, 0 skipped; `error-on` is `"warning"`). |
| R CMD check notes | L | S | ◐ | Unused Imports, `:::` and undefined globals are fixed (2026-10-08, `b22ed62`): `tidyselect` dropped from Imports, `Rcpp::sourceCpp` and `brand.yml::read_brand_yml` imported, workers use `utils::getFromNamespace()`, `stats`/`utils` imports and `globalVariables` added in `R/globals.R`, duplicate local `one_scenario` renamed in `mod_2_02_results.R`. The last `check(--no-tests)` before the rename showed only that NOTE plus the sandbox "future file timestamps" NOTE; re-run once to confirm. |
| CR-PERF-13 / R2-PERF-08 | M | S | ◐ | Env-configurable limits exist (`WISEAPP_DUCKDB_MEMORY_LIMIT`, `_THREADS`, `_TEMP_DIR`, `WISEAPP_THREADS`). Threads decided 2026-10-08: weather stays at 1 (shared Connect host: 8 cores, 31 GiB, other content on it, `Max Processes` 4, 1 connection per process). Open: choose the memory limit for Connect. Optional later: trial `WISEAPP_WEATHER_THREADS_AUTO_ENABLE=1` on `wise-app-dev` only (2 threads gave -16% to -20% on top of PERF-W1), with the memory limit set and the server admin consulted before promoting. |
| R2-OPS-09 | L | S | ◐ | Left: `set.seed` vs `local_seed` (116 calls in 48 files; convert only in files being touched); `tests/spelling.R` never fails (the `spelling` package is not installed here and there is no `inst/WORDLIST`; needs a WORDLIST pass first). The `localhost:1` tests are a refused connection with a 15-20 s deadline, so they finish at once; left as they are. |
| RED-06 | M | M | ◐ | One parameterised batch driver over `step2_compute()`. Consolidating the five `04_run_sim` copies deferred by user decision 2026-10-07. |
| Test suite: remaining | L | S-M | ☐ | (1) rename history-named test files to `test-<R file>.R`; (2) shared `helper-fixtures-*.R` only when two or more files share a builder; (3) `wiseapp.verbose` option to silence progress messages (an `R/` change); (4) `shinytest2` boot smoke plus one `conditionalPanel` check; (5) hygiene in touched files only (`library()`, `wiseapp:::`, `set.seed`, `expect_true(identical())`); (6) coverage job and ratchet in CI: dropped by user decision 2026-10-08. Coverage was 82.1% overall; `fct_predict_outcomes.R` 73%. Deliberately not done: bulk renames, test tiers, parallel test files. Background in `review/archive/test_suite_plan.md` and `test_suite_review.md`. |

## B6 - Performance (ranked by the report, section 5.6)

Rejected experiments not to reopen (section 11): Arrow fetch path, `csw()` stepwise fits, SQL `ORDER BY` for survey sort, `bw.SJ` subsampling, batched gemm (1.8x regression with reference BLAS), `shared_period` plan, reference weather as default, shared SSP monthly cache.

| Rank | ID | Eff | Status | Open task | Gate |
|---:|---|---|---|---|---|
| 3 | R2-PERF-01 | M | ◐ | Shrink the Step 2 result. Done: household-constant vectors shared once per artifact (BFA 3x3 shape: artifact 945 to 886 MB, main-thread read 0.93 to 0.49 s). Open: drop `hist_sim_result$svy` (4.5 MB), lazy per-scenario read off the main thread, slimmer `F_loading`. Real BFA artifact re-measured 2026-10-08 (see "Local measurements"): `weather_raw` per pipeline (5.0 MB) is the largest remaining part, then `y_point` (1.7 MB) and `F_loading` (3.4 MB, uncertainty on only); the main-thread read is already 1.2 s at 3x3, so the case for further work is memory (1.16 GB in the Shiny process), not read time. | Bit-identical |
| 4 | R2-PERF-04 | S-M | ◐ | Table construction done (`ac62773`; 1x1 1.93 s to 0.94 s, 2x2 7.21 s to 3.39 s, line-dependent group; record in the archive addendum). Still open: the C++ kernel `welfare_stats_all` (25% of the line-dependent group at 2x2, 1.99 s of 9.3 s before the fix) and preparation (`.aggregation_prepare_pipeline`, hashing; 29% when the prep cache misses). Re-profile before more work. | Bit-identical |
| 5 | CR-PERF-04 | M-L | ☐ | Decided 2026-10-08: scope is Step 3 only (run + decomposition); Step 2 is already fast and stays as is. Scheduled after the SP work lands. Design: option (b), a separate Step 3 runner reusing the artifact helpers, on the shared mirai pool (so the Connect memory cap still holds), with `input_task_button()`. Extract shared lifecycle helpers (task state, cancel, timeout, snapshot scrubbing) from the Step 2 coordinator only after Step 3 shows which parts it really shares; do not build a general framework first. Step 1 weather, LASSO/fit and exports are out of scope for now. Covers CR-SEC-07 and any post-delivery worker job for R2-PERF-13. The first visit of each Step 3 method still blocks the main thread (BFA 3x3 about 52 s). | Sync vs worker bit-identical |
| 10 | R2-PERF-03 | S-M | ☐ | Identity-keyed prep cache storing row indices, bounded by bytes. Do not enlarge the entry count (2.3 GB). Measured 2026-10-08 (BFA, line-dependent group): the app cache holds 32 entries (`mod_2_02_results.R:995`); at 1x1 (17 pipelines) a warm cache cuts a slider change from 2.9 s to 2.1 s; at 2x2 (63 pipelines) the 32-entry cache thrashes and gives nothing (9.3 s cold or warm); with all 63 entries held the slider change falls to 7.0 s (-25%, about 2.3 s) but the cache is 540 MB (8.6 MB per entry) against 274 MB at 32. So the gain is real but modest and bound to payload size; a byte-bounded cache of row indices would be the way to get it without the memory. Lower priority than the C++ kernel in R2-PERF-04. | Bit-identical |
| 18 | R2-PERF-07 | S-M | ☐ | `stop_mirai()` on cancel; checkpoints between SQL stages. | n/a |
| - | igraph removal | S-M | ☐ | Replace `igraph::components()` in `loc_panel()` (`R/fct_loc_panel.R`, its only use). Value is dropping igraph and its libglpk system library, not speed: base R is slower (TJK 6.5M edges: igraph 0.8 s, union-find 7.9 s, label propagation 2.5 s); SQL min-label propagation in DuckDB is about equal. The larger win in dense countries is the pair self-join (1.2-11 s; TJK 11.3 s cold), for example blocking by cell before the join. Keep `test-determinism.R:96`. | Partition identical |
| OPT-02 | - | - | ☐ | Startup and Step 3 backend: end-to-end timing and peak memory, interactive validation (lazy worker loading, run-owned decomposition context, compact future channels are implemented). Profile analytic baseline-delta validation and aggregation cache misses before changing more. | - |
| OPT-03 | - | - | ☐ | Hex engine lazy-load. mod_1_02/03 map containers are static, so deferral needs container restructuring. | - |
| OPT-06 | - | - | ☐ | Deferred 2026-10-08 (no measured pain behind it). Step 2 batching tuning (never implemented). XGBoost support deferred by the user. DuckDB 2.0 / Parquet v2 is in `review/duckdb_parquet_plan.md`. | - |

## B8 - Accessibility (WCAG 2.2 AA, section 9)

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-A11Y-08 | M | M | ◐ | Map "View as table" alternative: dropped by user decision 2026-10-08 (maps stay hover-only for values). ECharts `aria` in `wise_echart_theme()` (`utils_plot_theme.R`): deferred by user decision 2026-10-08 (generic generated descriptions judged not worth a screen-reader pass); reopen with hand-written descriptions on key charts if wanted. |
| CR-A11Y-09 | M | M | ☐ | axe-core via `shinytest2` in CI (same job as CR-OPS-01). |
| CR-A11Y-05 | L-M | S | ◐ | Done in code 2026-10-08 (`f224ab7`): legend `.wx-tip` markers have a `role="tooltip"` child with `aria-describedby`, are hoverable, and Escape dismisses them (`custom.js`); the hexmap pointer tooltip hides on Escape. Contract test in `test-a11y-contract.R`. Not checked in a browser; the 12 px target is R2-A11Y-06. |
| R2-A11Y-04 | L | S | ◐ | Done in code 2026-10-08 (`f224ab7`): orange, sky blue and yellow darkened in `.okabe_ito` (all series at least 3:1 on white) and `.wise_marker_alt` is `#A86400` (4.7:1, for the 10 px label); test in `test-a11y-contract.R`. Not seen in a browser. The wave-colour map palette (`fct_surveystats.R`) and `.coverage_ramp` keep canonical hexes. |
| R2-A11Y-05 | L | S | ◐ | Done in code 2026-10-08 (`de25603`): `custom.js` names untitled `.wise-info-icon`s "More information: <heading or label text>", including content added later. Checked in headless Chrome on a mock page (static and dynamic icons), not in the real app. Skip link, main landmark, heading levels and live region were done earlier. |
| R2-A11Y-06 | L | S | ◐ | Done in code 2026-10-08 (`de25603`): 24 px hit areas for `.wise-info-icon` (`custom.css`) and `.wx-tip` (`::before` overlay); a point 9 px from the icon hit it in headless Chrome. Left: pan buttons. MapLibre's default keyboard pan (arrow keys on the focused map) is not disabled in `hexmap.js` but was not tested in a browser; add pan buttons only if that fails. The dead click input is removed. |

## B9 - Code quality and docs

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-CQ-10 | L | S | ◐ | `AGENTS.md`: Testing section and counts are current. Not re-checked: deleted dev scripts, install one-liner. Stale refs in `fct_load_data.R:241` and `dev/00_make_manifest.R:16`. |
| CR-CQ-03 | L-M | M | ☐ | One `cachem` helper; `bindCache()` on run-pure outputs. Overlaps R2-PERF-03/04. |
| CR-CQ-04 | M | M | ☐ | Define outputs once at module level (58 are defined inside observers). |
| CR-CQ-01 | M | L | ☐ | Move static builders out; split the three giant server functions. |
| CR-CQ-02 | M | L | ☐ | Shared Results-pane module for Steps 2 and 3. |

Ordering note from the report: delete dead code before splitting files; one PR per file with characterisation tests.

## Performance baselines (BFA, report container, medians)

Local column measured 2026-10-08 on the developer laptop (8 cores, 16 GB, local data path, macOS) from a clean export of `dev` at 3633915, OLS, uncertainty off, compact payload, weather cache forced on, one repetition per cache state (1x1 had two). Scripts are in the session scratchpad, built on `dev/bench_step2.R` (the prefix is evaluated and `fct_run_simulation()` called directly). "Local after" shows the effect of landed perf changes.

| Measurement | Report value | Local before | Local after |
|---|---:|---:|---:|
| Step 2 worker, default scenario, warm (OLS) | 34 s | 1x1 (1 SSP, 1 period, 16 CMIP6 members plus historical): 16.5 s (cold 18.0 s) with the benchmark harness; historical only: 1.8 s. Direct `fct_run_simulation()` timing, median of 3: 1x1 14.05 s, 2x2 49.43 s | After PERF-W2: 1x1 13.14 s, 2x2 46.77 s. After PERF-W1 (same tree, 1 thread, median of 3): legacy window 1x1 13.20 s, 2x2 52.09 s (noisy); lag-join roll 1x1 9.87 s, 2x2 34.34 s |
| Step 2 worker, 3x3, warm (OLS / RIF) | 289 / 332 s | 147.9 s (cold 140.3 s) / RIF not run | |
| Step 2 peak RSS, 3x3 | 6.8 GB | max resident 6.6 GB (peak memory footprint 10.8 GB incl. compressed); sampled process tree 4.4 GB | |
| Step 2 artifact, 3x3 (OLS / RIF) | 521 MB / 1.03 GB | real worker artifact (`step2_async_worker()`, slim model fit, uncertainty off): `result.qs2` 428 MB on disk, 1.16 GB in memory after read (1x1: 52 MB / 169 MB; 1x1 with uncertainty on: 58 MB / 228 MB). The unslimmed harness result is 2.08 GB (2.44 GB serialised) | |
| Step 2 Results poverty-line change, default / 3x3 | 5.8 / 60.8 s | 1x1: 2.5 s (line-dependent group) of 4.6 s (all nine metrics); 3x3: 21.3 s of 39.8 s. Repeat timing with a warm prep cache holding every pipeline: 1x1 1.93 s, 2x2 7.21 s | After R2-PERF-04: 1x1 0.94 s, 2x2 3.39 s |
| Step 3 Run, default / 3x3 | 5.9 / 47.0 s | 3x3: apply-policy blocking 33.8 s | |
| Step 3 aggregation-method switch, default / 3x3 | 11.4 / 104.7 s | 3x3: first metric (mean) 35.2 s, second (headcount ratio) 22.4 s | |
| Step 1 residual diagnostics (N = 13.4k) | 8.7 s | not measured | |
| App cold start to first response | 7.0 s | not measured | |

### Local measurements 2026-10-08 that still matter for open items

- **R2-PERF-01 (shrink the Step 2 result): measured on the real worker artifact; household-constant sharing works, the rest is `weather_raw`.** The harness result (2.08 GB, 13.5 MB per pipeline, household-constant `id_vec`/`weight`/`svy_row_id`/`sim_year` 5.6 MB each) is the unslimmed object. The real artifact, written by `step2_async_worker()` with the app's slim snapshot, is much smaller: BFA OLS 3x3 `result.qs2` 428 MB on disk, 1.16 GB in memory after `qs_read` + `step2_unshare_constants()` (145 pipelines at 6.7 MB each, plus 7.3 MB of `.shared_constants`, historical arm 39 MB). Main-thread read-back 1.2 s (`qs_read` 1.20 s, unshare 0.01 s; 1x1: 0.19 s). Per pipeline now: `weather_raw` 5.0 MB (74%), `y_point` 1.7 MB (26%); with coefficient uncertainty on, `F_loading` adds 3.4 MB (1x1 artifact 169 to 228 MB, on disk 52 to 58 MB, so it compresses well). Historical arm: `pipeline` 17.9 MB, `weather_raw` 16.2 MB, `svy` 4.5 MB (the `hist_sim_result$svy` item). Implications: per-pipeline `weather_raw` is about 0.7 GB of the 1.16 GB at 3x3, so it is the only large lever left. Consumer check (code reading, 2026-10-08): the per-member `weather_raw` holds the member's value columns only (key columns are already shared in the scenario's `weather_shared`). Step 2 itself never reads it after the run: aggregation, the Results tab and `mod_2_02` do not touch it, and the Diagnostics tab (`mod_2_03_diagnostics.R:183-202`) reads the scenario-level representative (member 1) plus the historical arm. The per-member copies are read only by Step 3: `step2_exposure_resolve()` (`fct_simulations.R:912`) rebuilds each member's per-row exposure table from it (schema 2 stores a recipe, not the table), `.compute_hazard_values()` (`fct_policy_decompose.R:411`) reads period weather, and `fct_policy_metric_decompose.R:649` checks it for baseline/policy alignment. So it cannot simply be dropped (that would mean storing the larger exposure table instead). The existing alternative, `weather_storage = "reference"` (members read from the on-disk store), was measured and rejected as the default because Step 2 time rose about 80% from per-member disk reads (archive: `step2-optimization-decision-record.md`). Untested variant: keep members in the store only for Step 3 (lazy read when Step 3 runs, ideally inside the Step 3 worker of CR-PERF-04), which would keep up to 0.7 GB out of the Shiny process without slowing Step 2; the cost would move to the first Step 3 visit. Design this together with CR-PERF-04 rather than separately. The worker's own peak is the larger cost: process RSS 1.8 GB before, 5.3 GB after a 3x3 run in one process (the harness inputs add about 1 GB). Not measured: RIF artifact, 3x3 with uncertainty on, memory split between the worker and the Shiny process in a real session.
- **R2-PERF-04 (poverty-line change): the line-dependent group is about half the suite.** 1x1: 2.5 s of 4.6 s; 3x3: 21.3 s of 39.8 s (headcount_ratio, gap, fgt2). The line-free group is 3.6 s / 30.4 s, so a poverty-line change cannot get below roughly 21 s at 3x3 without making the line-dependent kernel itself faster (the three methods share one sort per group in `welfare_stats.cpp`; a per-method breakdown inside the suite was not taken).
- **CR-PERF-04 (Step 3 off the main thread): baseline for the worker comparison.** 3x3 targeted-SP: apply-policy blocking step 33.8 s, first metric 35.2 s, second metric 22.4 s (the second is cheaper because the context caches are warm: hazard cache hit 1, decile reuse 1, delta reuse 1). Output objects are small (15.8 MB per metric), so shipping results back from a worker is cheap; the cost is the input snapshot (Step 2 result, up to 2 GB in this harness). A reference check inside the harness found the optimised annual path equal to the reference (max abs difference 0).
- **Scale check, IRN (historical arm only).** The 1 SSP x 1 period run returned no future scenarios for IRN with the local data (1 key, historical only), so IRN future and Step 3 could not be measured here. IRN historical: 20.2 s total vs 1.8 s for BFA (11x for 22x the rows), hist result 143.7 MB vs 29.8 MB, process RSS 2.3 GB after the run.
- **Real worker artifact, other engines and settings (written by `step2_async_worker()`, read back as the main thread does).**

  | Case | `result.qs2` on disk | In memory after read | Main-thread read | Worker run |
  |---|---:|---:|---:|---:|
  | OLS 1x1 | 52 MB | 169 MB | 0.19 s | 19.2 s |
  | OLS 1x1, uncertainty on | 58 MB | 228 MB | 0.21 s | 20.1 s |
  | RIF 1x1 | 74.5 MB | 166 MB | 0.21 s | 18.6 s |
  | RIF 2x2 | 270.7 MB | 522 MB | 0.61 s | 58.8 s |
  | OLS 2x2, uncertainty on | 207.8 MB | 741 MB | 0.63 s | 63.9 s |
  | OLS 3x3 | 428 MB | 1.16 GB | 1.2 s | 144.5 s |

  RIF is larger on disk than OLS (74.5 vs 52 MB at 1x1) but the same in memory. Read-back stays under 1 s up to 2x2. Memory in the Shiny process is the cost to watch, not read time.
- **Not measured:** RIF with uncertainty on, 3x3 RIF, Step 1 timings, cold start, remote (Databricks) weather reads, concurrent sessions. The weather stage was profiled before PERF-W1 and PERF-W2 (archive addendum); re-profile before picking more weather work.

## Log

Newest entries only. Earlier entries (2026-10-06 to 2026-10-08) are in the archive record.

- 2026-10-08 - Tracker consolidated: finished rows (PERF-W1, PERF-W2, R2-OPS-08, the done part of R2-PERF-04), closed won't-fix rows and their measurement notes, and the older Log entries moved to the archive addendum. Open counts above are recomputed.
- 2026-10-08 - PERF-W1 (`5bb1ffc`): lag-join roll in `get_weather()`, bit-identical, 1x1 -25% and 2x2 -34% at 1 thread. Decision (user): weather threads stay at 1 in production (shared Connect host). `manifest.json` needs regenerating before deployment (also for PERF-W2 and R2-PERF-04).
