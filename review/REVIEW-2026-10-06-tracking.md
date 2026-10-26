# Review remediation tracking (REVIEW-2026-10-06)

Source of truth for findings: `review/REVIEW-2026-10-06.md` (immutable; reviewed commit `df37cdb`). This file tracks **open work only**. The full record of finished, closed and deferred work (commits, verification, measurements, Decision log, dated Log, performance baselines, reopen triggers) is in `review/archive/REVIEW-2026-10-06-tracking-full.md`; read it only for the evidence behind a finished or closed item. Compacted 2026-10-24.

Status: `☐` todo · `◐` in progress (remainder listed) · `✗` won't fix / deferred (reason given). Sev: C critical · H high · M medium · L low. Effort: S < 1 day · M 1-3 days · L > 3 days.

## Where things stand (2026-10-24)

All Critical and High findings, the docs/ revision (DOC-01 to DOC-14) and UNC-01 are done or closed. Nothing is pushed; `dev` is the working branch. Closed, deferred and won't-fix items, with the trigger for reopening each, are listed in the archive ("Closed and deferred list").

| Batch | Scope | Open |
|---|---|---|
| B2 | Security | 1 |
| B6 | Performance | 4 |
| B8 | Accessibility | 1 |
| B9 | Code quality and docs | 2 |

B1, B3, B4, B5, B7 have no open rows (B4: Step 3 lever numbers are owed, see Waiting on the user).

## Working rules

- One branch per batch off `dev`; within a batch, one commit per finding ID with the ID in the subject. Do not push or deploy without an explicit go-ahead.
- A finding is closed only when (a) a regression test fails before and passes after (or a reproducible command shows a config/docs fix), (b) the narrowest relevant `devtools::test(filter = ...)` passes, and (c) the Notes cell records the commit and what was verified. Then move it to the archive record (append the full row to the archive file's addendum), delete its row here and add a one-line entry to the Log.
- Numerical changes need a Decision log entry (in the archive file's table, or a new row here) with before/after BFA headline numbers, because outputs move.
- Performance changes follow `review/optimization_guidelines.md` section 9 (equivalence gate, before/after timing and peak RSS). Benchmarks: BFA 1x1 OLS (`WISEAPP_STEP2_WORKLOADS=one_ssp_one_period`, `WISEAPP_STEP2_MODELS=ols`) unless a larger payload is needed (user instruction 2026-10-07); 2x2 (`two_ssps_two_periods`) is the maximum for benchmarks and profiling, because 3x3 is an uncommon payload (user instruction 2026-10-08). The Step 3 harness is `dev/bench/bench_step2.R` with `WISEAPP_STEP2_INCLUDE_STEP3=1 WISEAPP_STEP3_POLICIES=targeted_sp`; the `covariate` fixture needs an electricity column in the fitted model. Report timings are from a 4-vCPU container, so re-measure locally.
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

## Log

Entries up to 2026-10-24 are in the archive ("Log 2026-10-23 to 2026-10-24 (moved)" and earlier addenda). Add new entries here.

- 2026-10-24 - Tracker compacted to open work; closed list, known gaps, baselines and the Log moved to the archive verbatim.
- 2026-10-24 - CR-SEC-03 and CR-A11Y-08 closed as won't fix (user decision; B2 open count 2 to 1, B8 2 to 1). Rows and reopen triggers in the archive addendum.
- 2026-10-24 - RED-06 and R2-OPS-09 closed as won't fix (B5 open count 1 to 0); DOC-11 severity raised L to M (the log-outcome transfer is worth 8% to 18% more than T with a residual term, so policy gains are overstated). Rows in the archive addendum.
- 2026-10-24 - DOC-11 closed (B9 open count 3 to 2): for a log outcome the cash transfer is now added after the residual, so the policy arm gains T and not T * exp(e); regular and shock-responsive SP, aggregation mean and its gradient, and the metric states. Outputs move (policy gains shrink by up to 8% at SD 0.4); Decision log entry, real-BFA before/after (policy mean gain 0.70 and 1.30 of the transfer before, 1.00 after, for original and resample residuals) and the row in the archive addendum. The Step 3 pane was not driven in the browser.
- 2026-10-25 - DOC-11 follow-up: the quantile model (RIF) now adds the transfer after repositioning (`E * exp(c + rho) + T`) and the level channels add it once with another lever active. RIF outputs move when a transfer combines with another lever or repositioning. Decision log in the archive addendum; real-BFA RIF before/after (transfer alone +1.8% gain, transfer plus electricity -0.7%) and the Decomposition tab driven in the browser, both in the archive. Also: `test-bench-step3.R` timing assertion made `expect_gte` (1 ms clock resolution made it flaky).
