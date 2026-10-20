# WISE-APP batch runs

Runs WISE-APP without the Shiny interface over a grid of samples and
specifications and writes tidy parquet tables: survey and weather statistics,
Step 1 models, Step 2 simulations and Step 3 policy runs. A run with a given
spec and seed gives the numbers the app shows for the same settings. Only
aggregate tables are published, never household-level results or microdata.
Work shared between runs (a sample, a weather variable, a fit, a simulation) is
computed once and cached by `targets`.

Table columns: `batch/docs/tables.md`. App input to spec field map:
`batch/docs/spec_inventory.md`. Design: `review/batch_pipeline_plan.md`. The old
scripts in `batch/legacy/` are not maintained.

## Requirements

- The `wiseapp` package with its dependencies (the pinned `duckdb` from
  `DESCRIPTION`), plus `targets`, `yaml`, `arrow`, and `crew` for parallel
  workers.
- Data: a local data folder in the environment variable `WISEAPP_DATA_PATH`.
  A simulation with projection periods also reads the CMIP6 projections from
  `<data folder>/hazard/weather/projections/<code>/`. Credentials for other
  sources come from the app's environment variables and never enter a spec.

## Run a batch

```r
wiseapp::wise_batch_template("my-study")   # copies _targets.R, spec.yaml, run.R, ...
setwd("my-study")
# edit spec.yaml, with WISEAPP_DATA_PATH set
wiseapp::wise_spec_expand("spec.yaml")     # preview: one row per run, with stage ids
```

```sh
Rscript run.R          # or, in R: targets::tar_make()
```

```r
runs     <- arrow::read_parquet("results/runs.parquet")
failures <- arrow::read_parquet("results/failures.parquet")   # read this first
annual   <- arrow::open_dataset("results/tables/annual") |> dplyr::collect()
```

Always preview first: an invalid spec fails there, listing every problem, before
anything runs. Real runs can take hours, and each Step 2 run holds hundreds of
MB.

## Which steps run

The sections of `spec.yaml` decide how far a run goes. Each step needs the one
before it:

| Add this section | To get | Tables |
|---|---|---|
| (none) | survey and weather statistics | `variable_stats`, `interview_dates`, `weather_stats` |
| `model: {}` | Step 1 model | `model_terms`, `model_fit`, `model_vcov` |
| `sim: {}` | Step 2 simulation (needs `model`) | `annual`, `summary`, `sim_weather` |
| `policy: {...}` | Step 3 policy (needs `sim`) | policy arm of `annual` and `summary`, `decomposition`, `policy_measures` |

`{}` means the app defaults. A step cannot run alone, but upstream stages are
cached, so after one full run a change to `policy` reruns only the policy
branches. `targets::tar_make(names = fit_tables)` builds one target and what it
depends on, without writing `results/`.

## The spec

```yaml
seed: 123                              # drives every random draw of a run
sample: {unit: hh, countries: [BFA]}   # unit: hh | ind | firm; one or two economies
outcome: {name: welfare, currency: PPP}
weather:                               # at most two variables
  tx: {ref_period: [1, 3], form: continuous}
  hist_years: [1991, 2020]
model:
  type: linear                         # linear | logistic | rif
  fixed_effects: [year, gaul1_code]
  covariates: {method: user, vars: [hhsize, urban]}   # or method: lasso
sim:
  future_periods: [[2025, 2035]]       # up to three; [] for historical only
  ssps: [ssp3_7_0]                     # ssp2_4_5 | ssp3_7_0 | ssp5_8_5
policy:
  sp: {transfer_amount_usd: 60, targeting: exante_poor, targeting_threshold_pct: 30}
```

Settings left out take the app defaults (`wise_spec_defaults()`); choices are
case-insensitive. A spec is checked when read.

| Section | Fields (default) |
|---|---|
| top level | `seed` (123), `base` (path of an app configuration JSON to start from) |
| `source` | `type` (`local`); credentials and paths come from the environment |
| `sample` | `unit` (`hh`), `countries` (`BFA` if available, else the first), `years.<code>` (all) |
| `outcome` | `name` (first outcome, `welfare`), `currency` (`PPP` or `LCU`), `poverty_line` (3.00 PPP; see the note below) |
| `weather.<var>` | `ref_period` ([1, 1] months before the interview), `temporal_agg` (Sum for mm and days, else Mean), `transformation` (`None`), `form` (`Binned`), `n_bins` (5), `binning_method` (`Equal frequency`), `custom_breaks`, `polynomial` |
| `weather` | `hist_years` ([1991, 2020]) |
| `stats` | `indicators` (`poor300`, `poor420`, `poor830`, `ttime_health_gt15/30/45/60`), `location_samples` (true) |
| `model` | `type` (linear; logistic for a binary outcome), `fixed_effects` (`year`, `gaul1_code`; `[]` none), `covariates.method` (`user`) and `.vars`, `covariates.lasso.*` (alpha 1, `lambda.1se`, 10 folds, ...), `interactions`, `policy_vars` (scenario key `A` to `M`) |
| `sim` | `hist_years` ([1991, 2020]), `future_periods` ([[2025, 2035]]), `ssps` (`ssp3_7_0`), `residuals` (`original` or `resample`), `coef_uncertainty` (true), `propagate_all_covariate_uncertainty` (false), `baseline_survey` (`CODE\|YEAR`, default the latest wave) |
| `policy` | levers `sp`, `infra`, `digital`, `labor`, `education`; settings are the app's control ids (see below) |

Notes:

- RIF models (`type: rif`) fit quantiles 0.1 to 0.9 on continuous outcomes;
  logistic needs a binary outcome. Random-forest and XGBoost engines are not
  available in batch.
- Covariates must exist at the unit of analysis (or area level) and be complete
  in at least 90% of every wave. A fit that cannot run is recorded in
  `failures.parquet`.
- Standard errors are clustered at the location panel when the H3 files are in
  the data folder, else fixest's default; `model_fit` and `provenance.parquet`
  say which.
- Every climate model with full coverage is a simulation member; there is no
  model choice.
- **Policy.** A lever that is present starts from the app's initial control
  values; an absent lever is not part of the run (`sp: {}` is a zero cash
  transfer). Infrastructure, digital and education levers set `<lever>_pct`
  (-20 to 100) or `<lever>_universal`; labour sets `labor_emp`,
  `sector_manufacturing`, `sector_services`. `sp_type: shock` adds the trigger,
  payout, budget and timing controls. Rules the app applies from the data after
  the controls render are not applied in batch: name `trigger_variable` (a binned
  variable through `<variable>_cont`), state `trigger_direction` (starts at
  `above`) and `trigger_return_period_years` (starts at 10), and give `pmt_variable`
  and `pmt_cutoff` for proxy targeting. The trigger poverty line follows the
  outcome's line (else 3.00).
- **Cash transfer amount.** `transfer_amount_usd` is the amount per payment in the
  outcome's currency (2021 PPP dollars, or local currency units for an LCU
  outcome); the name is historical. For a regular program with
  `budget_mode: transfer_first`, `transfer_amount_mode: pctile` with
  `transfer_pctile: 10` sets it instead to the 10th weighted percentile of
  baseline daily welfare x 365 / `transfer_n_payments`. The percentile is read
  from the Step 2 baseline survey (the same distribution as the `exante_poor`
  cutoff), once per run; `transfer_amount_usd` is then ignored. The amount used
  is in `policy_measures` (section `transfer_amount`). A shock or budget-first
  program cannot use it.
- **Poverty line.** For the `poor` outcome `outcome.poverty_line` defines the outcome, so it
  changes the data and every stage after it. For any other outcome (`welfare`) the fit does not use
  it: the line sets the simulation's poverty metrics (`headcount_ratio`, `gap`, `fgt2`, the
  policy cost-effectiveness and trigger lines), the starting value of the app's Step 2 poverty-line
  control. Runs that differ only in the line share the survey, weather and model fit and rerun the
  simulation: use a `poverty_line` axis for several lines. Survey poverty rates at other lines come
  from `stats.indicators`.
- A binary outcome or logistic model has no policy contrast: the run writes no
  policy rows and `failures.parquet` lists a `partial_policy_failure`.

## Grids

A grid file adds named `profiles` (partial settings of one section) and `axes`
(what varies); every combination is one run.

```yaml
profiles:
  weather:
    t_3m: {tx: {ref_period: [1, 3], form: continuous}}
    t_12m: {tx: {ref_period: [1, 12], form: continuous}}
  policy:
    none: {}
    cash: {sp: {transfer_amount_usd: 60}}
axes:
  country: [BFA, MWI]
  weather: [t_3m, t_12m]
  policy: [none, cash]
exclude:
  - {country: MWI, weather: t_12m}
zip: [[country, seed]]          # axes that vary together
```

- An axis named after a profile group takes profile names. A weather profile
  replaces the variable set; a policy profile is the whole policy; others merge.
  Profile groups are the section names (`weather`, `model`, `sim`, `policy`, ...)
  plus `covariates` and `fixed_effects`.
- Other axes: `country` (a code, or a list of two for a pooled sample), `unit`,
  `seed`, `hist_years`, `currency`, `poverty_line`, `outcome`, or any dotted spec
  path (`policy.sp.transfer_amount_usd: [30, 60, 90]`). Axis names cannot be
  run-table columns (`run_id`, `data_id`, `spec`, ...).
- `exclude` drops combinations by axis label; `base` starts from an app
  configuration exported with the app's Export.

## Output

```
results/
├── runs.parquet        one row per run: stage ids, axis labels (axis_<name>), settings
├── specs/<run_id>.json full spec of each run (read with wise_spec_read())
├── tables/<table>/     one parquet dataset per table, partitioned by country code
├── provenance.parquet  source, row counts and timings per stage
├── failures.parquet    failed stages, the runs they affect, the reason
└── manifest.json       package, R, duckdb versions, renv.lock hash, survey-file digests, times
```

Each table carries the id of the stage it depends on (`data_id`, `wxvar_id`,
`fit_id`, `sim_id`, `policy_id`); join to `runs` on it. The baseline arm of
`annual` and `summary` has `policy_id` `NA` and is stored once per simulation;
a policy's effect is the policy row minus the baseline row of the same scenario,
metric, member and year, or the `policy_expected` rows of `summary`. A few
statistics exist only in batch (location samples, deciles for every variable,
indicators); `tables.md` marks them.

## Caching, failures and re-runs

- Each spec hashes into stage ids. Runs with equal ids share the work: the survey
  loads once per sample, a weather variable once, a model fit once, a Step 2 run
  once. The statistics options belong to `data_id`, so changing them reruns the
  fits, simulations and policies too.
- A stage reruns when its inputs change, including when a file it reads was
  rebuilt (size and modification time). Changing `spec.yaml` and running again
  recomputes only what the change touches.
- The Step 2 run of each simulation with a policy is stored in
  `_targets/user/sims/` (hundreds of MB each). `wise_targets(keep_step2 = FALSE)`
  deletes them after a run; a policy-only change then needs
  `targets::tar_invalidate(sim_tables)`.
- A failed stage does not stop the others: it is listed in `failures.parquet`
  with the run ids it affects, and independent runs finish. A reported failure is
  stored as the stage's result, so `tar_make()` does not retry it: after fixing
  the cause, invalidate the stage target (`data_frames`, `wx_frames`,
  `fit_tables`, `sim_tables` or `policy_tables`) and run again.
- A crashed worker (typically out of memory in a Step 2 run) makes `targets`
  skip `results`, so no tables are written. Lower `WISEAPP_BATCH_SIM_WORKERS`, set
  `WISEAPP_BATCH_MEMORY_GB`, and run `tar_make()` again: finished branches are
  kept.
- A simulation that finishes without some climate models or scenarios keeps its
  tables and is listed as `partial_simulation_failure`.

## Resources

`run.R` sets the number of `crew` workers (`WISEAPP_BATCH_WORKERS`) and the Step 2
and 3 workers (`WISEAPP_BATCH_SIM_WORKERS`, default 1; each run holds hundreds of
MB). `wise_batch_controller()` divides the cores (`WISEAPP_DUCKDB_THREADS`,
`WISEAPP_THREADS`) and, with `WISEAPP_BATCH_MEMORY_GB`, the memory
(`WISEAPP_DUCKDB_MEMORY_LIMIT`) between workers, because each has its own DuckDB.
The weather cache (`WISEAPP_WEATHER_CACHE_DIR`) is shared.

## Reproducibility

Pin the software once, before the first run, and keep `renv.lock`, `spec.yaml`,
`run.R` and `_targets.R` with the results:

```r
renv::init()
renv::install("worldbank/wise-app@<tag or commit>")
renv::snapshot()
```

`manifest.json` records the package version and commit, R and duckdb versions,
the hash of `renv.lock` and the SHA-256 of the survey files (local data). On
another machine, restore the lock (`renv::restore()`), set `WISEAPP_DATA_PATH`
and run `Rscript check_reproducibility.R`; it exits with status 1 and prints
what differs. `Rscript run.R` then reproduces the tables.

## Checking against the app

`dev/batch_parity_bfa.R`, `dev/batch_parity_bfa_models.R`,
`dev/batch_parity_bfa_sim.R` and `dev/batch_parity_bfa_policy.R` run one BFA spec
through the pipeline and through the app's module servers and compare the tables.
They need real data and run per release; `dev/batch_parity_bfa_policy.R
--fixture` uses the small data folder of the tests.

## For agents

1. Set `WISEAPP_DATA_PATH` (never print or write credentials). Copy the template
   with `wise_batch_template()`.
2. Write `spec.yaml` from the spec above. Include only the sections the task
   needs, and no more steps than asked.
3. Preview with `wise_spec_expand("spec.yaml")`. Fix every problem it lists. Check
   `nrow()` and the distinct stage ids: they set the cost.
4. Confirm with the user before a long or memory-heavy run (a Step 2 or 3 grid).
5. Run `Rscript run.R`. Do not edit `_targets/` by hand; use
   `targets::tar_invalidate()` to force a rerun.
6. Read `results/failures.parquet` and `manifest.json` (`n_failures`) before using
   any table, and report failures with the run ids they affect.
7. Read tables with `arrow::open_dataset()`, filter by `code` and the stage id,
   and join to `runs.parquet` for settings. Values are raw: round only for
   display.
