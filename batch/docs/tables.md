# Batch output tables - column reference

All tables of a batch run: 11 result tables and the run-level files. The user
guide is `batch/README.md`; the design is `review/batch_pipeline_plan.md`.

## Conventions

- One parquet dataset per table in `results/tables/<table>/`, partitioned by
  `code`. Read with `arrow::open_dataset()`.
- Values are raw (never rounded). Rows with no value hold `NA`.
- Aggregates only: no household-level results, maps or microdata.
- Each table carries the id of the stage it depends on (below). Join to
  `results/runs.parquet` on that id for the settings and axis labels of the runs
  that use it. Runs that share a stage share its rows.
- A column marked **app** holds the value the app shows, computed by the app's
  own function and checked by parity tests. **batch** marks a statistic that
  only batch computes.
- Common columns: `code` (country code; sorted codes joined by `+` for a pooled
  two-economy sample), `scenario` (`Historical`, or `SSP3-7.0 / 2025-2035`),
  `metric`, `member` (climate model, or `Historical`), `sim_year` (the weather
  year the aggregate draws on, not a projection calendar year), `group` (`all`,
  `decile_1` ... `decile_10`).

## Stage ids

12 hex characters, each a hash of the spec sections the stage depends on.

| Id | Hash of | Keys the tables |
|---|---|---|
| `data_id` | source, sample, outcome, statistics options | `variable_stats`, `interview_dates` |
| `wxvar_id` | `data_id`, one weather variable's reference period, temporal aggregation, transformation, and the historical years (not the binning) | `weather_stats` |
| `weather_id` | `data_id`, the whole weather section (the seed only for K-means bins) | the survey-weather frame (not published) |
| `fit_id` | `data_id`, weather section, model section, seed | `model_terms`, `model_fit`, `model_vcov` |
| `sim_id` | `fit_id`, the simulation settings that change results | `annual`, `summary`, `sim_weather` (baseline arm) |
| `policy_id` | `sim_id`, the policy section; `NA` is the baseline arm | policy arm of `annual` and `summary`; `decomposition`, `policy_measures` |
| `run_id` | the whole spec, seed included | `runs` |

## Step 1: survey and weather data

### variable_stats

Key `data_id`. One row per scope (wave, `All`, pooled) x `var_group` x
`variable` x `sample`. Builders: `variable_stats_table()` (`R/fct_step1_tables.R`).

| Column | Meaning | Source |
|---|---|---|
| `wave` | Survey year as text (waves of one country and year are merged). `All` pools every wave of the country, or of both countries with `code` `A+B`. | app |
| `year`, `survname` | Year of the wave (`NA` for `All`); survey name(s), joined by `+`. | app |
| `var_group` | `outcome`, `policy` (variables the Step 3 levers act on), `ind`, `hh`, `firm`, `area` or `indicator`. A variable in two groups has a row in each. | batch |
| `variable` | Variable name. | |
| `sample` | `all`; `with_loc` (records with `loc_id` and, if present, `area_h3_7`); `without_loc`; `within_loc` (values minus the location mean over all waves; `n`, `mean`, `sd` only). | `all`: app; others: batch |
| `n` | Records with a finite value and a finite positive weight. | app |
| `n_rows`, `n_missing`, `n_unique` | Records in the scope and sample; records missing the variable; distinct non-missing values. | batch |
| `pct_missing` | `100 * n_missing / n_rows`. | app |
| `mean`, `unweighted_mean`, `sd`, `min`, `max` | Weighted mean (share of ones for a 0/1 variable), plain mean, weighted standard deviation, smallest and largest valid value. | app |
| `p10` ... `p90`, `p25`, `p75` | Weighted quantiles (`collapse::fquantile`, type 7). For the outcome the deciles equal the app's outcome summary. | batch |
| `share_one` | Weighted share of ones for a variable that is only 0 or 1; else `NA`. | batch |

Indicators (`var_group = indicator`) are 0/1 variables from `stats.indicators`
(variable, operator `<` or `>`, threshold). Default: `poor300`, `poor420`,
`poor830` (`welfare` below 3.00, 4.20, 8.30) and `ttime_health_gt15`, `_gt30`,
`_gt45`, `_gt60`. An indicator whose variable is not in the data is skipped.
`stats.location_samples: false` leaves only `sample = all`.

### interview_dates

Key `data_id`. One row per wave x interview month, plus one total row per wave
(`month` is `NA`).

| Column | Meaning | Source |
|---|---|---|
| `month` | Interview month, 1 to 12; `NA` on the total row. | app |
| `n` | Records interviewed in the month; on the total row, records with an interview date. | app |
| `n_dates`, `first_date`, `last_date`, `avg_dates_per_loc` | Total row only: distinct dates, earliest and latest date, mean distinct dates per location. | batch |

### weather_stats

Key `wxvar_id`. One row per wave (and `All`) x weather variable x `source` x
`sample`. Values are continuous (after aggregation and transformation, before
binning).

| Column | Meaning | Source |
|---|---|---|
| `variable` | Weather variable. | |
| `source` | `survey`: weather the sample was exposed to. `historical`: the same locations and calendar months over `weather.hist_years`, one value per location-month, weighted by households. | survey: app; historical: batch |
| `sample` | `all` or `within_loc` (`n`, `mean`, `sd` only). | `within_loc`: batch |
| `n` | Survey: records with a finite value and a positive weight. Historical: valid location-month cells. | app |
| `pct_missing` | Survey records without a value after the weather merge; `NA` for historical. | app |
| `n_unique`, `n_unique_per_loc` | Distinct values; mean distinct values per location. | batch |
| `unweighted_mean`, `mean`, `sd`, `min`, `max`, `p10` ... `p90`, `p25`, `p75` | As in `variable_stats`. | survey: app; others: batch |

Notes: records with an invalid weight count in `n_rows` and `pct_missing` but
not in weighted statistics; rows with `n = 0` are kept (the app hides them); a
location is a country and `loc_id`, shared by all waves.

## Step 1: model

Key `fit_id`. A fit is the app's "Run model" for the run's sample, outcome and
weather: three nested specifications on the same observations (`model` 1
weather only; 2 plus fixed effects; 3 plus fixed effects and covariates, the
one Steps 2 and 3 use). Linear and logistic models use fixest; the RIF model
fits the nine quantiles `tau` 0.1 to 0.9. Standard errors are clustered at the
location panel when the H3 files are in the data folder, else fixest's default
applies (recorded in `model_fit`). Fits are unweighted. Builders:
`R/fct_step1_model_tables.R`.

### model_terms

One row per `model` x term (x `tau` for RIF).

| Column | Meaning | Source |
|---|---|---|
| `model` | 1, 2 or 3. | app |
| `term` | Coefficient name as fixest reports it (`tx`, `I(I(tx^2))`, `tx(24, 27.4]`, `tx:urban`, `(Intercept)`). Fixed effects are absorbed. | app |
| `tau` | Quantile (RIF); else `NA`. | app |
| `is_weather` | Term involves a weather variable (main, bin, polynomial, interaction). | batch |
| `estimate`, `std_error`, `statistic`, `p_value` | Coefficient, standard error, t or z statistic, p-value, on the model scale. | app |
| `conf_low`, `conf_high` | 95% interval: estimate +/- 1.96 x SE (RIF: `broom::tidy()`). | app |
| `n_obs` | Observations of the specification (of the quantile's fit for RIF). | app |
| `importance_share` | Percent of the sum of squared standardised coefficients; model 3 only (RIF: median quantile). | app |
| `lasso_freq` | Lasso selection frequency; model 3 with Lasso covariates only. | app |
| `translation` | The At a glance translation of a weather term (for example `+2.9%` per +1 SD, or a bin contrast); model 3 (RIF: `tau` 0.5). | app |

### model_fit

Long form: `section`, `variable`, `model`, `tau`, `statistic`, `value` (number),
`text`, `detail` (text rows).

| `section` | `statistic` | Meaning |
|---|---|---|
| `fit` | `nobs`, `r2`, `ar2`, `wr2` (RIF per `tau`: `nobs`, `r2`, `wr2`); `nobs`, `pr2`, `aic` (binary outcome) | Goodness of fit per specification. `wr2` is `NA` without fixed effects. App (raw). |
| `sample` | `n_estimation` | Rows of the estimation sample. |
| `spec` | `engine`, `model_family`, `requested_type`, `vcov`, `fixed_effects`, `covariate_selection`, `location_panel` (`text`) | What was fitted. `vcov` is `clustered: loc_id_panel` or `default (IID)`; `location_panel` is `joined` or `unavailable: <reason>`. |
| `spec` | `fallback_model_family`, `fallback_vcv` (`text` = `requested -> used`, `detail` = reason) | A fallback the fitter applied; present only when it happened. |
| `effect_inputs` | `x_min`, `x_max`, `x_mean`, `x_sd` per continuous weather variable; `profile_eta` (binary outcomes); per moderator `mod_min`, `mod_max`, `mod_mean`, `mod_sd`, `mod_n_distinct` (numeric or binary) or `mod_n_distinct` and `mod_levels` (`text`, categorical) | What the effect charts need besides coefficients and `model_vcov`. Binned variables have no `x_` rows. |
| `headline` | The card label (`Effect of Max temperature`, `Spec robustness`, ...) | The At a glance cards: `text` the value, `detail` the note. App. |

### model_vcov

Variance-covariance matrix of model 3, restricted to the weather terms, as a long
full matrix (both triangles); one block per quantile for RIF. Columns: `tau`,
`term_1`, `term_2`, `covariance` (under the fit's variance estimator; the
diagonal is `std_error^2`). With `model_terms` and the `effect_inputs` rows it
rebuilds the app's effect charts. The observed-weather rug is not stored.

## Step 2: simulation

Key `sim_id`. The app's "Run simulation": the baseline survey (default the
latest wave of each economy) is predicted under every historical weather year
(`sim.hist_years`) and, for each projection period and SSP, under the same years
perturbed by each CMIP6 climate model (additive for temperature, multiplicative
for rain and days). The poverty line is the outcome's own (3.00 a day if none).
Builders: `R/fct_step2_tables.R`. Step 3 reuses these tables for the policy arm;
`policy_id` is `NA` for the baseline arm.

### annual

One row per `scenario` x `metric` x `member` x `sim_year` (x `policy_id`).
`metric` is `mean`, `median`, `total`, `headcount_ratio`, `gap`, `fgt2`,
`gini`, and for a welfare outcome `prosperity_gap`, `avg_poverty` (a binary
outcome has `mean` only). Every view that needs no contrast between scenarios
(exceedance curves, distributions, trajectories, other bands) is a function of
this table.

| Column | Meaning |
|---|---|
| `policy_id` | `NA` for the baseline arm. |
| `member` | Climate model as named in the projection files (`model_<n>` if none), or `Historical`. |
| `value` | The member's annual aggregate in outcome units (back-transformed for log outcomes). |
| `sd` | Delta-method standard deviation: coefficient uncertainty plus residual variance (residual only with `sim.coef_uncertainty: false`). |
| `var_within`, `var_across` | Variance of the year's aggregate within a member and across members; repeated on each member row; `var_across` is 0 for the historical run. |
| `weighted` | The aggregate uses survey weights. |

The equal-model mean of a year is the mean of `value` over its member rows.
Per-year coefficient gradients are not stored; views that need a contrast with
coefficient uncertainty are in `summary`.

**Policy arm.** Same columns for the policy pipelines; the effect of a policy on
a member-year is the policy `value` minus the baseline `value`. For a
shock-responsive program the table also holds per member-year rows as metrics
`shock_<column>` (with `sd`, `var_within`, `var_across`, `weighted` `NA`):
`shock_activated` (1 if any household is paid), `shock_exposed_share`,
`shock_transfer_cost`, `shock_admin_cost`, `shock_total_cost`,
`shock_pop_tp`, `_fp`, `_fn`, `_tn` (population weight of locations paid or not
against a loss event, `policy.sp.loss_event_pct`), `shock_spend_total`,
`shock_spend_no_event`, `shock_loss_value`, `shock_paid_value`.

### summary

Long form at the app defaults: outcome level, coefficient band p10-p90, ensemble
band p10-p90 across climate models. Columns: `policy_id`, `scenario`, `metric`
(`NA` for `incidence`), `section`, `measure`, `group`, `return_period` (`1:5`,
`1:10`, `1:20`, `1:50`; `1:1` the median year, `4:5` ... `49:50` the favourable
tail), `estimate`, `lo`, `hi`, `n`, `text` (the app's displayed text).

| `section` | `measure` / `group` | Meaning |
|---|---|---|
| `expected` | `expected` / `interannual`, `intermodel` | Equal-model mean (`estimate`) with the range of weather years within models (`lo`, `hi`, averaged across models) or of the model means. `n` = climate models. |
| `adverse_year` | `adverse_year_outcome` / `coefficient`, `ensemble`, `pooled` | Outcome in an adverse year of the `return_period`; `lo`, `hi` the coefficient, ensemble and pooled bands. The historical run has the coefficient band only. `n` = weather years. |
| `adverse_dot` | `Expected`, `Adverse 1-in-5` ... `1-in-50` / `ensemble` | Values behind the adverse-year dot plot, only the decision return periods the record supports. |
| `uncertainty` | `var_coef`, `var_within`, `var_across` | Variance components (coefficient including residual; weather year within models; between models). |
| `headline` | `Expected change`, `Adverse weather years`, `Signal vs noise`, `Year-to-year range`, `Simulation years` / `historical`, `focus`, `difference`, `range`, `count` | Headline cards for the focus scenario (the first future scenario, else historical). `text` holds the displayed value on the `focus` row. |
| `incidence` | `household_effect` / `decile_1` ... `decile_10` | Mean effect of the scenario on each fixed baseline decile, in outcome units; `n` = households. |

**Policy arm** sections start with `policy_`; stored for every metric:

| `section` | `measure` / `group` | Meaning |
|---|---|---|
| `policy_expected` | `effect` / `intermodel`, `coefficient`, `interannual`, `range` | Expected effect (policy minus baseline, equal-model mean on matched support) with the p10-p90 band of the model means, of the paired coefficient uncertainty, of weather years within models, or the full range of the model means. |
| `policy_expected` | `baseline`, `policy` / `level` | Matched endpoint levels. |
| `policy_adverse` | `Adverse 1-in-5` ... `1-in-50` / `effect`, `baseline`, `policy` | Baseline-anchored adverse-year values; `return_period` = years; `text` = reason when unavailable. |
| `policy_threshold` | `Single historical estimate`, `Equal-model mean`, `Coef P10/P90`, `Ensemble P10/P90`, `Pooled P10/P90` / `Baseline`, `Policy` | Return-period table for both arms with the bands. |
| `policy_adverse_dot` | `Expected`, `Adverse 1-in-5` ... / `baseline`, `policy`, `effect` | Dot-plot values for both arms and their difference. |
| `policy_headline` | card label / `card_<k>_value`, `card_<k>_note` | Headline cards; on `card_1_value`, `lo`, `hi` are the 95% interval of the effect. |
| `policy_incidence` | `household_effect` / `decile_1` ... `decile_10` | Mean policy effect per baseline decile for the weather-year basis in `return_period` (`mean`, `adverse_5`, `adverse_10`, `adverse_20`); `metric` `NA`. |

### sim_weather

Key `sim_id`. Long form: `scenario` (projection scenarios; the historical run is
the reference), `section`, `member`, `variable`, `statistic`, `value`, `text`.

| `section` | `statistic` | Meaning |
|---|---|---|
| `scenario` | `period_start`, `period_end`; `n_models`, `n_models_requested` | The projection period; models that ran and models requested (they differ when a model lacks coverage; see `failures.parquet`). |
| `members` | `member` | One row per climate-model member (`value` = 1). |
| `support` | `n_reference`, `n_scenario`, `robust_lo`, `robust_hi`, `outside_n`, `outside_share`, `warning`, `n_members`, `max_member_share`; `reference_label`, `warning_rule`, `is_binned` (`text`) | The weather-support summary of the Diagnostics tab per variable: historical and simulated value counts, the 1%-99% historical support, simulated values outside it (or in a bin the history never had), and `warning` = 1 when more than 5% are outside (the model extrapolates). |

## Step 3: policy

Keys `sim_id` and `policy_id`. The app's Step 3 "Run simulation": the lever
settings change the covariates (or add a cash transfer) of the Step 2 baseline
survey, and the policy effect is added to the stored baseline predictions of
every member and weather year (the analytic correction of
`apply_policy_delta_to_baseline()`). The baseline arm is the Step 2 result
unchanged. A shock-responsive transfer is paid per prediction row from the
trigger on the historical thresholds. The seed is the spec's seed, under R's
default random number generator. A binary outcome or logistic model has no
policy contrast (the app shows "unavailable"): such a run writes no policy rows
and is listed in `failures.parquet` as `partial_policy_failure`. Builders:
`R/fct_step3_tables.R`.

### decomposition

Long form, one row per `source` x `scenario` x `member` x `sim_year` x `group`
x `channel`. Every average of the Decomposition tab (all weather-year bases, in
absolute units or percent of baseline) is rebuilt from it with the app's
functions.

| Column | Meaning |
|---|---|
| `source` | `compact` (channel sums of the run) or `metric` (one metric-aware decomposition per metric). |
| `metric` | Metric of a `metric` row; `NA` for `compact`. |
| `group` | `all` or `decile_1` ... `decile_10` (fixed baseline welfare deciles, 1 the poorest). |
| `channel` | `compact`: `delta_total`, `delta_main`, `delta_sp`, `delta_main_covar`, `delta_res`, `delta_res1`, `delta_res2`, `delta_sp_shock` (log-scale effects); `baseline_y_point`, `baseline_level`; `lvl_main`, `lvl_res1`, `lvl_res2`, `lvl_total`, `lvl_sp_shock` (effects in outcome units). `metric`: states `baseline`, `after_static_main`, `after_main`, `after_repositioning`, `policy` and contributions `main`, `sp_shock`, `repositioning`, `interaction`, `resilience`, `total`, in the metric's units. |
| `value` | `compact`: `sum / weight` (`NA` when the weight is 0); `metric`: the metric value. |
| `sum`, `weight` | Weighted sum and weight behind a `compact` value; `NA` for `metric`. Averages over years or members are weighted averages of these. |
| `n_units` | `compact` decile rows: weighted population of the decile. `metric` rows: retained prediction rows. |

Direct effect is `main`; `resilience` is `repositioning` plus `interaction`;
`sp_shock` is the shock-responsive transfer. `main + sp_shock + repositioning +
interaction = total = policy - baseline`.

### policy_measures

Long form: `section`, `scenario`, `metric` (where the section has them),
`measure` (a column of the app's table), `group` (the app's row label), `value`,
`text` (a note or status).

| `section` | Contents |
|---|---|
| `transfer` | Annual cost of the cash transfer over the represented recipients (administration and total when an administration share is set) and the annual transfer per recipient. Shock program: annual means over the historical years. |
| `sp_effectiveness` | Annual cost per person, administration share, realised inclusion and exclusion error, coverage of the poor, leakage to the non-poor, adequacy for poor recipients. `group` = `money` or `percent`. A shock program describes a year in which every eligible household is paid. |
| `transfer_amount` | Only when the cash transfer amount is set from a welfare percentile (`transfer_amount_mode: pctile`): `percentile`, `daily_value` (baseline daily welfare at the percentile), `per_payment`, `per_year`, `n_obs`; `text` = the currency (`PPP` or `LCU`). |
| `reach` | Population reached by any lever: `share`, `people`, `households`. |
| `components` | One row per lever touched: units affected, population, share, realised cost, households. `group` = the component. |
| `treatment` | Eligibility-by-treatment matrix of the cash transfer: units, population, share and households per coverage status. |
| `input_diagnostics` | Before and after summary of each covariate the policy changed (units changed, baseline and policy mean and spread). `group` = the variable. |
| `cost_effectiveness` | Cash-transfer cost-effectiveness per `metric`, `scenario` and basis (`Average year` or `1-in-20 year`): `cost`, `amount` (net people lifted or annual value of the change), `value` (the ratio), `lo`, `hi` (95% interval of the average year), `poverty_line`, `admin_share`; `text` = `ok`, `not_applicable` or `unavailable`. Only when a cash transfer with spending is configured. |
| `shock_summary` | Shock programs, by scenario: member-years, activation frequency, mean, median and 95th percentile annual cost, transfer and administration cost, false-positive and false-negative rate of the trigger, leakage share, cost variation, share of modelled loss offset, share of years the cap binds, and for an anticipatory design the false-alarm cost share and break-even multipliers. Scored with `policy.sp.loss_event_pct`. |
| `shock_climate_cost` | The program's bill per scenario against history: activation frequency, mean and 95th percentile cost, change from the historical run. |
| `shock_affected_poor` | Coverage (share of loss-event household-years of the baseline poor in which the household was paid) and adequacy (payments as a share of modelled loss) at the outcome's poverty line (else 3.00). |

## Run-level files

| File | Contents |
|---|---|
| `runs.parquet` | One row per run: `run_id`, the stage ids (`wxvar_ids` is a list), axis labels (`axis_<name>`), the flattened spec, `spec_json`. |
| `specs/<run_id>.json` | Full normalised spec of each run; read with `wise_spec_read()`. |
| `provenance.parquet` | One row per finished stage: `stage`, `id`, `n_rows`, `n_surveys`, `source_type`, `source_origin`, `source_files` (names and sizes), `location_panel`, `n_no_panel`, `n_scenarios`, `n_failed_keys`, `r_peak_mb`, `seconds`, `wiseapp_version`, `completed_at` (columns a stage does not have are `NA`). |
| `failures.parquet` | `stage`, `id`, `run_ids` (comma-separated), `n_runs`, `error_class`, `message`. Empty when everything ran. Partial results have `error_class` `partial_simulation_failure` or `partial_policy_failure`. |
| `manifest.json` | `schema_version`, `wiseapp_version`, `wiseapp_git_sha`, `r_version`, `duckdb_version`, `renv_lock_sha256`, `data_source`, `data_files` (SHA-256 of the survey files, local data), `started_at`, `finished_at`, counts, `tables`. Values that could not be recorded are `null`. |

## Not stored

Household-level frames and residuals, maps and map data, survey and weather
densities, bin counts and binscatter, weather input distributions, per-year
coefficient gradients, before/after histograms of policy variables, charts. App
views that need only stored rows (effect charts, exceedance curves, decomposition
views, shock summaries) are rebuilt from the tables with the app's functions.

## Size

Per fit at BFA scale: `annual` about 5,700 rows per arm (one SSP and period, 20
climate models, 30 weather years, 9 metrics), `summary` hundreds, `sim_weather`
about 50, `decomposition` about 13,000 per policy, Step 1 tables low thousands.
A grid of 1,000 runs stays around 100 MB of parquet.
