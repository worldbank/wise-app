# Batch output tables - catalogue

Status: Phase 0, 2026-10-19. Decisions D1-D4 taken; second consolidation
round (11 result tables) proposed. Part of `review/batch_pipeline_plan.md`.
Column lists are indicative; each phase fixes the exact schema from the core
table builder it extracts.

## 1. Scope rules (decided)

- **Aggregate results only.** No observation-level results: no household
  predictions, residuals, policy-variable values per household or per-row
  transfers.
- **No maps and no map data.** H3 cells, location geometries, per-location
  map values and legends are not stored.
- **No underlying data.** Survey microdata, weather frames and Step 2/3
  payloads stay in the `targets` store as intermediates and are never
  published.
- **App-identical values.** A statistic the app shows is computed by the same
  core function the app uses, and parity tests compare them.
- **Batch-only statistics** (section 5) are allowed when requested. They are
  computed by package functions next to the app builders, with tests, and are
  marked as batch-only in the column reference.
- **Display options.** A choice that selects different results (for example
  the metric) becomes a column. A choice that only transforms stored values
  is stored at the app default and applied later with the app's own function.
- **Store at the finest app grain, derive the rest.** Where the app collapses
  an internal table into several views (weather-year bases, deciles,
  headline), the internal table is stored and the views are rebuilt with the
  app's functions.

## 2. Keys and common columns

Every table carries the key of the stage it depends on, and nothing more
specific. Labels come from joining `runs`.

| Key | Identifies | Hash of spec sections |
|---|---|---|
| `data_id` | survey sample + outcome + statistics options | source, sample, outcome, stats |
| `wxvar_id` | one weather variable construction | data_id + variable, reference period, temporal aggregation, transformation, historical years |
| `fit_id` | weather profile + model | data_id + weather (incl. binning) + model + seed |
| `sim_id` | + simulation settings | fit_id + sim |
| `policy_id` | + one policy profile; `NA` for the baseline arm | sim_id + policy |

`wxvar_id` is finer than a weather profile: two profiles that bin the same
variable differently share its descriptive statistics.

Common columns where they apply: `code` (country code, or pool label),
`wave` (survey wave label; `All` for pooled rows), `variable`, `metric`,
`scenario` (`Historical` or SSP + period), `member` (climate model id),
`sim_year`, `group` (`all`, `decile_1` ... `decile_10`, or a moderator
level).

Format: one parquet dataset per table, partitioned by `code`. Raw values, no
display rounding.

## 3. Published tables (proposed: 11)

### 3.1 Step 1 - data (Phase 1)

| # | Table | Key | Grain | Built from |
|---|---|---|---|---|
| 1 | `variable_stats` | `data_id` | code x wave (+ `All`) x var_group x variable x sample | App: `weighted_summary_long()` + `survey_missingness_long()` (the five `survey_summary_*` exports, `mod_1_02_surveystats.R:641,718`) and `outcome_summary_wide()` (`mod_1_03_outcome.R:216`). Batch-only: deciles for every variable, location samples, indicator variables (section 5). |
| 2 | `interview_dates` | `data_id` | code x wave x month, plus one wave-total row (`month = NA`) | App: `summarise_interview_dates()` (`mod_1_02:103`). Batch-only on the total row: distinct interview dates, first and last date, average distinct dates per location. |
| 3 | `weather_stats` | `wxvar_id` | code x wave x variable x source (survey, historical) x sample (all, within_loc) | App: `build_weather_stats_table()` (`mod_1_05_weatherstats.R:647`) for the survey rows; the historical comparison sample (same locations and calendar months over `hist_years`, `mod_1_05`) for the historical rows. Continuous (pre-binning) values only. Batch-only: within-location rows, distinct values per location. |

`variable_stats` columns: `n`, `n_missing`, `pct_missing`, `n_unique`,
`mean` (weighted), `unweighted_mean`, `sd`, `min`, `max`, `p10` ... `p90`,
`p25`, `p75`, `share_one` (binary variables). `sample` is `all`,
`with_loc`, `without_loc` or `within_loc` (location-demeaned values; mean and
SD only). The wave-level survey identifiers (`survname`, `source`, `year`)
are columns, which replaces the `surveys` table.

`weather_stats` columns: `n`, `pct_missing`, `n_unique`, `n_unique_per_loc`,
`mean`, `sd`, `min`, `max`, `p10` ... `p90`.

Dropped from the first draft:
- `surveys`: redundant; identifiers are columns of `variable_stats`.
- `weather_distribution` and the binned distribution table: bin counts are
  not stored. Bin edges are in the term labels of `model_terms` and in
  `provenance`; the continuous deciles describe the distribution.
- `weather_binscatter`: depends on the outcome and is a chart aid, not a
  result.

### 3.2 Step 1 - model (Phase 2)

| # | Table | Key | Grain | Built from |
|---|---|---|---|---|
| 4 | `model_terms` | `fit_id` | model (fit1-3) x term x tau | `model_coefficients` export / `make_regtable_df()` (`mod_1_07_results.R:693,717`), with the per-term fit contribution (`echart_importance()`, `mod_1_08:192`) and the lasso selection frequency (`run_lasso_selection()`, `mod_1_06_model.R:842`) as columns. RIF rows cover every tau of `rif_grid`. |
| 5 | `model_fit` | `fit_id` | model x tau x statistic | `model_fit_statistics` export + `additional_stats` (`mod_1_08_modelfit.R:227,248`), headline cards and focused table (`mod_1_07:734,839`), and the model-sample values that the effect curves need (below), as long rows with a `section` column. |
| 6 | `model_vcov` | `fit_id` | term x term (fit3) | `vcov()` of fit3 with the app's `COEF_VCOV_SPEC`, restricted to the weather terms and their interactions. Small (at most a few dozen terms). |

`weather_effects` is no longer stored. The app's effect charts are functions
of these inputs:

| Chart | Inputs (`echart_weather_effect_plot()`, `fct_results.R:1542`) | Stored in |
|---|---|---|
| Binned weather effects | bin coefficients and their CIs | `model_terms` |
| Continuous marginal effect | weather coefficients (incl. polynomial and interaction terms), their covariance, the x range of the model sample (min, max), moderator values | `model_terms`, `model_vcov`, `model_fit` (section `effect_inputs`) |
| Who is affected (moderated) | main and interaction coefficients and their covariance, moderator values (0/1, or mean and +/- 1 SD in the model sample) | `model_terms`, `model_vcov`, `model_fit` |
| RIF effect by tau | coefficients by tau; for moderated or polynomial curves, the per-tau covariance of those terms | `model_terms`, `model_vcov` (one block per tau for RIF) |
| Logistic pp effects | coefficients and the median-risk profile linear predictor (`profile_eta`) | `model_terms`, `model_fit` |

Phase 2 task: split the data step out of `echart_weather_effect_plot()`
into a pure `weather_effect_data()` that takes these inputs. The app chart
and batch post-processing then call the same function. The observed-weather
rug is observation-level and is not reproduced.

Check in Phase 2: whether the app draws effect curves for the ranger and
xgboost engines. If it does (partial dependence, for example), those curves
cannot come from coefficients, and their curve points go into `model_fit`.

### 3.3 Steps 2 and 3 - outcomes (Phases 3-4)

One set of tables serves both steps. The baseline arm has `policy_id = NA`.
Step 3 passes the Step 2 results through unchanged as its baseline arm
(`step3_baseline_arm()`), so the baseline is stored once per `sim_id` and
each policy adds only its own rows.

| # | Table | Key | Grain | Built from |
|---|---|---|---|---|
| 7 | `annual` | `sim_id`, `policy_id` | arm x scenario x member x sim_year x metric | `aggregate_pipeline_tables_multi()` via `step2_display_aggregation_suite()` (`fct_aggregation.R`), `value_all` / `value_all_sd` unnested to one row per member. Columns `value`, `sd`, `var_within`, `var_across`, `weighted`; `F_agg_all` dropped (D2). Shock-responsive programmes add their per member-year rows (`policy_shock_annual` export, `mod_3_08_diagnostics.R:767`) as metrics `shock_activated`, `shock_exposed_share`, `shock_transfer_cost`, `shock_admin_cost`, and the population weights. |
| 8 | `summary` | `sim_id`, `policy_id` | arm x scenario x metric x section x measure x group (x return period) | Views that need contrasts or coefficient gradients, at app defaults (D3): Step 2 headline (`step2_headline_df()`), thresholds and return periods (`build_threshold_table_df()`), ensemble bands (pointrange data), uncertainty sources (`echart_variance_contribution()` data), adverse support (`step2_adverse_dot_data()`), distributional incidence by baseline decile (`climate_distributional_incidence_data`, `mod_2_02_results.R:2247`); Step 3 headline (`step3_headline_df()`), threshold table, adverse support (`step3_adverse_dot_data()`), paired effects (`paired_effect_summary()`). Columns `estimate`, `lo`, `hi`. |
| 9 | `sim_weather` | `sim_id` | scenario x member x variable x statistic | `simulation_weather_support_summary` export (`mod_2_03_diagnostics.R:481`) and the CMIP6 member list with periods. |
| 10 | `decomposition` | `policy_id` | source x scenario x member x sim_year x group x channel (x metric) | The app's internal per-year tables: the compact decomposition (`channel_summary`, `decile_summary`: sums and weights of each channel by scenario, member, year and baseline decile; `fct_policy_metric_decompose.R:400-470`) and the metric-aware decomposition (`annual`, `decile_annual` of `.policy_metric_decomposition()`). Columns: channel sums and weights, so every average is exact. |
| 11 | `policy_measures` | `policy_id` | section x measure x group (x scenario) | Small measure/value tables: transfer summary (`mod_3_08:521`), SP effectiveness (`mod_3_08:609`), reach (`policy_reach_summary()`), components (`.policy_component_table_raw()`), treatment matrix (`policy_treatment_matrix()`; row and column labels in `group`), input diagnostics (`policy_input_diagnostics()`; before and after means per lever variable), cost-effectiveness (`ce_table`, `ce_climate`, `ce_reach`, `mod_3_10_cost_effectiveness.R:295,395,497`). |

### 3.4 Run-level tables (all phases)

| Table | Contents |
|---|---|
| `runs` | One row per leaf run: all stage ids, profile labels, the flattened spec (weather specification, policy lever settings). |
| `specs/<run_id>.json` | Full normalised spec per run. |
| `provenance` | `wise_provenance()` record per stage id (data source digest, model signature, bin edges, timings). |
| `failures` | Stage, stage id, affected run ids, error class, message. |
| `manifest.json` | wiseapp version and git SHA, R and duckdb versions, `renv.lock` hash, schema version, start and end times. |

### 3.5 Derived later, not stored

Each is rebuilt by an app function from published tables. "Verify" marks a
claim to confirm when the phase extracts the function.

| App output | Rebuilt from | App function |
|---|---|---|
| Weather effect charts (`mod_1_07:920,936`) | `model_terms`, `model_vcov`, `model_fit` | `weather_effect_data()` (Phase 2 split of `echart_weather_effect_plot()`) |
| RIF weather curve (`mod_3_09_decomposition.R:749`) | `model_terms` | `echart_rif_weather_curve()` |
| Coefficient-stability chart, model specification table | `model_terms`, `runs` | coefficient plot builder, `make_regtable_specs_reactable()` |
| Exceedance curves, annual distribution, model robustness | `annual` | exceedance builder; `model_robustness_data()` (`fct_sim_compare.R:1466`). Verify: exceedance reads only `value_all` and `value_all_sd`. |
| Decomposition headline and by decile, all 4 weather-year bases (`mod_3_09:520,636`) | `decomposition` | `.compact_future_decomp()`, `.compact_future_decile_summary()` |
| Step 3 incidence by decile | `decomposition` | `step3_incidence_by_decile()` (`fct_incidence.R:176`) |
| Metric decomposition summaries and tails | `decomposition` (metric rows) | `.policy_metric_summary()`, `.policy_metric_tails()`. Verify: no coefficient gradients needed. |
| Shock summary (activation frequency, cost distribution, basis risk, leakage) and shock charts | `annual` (shock metrics) | `sp_shock_summary()`, `echart_shock_*`. Verify: needs only the per member-year rows and spec values. |
| Decomposition in % of baseline | `decomposition` | module's relative-units step |
| Bands at other quantiles; deviation from mean or median year | `annual` | `resolve_band_q()`, `deviation_from_centre()`; only for views without contrasts (D2) |

### 3.6 Excluded

| App output | Reason |
|---|---|
| Survey density map, outcome coverage map, weather maps, location coverage | maps |
| Outcome distribution chart, continuous weather density, simulated weather input distribution | computed from microdata (D1) |
| Weather bin counts and binscatter | consolidation (3.1) |
| Residuals vs weather, predicted vs actual, residual panels (`mod_1_08`) | observation level |
| Before/after histograms of policy variables (`mod_3_08:1173`) | observation level; means are in `policy_measures` |

## 4. Decisions

**D1 - Distributions computed from microdata: Exclude** (decided).

**D2 - Coefficient gradients: drop** (decided). `value_all` holds the
per-member values of each year, so unnesting it gives the member rows of
`annual` at no extra cost. The column dropped is `F_agg_all`, the per-year
gradient that the delta method uses for contrasts between scenarios or arms.
Views that need a contrast with coefficient uncertainty are stored in
`summary` at the app defaults.

**D3 - Display options** (decided). Every metric is stored. Deviation and
band are stored at the app defaults (`none`, `p10_p90`). The poverty line
comes from the spec; extra lines are a spec axis.

**D4 - Decomposition** (decided, refined). All four weather-year bases and
both unit choices are derived from the per-year `decomposition` table (3.5),
so no basis or unit is fixed at write time.

**D5 - Decomposition by year** (answered). The app does not show or export
it, but computes it: the compact decomposition holds channel sums and weights
per scenario, member, year and baseline decile, and the metric decomposition
returns `annual` and `decile_annual`. These are app-identical aggregates, not
observations. Storing them gives the legacy `decile_decomposition_by_year`
output and lets every app view be derived (D4).

## 5. Batch-only statistics (requested)

Carried over from the legacy scripts. Computed by package functions in the
same file as the app builder they extend, and tested against the legacy
definitions on a fixture.

| Statistic | Table | Definition (legacy source) |
|---|---|---|
| Location samples `with_loc`, `without_loc` | `variable_stats` (`sample`) | rows with `loc_id` and `area_h3_7` present, or either missing (`batch/legacy/R/batch_utils.R`, `weighted_survey_stats()`) |
| Location-demeaned `within_loc` | `variable_stats`, `weather_stats` (`sample`) | `with_loc` rows, values demeaned within `loc_id` (weighted); mean and SD |
| `n_unique_per_loc` | `weather_stats` | mean number of distinct values per `loc_id` |
| Interview-date summary | `interview_dates` (total row) | distinct dates, first and last date, average distinct dates per `loc_id` |
| Indicator variables | `variable_stats` (`var_group = indicator`) | binary variables defined in the spec, with the same statistics; mean = share. Default set: `poor300`, `poor420`, `poor830` (`welfare` below 3.00, 4.20, 8.30) and `ttime_health_gt15/30/45/60` (legacy `01b_policy_var_percentiles.R` thresholds) |
| Deciles and quartiles for every variable | `variable_stats` | weighted `p10` ... `p90`, `p25`, `p75`, with the weighted quantile rule of `outcome_summary_wide()`, so the outcome rows equal the app's deciles |

Spec options: `stats.indicators` (name -> variable, operator, threshold) and
`stats.location_samples` (default `true`).

## 6. Comparison with the legacy outputs

| Legacy output | New equivalent |
|---|---|
| `survey_stats.csv` (01), `policy_percentiles.csv` (01b) | `variable_stats` + `interview_dates` (all legacy columns carried, section 5) |
| `weather_stats.csv` (02) | `weather_stats` (survey and historical sources; within-location rows) |
| `model_coefficients`, `model_fit_stats` (03) | `model_terms`, `model_fit` (+ `model_vcov`) |
| `_interactions_not_available.csv` | `failures` with error class `interaction_unavailable` |
| `simulations/outcomes.parquet` (04) | `annual` (same design: one long table, baseline and policy rows together) |
| `return_periods.csv` | `summary` (threshold and return-period rows) |
| `weather_quantiles.csv`, `sim_metadata.csv` | `sim_weather` |
| `decile_decomposition_by_year.parquet` | `decomposition` (D5) |
| `policy_config.csv` | `runs` + `specs/` |
| Spec-curve and model-selection scripts (02a, 03a) | Post-processing on `model_terms` / `model_fit` (Phase 5) |

## 7. Size estimate (per fit, BFA scale, to verify in Phase 3)

`annual`: about 4 scenarios x 10 members x 30 years x 9 metrics, roughly 11k
rows per arm. `decomposition`: about 4 x 10 x 30 x 11 groups, roughly 13k
rows per policy (channels as columns). `summary`: hundreds of rows. Step 1
tables: low thousands of rows per `data_id`. A grid of 1,000 runs stays
around 100 MB of parquet.
