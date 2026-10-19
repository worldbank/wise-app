# Batch run spec - input inventory (Phase 0)

Status: Phase 0 draft, 2026-10-19. Part of `review/batch_pipeline_plan.md`.
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
loading (`load_overview_metadata()`), already Shiny-free.

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
| `mod_1_04_weather` | `weather_variable_selector` | Spec | `weather.variables` (names; at most 2) | first weather variable | `build_selected_weather()` |
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

Batch-only statistics options (no app input; see `batch/docs/tables.md`
section 5):

| Spec field | Default | Effect |
|---|---|---|
| `stats.indicators` | `poor300`, `poor420`, `poor830` (welfare below 3.00, 4.20, 8.30); `ttime_health_gt15/30/45/60` | binary indicator rows in `variable_stats` |
| `stats.location_samples` | `true` | `with_loc`, `without_loc` and `within_loc` rows in `variable_stats` and `weather_stats` |

Glue to extract in Phase 1 (module -> core):
- Survey load and preparation: `load_data()`, `add_time_columns()`,
  `assign_data_level()`, `convert_lcu_to_ppp()`, `bottom_code_welfare()` as
  chained in the `survey_data` reactive (`mod_1_02_surveystats.R` around line
  279 and `mod_1_modelling.R`).
- Outcome data (`outcome_data()` in `mod_1_03`), then `outcome_summary_wide()`.
- Weather load and merge: `get_weather()` + `merge_survey_weather()` and the
  historical comparison (`expand_hist_dates()`, `join_hist_sample_cells()`)
  in `mod_1_05_weatherstats.R` lines 215-310; stored bin breaks.
- Table closures listed in `batch/docs/tables.md` section 3.1.

## 3. Step 1 - model (Phase 2)

| Module | Input ids | Kind | Spec field |
|---|---|---|---|
| `mod_1_06_model` | `model_type` | Spec | `model.type` (selects the engine via `ENGINE_REGISTRY`) |
| `mod_1_06_model` | `fixedeffects` | Spec | `model.fixed_effects` |
| `mod_1_06_model` | `interactions` | Spec | `model.interactions` |
| `mod_1_06_model` | `covariates` (method), `indcov`, `hhcov`, `areacov`, `firmcov` | Spec | `model.covariates.method`, `model.covariates.vars.<level>` |
| `mod_1_06_model` | `selected_policies` | Spec | `model.policy_vars` (policy-relevant variables kept in the model so Step 3 levers apply) |
| `mod_1_06_model` | `lasso_alpha`, `lasso_nfolds`, `lasso_standardize`, `lasso_interactions`, `stability_threshold`, `use_mice`, `mi_m`, `mi_maxit`, `force_in_<level>`, `force_out_<level>` | Spec | `model.lasso.*` |
| `mod_1_07_results` | `rif_tau` | Display | `tau` dimension of Step 1 tables |
| `mod_1_06_model` | `run_model` | UI | - |

Glue: the covariate and FE assembly before `fit_model()` (`mod_1_07_results.R`
around line 185) and before `run_lasso_selection()` (`mod_1_06_model.R`
around line 842). RIF taus come from the model type.

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

Glue: `mod_2_01_weathersim.R` lines 1002-1050 build the `step2_compute()`
input: `build_hist_sim_dates()`, `fp_list`, `build_perturbation_method()`,
the baseline survey subset, `stored_breaks`, `step2_slim_model_fit()`.

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
