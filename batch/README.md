# WISE-APP batch runs

> **Status: Phase 3.** The run spec, the grid, the runner, the Step 1 data
> tables (survey and weather statistics), the Step 1 model tables and the
> Step 2 simulation tables work. The policy tables follow in a later phase
> (see Status). The old scripts are in `legacy/` for reference only; they are
> not maintained. Design: `review/batch_pipeline_plan.md`. Tables:
> `batch/docs/tables.md` and, for the tables that exist,
> `batch/docs/phase1_tables.md` (data), `batch/docs/phase2_tables.md` (model)
> and `batch/docs/phase3_tables.md` (simulation).

The batch pipeline runs WISE-APP without the Shiny interface for many
samples and specifications. It writes tidy result tables for reports, papers
and reproducibility packages.

- **Same results as the app.** Batch calls the same package functions as the
  app. A run with a given spec and seed gives the numbers the app shows for
  the same settings.
- **Tables only.** Batch publishes aggregate tables in parquet format. It
  does not publish household-level results, maps or the underlying survey
  and weather data. Figures are made afterwards from the tables.
- **Computed once.** Runs that share a sample or a weather variable reuse that
  work. Changing one setting reruns only what depends on it.

## Requirements

- The `wiseapp` package (this repository) and its dependencies, with the
  pinned `duckdb` version from `DESCRIPTION`.
- `targets`, `yaml` and `arrow`; `crew` for parallel workers.
- Data: a local data folder, named in the environment variable
  `WISEAPP_DATA_PATH` (for example in `~/.Renviron`). Credentials of other
  sources come from the environment variables the app uses; they never enter
  a spec. A simulation with projection periods also reads the CMIP6 climate
  projections from the data folder (`hazard/weather/projections/<code>/`),
  as the app does.

## Quick start

```r
# 1. Copy the template into a new project folder
wiseapp::wise_batch_template("my-study")
setwd("my-study")

# 2. Edit spec.yaml (see below), then preview the runs
wiseapp::wise_spec_expand("spec.yaml")

# 3. Run: Rscript run.R, or
targets::tar_make()

# 4. Read results
runs <- arrow::read_parquet("results/runs.parquet")
stats <- arrow::open_dataset("results/tables/variable_stats") |> dplyr::collect()
```

`wise_spec_expand()` lists one row per run with the profile label of each
axis, the stage ids and the full spec. With `WISEAPP_DATA_PATH` set it
resolves the data-dependent defaults, so its ids are the ids of the run.

## Specifying runs

A run spec describes one run. A grid file lists named profiles and the axes
to combine; every combination is one run.

```yaml
base: configs/bfa_baseline.json      # optional: a configuration exported from the app
seed: 123                            # the app default

sample:
  unit: hh
outcome:
  name: welfare
  currency: PPP

profiles:
  weather:
    t_12m:
      tx: {ref_period: [1, 12], form: continuous}
    t_3m_bins:
      tx: {ref_period: [1, 3], form: binned, n_bins: 5}
    t_r:
      tx: {ref_period: [1, 3], form: continuous}
      r: {ref_period: [1, 12], form: continuous}

axes:
  country: [BFA, MWI, SEN]
  weather: [t_12m, t_3m_bins, t_r]

exclude:
  - {country: MWI, weather: t_r}
```

- **Sections** at the top level (`sample`, `outcome`, `weather`, `stats`,
  `source`, `seed`) set what every run shares.
- **Profiles** are named partial settings of one section. A weather profile
  lists the weather variables (names from the variable list, at most two) and
  replaces the variable set; other profiles merge.
- **Axes** say what varies. An axis named after a profile group takes profile
  names. These also work: `country` (a code, or a list of two for a pooled
  sample), `unit`, `seed`, `hist_years`, `currency`, `poverty_line`, `outcome`
  (a name), and any dotted spec path such as `sample.unit`. Axes are crossed.
- **`zip`** makes axes vary together: `zip: [[country, seed]]`.
- **`exclude`** drops combinations by axis label.
- **`base`** is an app configuration (Export in the app). Explore one case in
  the app, export, then vary it here. Only the Step 1 sample, outcome and
  weather settings and the seed are read.

The `policy` section is rejected until its phase exists.

### The model

A `model` section adds the Step 1 model to every run: the three progressive
fits of the Model tab and the tables `model_terms`, `model_fit` and
`model_vcov`. Without a `model` section a run only produces the descriptive
tables; `model: {}` fits the app's defaults.

```yaml
model:
  type: linear                    # linear (default), logistic, rif
  fixed_effects: [year, gaul1_code]
  covariates:
    method: user                  # user (default) or lasso
    vars: [hhsize, urban]

profiles:
  covariates:
    basic: {method: user, vars: [hhsize, urban]}
    lasso: {method: lasso, lasso: {alpha: 1, lambda: lambda.1se, nfolds: 10}}
  model:
    linear: {type: linear}
    rif: {type: rif}
axes:
  model: [linear, rif]
  covariates: [basic, lasso]
```

- **type** is `linear`, `logistic` (binary outcomes) or `rif` (the
  unconditional quantile regression, quantiles 0.1 to 0.9, continuous
  outcomes). The default is the first choice the Model tab offers for the
  outcome. Fixest runs linear and logistic models; RIF has its own engine.
  The random-forest and XGBoost engines are not available in batch yet.
- **fixed_effects** left out follows the app: `year` and `gaul1_code`, where
  the data offers them. `[]` means none. Other names must be fixed-effect
  variables of the variable list that are complete enough to use.
- **covariates.vars** lists the covariates by name (household, individual,
  firm and area variables, as the Model tab offers them for the unit of
  analysis). With `method: lasso` the covariates come from the stability
  Lasso of the app; its settings are `alpha`, `lambda` (`lambda.1se` or
  `lambda.min`), `nfolds`, `standardize`, `use_mice`, `mi_m`, `mi_maxit`,
  `stability_threshold`, plus `force_in` and `force_out` lists. The
  Lasso uses the run's `seed`.
- **Axes** `model`, `fixed_effects` and `covariates` take profile names; the
  dotted path of any setting works as well (`model.covariates.lasso.alpha`).
- Interactions and policy-relevant variables are not available yet; an app
  configuration that sets them is read without them, with a warning.
- A fit that cannot run (an unavailable covariate, a Lasso that selects
  nothing) is recorded in `failures.parquet` with its run ids; the other fits
  still run.
- The standard errors are clustered at the location panel when the H3 files
  are in the data folder, as in the app. Without them the fit uses fixest's
  default variance, and `model_fit` and `provenance.parquet` say so.

### The simulation

A `sim` section adds the Step 2 simulation to every run that has a model: the
same run as "Run simulation" in the app (the historical weather and the
climate projections applied to the baseline survey) and the tables `annual`,
`summary` and `sim_weather`. It needs a `model` section. Without `sim` a run
stops at the model tables; `sim: {}` runs the app's initial state.

```yaml
sim:
  hist_years: [1991, 2020]                      # the historical weather period
  future_periods: [[2025, 2035], [2040, 2050]]  # up to three; [] for historical only
  ssps: [ssp2_4_5, ssp3_7_0]                    # ssp2_4_5, ssp3_7_0, ssp5_8_5
  residuals: original                           # original or resample
  coef_uncertainty: true
  propagate_all_covariate_uncertainty: false
  baseline_survey: [BFA|2021]                   # survey waves, CODE|YEAR

profiles:
  sim:
    ssp3: {ssps: [ssp3_7_0], future_periods: [[2025, 2035]]}
    historical: {future_periods: []}
axes:
  sim: [ssp3, historical]
```

- **hist_years** is the period of historical weather that the simulation
  draws weather years from (1950 to 2024, as the slider). It is separate from
  `weather.hist_years` of the Step 1 comparison.
- **future_periods** are start and end years of the projection periods (2015
  to 2100; at most three). Every SSP is run for every period, and every
  climate model of the data is a member. `[]` runs the historical weather only.
- **ssps** are the scenarios (`ssp2_4_5`, `ssp3_7_0`, `ssp5_8_5`). The order
  of the runs follows the app (SSP outer, period in the order given).
- **residuals** is how household residuals enter the prediction: `original`
  (each household keeps its own) or `resample`. RIF models draw none: the
  setting is ignored for them and does not change the run's id.
- **baseline_survey** names the survey waves whose households are simulated.
  Left out, it is the latest wave of each economy, as in the app.
- The standard deviations of the tables include coefficient uncertainty
  (`coef_uncertainty`); `propagate_all_covariate_uncertainty` extends it to
  all covariates, as the app's box does.
- A simulation that fails (a missing projection file, no climate model with
  full coverage) is recorded in `failures.parquet` with its run ids; the other
  simulations still run. One that finishes without some climate-model members
  or scenarios keeps its tables and is listed with the error class
  `partial_simulation_failure`.
- The Step 2 runs hold hundreds of MB each. `run.R` gives them their own,
  smaller set of workers (`WISEAPP_BATCH_SIM_WORKERS`, default 1).

### Spec fields and defaults

Settings not given take the app's defaults, which live in one place
(`wise_spec_defaults()`) that the app's controls read as well.

| Field | Default |
|---|---|
| `seed` | 123 |
| `source.type` | `local` |
| `sample.unit` | `hh` (`ind`, `firm`) |
| `sample.countries` | `BFA` when available, otherwise the first economy; at most two |
| `sample.years.<code>` | every available survey year |
| `outcome.name` | the first available outcome (`welfare`), resolved from the survey columns when the grid is read |
| `outcome.currency` | `PPP` (`LCU`) |
| `outcome.poverty_line` | 3.00 for PPP; for LCU the app default. Used by the `poor` outcome only. |
| `weather.<var>.ref_period` | `[1, 1]` (months before the interview, 0 to 12) |
| `weather.<var>.temporal_agg` | `Sum` for days and mm, otherwise `Mean` |
| `weather.<var>.transformation` | `None` (`Standardized anomaly` for dimensionless variables) |
| `weather.<var>.form` | `Binned` (`Continuous`) |
| `weather.<var>.n_bins`, `binning_method`, `custom_breaks` | 5, `Equal frequency`, none (binned only) |
| `weather.<var>.polynomial` | none (continuous only) |
| `weather.hist_years` | `[1991, 2020]` |
| `stats.indicators` | `poor300`, `poor420`, `poor830`, `ttime_health_gt15/30/45/60` |
| `stats.location_samples` | `true` |
| `model` | none (no model); `{}` is the app default model |
| `model.type` | `linear` (`logistic` for a binary outcome) |
| `model.fixed_effects` | `year`, `gaul1_code` where valid |
| `model.covariates.method` | `user` with no covariates |
| `model.covariates.lasso.*` | alpha 1, `lambda.1se`, 10 folds, standardize, no MICE, 5 imputations, 5 iterations, stability threshold 0.5 |
| `sim` | none (no simulation); `{}` is the app's initial state |
| `sim.hist_years` | `[1991, 2020]` |
| `sim.future_periods` | `[[2025, 2035]]` |
| `sim.ssps` | `[ssp3_7_0]` |
| `sim.residuals` | `original` |
| `sim.coef_uncertainty`, `sim.propagate_all_covariate_uncertainty` | true, false |
| `sim.baseline_survey` | the latest wave of each economy, resolved when the grid is read |

Values are case-insensitive for choices (`form: continuous`). In R,
`wiseapp::wise_spec(...)` builds and validates one spec, and
`wise_spec_from_config()` reads an app configuration.

### Stage ids

Each spec hashes into stage ids that decide what is shared:

| Id | Hash of | Keys |
|---|---|---|
| `data_id` | source, sample, outcome, statistics options | `variable_stats`, `interview_dates` |
| `wxvar_id` | the data id, one weather variable's settings, the historical years | `weather_stats` |
| `weather_id` | the data id and the whole weather section (binning included; the seed only for K-means bins) | the survey-weather frame (not published) |
| `fit_id` | the data id, the weather section, the model section and the seed | `model_terms`, `model_fit`, `model_vcov` |
| `sim_id` | the fit id and the simulation settings that change results | `annual`, `summary`, `sim_weather` |
| `run_id` | the whole spec, including the seed | `runs` |

Two runs with the same sample load the survey once; two runs that use the
same weather variable settings compute its statistics once; runs that differ
only in the model share the weather frame and fit separately; runs that differ
only in the simulation share the fit. Because the statistics options are part
of `data_id`, changing them reruns the fits and the simulations too.

## Output

```
results/
├── runs.parquet        one row per run: run_id, stage ids, axis labels (axis_<name>), settings
├── specs/              full settings of each run (JSON, readable with wise_spec_read())
├── tables/             one parquet dataset per table, partitioned by country code
├── provenance.parquet  data source, row counts and timings per stage
├── failures.parquet    stages that failed, the runs they affect, the reason
└── manifest.json       package, R and duckdb versions, data source digest, start and end times
```

Tables join to `runs` on their stage id.

| Step | Tables | Status |
|---|---|---|
| Survey and weather data | `variable_stats`, `interview_dates`, `weather_stats` | available |
| Model | `model_terms`, `model_fit`, `model_vcov` | available |
| Simulation | `annual`, `summary`, `sim_weather` | available |
| Policy | `decomposition`, `policy_measures` (and the policy arm of `annual`, `summary`) | planned |

Column definitions of the available tables: `batch/docs/phase1_tables.md`
(data), `batch/docs/phase2_tables.md` (model) and `batch/docs/phase3_tables.md`
(simulation). The plan for the others is `batch/docs/tables.md`.

A stage that fails (a missing survey file, an outcome the surveys do not
have) does not stop the others: it is listed in `failures.parquet` with the
run ids it affects, and the runs that do not depend on it finish.

A few statistics are computed by batch only (not shown in the app): location
samples, location-demeaned statistics, deciles for every variable, indicator
variables such as `poor300` and the interview-date totals. The column
reference marks them.

## Seeds

Each run uses the spec's `seed` (default 123, as in a new app session). The
seed controls all randomness of a run: model fits, lasso selection, K-means
bins, simulation draws, display residual draws and policy draws. The Phase 1
tables use no random numbers, so the seed only labels them; the Lasso (fold
assignment and imputation) and K-means bins use it, so it matters for the
model tables of those specs. A `seed` axis in the grid gives a robustness check
across seeds.

## Parallel runs and resources

`run.R` sets the number of `crew` workers (`WISEAPP_BATCH_WORKERS`). Every
worker has its own DuckDB, so `wise_batch_controller()` divides the cores
(`WISEAPP_DUCKDB_THREADS`, `WISEAPP_THREADS`) and, with
`WISEAPP_BATCH_MEMORY_GB`, the memory (`WISEAPP_DUCKDB_MEMORY_LIMIT`) between
them. The weather disk cache (`WISEAPP_WEATHER_CACHE_DIR`) is shared.

## Checking against the app

`dev/batch_parity_bfa.R` (data tables) and `dev/batch_parity_bfa_models.R`
(model tables) run one BFA spec through the pipeline and through the app's
module servers on the same selections and compare the tables. They need the
real data and are run per release.

## Status

| Phase | Content | Status |
|---|---|---|
| 0 | Plan, input inventory, table catalogue | done |
| 1 | Spec, runner, survey and weather tables | done |
| 2 | Model tables | done |
| 3 | Simulation tables | done |
| 4 | Policy tables | planned |
| 5 | Figures from tables, reproducibility package template | planned |
