# Batch run spec - input inventory (Phase 0)

Status: Phase 0 draft, 2026-10-19; sections 1 and 2 updated for Phase 1
(implemented, 2026-10-19). Part of `review/batch_pipeline_plan.md`.
Maps every user-facing app input to a run-spec field, the boundary argument
it feeds, and where the glue lives today. Defaults are filled in for the
Phase 1 sections. Later phases fill in theirs when that glue is extracted.

Legend for "Kind":
- **Spec:** a setting that changes results. It becomes a run-spec field.
- **Display:** a presentation choice. It becomes a table dimension or a
  post-processing option (see `batch/docs/tables.md`, section 1).
- **UI:** has no effect on results (map views, tab buttons). Not carried.

## 1. Step 0 - source (`mod_0_overview.R`)

| Input id | Kind | Spec field | Notes |
|---|---|---|---|
| connection type, `s3_*`, `gcs_*`, `azure_*`, `hf_*` | Spec | `source.type`, `source.location` | Credentials never enter the spec; they come from the environment variables listed in AGENTS.md. The local path is `WISEAPP_DATA_PATH`. Batch v1 targets `local`. |

Glue: `build_connection_params` family (`fct_connection.R`) and metadata
loading (`load_overview_metadata()`), already Shiny-free. In batch the spec
holds only `source.type`; `wise_batch_connection()` builds the connection from
the environment.

## 2. Step 1 - sample, outcome and weather (Phase 1)

| Module | Input id | Kind | Spec field | App default | Feeds |
|---|---|---|---|---|---|
| `mod_1_01_sample` | `unit` | Spec | `sample.unit` | `"hh"` | `build_survey_fnames()` |
| `mod_1_01_sample` | `economy` | Spec | `sample.countries` | `"BFA"` if available, else the first | `build_selected_surveys()` |
| `mod_1_01_sample` | `year_<code>` (dynamic) | Spec | `sample.years.<code>` | all available years | `build_selected_surveys()` |
| `mod_1_02_surveystats` | `survey_stats` (button), `map_wave` | UI | - | - | - |
| `mod_1_03_outcome` | `outcome` | Spec | `outcome.name` | first outcome in the filtered variable list | `build_selected_outcome()` |
| `mod_1_03_outcome` | `currency` | Spec | `outcome.currency` | `"PPP"` | `build_selected_outcome()`, LCU/PPP conversion |
| `mod_1_03_outcome` | `poverty_line` | Spec | `outcome.poverty_line` | 3.00 for PPP; `default_lcu_poverty_line()` for LCU. Shown only for outcome `poor`. | `build_selected_outcome()` |
| `mod_1_03_outcome` | `summary_wave`, `cov_view`, `cov_wave`, `outcome_stats_btn` | Display / UI | - | - | The summary wave is a dimension of `outcome_summary`. |
| `mod_1_04_weather` | `weather_variable_selector` | Spec | the names of the `weather.<var>` entries (at most 2) | first weather variable | `build_selected_weather()` |
| `mod_1_04_weather` | `<var>_relativePeriod` | Spec | `weather.<var>.ref_period` | `c(1, 1)` | `build_weather_spec()` |
| `mod_1_04_weather` | `<var>_temporalAgg` | Spec | `weather.<var>.temporal_agg` | `temporal_agg_default(units)`: Sum for mm/days, else Mean | same |
| `mod_1_04_weather` | `<var>_varConstruction` | Spec | `weather.<var>.transformation` | `transformation_default(units)` | same |
| `mod_1_04_weather` | `<var>_contOrBinned` | Spec | `weather.<var>.form` | `"Binned"` | same |
| `mod_1_04_weather` | `<var>_numBins` | Spec | `weather.<var>.n_bins` | 5 | same |
| `mod_1_04_weather` | `<var>_binningMethod` | Spec | `weather.<var>.binning_method` | `"Equal frequency"` | same |
| `mod_1_04_weather` | `<var>_customBreaks` | Spec | `weather.<var>.custom_breaks` | none | `parse_custom_breaks()` |
| `mod_1_04_weather` | `<var>_polynomial` | Spec | `weather.<var>.polynomial` | none | same |
| `mod_1_04_weather` | `hist_years` | Spec | `weather.hist_years` | `c(1991, 2020)` | historical comparison in mod_1_05 and the bin breaks |
| `mod_1_05_weatherstats` | `weather_stats` (button), `wxmap_*` | UI | - | - | maps excluded |

Implementation notes (Phase 1):
- `weather.<var>` entries sit directly in the `weather` section, next to
  `weather.hist_years`; the variables are the names in the section (at most
  two). `form` accepts `Binned` or `Continuous` in any case.
- A field set to `NULL` follows a data-dependent rule: the default economy,
  every available year, the first outcome, the first weather variable, and
  the unit-dependent aggregation and transformation. The first two and the
  weather rules are resolved when the grid is read (`wise_spec_resolve()`);
  the default outcome and the LCU poverty line need the loaded survey and
  stay as given in the spec.
- Fields that do not apply are dropped when a spec is built (`n_bins`,
  `binning_method` and `custom_breaks` for a continuous variable,
  `polynomial` for a binned one), so equal specs hash equal.
- `wxvar_id` hashes the reference period, temporal aggregation and
  transformation only, because the weather statistics describe the values
  before binning.

Batch-only statistics options (no app input; see `batch/docs/tables.md`
section 5):

| Spec field | Default | Effect |
|---|---|---|
| `stats.indicators` | `poor300`, `poor420`, `poor830` (welfare below 3.00, 4.20, 8.30); `ttime_health_gt15/30/45/60` | binary indicator rows in `variable_stats` |
| `stats.location_samples` | `true` | `with_loc`, `without_loc` and `within_loc` rows in `variable_stats` and `weather_stats` |

Glue extracted in Phase 1 (module -> core, `R/fct_step1_data.R`):

| Glue | Core function | Module |
|---|---|---|
| Surveys available for a unit | `wise_available_surveys()` (batch: `wise_select_surveys()`) | `mod_1_01` |
| Survey load and preparation (`add_time_columns()`, `assign_data_level()`, `convert_lcu_to_ppp()`, `bottom_code_welfare()`, `apply_policy_derivations()`) | `load_survey_frame()`, `prepare_survey_data()`, `survey_n_no_deflator()` | `mod_1_02` |
| Variables behind the survey summary tables | `wise_stats_vars()`, `wise_policy_vars()` | `mod_1_02` |
| Outcome data with the synthetic `poor` | `wise_outcome_data()` (batch: `wise_selected_outcome()`) | `mod_1_03` |
| Selected weather from the inputs | `build_selected_weather()` (batch: `wise_selected_weather()`) | `mod_1_04` |
| Weather fetch, survey merge and the historical comparison cells | `wise_weather_fetch()`, `merge_survey_weather()`, `wise_weather_companions()` (batch: `wise_load_weather()`) | `mod_1_05` |
| Defaults of the controls | `wise_spec_defaults()`, `wise_default_*()`, `wise_weather_var_defaults()` (`R/fct_spec_defaults.R`) | `mod_1_01` to `mod_1_05` |

Not extracted: the H3 map data of `mod_1_02` (maps; the location panel join
moved out in Phase 2, see section 3); the Weather stats tab's reload of the historical comparison when its year
range changes (screen-only state).

The table closures of `batch/docs/tables.md` section 3.1 are built by
`variable_stats_table()`, `interview_dates_table()` and
`weather_stats_table()` (`R/fct_step1_tables.R`).

## 3. Step 1 - model (Phase 2)

| Module | Input ids | Kind | Spec field | App default |
|---|---|---|---|---|
| `mod_1_06_model` | `model_type` | Spec | `model.type` (`linear`, `logistic`, `rif`; the engine follows from the type) | first of `model_type_choices()` for the outcome type |
| `mod_1_06_model` | `fixedeffects` | Spec | `model.fixed_effects` | `year`, `gaul1_code` where valid fixed-effect variables |
| `mod_1_06_model` | `interactions` | Spec | not in the spec yet (policy phase) | `urban` where available; batch uses none, an import warns |
| `mod_1_06_model` | `covariates` (method), `indcov`, `hhcov`, `areacov`, `firmcov` | Spec | `model.covariates.method` (`user`, `lasso`), `model.covariates.vars` (flat; the level of each follows from the variable list) | user-defined, none |
| `mod_1_06_model` | `selected_policies` | Spec | not in the spec yet (policy phase) | none |
| `mod_1_06_model` | `lasso_alpha`, `lasso_interactions` (the lambda rule), `lasso_nfolds`, `lasso_standardize`, `use_mice`, `mi_m`, `mi_maxit`, `stability_threshold` | Spec | `model.covariates.lasso.{alpha, lambda, nfolds, standardize, use_mice, mi_m, mi_maxit, stability_threshold}` | `wise_default_lasso()` |
| `mod_1_06_model` | `force_in_<level>`, `force_out_<level>` | Spec | `model.covariates.lasso.{force_in, force_out}` (flat) | none |
| `mod_1_07_results` | `rif_tau` | Display | `tau` dimension of Step 1 tables | - |
| `mod_1_06_model` | `run_model` | UI | - | - |

Notes (Phase 2): RIF taus come from the model type (0.1 to 0.9, no control).
A run spec without a `model` section fits nothing. Defaults live in
`wise_default_model()`, `wise_default_lasso()`, `wise_default_fixed_effects()`
and `wise_default_model_type()` (`R/fct_spec_defaults.R`); the Model tab reads
the Lasso and fixed-effect defaults from them.

Glue extracted in Phase 2 (module -> core):

| Glue | Core function | Module |
|---|---|---|
| H3 files, location panel (`loc_id_panel`) and its join | `wise_h3_fnames()`, `wise_location_panel()`, `wise_join_location_panel()` (batch: `wise_load_location_panel()`) in `R/fct_step1_data.R` | `mod_1_02` |
| Valid variables, Lasso settings and run, covariates from a selection, cluster variable, model specification | `wise_valid_vars()`, `wise_lasso_settings()`, `wise_lasso_candidates()`, `wise_lasso_selection()`, `wise_lasso_covariates()`, `wise_cluster_var()`, `wise_selected_model()` in `R/fct_step1_model.R` (batch: `wise_model_from_spec()`) | `mod_1_06` |
| Bin relabel, outcome scale, `fit_model()`, fit snapshot | `wise_fit()` | `mod_1_07` |
| Effect scenarios, headline cards, focused estimates | `step1_translations()`, `step1_focused_df()` in `R/fct_step1_model_tables.R` | `mod_1_07` |
| Fit statistics, importance shares | `fit_stats_raw()` (behind `calc_fit_stats()`), `importance_shares()` (behind `echart_importance()`) in `R/fct_results.R` | `mod_1_08` |

The tables are built by `model_terms_table()`, `model_fit_table()` and
`model_vcov_table()`.

## 4. Step 2 - simulation (Phase 3)

| Module | Input ids | Kind | Spec field |
|---|---|---|---|
| `mod_2_01_weathersim` | `baseline_survey` | Spec | `sim.baseline_survey` |
| `mod_2_01_weathersim` | `hist_years` | Spec | `sim.hist_years` |
| `mod_2_01_weathersim` | `fut_period_1..3` | Spec | `sim.future_periods` (up to 3) |
| `mod_2_01_weathersim` | `climate` | Spec | `sim.ssps` |
| `mod_2_01_weathersim` | `residuals` | Spec | `sim.residuals` (forced to `"none"` for RIF) |
| `mod_2_01_weathersim` | `include_coef_uncertainty` | Spec | `sim.coef_uncertainty` |
| `mod_2_01_weathersim` | `propagate_all_covariate_uncertainty` | Spec | `sim.propagate_all_covariate_uncertainty` |
| `mod_2_02_results` | `cmp_agg_method`, `cmp_deviation`, `ensemble_band`, `annual_distribution_type`, `exceedance_model_spread`, `pov_line` | Display | `metric` dimension; the rest at defaults (tables D3) |
| `mod_2_03_diagnostics` | `diag_weather_vars`, `diag_weather_scenario` | Display | dimensions |
| `mod_2_01_weathersim` | `run_sim`, `stop_sim` | UI | - |

App defaults (Phase 3): `sim.hist_years` 1991-2020, `sim.future_periods`
2025-2035 (periods 2 and 3 start unused, 2015-2015), `sim.ssps` SSP3-7.0,
`sim.residuals` `"original"`, `sim.coef_uncertainty` true,
`sim.propagate_all_covariate_uncertainty` false, `sim.baseline_survey` the
latest wave of each economy. They live in `wise_default_sim()` and
`wise_default_baseline()` (`R/fct_spec_defaults.R`); the sidebar reads its
initial values from them. The ids in a configuration export are
`step2-weathersim-<input>`.

Spec notes (Phase 3): `sim` needs a `model` section. A period that is
incomplete, empty (end not after start) or starts before 2015 is excluded in the
app and is an error in the spec (a configuration import drops it, as the app
does). The residual rule and the scenarios do not enter the `sim_id` when they
have no effect (RIF; no projection period). The spec has no choice of climate
models: every model of the projection files with full coverage is a member.

Glue extracted in Phase 3 (module -> core, `R/fct_step2_input.R`):

| Glue | Core function | Module |
|---|---|---|
| Baseline waves, default and subset of the frame, label | `step2_baseline_choices()`, `wise_default_baseline()`, `step2_baseline_svy()`, `.step2_filter_baseline_surveys()`, `step2_baseline_label()` | `mod_2_01` |
| Dates, periods, scenarios, perturbation, residual rule, RIF fits, model snapshot | `wise_step2_input()` (async snapshot and debugging path) | `mod_2_01` |
| Historical label and run summary | `step2_hist_label()`, `wise_step2_annotate()` | `mod_2_01` |
| Results views: bands, thresholds, variance, adverse dots, timeseries, incidence, headline inputs | `step2_pointrange_bands()`, `step2_headline_bands()`, `step2_threshold_table()`, `step2_variance_breakdown()`, `step2_adverse_dot_view()`, `step2_timeseries_curves()`, `step2_incidence_all()`, `step2_baseline_check_view()`, `step2_delta_ci_view()`, `step2_weather_support_view()`, `step2_card_metadata()`, `step2_contrast_sd()`, `step2_hist_ref()`, `step2_hist_f_ref()` (`R/fct_step2_tables.R`) | `mod_2_02` |
| Weather support | `weather_support_from_stored()` (already pure) | `mod_2_03` |

The tables are built by `step2_annual_table()`, `step2_summary_table()` and
`step2_sim_weather_table()` from the aggregation tables of
`step2_run_aggregates()`.

## 5. Step 3 - policy (Phase 4)

| Module | Input ids | Spec field |
|---|---|---|
| `mod_3_01_sp` | `sp_type`, `unit`, `targeting`, `targeting_threshold_pct`, `pmt_variable`, `pmt_cutoff`, `inclusion_error_pct`, `exclusion_error_pct`, `error_concentration`, `budget_mode`, `budget_fixed`, `transfer_amount_usd`, `amount_basis`, `transfer_frequency`, `transfer_n_payments`, `admin_cost_pct` | `policy.sp.*` (regular program) |
| `mod_3_01_sp` | `trigger_type`, `trigger_variable`, `trigger_metric`, `trigger_direction`, `trigger_level`, `trigger_value`, `trigger_value_low`, `trigger_return_period_years`, `trigger_pov_line`, `national_k_pct`, `loss_event_pct`, `payout_scope`, `payments_per_activation`, `budget_rule`, `loss_share_pct`, `annual_cap`, `dyn_geo`, `dyn_geo_pct`, `dyn_welfare`, `dyn_welfare_pct`, `dyn_incl_error_pct`, `dyn_excl_error_pct`, `transfer_timing`, `forecast_pod_pct`, `forecast_far_pct`, `effect_multiplier`, `timeliness_weeks`, `delay_loss_pct_per_week` | `policy.sp.shock.*` |
| `mod_3_02_infra` | `elec_*`, `water_*`, `sanitation_*`, `piped_*`, `piped_to_prem_*`, `imp_wat_san_*`, `health_mode`, `health_travel_max`, `health_travel_pct` | `policy.infra.*` |
| `mod_3_03_digital` | `internet_*`, `mobile_*` | `policy.digital.*` |
| `mod_3_04_labor` | `labor_emp`, `sector_manufacturing`, `sector_services` | `policy.labor.*` |
| `mod_3_05_education` | `primary_*`, `secondary_*`, `postsec_*` | `policy.education.*` |
| `mod_3_07_results`, `fct_policy_sim_compare.R` | `show_coef_uncertainty`, `cmp_*`, `uncertainty_band`, `ensemble_band` | Display |
| `mod_3_09_decomposition` | `headline_scenario`, `decile_scenario`, `headline_weather_basis`, `decile_weather_basis`, `decomp_units` | Display (dimensions per tables D4) |

Glue: lever configs (`sp_cfg`, `infra_cfg`, ...) built from inputs in
`mod_3_01`-`mod_3_05` and passed by `mod_3_06_policy_sim.R` (around lines
420-510) to `step3_compute()`; the SP preview passes `seed` and
`hist_exposure` (`mod_3_01_sp.R` lines 1662-1684).

## 6. Seeds and RNG

The session seed (`wise_current_seed()`, default `WISEAPP_DEFAULT_SEED` =
123, `utils_math.R:12`) reaches these places:

| Where | Seed used | Reaches spec seed? |
|---|---|---|
| `fit_model()` (ranger/xgboost specs), `mod_1_07:192` | session seed | yes |
| `step2_compute()`: sets `RNGkind("Mersenne-Twister", "Inversion", "Rejection")` + `set.seed(seed)` | session seed | yes |
| `step3_compute()` lever draws: `wise_seed(seed, "policy", <lever>)` | session seed | yes |
| SP shock plan and preview (`fct_sp_shock.R:850,1080,1806`) | session seed via `wise_seed()` | yes |
| Lasso (`run_lasso_selection(parallel_seed = seed_val)`, `mod_1_06`) | session seed (was hard-coded 123) | yes (2026-10-19) |
| K-means binning (`.compute_breaks(seed =)` via `get_weather(seed =)`, `fct_get_weather.R`) | session seed (was hard-coded 123) | yes (2026-10-19) |
| Display aggregation residual draws: Step 2 pane (`mod_2_02_results.R`), Step 3 pane (`fct_policy_sim_compare.R`), in-run partial tables and preview (`fct_run_simulation.R`), metric decomposition (`.policy_metric_residuals()`) | seed of the Step 2 run, `.step2_run_seed(hs)` (was the default constant) | yes (2026-10-19) |
| Binscatter jitter (`utils_mod_1_helpers.R:833`) | 1 | no (display only) |

Change made on 2026-10-19: the session seed now controls all randomness of a
run.
- Each call that used the constant 123 now receives the plain seed, not a
  `wise_seed()` derivative. Results at the default seed (123) are therefore
  unchanged.
- `fct_run_simulation()` stamps the seed on `hist_sim_result$seed`. Every
  display consumer reads it with `.step2_run_seed()`, so Step 2 and Step 3
  tables use the seed of the run they show, even if the session seed changes
  afterwards. Both Step 3 arms use the baseline run's seed, which keeps
  paired draws aligned. Results without a stamp (older runs) fall back to the
  default.
- Cache keys include the seed: the lasso memo key, the mod_1_05 weather load
  signature, `shared_aggregation_cache_key()` and the metric decomposition
  residual cache.

Implications for batch:
- A seeds axis is now meaningful: each seed varies fits, lasso, K-means bins,
  Step 2 draws, display residuals and policy draws.
- Step 3 RNG kind: the async worker copies the main process's `RNGkind()`.
  Batch must run Step 3 under the R default kind (Mersenne-Twister), as the
  app's main process does.
