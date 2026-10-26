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
| B12 | Methodology review follow-ups | 8 |
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

## B12 - Methodology review follow-ups

Source: `review/archive/methodology_review_2026-10-26.md` (closed 2026-10-26). Done: documentation corrections (`0d50062`), run-seed provenance, batch survey fingerprints and the climate-member grid check (`f9cdc08`), sector targets in survey weights (`52561c6`, Decision log above) and the RIF joint covariance (finding 2, Decision log above). Finding 1 (additive fixed effects) is documented, not changed. Closed 2026-10-26 (user): MR-01 dropped (cost-effectiveness person weights, not pursued); MR-02 (only a column named `weight` is a survey weight, `survey_weight_column()`), MR-03 (strict poverty cutoff in `.headcount_resid_variance()`) and MR-10 (a RIF fit records the fallback to independent equations as a `rif_joint_covariance` fallback, shown in `model_fit` and in provenance), see the Decision log below. Open remainders:

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| MR-04 | L | M | ☐ | The weather-support diagnostic compares with the historical-window weather at baseline locations, not the fitted sample (`docs/30_simulation.md` Section 6 says so). Add a separate fitted-sample check if the result is to warn about regression extrapolation; a marginal check does not establish joint weather and moderator support. |
| MR-05 | L | S | ☐ | The batch data work item fingerprints the survey files only. H3 and weather files do not enter any stage identifier (stated in `docs/52_batch_runs.md`). Add their fingerprints and a two-run integration test that changes one input file and checks the affected branches rerun. |
| MR-06 | L | S | ☐ | Real-data check of the climate grid rule (expected location-months from the requested locations, independent of members): a location with no climate cell excludes every member. The five BFA members excluded on 2026-10-26 (all 7152 location-months missing) are known and expected; what is left is to confirm that no requested location lacks a climate cell. |
| MR-07 | L | S | ☐ | Sector targets: working rows with no sector flag (about 4% of BFA 2021 working rows) stay in the denominator, so the services target falls short by their weight (`docs/41_policy_levers.md`). Decide whether they should be excluded from the working population or reported. |
| MR-08 | L | S | ☐ | No model-level BFA before/after of welfare for the sector lever: the sector variables are not model variables in the batch run on BFA. Needs a spec or fixture where they are. |
| MR-09 | M | M | ☐ | Finding 1 follow-up: add a specification test that distinguishes additive from interacted fixed effects, and assess an area-by-round specification as a separate methodological decision (identification and support diagnostics, numerical parity). Do not change the estimator silently. |
| MR-11 | M | S | ☐ | RIF joint covariance, owed checks: drive the Step 2 and Step 3 panes in the browser; a covariate lever (infrastructure) on real data; adequacy of the number of clusters against 9 times the active coefficients in other countries (a singular block falls back to independent equations); timing and peak memory of the 9-fold wider loading (decided not to measure, 2026-10-26; do it if a large country runs slowly). |
| MR-12 | M | M | ☐ | RIF policy-effect bands widened by about an order of magnitude under the joint covariance (headcount effect of a transfer: -0.0017, half-width 0.00007 before, 0.0008 after). The cause is the repositioning term `x (b(tau_post) - b(tau_pre))`, with `x` the weather level. Decide whether this is the intended coefficient uncertainty for a transfer, and check it against a Monte Carlo of the full pipeline. |

## B13 - Batch pipeline follow-ups

Source: `review/archive/batch_pipeline_plan.md` (archived 2026-10-26). Phases 1 to 4, the reproducibility template/checker, early-stage artifact stamps and local survey fingerprints are implemented. Broader source-input fingerprints remain MR-05; do not duplicate that task here.

| ID | Sev | Eff | Status | Open task |
|---|---|---|---|---|
| BP-01 | L | M | ☐ | Per-release parity against a downloaded headless-app Export bundle. Existing `dev/batch_parity_bfa*.R` checks compare module-server tables with batch, not the downloaded bundle. Compare the same spec and seed through Steps 1 to 3, including policy tables. |
| BP-02 | L | S | ✗ | Separate policy-stage crew controller; policy currently shares the bounded `sim` controller. Defer until a measured batch workload needs different Step 2/3 concurrency or memory limits. |
| BP-03 | L | M | ✗ | A frame key independent of descriptive-statistics options, which currently enter `data_id` and invalidate downstream fits. Defer until changing statistics causes material rerun cost; preserve table identity and cache correctness if split. |

Closed scope decision (user, 2026-10-26): figures and model/spec selection are supported downstream in study-specific reproducibility packages, not a shared Phase 5. Extract `weather_effect_data()` only if a concrete app or downstream consumer needs it; no standalone batch task. Each study owns its `renv.lock` and software pins.

## Decision log (uncertainty and residuals, 2026-10-26)

Numerical changes, BFA unless stated, "original" rule unless stated. Evidence and tables are in the archived review.

- F0 (residual key): BEN 2018 + 2021, historical average mean / poverty rate / Gini 5.4948 / 0.2916 / 0.3782 before, 5.2755 / 0.2685 / 0.3410 after (observed 5.2510 / 0.2729 / 0.3432). BFA unchanged to every printed digit (4.3606 / 0.4358 / 0.3725).
- F8 (logistic loading): agriculture employment, first historical year, coefficient SD 0.5036 before, 0.1140 after (Monte Carlo 0.107); band at 10/90 [-0.194, 1.097] before, [0.314, 0.598] after.
- F1 (median reference under "resample"): the reference year's residual variance is added to the contrast; the mean reference, same-year and year-averaged contrasts are unchanged.
- F2 (own residual bar): "resample", level, coefficient bar 0.5461 before (residual inside), 0.5429 after, residual bar 0.0588.
- F9 (poverty-rate residual variance): residual SD under "resample" 0.00967 before, 0.00758 after (Monte Carlo 0.00778).
- Normal rule removed: point estimates under "original" and "resample" identical to every printed digit (mean 4.36060483590172 and 4.77585348505506).

## Decision log (sector targets, 2026-10-26)

- Methodology review finding 4b (user, 2026-10-26): the labour sector lever sized its targets in working rows while the sliders start from weighted shares. The applied target now uses survey-weight sizes, the same shares the sliders initialise from (`R/fct_policy_sim.R`, the sector block of `apply_policy_to_svy()`). With equal or absent weights the sizes are row counts and outputs are unchanged. Alternative rejected: relabel the sliders as row shares.
- BFA 2021 individual survey (47,090 rows, weights 15 to 3,225), targets industry 30 and services 35 (agriculture 35), seed 123, survey level (`apply_policy_to_svy()` on the real frame; HEAD `72a2fdb` before, this change after). Weighted shares of industry / services / agriculture among the working: start 18.54 / 25.82 / 51.68; before 29.73 / 25.82 / 40.49 (row shares 29.1 / 31.06 / 35.0, so the row target was met and the weighted one was not); after 30.00 / 31.03 / 35.00. Weighted share of the working who changed sector: 11.19 before, 16.68 after. About 4% of working rows carry no sector flag; their weight is part of the denominator and the services target falls short by it.
- Not checked: a model-level BFA before/after of welfare. The sector variables are not available as model variables in the batch run on BFA (the fit stops with "not available in the data"), so the policy gain was not compared. The Step 3 pane was not driven in the browser.

## Decision log (RIF joint covariance, 2026-10-26)

- Methodology review finding 2 (step 3b; user, 2026-10-26: joint covariance, independent blocks as the fallback with a warning, no separate timing/memory run for the wider loading). Before: every quantile equation's deviation was drawn as `L_k z` with one shared `z`, so `Cov(b_k, b_l) = L_k L_l'`, which depends on the Cholesky column order and is close to perfect correlation for similar factors. After: the stacked cluster sandwich `V_kl = c (X'X)^-1 (sum_g X_g' e_kg e_lg' X_g) (X'X)^-1` over the nine equations (Eq. (6.1) in `docs/33_uncertainty.md`), one Cholesky factor of its active block, and a loading `F_i = (1-w) x' L_J[k,] + w x' L_J[k+1,]` with `9 * p_active` columns. Alternative rejected as the default: independent per-quantile blocks (bands probably too narrow). It stays as the fallback (missing or invalid joint covariance, block not positive definite).
- Where: `compute_rif_joint_vcov()` (built in `fit_model()` before the fits are slimmed, stored on `fit3`) and `rif_joint_factor()` in `R/fct_simulations.R`; `interpolate_F_loading()` in `R/fct_rif_sim.R`; the Step 3 policy arm's basis in `R/fct_policy_loading.R` (`.policy_loading_rows_rif()`, `.policy_loading_rows_cov()`), so `F_base + d` stays in one space. The metric decomposition reaches the same code through `.policy_loading_terms_rif()`. Consumers that only take `F_agg` (aggregation, contrasts, `step2_contrast_sd()`) are unchanged. The validity check at fit time: equal rows, coefficients and X'X across equations, and each diagonal block reproduces `vcov()` of its equation.
- Tests: new tests compare the loadings with `B V B'` and with Monte Carlo draws from the joint covariance (tau 0.1 and 0.9 included), check column-order independence, a brute-force cluster sandwich (off-diagonal blocks), and the fallback warning. Changed on purpose: the interpolation test in `test-fct_rif_sim.R` (it asserted the old blend into shared columns; it now asserts one block of columns per quantile, zero covariance between quantiles under independence), and in `test-fct_policy_loading.R` the basis width (`k_base` is 2 per equation times 9, and the policy coefficient adds one column per equation) with a clustered fixture. No other assertion moved.
- BFA before/after (HEAD `d5a8be4`, code of `52561c6`, against this change; RIF with 3-month `tx`, default fixed effects, clustered at the location panel, historical and SSP3-7.0 2025-2035, coefficient uncertainty on, cash transfer 60 to the poorest 30%, seed 123; `tar_make()` in the main process, each build in its own library, weather cache disabled). A third run forces independent equations (the fallback) for reference. All 9,720 annual point estimates are identical in the three runs (max absolute difference 0); Step 1 coefficients and standard errors are identical. Median per-year coefficient SD, shared shock (before) / independent (fallback) / joint (after):
  - Baseline arm: mean 0.00936 / 0.00433 / 0.00818; median 0.00575 / 0.00327 / 0.00557; headcount rate 0.00120 / 0.00099 / 0.00119; gap 0.00054 / 0.00033 / 0.00052; Gini 0.00049 / 0.00054 / 0.00073; total 205k / 95k / 179k.
  - Policy arm, per year: mean 0.00943 / 0.01160 / 0.00922; headcount rate 0.00117 / 0.00215 / 0.00134; Gini 0.00050 / 0.00246 / 0.00128; gap 0.00057 / 0.00382 / 0.00169.
  - Policy effect, coefficient half-width (point estimate, historical): mean 0.00097 / 0.01410 / 0.00697 (+0.0355); headcount rate 0.00007 / 0.00243 / 0.00081 (-0.00173); Gini 0.00004 / 0.00310 / 0.00126 (-0.00595). SSP3-7.0: headcount rate effect 0.00014 / 0.00207 / 0.00076 (-0.00195).
  - The pooled expected-level band (coefficient, models, years) barely moves because climate-model and year spread dominate.
- Reading: the joint baseline bands lie between the independent lower bound and the shared-shock bands and are 5% to 15% narrower than before for most metrics (the shared shock implied near-perfect correlation between equations). The Gini band widens by about half. Policy-effect bands widen by about one order of magnitude. The policy arm adds the repositioning term `x (b(tau_post) - b(tau_pre))`, with `x` the weather level. Under the shared shock its loading nearly cancelled; under the estimated covariance it does not, because the weather curve is estimated with real noise across quantiles. The headcount effect of the transfer is now about 0.0017 +/- 0.0008, not +/- 0.00007. This follows from the model as specified. It was not checked against a Monte Carlo of the full pipeline.
- Found on the way: the first "after" run fell back to independent equations. Cause: the diagonal-block check compared by mean relative difference, which tiny off-diagonal entries inflate. It now uses the largest difference relative to the largest entry (tolerance 1e-6), and the warning reports it. The fallback is silent in the batch tables (a warning in `tar_meta()` only): a run whose bands came from the fallback is not marked in `provenance` or the model tables. Not changed here.
- Not checked: the Step 2 and Step 3 panes were not driven in the browser; no timing or peak memory of the 9x wider loading (user decision above); a covariate lever (infrastructure) on real data, which the unit tests cover with a synthetic fixture; clusters-per-coefficient adequacy on real data (the joint block has `9 * p_active` rows; the BFA run built the joint covariance without the fallback warning, other countries are untested). Models fitted before this change carry no joint covariance and fall back to independent equations with a warning until they are refitted.

- Methodology review MR-02, MR-03, MR-10 (user, 2026-10-26). MR-02: `survey_weight_column()` returns `weight` only; a frame with `hhweight`, `wgt` or `pw` and no `weight` is unweighted everywhere, which is what the aggregation already did (before, the decomposition and the dropped-share paths weighted by the alias). Harmonised data always carry `weight`, so no BFA number moves. MR-03: `.headcount_resid_variance()` counts residuals strictly below the cut-off (`findInterval(..., left.open = TRUE)`), as poverty does; it differs from before only when a residual equals the cut-off exactly (example: prediction 0, line 1, residuals {0, 1}: variance 0, was 0.25). MR-10: `fit_model()` appends a `rif_joint_covariance` fallback when the joint covariance cannot be built or the weather block is not positive definite; `model_fit` and the provenance record show it. Tests: `test-w3-a-aggregation-characterization.R` (weight column), `test-fct_aggregation_delta.R` (tie), `test-fct_policy_loading.R` (fallback record). Not run: a BFA before/after (none of the three moves BFA numbers).

## Log

Entries up to 2026-10-24 are in the archive ("Log 2026-10-23 to 2026-10-24 (moved)" and earlier addenda). Add new entries here.

- 2026-10-24 - Tracker compacted to open work; closed list, known gaps, baselines and the Log moved to the archive verbatim.
- 2026-10-24 - CR-SEC-03 and CR-A11Y-08 closed as won't fix (user decision; B2 open count 2 to 1, B8 2 to 1). Rows and reopen triggers in the archive addendum.
- 2026-10-24 - RED-06 and R2-OPS-09 closed as won't fix (B5 open count 1 to 0); DOC-11 severity raised L to M (the log-outcome transfer is worth 8% to 18% more than T with a residual term, so policy gains are overstated). Rows in the archive addendum.
- 2026-10-24 - DOC-11 closed (B9 open count 3 to 2): for a log outcome the cash transfer is now added after the residual, so the policy arm gains T and not T * exp(e); regular and shock-responsive SP, aggregation mean and its gradient, and the metric states. Outputs move (policy gains shrink by up to 8% at SD 0.4); Decision log entry, real-BFA before/after (policy mean gain 0.70 and 1.30 of the transfer before, 1.00 after, for original and resample residuals) and the row in the archive addendum. The Step 3 pane was not driven in the browser.
- 2026-10-25 - DOC-11 follow-up: the quantile model (RIF) now adds the transfer after repositioning (`E * exp(c + rho) + T`) and the level channels add it once with another lever active. RIF outputs move when a transfer combines with another lever or repositioning. Decision log in the archive addendum; real-BFA RIF before/after (transfer alone +1.8% gain, transfer plus electricity -0.7%) and the Decomposition tab driven in the browser, both in the archive. Also: `test-bench-step3.R` timing assertion made `expect_gte` (1 ms clock resolution made it flaky).
- 2026-10-26 - Uncertainty and residuals review closed and archived (B10 opened with 2 low-severity rows): residual key (F0), logistic loading (F8), own residual bar and median reference (F2, F1), poverty-rate residual variance (F9), the all-covariates control removed (F3), the applied residual rule recorded in the run summary, Step 2 provenance and batch provenance, the "normal" rule removed, docs 30, 32, 33, 40, 43, 50. Commits `c5ccb9e`, `1ecc93e`, `f84b9e3`, `235bce2`. Decision log rows above.
- 2026-10-26 - `REVIEW-2026-10-06.md`, the shock-responsive SP plan and tasks and the cost-effectiveness plan moved to `review/archive/` (code comments, tests, `ARCHITECTURE.md` and the `wise-close-finding` skill re-pointed). Their open or deferred items are B11 (8 rows, none scheduled).
- 2026-10-26 - Batch pipeline plan archived with incoming references updated; B13 retains the Export-bundle parity check and two demand-driven optimization deferrals. Phase 5 figures and selection are downstream study work; implemented reproducibility support stays in the batch template. Source fingerprint coverage remains MR-05.
