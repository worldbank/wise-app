# WISE-APP batch runs

> **Draft.** This describes the planned batch pipeline. None of it is
> implemented yet. Design: `review/batch_pipeline_plan.md`. Tables:
> `batch/docs/tables.md`. The old scripts are in `legacy/` for reference
> only; they are not maintained.

The batch pipeline runs WISE-APP without the Shiny interface for many
samples and specifications. It writes tidy result tables for reports, papers
and reproducibility packages.

- **Same results as the app.** Batch calls the same package functions as the
  app. A run with a given spec and seed gives the numbers the app shows for
  the same settings.
- **Tables only.** Batch publishes aggregate tables in parquet format. It
  does not publish household-level results, maps or the underlying survey
  and weather data. Figures are made afterwards from the tables.
- **Computed once.** Runs that share a sample, weather specification, model
  or simulation reuse that work. Changing one setting reruns only what
  depends on it.

## Requirements

- The `wiseapp` package (this repository) and its dependencies, with the
  pinned `duckdb` version from `DESCRIPTION`.
- `targets`, `crew`, `yaml` and `arrow`.
- Data: a local data folder (`WISEAPP_DATA_PATH`). Other sources the app
  supports may follow.

## Quick start (planned)

```r
# 1. Copy the template into a new project folder
wiseapp::wise_batch_template("my-study")

# 2. Edit my-study/spec.yaml (see below), then preview the runs
wiseapp::wise_spec_expand("my-study/spec.yaml")

# 3. Run
setwd("my-study")
targets::tar_make()

# 4. Read results
runs <- arrow::read_parquet("results/runs.parquet")
annual <- arrow::open_dataset("results/tables/annual")
```

## Specifying runs

A run spec describes one complete run: sample, outcome, weather variables,
model, simulation settings and policy. A grid file lists named profiles and
the axes to combine. Every combination becomes one run.

```yaml
base: configs/bfa_baseline.json      # optional: a configuration exported from the app
seed: 123                            # the app default

sample:
  unit: hh

outcome:
  name: welfare
  currency: PPP
  poverty_line: 3.00

profiles:
  weather:
    t_r_12m:
      t: {ref_period: [1, 12], form: continuous}
      r: {ref_period: [1, 12], form: continuous}
    t_r_3m_bins:
      t: {ref_period: [1, 3], form: binned, n_bins: 10}
      r: {ref_period: [1, 3], form: binned, n_bins: 10}
  covariates:
    basic: {method: user, vars: {hh: [hhsize, urban]}}
    lasso: {method: lasso}
  policy:
    none: {}
    cash_20pct: {sp: {type: regular, targeting: poorest, share_pct: 20}}

axes:
  country: [BFA, MWI, SEN]
  weather: [t_r_12m, t_r_3m_bins]
  model:
    - {type: Linear regression}
    - {type: Unconditional quantile regression (RIF)}
  fixed_effects: [[year, gaul1_code]]
  covariates: [basic, lasso]
  policy: [none, cash_20pct]

sim:
  hist_years: [1991, 2020]
  future_periods: [[2041, 2060]]
  ssps: [ssp2_4_5, ssp3_7_0]
  residuals: original
  coef_uncertainty: true
```

Settings not given take the app's defaults. The field names and defaults
are listed in `batch/docs/spec_inventory.md` and will move to a reference
page when the spec is implemented.

An exported app configuration can be used as `base:`. Explore one case in the
app, export the configuration, then vary it in batch.

## Output

```
results/
├── runs.parquet        one row per run: stage ids, profile labels, settings
├── specs/              full settings of each run (JSON)
├── tables/             one parquet dataset per table, partitioned by country
├── provenance.parquet  data source and model signatures per stage
├── failures.parquet    runs or stages that failed, with the reason
└── manifest.json       package, R and duckdb versions, start and end times
```

Tables join to `runs` on their stage id (`data_id`, `wxvar_id`, `fit_id`,
`sim_id` or `policy_id`).

| Step | Tables |
|---|---|
| Survey and weather data | `variable_stats`, `interview_dates`, `weather_stats` |
| Model | `model_terms`, `model_fit`, `model_vcov` |
| Simulation and policy | `annual`, `summary`, `sim_weather`, `decomposition`, `policy_measures` |

Column definitions: `batch/docs/tables.md` (to become a reference page).

Tables store the finest level the app computes. Many app views are rebuilt
from them with the app's own functions, for example:
- weather effect curves, from `model_terms`, `model_vcov` and `model_fit`;
- decomposition by weather-year basis or by decile, from the per-year
  `decomposition` table.

Values that depend on a display choice in the app follow these rules:
- Every metric is stored (mean, poverty rate, Gini and the rest).
- Uncertainty bands use the app default (10th to 90th percentile).
- Values are levels, not deviations from the mean year.

A few statistics are computed by batch only (not shown in the app). They
include location samples, location-demeaned statistics, deciles for every
variable, and indicator variables such as `poor300`. They are marked in the
column reference.

## Seeds

Each run uses the spec's `seed` (default 123, as in a new app session). The
seed controls all randomness of a run: model fits, lasso selection, K-means
bins, simulation draws, display residual draws and policy draws. A `seed`
axis in the grid therefore gives a full robustness check across seeds.

## Status

| Phase | Content | Status |
|---|---|---|
| 0 | Plan, input inventory, table catalogue | done |
| 1 | Spec, runner, survey and weather tables | planned |
| 2 | Model tables | planned |
| 3 | Simulation tables | planned |
| 4 | Policy tables | planned |
| 5 | Figures from tables, reproducibility package template | planned |
