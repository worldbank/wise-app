# Review remediation tracking (REVIEW-2026-10-06)

Source of truth for findings: `review/REVIEW-2026-10-06.md` (immutable; reviewed commit `df37cdb`). This file tracks **open work only**. Finding text, evidence and remediation advice stay in the report; `§` numbers refer to it. The full per-finding record of finished work (commits, verification, Decision log, dated Log) is in `review/archive/REVIEW-2026-10-06-tracking-full.md`; read it only for the evidence behind a finished item.

Status: `☐` todo · `◐` in progress (remainder listed) · `✗` won't fix / deferred (reason given). Sev: C critical · H high · M medium · L low. Effort: S < 1 day · M 1-3 days · L > 3 days.

## Where things stand (2026-10-07)

All Critical and High findings are done in code, except where noted below. Done: B3 (headline numerics) and B4 (Step 3 levers) in code; B1, B2, B5 and B8 quick wins; most of B6 and B7. What is left is below, grouped by what kind of work it needs. Nothing is pushed. The `dev` branch is the working branch.

| Batch | Scope | Open |
|---|---|---|
| B1 | Deployment and dependencies | 1 partial |
| B2 | Security | 3 (plus 2 closed as won't fix) |
| B3 | Headline numerics | 0 |
| B4 | Step 3 levers | 0 (numbers owed, see Waiting on the user) |
| B5 | Robustness, CI, tests | 8 |
| B6 | Performance | 13 (incl. 5 carried over from the old optimization tracker) |
| B7 | Medium/Low bugs | 1 |
| B8 | Accessibility | 6 |
| B9 | Code quality and docs | 5 |

## Working rules

- One branch per batch off `dev`; within a batch, one commit per finding ID with the ID in the subject. Do not push or deploy without an explicit go-ahead.
- A finding is closed only when (a) a regression test fails before and passes after (or a reproducible command shows a config/docs fix), (b) the narrowest relevant `devtools::test(filter = ...)` passes, and (c) the Notes cell records the commit and what was verified. Then move it to the archive record by deleting its row here and adding a one-line entry to the Log.
- Numerical changes need a Decision log entry (in the archive file's table, or a new row here) with before/after BFA headline numbers, because outputs move.
- Performance changes follow `review/optimization_guidelines.md` section 9 (equivalence gate, before/after timing and peak RSS). Benchmarks: BFA 1x1 OLS (`WISEAPP_STEP2_WORKLOADS=one_ssp_one_period`, `WISEAPP_STEP2_MODELS=ols`) unless a larger payload is needed (user instruction 2026-10-07). The Step 3 harness is `dev/bench_step2.R` with `WISEAPP_STEP2_INCLUDE_STEP3=1 WISEAPP_STEP3_POLICIES=targeted_sp`; the `covariate` fixture needs an electricity column in the fitted model. Report timings are from a 4-vCPU container, so re-measure locally.
- Run `devtools::document()` (roxygen2 as pinned in `DESCRIPTION`), `devtools::check()` and the full suite once per batch with the tree quiescent. Regenerate `manifest.json` (`dev/00_make_manifest.R`) at the end of any batch that changes dependencies or `R/` files.
- Code hygiene conventions: `review/code_hygiene.md`.

## Waiting on the user

- **BFA before/after numbers (B4):** CR-BUG-02, R2-BUG-04, R2-BUG-06 and R2-BUG-07 move Step 3 outputs. Their Decision log rows (archive file) hold synthetic checks only; the BFA values need a manual Step 3 run in the app (BFA's outcome is not confirmed to be LCU, so the CR-BUG-02 and R2-BUG-04 LCU effects also need an LCU-outcome run).
- **Browser spot-check of recent UI changes:** columnar chart tooltips, map without pointer cursor, tab empty state, data-check notice, Step 1 diagnostics, a11y changes not yet seen in a browser.
- **Live Databricks check** of the scoped bearer-token secret on the first Connect load after the next deploy (CR-SEC-03).
- **Connect values** for DuckDB memory limit and threads (CR-PERF-13).
- **Manifest:** regenerate once more at the end (`91f599c` predates comment-only changes to 13 `R/` files in `3666d97`).

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

## B1 - Deployment and dependencies

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| R2-OPS-05 | M | S | ✗ | Decided 2026-10-08: stay on DuckDB 1.5.6 (no move to the 1.4.x LTS). `DESCRIPTION` pins `duckdb (== 1.5.6)` with bundled extensions checked by SHA-256 (`R/fct_load_data.R`; `AGENTS.md`). Azure/delta are not bundled (decision 2026-10-07: Connect uses Databricks only; local runs install them normally). |

## B2 - Security

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-SEC-03 | H | M | ◐ | Per-session secret names and a per-session connection. Two sessions in one process using different credentials for the same bucket still share one secret. Low priority: Connect uses one service principal and UI credentials are a local-use path. Confirm the scoped Databricks secret after the next deploy. |
| CR-SEC-07 | M | L | ☐ | Per-run size limits from config; cap the Step 2 queue by bytes; small profile for metadata. Folds into CR-PERF-04. |
| CR-SEC-09 (rest) | L | S | ☐ | Move inline JS/CSS to `custom.js`/`custom.css` (enables a CSP). Deferred (decisions 2026-10-07 and 2026-10-08): do last, in two steps. (1) Move our inline code to files (low risk). (2) Run the CSP in report-only mode on a staging Connect instance to list violations from Shiny, htmlwidgets, echarts4r, reactable and bslib; enforce only if the list is short, with a script-only target (strict `script-src`, lenient `style-src`) as the realistic goal. Connect or a proxy has to set the header. Not needed before the next deploy. |
| CR-SEC-02 | H | M | ✗ | Remaining DuckDB lockdown deliberately not done (see Known gaps). |
| R2-SEC-07 | Info | S | ✗ | Won't fix (user decision 2026-10-07): prepared-weather persistent cache is off by default; reopen if it is ever enabled. |

## B5 - Robustness, CI and test hygiene

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-OPS-01 | M | M | ◐ | Decided 2026-10-08: add a `shinytest2`/axe smoke job to CI (shared with CR-A11Y-09). Scope: one app-boot smoke, one `conditionalPanel` check and one axe run on the first screens; start as a non-blocking job, make it required once it is stable. Investigate why the headless-Chrome PNG test skips on some CI runs. CI is otherwise green (Tests step about 340 s, 0 failed, 0 skipped; `error-on` is `"warning"`). |
| R CMD check notes | L | S | ◐ | Unused Imports, `:::` and undefined globals are fixed (2026-10-08, uncommitted): `tidyselect` dropped from Imports, `Rcpp::sourceCpp` and `brand.yml::read_brand_yml` imported, workers use `utils::getFromNamespace()`, `stats`/`utils` imports and `globalVariables` added in `R/globals.R`, duplicate local `one_scenario` renamed in `mod_2_02_results.R`. The last `check(--no-tests)` before the rename showed only that NOTE plus the sandbox "future file timestamps" NOTE; re-run once to confirm. |
| CR-PERF-13 / R2-PERF-08 | M | S | ◐ | Env-configurable limits exist (`WISEAPP_DUCKDB_MEMORY_LIMIT`, `_THREADS`, `_TEMP_DIR`, `WISEAPP_THREADS`); choose values for Connect. |
| R2-OPS-08 | M | S | ☑ | Done 2026-10-08: `.profile_record()` takes the stage clock before its own `serialize()`/RSS work. Delete this row at the next tidy. |
| R2-OPS-09 | L | S | ◐ | Left: `set.seed` vs `local_seed` (116 calls in 48 files; convert only in files being touched); `tests/spelling.R` never fails (the `spelling` package is not installed here and there is no `inst/WORDLIST`; needs a WORDLIST pass first). The `localhost:1` tests are a refused connection with a 15-20 s deadline, so they finish at once; left as they are. |
| RED-06 | M | M | ◐ | One parameterised batch driver over `step2_compute()`. Consolidating the five `04_run_sim` copies deferred by user decision 2026-10-07. |
| Test suite: remaining | L | S-M | ☐ | (1) rename history-named test files to `test-<R file>.R`; (2) shared `helper-fixtures-*.R` only when two or more files share a builder; (3) `wiseapp.verbose` option to silence progress messages (an `R/` change); (4) `shinytest2` boot smoke plus one `conditionalPanel` check; (5) hygiene in touched files only (`library()`, `wiseapp:::`, `set.seed`, `expect_true(identical())`); (6) coverage job and ratchet in CI: dropped by user decision 2026-10-08. Coverage was 82.1% overall; `fct_predict_outcomes.R` 73%. Deliberately not done: bulk renames, test tiers, parallel test files. Background in `review/archive/test_suite_plan.md` and `test_suite_review.md`. |
| CR-PERF-15 | M | S | ✗ | Deferred (user decision 2026-10-06): keep `load_all()` in `app.R` and git-backed deploys. Cheaper lever: Min Processes / idle timeout on Connect. |

## B6 - Performance (ranked by the report, section 5.6)

Rejected experiments not to reopen (section 11): Arrow fetch path, `csw()` stepwise fits, SQL `ORDER BY` for survey sort, `bw.SJ` subsampling, batched gemm (1.8x regression with reference BLAS), `shared_period` plan, reference weather as default, shared SSP monthly cache.

| Rank | ID | Eff | Status | Open task | Gate |
|---:|---|---|---|---|---|
| 3 | R2-PERF-01 | M | ◐ | Shrink the Step 2 result. Done: household-constant vectors shared once per artifact (BFA 3x3 shape: artifact 945 to 886 MB, main-thread read 0.93 to 0.49 s). Open: drop `hist_sim_result$svy` (4.5 MB), lazy per-scenario read off the main thread, slimmer `F_loading` (the remaining bulk). Real BFA artifact not re-measured. | Bit-identical |
| 4 | R2-PERF-04 | S-M | ◐ | Poverty-line change recomputes only line-dependent metrics (done, 2.7 s to 1.1 s synthetic). Open: columnar threshold table / single support pass, contrast SD once, md5/serialise copies on reads. | Bit-identical |
| 5 | CR-PERF-04 | M-L | ☐ | Decided 2026-10-08: scope is Step 3 only (run + decomposition); Step 2 is already fast and stays as is. Scheduled after the SP work lands. Design: option (b), a separate Step 3 runner reusing the artifact helpers, on the shared mirai pool (so the Connect memory cap still holds), with `input_task_button()`. Extract shared lifecycle helpers (task state, cancel, timeout, snapshot scrubbing) from the Step 2 coordinator only after Step 3 shows which parts it really shares; do not build a general framework first. Step 1 weather, LASSO/fit and exports are out of scope for now. Covers CR-SEC-07 and any post-delivery worker job for R2-PERF-13. The first visit of each Step 3 method still blocks the main thread (BFA 3x3 about 52 s). | Sync vs worker bit-identical |
| 9 | R2-PERF-10 / CR-PERF-02 | S-M | ☐ | Normalise weather cache keys (Date vs character, year-aligned spans); reuse Step 1 weather for Step 2 historical. | Bit-identical |
| 10 | R2-PERF-03 | S-M | ☐ | Identity-keyed prep cache storing row indices, bounded by bytes. Do not enlarge the entry count (2.3 GB). | Bit-identical |
| 16 | CR-PERF-03 | L | ☐ | Factorised per-key predictor behind a flag. Agree tolerances first. | Pre-agreed tolerance |
| 18 | R2-PERF-07 | S-M | ☐ | `stop_mirai()` on cancel; checkpoints between SQL stages. | n/a |
| - | igraph removal | S-M | ☐ | Replace `igraph::components()` in `loc_panel()` (`R/fct_loc_panel.R`, its only use). Value is dropping igraph and its libglpk system library, not speed: base R is slower (TJK 6.5M edges: igraph 0.8 s, union-find 7.9 s, label propagation 2.5 s); SQL min-label propagation in DuckDB is about equal. The larger win in dense countries is the pair self-join (1.2-11 s; TJK 11.3 s cold), for example blocking by cell before the join. Keep `test-determinism.R:96`. | Partition identical |
| OPT-01 | - | - | ☐ | Step 2 progressive results: interactive Stop / rerun / input-change checks, full-app responsiveness, reliable peak-memory validation. Implemented 2026-10-01; in-app testing was confirmed by the user. | - |
| OPT-02 | - | - | ☐ | Startup and Step 3 backend: end-to-end timing and peak memory, interactive validation (lazy worker loading, run-owned decomposition context, compact future channels are implemented). Profile analytic baseline-delta validation and aggregation cache misses before changing more. | - |
| OPT-03 | - | - | ☐ | Hex engine lazy-load. mod_1_02/03 map containers are static, so deferral needs container restructuring. | - |
| OPT-05 | - | - | ☐ | Aggregation remainders, quantify first: radix sort in `src/welfare_stats.cpp` (about 0.1 s at IRN); median-gradient `stats::density()` (0.06 s); route the unweighted-with-weights lazy arm through `tables_multi` (behaviour change); persist compact aggregate tables for batch/replay; vendor BLAS only with a measured deploy-side win. | - |
| OPT-06 | - | - | ☐ | Step 2 batching tuning (never implemented). XGBoost support deferred by the user. DuckDB 2.0 / Parquet v2 is in `review/duckdb_parquet_plan.md`. | - |
| - | R2-PERF-13, R2-PERF-09, CR-PERF-05 | - | ✗ | Won't fix. R2-PERF-13 (partial suite first): the cost is shared preparation, so the saving is about 4% of worker time and method switches would recompute (user decision 2026-10-07). R2-PERF-09 (fast vs bounded weather collection): fast saves about 5% CPU for +20-30% peak RSS, so bounded stays. CR-PERF-05 (offline pre-aggregation): out of app scope. | - |

## B7 - Remaining bugs

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-PERF-07 | M | M | ✗ | Measured 2026-10-08 on BFA (OLS, default spec, 13,779 rows x 87 columns, `lobstr::obj_size`): the whole live `model_fit` plus `.snap$survey_weather` is 19.1 MB. Parts: `train_data` 8.6 MB, `.snap$survey_weather` 8.6 MB (16.2 MB together, so some columns are shared), fit1-3 about 11.5 MB but that is one shared captured environment, not three copies; `wise_mm` 0.2 MB (fit3 only); `formulas` 0.6 MB. `.snap$survey_weather` is the same object as the upstream `survey_weather()` reactive unless `relabel_bin_levels()` changes it, so the extra cost is between 0 and 8.6 MB per session. The worker copy is already slim (`step2_slim_model_fit()`, 10.2 MB). Not worth the risk: every Step 1 renderer reads these fields lazily, so a field dropped too early breaks a tab only when it is opened. Memory scales with rows, so reopen only if a large-country session (for example IRN) shows high RSS; measure with `dev/` scratch script pattern: build inputs via `bench_step2.R`, then `lobstr::obj_size()` per field. |

## B8 - Accessibility (WCAG 2.2 AA, section 9)

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-A11Y-08 | M | M | ◐ | Map "View as table" alternative: dropped by user decision 2026-10-08 (maps stay hover-only for values). ECharts `aria` in `wise_echart_theme()` (`utils_plot_theme.R`): deferred by user decision 2026-10-08 (generic generated descriptions judged not worth a screen-reader pass); reopen with hand-written descriptions on key charts if wanted. |
| CR-A11Y-09 | M | M | ☐ | axe-core via `shinytest2` in CI (same job as CR-OPS-01). |
| CR-A11Y-05 | L-M | S | ◐ | Done in code 2026-10-08 (uncommitted): legend `.wx-tip` markers have a `role="tooltip"` child with `aria-describedby`, are hoverable, and Escape dismisses them (`custom.js`); the hexmap pointer tooltip hides on Escape. Contract test in `test-a11y-contract.R`. Not checked in a browser; the 12 px target is R2-A11Y-06. |
| R2-A11Y-04 | L | S | ◐ | Done in code 2026-10-08 (uncommitted): orange, sky blue and yellow darkened in `.okabe_ito` (all series at least 3:1 on white) and `.wise_marker_alt` is `#A86400` (4.7:1, for the 10 px label); test in `test-a11y-contract.R`. Not seen in a browser. The wave-colour map palette (`fct_surveystats.R`) and `.coverage_ramp` keep canonical hexes. |
| R2-A11Y-05 | L | S | ◐ | Done in code 2026-10-08 (uncommitted): `custom.js` names untitled `.wise-info-icon`s "More information: <heading or label text>", including content added later. Checked in headless Chrome on a mock page (static and dynamic icons), not in the real app. Skip link, main landmark, heading levels and live region were done earlier. |
| R2-A11Y-06 | L | S | ◐ | Done in code 2026-10-08 (uncommitted): 24 px hit areas for `.wise-info-icon` (`custom.css`) and `.wx-tip` (`::before` overlay); a point 9 px from the icon hit it in headless Chrome. Left: pan buttons. MapLibre's default keyboard pan (arrow keys on the focused map) is not disabled in `hexmap.js` but was not tested in a browser; add pan buttons only if that fails. The dead click input is removed. |

## B9 - Code quality and docs

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| CR-CQ-10 | L | S | ◐ | `AGENTS.md`: Testing section and counts are current. Not re-checked: deleted dev scripts, install one-liner. Stale refs in `fct_load_data.R:241` and `dev/00_make_manifest.R:16`. |
| CR-CQ-03 | L-M | M | ☐ | One `cachem` helper; `bindCache()` on run-pure outputs. Overlaps R2-PERF-03/04. |
| CR-CQ-04 | M | M | ☐ | Define outputs once at module level (58 are defined inside observers). |
| CR-CQ-01 | M | L | ☐ | Move static builders out; split the three giant server functions. |
| CR-CQ-02 | M | L | ☐ | Shared Results-pane module for Steps 2 and 3. |
| CR-CQ-07 | L | M | ✗ | One integer `year` type: deferred. The varying types are a model contract (documented in `AGENTS.md`, Simulation Pipeline). Reopen only with an engine parity gate on every engine. |

Ordering note from the report: delete dead code before splitting files; one PR per file with characterisation tests.

## Performance baselines (BFA, report container, medians)

Re-measure locally before further B6 work and fill the local columns.

| Measurement | Report value | Local before | Local after |
|---|---:|---:|---:|
| Step 2 worker, default scenario, warm (OLS) | 34 s | | |
| Step 2 worker, 3x3, warm (OLS / RIF) | 289 / 332 s | | |
| Step 2 peak RSS, 3x3 | 6.8 GB | | |
| Step 2 artifact, 3x3 (OLS / RIF) | 521 MB / 1.03 GB | | |
| Step 2 Results poverty-line change, default / 3x3 | 5.8 / 60.8 s | | |
| Step 3 Run, default / 3x3 | 5.9 / 47.0 s | | |
| Step 3 aggregation-method switch, default / 3x3 | 11.4 / 104.7 s | | |
| Step 1 residual diagnostics (N = 13.4k) | 8.7 s | | |
| App cold start to first response | 7.0 s | | |

## Log

Newest entries only. Earlier entries (2026-10-06 to 2026-10-07 waves, merges and measurements) are in the archive record.

- 2026-10-07 - Tracker restructured: finished rows, the Decision log and the full Log moved to `review/archive/REVIEW-2026-10-06-tracking-full.md`; this file now lists open work only. Status corrections made while restructuring: R2-BUG-26 and R2-BUG-24 closed (their Notes and the 2026-10-07 log show all listed work done), R2-BUG-25 and CR-BUG-19 shown as done. Not changed: the archived record still shows the old states.
- 2026-10-07 - `optimization_tracking.md` archived (`review/archive/`); its open items are OPT-01, 02, 03, 05, 06 in B6. Weather #4/#5 are closed (`optimize_get_weather.md`: #4 partly adopted, #5 measured no change); phantom inputs closed by CR-BUG-11.
- 2026-10-07 - Code hygiene prompt revised into standing guidelines (`review/code_hygiene.md`).
- 2026-10-07 - Test-suite work closed and archived: CI green, 7920 expectations, Step 3 coverage targets done, `predict_outcome` residual fixes (2a1c498), Rd gaps fixed (3666d97). Open items are in B5.
