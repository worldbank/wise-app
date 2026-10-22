# Batch run spec - map from app inputs to spec fields

For developers. Each user-facing app input is either a **spec** field (it
changes results), a **display** choice (a table column or later
post-processing) or **UI** only (not carried). The spec fields and defaults for
users are in `batch/README.md`; the defaults live in `R/fct_spec_defaults.R` and
the app's controls read their initial values from there. A configuration
exported from the app names inputs `<step>-<module>-<input>`
(`wise_spec_from_config()` reads them). Design: `review/batch_pipeline_plan.md`.

The glue that both a module and batch call is Shiny-free and lives in `R/fct_*`;
the module-to-core pairs are listed under each step.

## 1. Step 0 - source

Connection type and location (`mod_0_overview`) map to `source.type`. Credentials
never enter a spec: they come from the environment variables the app uses, and
the local folder from `WISEAPP_DATA_PATH`. `wise_batch_connection()` builds the
connection from the type.

## 2. Step 1 - sample, outcome, weather

| Input (`mod_1_0x`) | Spec field | Default |
|---|---|---|
| `unit` | `sample.unit` | `hh` |
| `economy` | `sample.countries` | `BFA` if available, else the first |
| `year_<code>` | `sample.years.<code>` | all available years |
| `outcome` | `outcome.name` | first outcome of the filtered variable list |
| `currency` | `outcome.currency` | `PPP` |
| `poverty_line` | `outcome.poverty_line` | 3.00 PPP; `default_lcu_poverty_line()` for LCU (outcome `poor`). Any other monetary outcome: the line of the Step 2 poverty metrics (`wise_outcome_run_line()`), in `sim_id`, not in `data_id` or `fit_id` |
| `weather_variable_selector` | the names of the `weather.<var>` entries (at most 2) | first weather variable |
| `<var>_relativePeriod` | `weather.<var>.ref_period` | `[1, 1]` |
| `<var>_temporalAgg` | `weather.<var>.temporal_agg` | Sum for mm and days, else Mean |
| `<var>_varConstruction` | `weather.<var>.transformation` | `None` (anomaly for dimensionless) |
| `<var>_contOrBinned` | `weather.<var>.form` | `Binned` |
| `<var>_numBins`, `_binningMethod`, `_customBreaks` | `n_bins`, `binning_method`, `custom_breaks` | 5, `Equal frequency`, none |
| `<var>_polynomial` | `weather.<var>.polynomial` | none |
| `hist_years` | `weather.hist_years` | `[1991, 2020]` |

Display or UI only: the map and button inputs, `summary_wave`, `cov_view`,
`cov_wave`. Batch-only statistics options (no app input): `stats.indicators`,
`stats.location_samples` (see `tables.md`).

- `form` accepts `Binned` or `Continuous` in any case. Fields that do not apply
  are dropped (`n_bins`, `binning_method`, `custom_breaks` for continuous;
  `polynomial` for binned), so equal specs hash equal.
- A field left out follows a data rule: default economy, every year, first
  outcome, first weather variable, unit-dependent aggregation and
  transformation. `wise_spec_resolve()` resolves them when the grid is read, so
  the stage ids encode the resolved values.

Glue (`R/fct_step1_data.R`): `wise_select_surveys()`, `load_survey_frame()`,
`prepare_survey_data()`, `wise_selected_outcome()`, `wise_outcome_data()`,
`wise_selected_weather()`, `wise_load_weather()`, `wise_load_location_panel()`.
The table builders are `variable_stats_table()`, `interview_dates_table()` and
`weather_stats_table()` (`R/fct_step1_tables.R`).

## 3. Step 1 - model (`mod_1_06`)

| Input | Spec field | Default |
|---|---|---|
| `model_type` | `model.type` (`linear`, `logistic`, `rif`; the engine follows) | first type offered for the outcome |
| `fixedeffects` | `model.fixed_effects` | `year`, `gaul1_code` where valid |
| `interactions` | `model.interactions` | none (the app starts at `urban`) |
| `selected_policies` | `model.policy_vars` (lever codes such as `electricity`, earlier keys `A` to `M`, or labels; at most one) | none |
| `covariates`, `indcov`, `hhcov`, `areacov`, `firmcov` | `model.covariates.method` (`user`, `lasso`), `.vars` (flat list) | `user`, none |
| `lasso_alpha`, `lasso_interactions` (the lambda rule), `lasso_nfolds`, `lasso_standardize`, `use_mice`, `mi_m`, `mi_maxit`, `stability_threshold` | `model.covariates.lasso.*` | `wise_default_lasso()` |
| `force_in_<level>`, `force_out_<level>` | `model.covariates.lasso.force_in`, `.force_out` (flat) | none |

`rif_tau` is a display choice (RIF quantiles are 0.1 to 0.9). No `model`
section means nothing is fitted. Sets are sorted, so equal sets are one fit.

Glue: `wise_valid_vars()`, Lasso helpers, `wise_selected_model()`,
`wise_model_from_spec()`, `wise_fit()` (`R/fct_step1_model.R`); effect
translations and the table builders `model_terms_table()`, `model_fit_table()`,
`model_vcov_table()` (`R/fct_step1_model_tables.R`); `fit_stats_raw()` and
`importance_shares()` (`R/fct_results.R`).

## 4. Step 2 - simulation (`mod_2_01_weathersim`)

| Input | Spec field | Default |
|---|---|---|
| `baseline_survey` | `sim.baseline_survey` (`CODE\|YEAR`) | latest wave of each economy |
| `hist_years` | `sim.hist_years` | `[1991, 2020]` |
| `fut_period_1..3` | `sim.future_periods` (at most 3) | `[[2025, 2035]]` |
| `climate` | `sim.ssps` | `ssp3_7_0` |
| `residuals` | `sim.residuals` (`none` is forced for RIF) | `original` |
| `include_coef_uncertainty` | `sim.coef_uncertainty` | true |
| `propagate_all_covariate_uncertainty` | same name | false |

Results and Diagnostics controls (`cmp_*`, `ensemble_band`, `pov_line`,
`diag_weather_*`) are display choices: `metric` is a table column, the rest are
stored at the app defaults.

- `sim` needs a `model` section.
- A period that is incomplete, empty or starts before 2015 is an error in the
  spec (a configuration import drops it, as the app does).
- The residual rule (RIF) and the scenarios (no projection period) do not enter
  `sim_id` when they have no effect.
- No choice of climate models: every model with full coverage is a member.

Glue (`R/fct_step2_input.R`, `R/fct_step2_tables.R`): the baseline helpers,
`wise_step2_input()`, `wise_step2_annotate()`, the Results views
(`step2_pointrange_bands()`, `step2_threshold_table()`,
`step2_variance_breakdown()`, ...) and the builders `step2_annual_table()`,
`step2_summary_table()`, `step2_sim_weather_table()`.

## 5. Step 3 - policy (`mod_3_01` to `mod_3_05`, `mod_3_11`)

The spec fields are the control ids, grouped by lever: `policy.sp.*`,
`policy.infra.*`, `policy.digital.*`, `policy.labor.*`, `policy.education.*`,
`policy.other.*` (ids in `STEP3_*_IDS`, `R/fct_step3_input.R`). The access
levers (`infra`, `digital`, `education`, `other`) are controlled by lever code,
`<code>_universal` and `<code>_pct`: the codes are those of the `policy` column
of the variable list (`policy_registry()`), so a lever added to the list needs
no spec change beyond naming it; `other` holds levers whose group has no module
of its own. A code the variable list does not have, or one named under the wrong
lever, stops the run. Specs written with the earlier control stems (`elec`,
`imp_wat_san`, `primary`, `secondary`, `postsec`) are read as the codes. `policy.sp` covers the regular
program and, with `sp_type: shock`, the shock-responsive one (trigger, payout,
budget and timing controls). A lever that is present starts from the initial
values of its controls (`wise_default_policy()`; a test compares them with the
rendered controls); an absent lever is not part of the run. Results and
Decomposition controls (`cmp_*`, `headline_*`, `decomp_units`) are display
choices.

`transfer_amount_usd` is the amount per payment in the outcome's currency (the
id is historical). With `transfer_amount_mode: pctile` (regular program,
`budget_mode: transfer_first`) it is replaced by `transfer_pctile` (1 to 99) of
the baseline survey's weighted daily welfare x 365 / `transfer_n_payments`
(`wise_sp_resolve_amount()`, read once from the survey the run uses; a batch run
stops if the percentile is not available). Both fields are dropped from the
normalised spec while the mode is `fixed`, so ids of existing specs hold.

Fields the app fills from the data and the spec leaves to the user: `pmt_variable`,
`pmt_cutoff`, `trigger_variable`, `trigger_value`, `trigger_value_low`,
`annual_cap`. `trigger_pov_line` follows the outcome's line. The app also moves
some controls after they render (trigger direction to the end the response
check finds, return period to the longest the record supports, `trigger_level`
back to national); batch applies none of these, so a spec states the values.
`sp_reach` and `sp_shock_state` (sidebar previews) are not read.

Glue (`R/fct_step3_input.R`, `R/fct_step3_tables.R`): `wise_sp_config()`,
`wise_infra_config()`, `wise_digital_config()`, `wise_labor_config()`,
`wise_education_config()`, `wise_policy_configs()`, `wise_step3_input()`; the
Results-pane views (`step3_series()`, `step3_threshold_table()`,
`step3_paired_*()`); the diagnostics and cost-effectiveness helpers of `mod_3_08`
and `mod_3_10`; and `step3_batch_tables()`, which builds the policy arm of
`annual` and `summary`, `decomposition` and `policy_measures`.

## 6. Seeds and RNG

The session seed (default `WISEAPP_DEFAULT_SEED`, 123) controls all randomness
of a run, and the spec's `seed` is that seed:

- model fits for ranger and xgboost, the Lasso (folds and imputation) and
  K-means bin breaks;
- the Step 2 run (`RNGkind("Mersenne-Twister", "Inversion", "Rejection")` and
  `set.seed(seed)`) and its display residual draws;
- Step 3 lever draws (`wise_seed(seed, "policy", <lever>)`) and the shock plan.

Each call receives the plain seed (not a derivative), so results at the default
seed are unchanged. `fct_run_simulation()` stamps the seed on
`hist_sim_result$seed`; every display consumer reads it with `.step2_run_seed()`,
so Step 2 and Step 3 tables use the seed of the run they show, and both Step 3
arms use the baseline run's seed, which keeps paired draws aligned. Cache keys
include the seed. Only the binscatter jitter (display) ignores it.

In batch, `wise_batch_policy()` sets the default generator kind before
`step3_compute()` and restores it on exit, so a `crew` worker draws as the app's
main process does. A `seed` axis is meaningful: each seed varies fits, Lasso,
K-means bins, Step 2 draws, display residuals and policy draws.
