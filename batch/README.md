# WISE-APP batch runs

> **Status: Phase 1.** The run spec, the grid, the runner and the Step 1
> data tables (survey and weather statistics) work. The model, simulation and
> policy tables follow in later phases (see Status). The old scripts are in
> `legacy/` for reference only; they are not maintained. Design:
> `review/batch_pipeline_plan.md`. Tables: `batch/docs/tables.md` and, for the
> three tables that exist, `batch/docs/phase1_tables.md`.

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
  a spec.

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

Sections of later steps (`model`, `sim`, `policy`) are rejected until their
phase exists.

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
| `outcome.name` | the first available outcome (`welfare`) |
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

Values are case-insensitive for choices (`form: continuous`). In R,
`wiseapp::wise_spec(...)` builds and validates one spec, and
`wise_spec_from_config()` reads an app configuration.

### Stage ids

Each spec hashes into stage ids that decide what is shared:

| Id | Hash of | Keys |
|---|---|---|
| `data_id` | source, sample, outcome, statistics options | `variable_stats`, `interview_dates` |
| `wxvar_id` | the data id, one weather variable's settings, the historical years | `weather_stats` |
| `run_id` | the whole spec, including the seed | `runs` |

Two runs with the same sample load the survey once; two runs that use the
same weather variable settings compute its statistics once.

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
| Model | `model_terms`, `model_fit`, `model_vcov` | planned |
| Simulation and policy | `annual`, `summary`, `sim_weather`, `decomposition`, `policy_measures` | planned |

Column definitions of the available tables: `batch/docs/phase1_tables.md`.
The plan for the others is `batch/docs/tables.md`.

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
tables use no random numbers, so the seed only labels them. A `seed` axis
in the grid gives a robustness check across seeds once the model and
simulation tables exist.

## Parallel runs and resources

`run.R` sets the number of `crew` workers (`WISEAPP_BATCH_WORKERS`). Every
worker has its own DuckDB, so `wise_batch_controller()` divides the cores
(`WISEAPP_DUCKDB_THREADS`, `WISEAPP_THREADS`) and, with
`WISEAPP_BATCH_MEMORY_GB`, the memory (`WISEAPP_DUCKDB_MEMORY_LIMIT`) between
them. The weather disk cache (`WISEAPP_WEATHER_CACHE_DIR`) is shared.

## Checking against the app

`dev/batch_parity_bfa.R` runs one BFA spec through the pipeline and through
the app's module servers on the same selections and compares the tables. It
needs the real data and is run per release.

## Status

| Phase | Content | Status |
|---|---|---|
| 0 | Plan, input inventory, table catalogue | done |
| 1 | Spec, runner, survey and weather tables | done |
| 2 | Model tables | planned |
| 3 | Simulation tables | planned |
| 4 | Policy tables | planned |
| 5 | Figures from tables, reproducibility package template | planned |
