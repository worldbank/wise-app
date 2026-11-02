# Seasonal forecast: implementation review

Review date: 2026-11-02. Scope: commits `d09a4ac` to `2d73f7f` on `seasonal-forecast`, and the forecast pilot in `wise-app-data` (`R/forecast_*.R`, `steps/forecast_bfa.R`, the published BFA runs). Companion to `roadmap/seasonal_forecast.md`, which tracks the plan; this file records what the review found and what to change.

Trigger: in an interactive run (seasonal forecast only, no SSP), Step 2 was slow, the forecast did not appear on every chart, and the console showed `Warning: Unknown or uninitialised column: 'n_forecast_members'`.

## Summary

| # | Issue | Severity | Where |
|---|---|---|---|
| 1 | The Historical comparator does not match the forecast's months, so forecast-versus-Historical differences are mostly seasonality (on BFA the sign flips). Agreed fix: place members in a same-window historical distribution. With `int_month` fixed effects, target months without interviews give NA predictions, and the run still reports 0 failures. | High (method, bug) | `.step2_forecast_expand_survey()`, headline cards, Historical-versus-forecast contrasts |
| 2 | The forecast weather builder takes 82 s on BFA. A complete historical-only Step 2 run takes 1.5 s. | High (performance) | `R/fct_forecast_weather.R` |
| 3 | `focus$n_forecast_members` is read from a tibble row that never has that column, which raises the warning. The member count falls back to `n_models`. | Medium (bug) | `R/fct_sim_compare.R` (forecast branch of the headline cards) |
| 4 | Results sections that exclude the forecast (adverse years, exceedance, return-period table) show no forecast content and no in-place explanation, so a forecast-only run looks incomplete. | Medium (UX) | `R/mod_2_02_results.R`, `R/fct_sim_compare.R` |
| 5 | `observed_through` is 2025-12-01 for an October 2026 run, so January to September 2026 are missing. Any lag that reaches before initialization is blocked, and lead-1 forecast values stand in for months that have already been observed. | High (data) | `wise-app-data` ERA5-Land refresh; catalogue |
| 6 | Forecast handling is spread across label regexes and parallel code paths rather than a scenario type. The weather builder duplicates `get_weather()` internals. | Medium (maintainability) | `R/fct_sim_compare.R`, `R/fct_sim_diag.R`, `R/fct_run_simulation.R`, `R/fct_forecast_weather.R` |
| 7 | One invalid catalogue row, or a refreshed ERA5-Land file, makes the whole catalogue fail, hiding every run. | Medium (robustness) | `R/fct_forecast_catalogue.R` |

## 1. Method: forecast outcome placed in the same-window historical distribution

### Findings

The forecast scenario is not crossed with historical years: each member is one weather state for the target window. That part is right. The comparator is wrong. Historical evaluates each household in its own interview month. The forecast evaluates every household in each target month (weight `weight / L`). On BFA (2021 EHCVM baseline, `t`), the interview-month climatology is about 28.9 degrees C and the November to January climatology is 26.5 degrees C. The October 2026 run's member mean for those months is 27.5 degrees C. The forecast is therefore about 1.0 degrees C warmer than normal for these months, but reads as about 1.4 degrees C cooler than Historical. Contrasts with Historical mostly measure the difference between survey months and target months.

### Agreed method (2026-11-02)

**Estimand.** For the baseline population and a target window W of L calendar months, compute the outcome distribution implied by forecast weather. Place it in the distribution of the same outcome under observed weather for W in each historical year.

1. **Forecast.** For each member, evaluate every household in each month of W with that member's weather, apply the model and residuals, and aggregate with weight `weight / L`. The result is one window aggregate per member. The metric is the average over the window's months (for example, the mean monthly headcount).
2. **Reference: same-window climatology.** Do the same with observed weather for W in each year of the historical period, using the same model, residual treatment, weights and predictor lags. The result is one window aggregate per year (about 30). This reference replaces Historical (interview months) for every forecast contrast. Historical stays a separate annual reference.
3. **Placement.** Report where each member falls in the reference, for example "median member is about a 1-in-4 outcome; 30% of members are worse than the historical 1-in-10". Do not give a return period for the ensemble mean, because averaging pulls it towards the centre. Call the member share an indicator, not a probability, because the spread is uncalibrated and skill is not established. With about 30 reference years, report outcomes beyond about 1-in-15 as "beyond the observed range" rather than extrapolating.

### Seasonality: estimation and prediction

Survey interview months need not match W. The survey supplies the population and the model supplies the weather response; the window sets the timing. This is valid under the following conditions.

- **Estimation.** Weather levels and welfare both have a seasonal cycle (lean season, harvest). Without seasonal controls, the weather coefficient absorbs the welfare cycle. Recommended specification for forecast use:
  - Weather as a calendar-month anomaly ("Deviation from mean" or "Standardized anomaly"; the app's climate reference is already per location and calendar month, 1991-2020), so the coefficient is identified from departures from monthly normals.
  - Interview-month fixed effects (`int_month`, or a coarser season grouping) to absorb the seasonal welfare level.
- **Prediction.** The seasonal fixed effect is common to the forecast and the same-window reference, so it does not change ranks and cancels in differences for additive models. Keep each household's own interview-month fixed effect, and set only the weather to month m of W. The absolute level then reads as "survey-time welfare level plus the target-month weather effect". Using the fixed effect of the target month instead would also add the seasonal welfare cycle, and it is undefined for months with no interviews (see the bug below).
- **Effect homogeneity.** One coefficient applies the same weather response in every season. If the target months are rare in the training data, that is an untested extrapolation. Show the share of training observations interviewed in the target months, and warn when it is low. With level predictors (not anomalies), also check that the forecast values lie within the training support (reuse the weather-support checks).
- **Composition.** As with the SSPs, the baseline population and its non-weather characteristics are held fixed across the window.

### Bug: interview-month fixed effects with forecast targets

`.step2_forecast_expand_survey()` overwrites `int_month` with the target month. `int_month` is both the weather join key and an available fixed effect. Checked on BFA (fixed effects `year`, `loc_id_panel`, `int_month`; continuous `t`, lag 1):
- A March 2027 target (no March interviews in the baseline) gives 100% NA predictions.
- A February to March window drops half of the household-months.
- Both runs report 0 failures.

Fix: keep a separate weather-month column for the join and leave `int_month` (and any column derived from interview timing) at its survey value. Fail loudly if any forecast prediction is NA.

## 2. Performance

Measurement (macOS, BFA, `t` lag 1-1 Mean Binned, OLS, original residuals, no coefficient draws, October 2026 run, November to January, 51 members; scratch profile using the `dev/bench/bench_step2.R` input builders):

| Stage | Time |
|---|---|
| `fct_run_simulation()` historical only | 1.5 s |
| `fct_run_simulation()` historical plus forecast | 106 s (weather 105 s) |
| `.get_forecast_weather()` alone | 82 s |
| `.forecast_catalogue_runs()` once | 0.13 s |

Pipelines are not the problem (52 keys in about 1 s more than historical). Line profile of `.get_forecast_weather()`:

| Line | Share | Cause |
|---|---|---|
| `fct_forecast_weather.R` member loop (`monthly \|> filter(member == ...) \|> mutate(roll) \|> ... \|> collect()`) | 40% | The lazy query is re-executed 51 times. Each run rebuilds the H3-to-location population-weighted joins for observed and forecast data, the cross join of the full observed history (1991 onward) with members, the union and the window over the whole history. |
| `missing_h3` anti-join (uses `forecast_grid`) | 27% | `dplyr::filter(timestamp %in% !!expected_grid$timestamp)` inlines `expected_grid$timestamp`, a vector with one entry per H3 x member x month (about 900,000 dates), as an SQL `IN` list. |
| `missing_weather` | 22% | The same `%in% !!expected_grid$timestamp` pattern. |

Fixes, in order of payoff (all behaviour-preserving, so outputs must be bit-identical per `review/optimization_guidelines.md` section 9):

1. Use `forecast_months` (six dates) in place of `expected_grid$timestamp` in both filters. This removes about half the time on its own.
2. Restrict the predictor source to `needed_months`. The window is `RANGE BETWEEN ref_end PRECEDING AND ref_start PRECEDING` over month indices, so rows outside `needed_months` never enter a target row's window. Stop cross-joining the full observed history with every member.
3. Compute `forecast_loc`, `observed_loc` and `monthly` once (`dplyr::compute()`). Run the rolling window for all members in one query (the partition already includes `member`). Collect once and split by member in R. This keeps the per-member consumer contract.
4. Fold the validation queries (duplicates, missing grid, missing values, coverage) into one or two aggregate queries over the computed tables.
5. Verify the catalogue once per run. Today the identity check runs in the UI reactive, in `step2_compute()` and again in `.get_forecast_weather()`, and each check hashes the forecast file and the ERA5-Land historical file. That takes 0.13 s on BFA, but it scales with the historical file size. Pass the verified run object through instead.
6. Reuse the climate reference and stored breaks that `get_weather()` has already built for historical weather in the same call, instead of scanning ERA5-Land from 1991 again.

Expected result: a few seconds for the weather step. Confirm with skill `wise-benchmark` (before/after time and peak memory) and add a forecast workload to `dev/bench/bench_step2.R`.

## 3. Bug: `n_forecast_members` warning

In `R/fct_sim_compare.R`, `focus` is `fut_rows[1L, ]`, a one-row tibble. The forecast branch reads `focus$n_forecast_members` in three places (`n_mods` twice, then `n_members`). The column never exists. `fct_run_simulation()` stores `n_forecast_members` on the top-level result, not on rows, so tibble warns and the code falls back to `n_models` or 1. The `n_mods` assignment is also duplicated on consecutive lines. Fix: take the count from the scenario object (`length(scenario$forecast$members)`), as `R/fct_step2_tables.R` does, or carry it as a column when `fut_rows` is built. Add a test that runs the headline builder on a forecast scenario under `expect_no_warning()`.

## 4. Charts: missing forecast content

By design the forecast is excluded from the adverse-year dot plot, the exceedance curves and the return-period and threshold tables, because a member is a target-window state, not an annual weather sample. The exclusion is correct. The presentation is the problem:

- In a forecast-only run, these sections render Historical only, with a sentence in the footnote. The user reads this as missing results.
- The uncertainty-sources chart and the diagnostics trajectory and robustness charts were built around climate-model and weather-year axes. They have partial forecast branches (`step2_variance_breakdown()` treats members as the only spread), but the axis labels and export titles still say climate models.

Recommendations:

- When the selected scenarios are forecast plus Historical only, replace each annual section with a short in-place message that says why it does not apply and where the forecast view is. Do not show a Historical-only chart under a title that implies scenario comparison.
- Give the forecast one dedicated view: member distribution of the target-window aggregate against the same-window climatology distribution (item 1). This is the forecast's adverse-outcome view: the share of members below the climatology's lower tercile or decile.
- Check every Results and Diagnostics output in the running app with forecast only, and with forecast plus one SSP (skill `wise-ui-check`). This review did not drive the browser. The chart list above comes from the code.

## 5. Architecture and consistency

- **Scenario type by label regex.** The pattern `.step2_is_forecast_scenario(x) || grepl("^(Seasonal|Subseasonal)( forecast)? / ", x)` is repeated in `fct_sim_compare.R` and `fct_sim_diag.R`. The `grepl` half is redundant, because the helper already matches those prefixes. Its variants also differ: one makes " forecast" optional. Existing SSP code also parses labels (`.normalise_ssp()`), but a scenario now has a `forecast` field. Prefer a `kind` (`historical`, `ssp`, `forecast`) on the scenario object and on derived tables, set once in `fct_run_simulation()`. Readers then test the field, not the name.
- **Duplicated weather internals.** `.get_forecast_weather()` re-implements the population-weighted H3-to-location aggregation and the rolling-window SQL. `get_weather()` has its own copies (two rolling-window builders). Fixing the performance items above is the moment to extract one shared helper for each, so the Step 1 lag semantics cannot drift between historical, SSP and forecast.
- **Forecast branching in `fct_run_simulation()`.** The forecast adds a parallel survey (`forecast_svy`, `forecast_svy_prepared`, `forecast_weather_join_cache`), member metadata reconstructed in three places (`forecast_member_info()`, the consumer wrapper, `get_weather()`'s emitter) and key rewriting (`member_<n>`) in both the manifest and direct paths. Specific defects:
  - `.step2_forecast_group(forecast)` runs twice. The first result is discarded.
  - The `weather_consumer` wrapper in the direct path has drifted indentation (mixed 7, 8 and 9 spaces).
  - `.get_forecast_weather()` is called with `weather_consumer = NULL` inside `get_weather()`, which collects all members and then re-emits them. That is harmless at BFA size, but it bypasses the streaming design.

  Prefer one place that emits forecast keys with complete metadata (the builder's own `weather_consumer` path already does this) and let `fct_run_simulation()` read it.
- **Signatures.** The forecast identity is assembled four times with different fields: `prepare_weather_manifest()` cache identity, the weather-store signature, `.step2_compute_signature()` and `.step2_forecast_group()`'s digest. One `.forecast_identity(run, start, len)` helper would keep them consistent.
- **Catalogue failure mode.** `.forecast_catalogue_runs()` calls `stop()` inside the per-run loop. One bad row, one manifest mismatch or a refreshed `BFA_era5land.parquet` (the `historical_sha256` check) therefore hides every run. The UI then shows a catalogue error. Skip and report the invalid run instead, and let the historical-identity check apply only to runs that need observed months (see section 6, item A).
- **Consistent with the architecture:** Shiny-free `fct_*` builder; errors routed through `wise_user_error()` in the module; reactable and echarts4r builders reused; forecast-off signatures unchanged; Step 3 explicitly blocked. These are good and should stay.

## 6. Upstream data and schema (`wise-app-data`)

The published files are small and clean: 907,596 rows per run (2,966 cells x 51 members x 6 leads), 1.4 MB, ZSTD, int64 H3 at resolution 6, adjusted `t`, verified checksums. Size is not the bottleneck. The gaps are about what the app needs to compute and interpret the forecast:

**A. Observed months up to initialization (high).** `observed_through` is the end of the ERA5-Land historical file (2025-12-01), 10 months before the October 2026 initialization. Consequences:

- Any fitted lag that reaches before the initialization month is blocked (for example, 1-3 lags for November and December targets).
- For the default 1-1 lag, the November predictor is the lead-1 forecast for October. An observed October will exist by the time the run is used.
- Refreshing the historical file changes its checksum and invalidates every published run (item 7).

Proposal: publish, with each run, an immutable observed-context file, `<run_id>_observed.parquet`. It holds ERA5-Land (or ERA5T for the most recent months) for `h3, timestamp, <vars>` over the months from `init - k` to `init - 1`, where `k` is at least the longest supported lag (for example 12). Record its checksum and `observed_through = init - 1 month` in the manifest. The app then builds predictor windows only from the run's own files. The forecast no longer depends on the version of the historical ERA5-Land file, which the app keeps for the climate reference and bin breaks.

**B. Hindcast comparator (low, optional).** The agreed reference (section 1) needs only ERA5-Land. A model-consistent comparator would be the adjusted hindcast ensemble for the same initialization month and leads (1993-2016, 25 members), published as `<model>_<init_month>_hindcast_adjusted.parquet`. It lets the app compare the forecast distribution with the model's own climatological distribution. This removes any residual lead-dependent drift from the comparison, and it is the comparison seasonal forecasters use.

**C. Skill table (high before any non-experimental use).** `R/forecast_evaluate.R` already computes hindcast metrics. Publish a small table per initialization month, lead and country (optionally per admin-1): correlation of anomalies, CRPSS or tercile ROC, and the number of years. The app can then grey out or flag target months with no demonstrated skill, using wording agreed in roadmap item 2.

**D. App-facing manifest versus provenance (low).** The run JSON carries about 50 `source_requests` entries, including absolute local cache paths (`C:/Users/.../wise-app-data-cache/...`). The app reads none of them. Move provenance to `<run_id>_provenance.json`, keep the app manifest to the fields `.forecast_catalogue_runs()` checks, and do not publish machine-local paths.

**E. Catalogue completeness (low).** Add `data_sha256`, `manifest_sha256`, `variables` and `observed_context_file` to `catalogue.csv` (or replace it with `catalogue.json`). The app can then list runs without opening every manifest, and hash files only for the run it uses.

**F. Row order (low).** Files are ordered by `h3, member, lead_month`. If the app keeps per-member streaming, `member, timestamp, h3` would allow row-group pruning. At 1.4 MB per run this does not matter yet.

**G. Keep H3, do not pre-aggregate to survey locations.** The H3-to-location mapping is survey-specific, and historical and CMIP6 data use the same H3 contract. Pre-aggregating upstream would break that consistency for little gain.

**H. Stale handover.** `dev/forecast_handover.md` still says the app does not read the files and does not enforce the predictor-window rule. Update it when item A is agreed.

## Status (2026-11-02)

Done on `seasonal-forecast` (tested on the synthetic draft-2 fixture, `dev/make_fixture_forecast_draft2.R`; no real draft-2 files exist yet):

- Order of work 1 to 5, 7 (skill) and the reduced step 6. The draft-2 reader skips invalid runs (item 7 and upstream A), the weather builder is bit-identical and about 100 times faster, the `int_month` and `n_forecast_members` bugs are fixed, the same-window reference and member placement drive the cards and a placement chart, and annual sections are hidden for a forecast-only run.
- Skill: the app reads the pipeline's `skill_flag` (agreed rule "balanced", `acc_detrended` and `crpss`, set upstream) and reports it per target month.
- `dev/check_forecast_data.R` checks a real data root against the reader.

Open:

- Real draft-2 files from `wise-app-data` (CDS requests need approval there), then a first review of placement and skill on real BFA data.
- Step 6 not done: a `kind` field on scenarios and tables, and shared weather helpers with `get_weather()` (protected numerics; needs parity runs on all engines).
- Step 3 still rejects policy runs with a forecast (the annual exposure contract has no target-month replication).
- `manifest.json` is regenerated only when the branch is ready for the PR into `dev` (`deploy-contract` fails until then).

## Proposed order of work

1. Performance fixes 1 to 4 in section 2, with bit-identical member frames on BFA (save the current output first) and a `wise-benchmark` before/after.
2. The `n_forecast_members` bug (section 3) and the `int_month` bug (section 1). For the second, add a separate weather-month column for the forecast weather join and keep `int_month` at its survey value. Test each: no warning; no NA forecast predictions with month fixed effects, including a target month with no interviews; any NA forecast prediction stops the run.
3. Upstream item A (observed context per run) with the matching app reader change, so `observed_through = init - 1`. Then fix item 7 (catalogue skips, not fails).
4. Same-window reference and member placement (section 1), with the forecast view that replaces the annual sections for forecast scenarios (section 4). This changes displayed contrasts, so handle it as a numeric change (skill `wise-numeric-change`, Decision log). Update `docs/34_seasonal_forecast.md`, including the seasonality conditions and the training-month coverage warning.
5. Check every Results and Diagnostics view in the running app.
6. Scenario `kind` field and shared weather helpers (section 5), as a behaviour-preserving refactor.
7. Upstream items C, D and E; then B if the hindcast comparator is wanted.
