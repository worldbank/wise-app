# Batch pipeline rebuild - plan

Status: Phases 1 to 4 implemented (2026-10-20); Phase 5 planned.
Supersedes: `docs/batch_pipeline.md` (legacy) and the scripts in `batch/`.

## 1. Goal

A programmatic way to run WISE-APP for many samples and specifications and
collect complete result tables for reports and papers. The same tables feed a
later post-processing step that can reproduce the app's figures or build
paper-specific ones. The pipeline should also serve as the "compute results"
stage of a paper's reproducibility package.

Principles:

- **Parity with the app, not with the legacy scripts.** A batch run with a
  given spec produces exactly the numbers the app shows for the same settings
  and seed.
- **One code path.** Batch and app modules call the same package functions; no
  reimplemented glue in batch.
- **Headless and serial per run.** No Shiny, no async coordinator, no UI
  state. Parallelism comes from running many runs at once.
- **Compute once.** Shared upstream work (data loads, weather, fits, Step 2
  payloads) is computed once and reused by every downstream run.
- **Tables first.** v1 publishes tidy tables only; figures are a later
  post-processing step on those tables.

## 2. Decisions taken

| Topic | Decision |
|---|---|
| Parity strategy | Extract module glue into shared package functions ("core") used by both modules and batch; parity tests compare the two. |
| Orchestration | `targets` (content-hash caching, DAG, dynamic branching; parallel workers via `crew`). |
| Location | Core + spec functions in the `wiseapp` package; a `targets` project template in the repo (`inst/batch/`), copied into a paper repo. The reproducibility package is the paper repo + a pinned `wiseapp` version. |
| Published outputs | Tidy parquet tables. Intermediate objects (fits, Step 2 payloads) live only in the `targets` store. |
| Figures | Deferred. Tables must be figure-complete (see 6.3) so app figures can be rebuilt from them later. |
| Compute | Laptop / workstation, local data, `crew` local workers. |
| Seeds | `seed` is a spec field, default `WISEAPP_DEFAULT_SEED`, so a default batch run equals a fresh app session. Coefficient uncertainty on/off is a spec setting as in the app. |
| Legacy scripts | Move to `batch/legacy/`, kept for reference only. Not a parity target. |
| Scope | Plan covers every step and every user-facing setting of the app. Phase 1 delivers survey and weather descriptive statistics (Step 0/1 data side). |

## 3. Current state

### 3.1 Legacy `batch/`

About 20 scripts. `04_run_sim.R` is about 2,000 lines and is copied once per
country (`04_run_sim_BFA.R`, `_BRA`, `_MWI`, `_SEN`, `_ZMB`), each with its own
configuration block. Each script reimplements the module glue (sample selection,
merge, fit, simulation, policy) and has already drifted from the app. Helper
files are in `batch/R/` (`batch_utils.R`, `expand_weather_specs.R`,
`aaa_load.R`).

### 3.2 App compute boundaries that already exist

| Step | Boundary | File |
|---|---|---|
| 0 | `load_overview_metadata()`, `build_connection_params` family, `load_data()` | `fct_overview_metadata.R`, `fct_connection.R`, `fct_load_data.R` |
| 1 | `build_selected_surveys()`, `build_selected_outcome()`, `build_selected_weather()`, `get_weather()`, `merge_survey_weather()`, `run_lasso_selection()`, `fit_model()` | `fct_sample.R`, `fct_outcome.R`, `fct_weather_select.R`, `fct_get_weather.R`, `fct_weatherstats.R`, `fct_fit_model.R` |
| 2 | `step2_compute(input, seed)` (pure, serial; validated input list) | `fct_step2_compute.R` |
| 3 | `step3_compute(svy, hs, ss, mf, ...)`, `.policy_metric_decomposition()` | `fct_step3_async.R`, `fct_policy_metric_decompose.R` |
| Export | `wise_config_snapshot()` (config JSON, input-id keyed), `wise_export_table()` registry, `wise_provenance()` | `fct_export.R`, `fct_provenance.R` |

### 3.3 The gap

The code that turns user settings into the arguments of these boundaries
still lives inside module servers. Examples:

- Step 2 (`mod_2_01_weathersim.R`, around lines 1002-1050): `sim_dates` from
  `build_hist_sim_dates()`, `fp_list` from future periods, SSP list,
  `perturbation_method`, residuals forced to `"none"` for RIF, the baseline
  survey subset, `stored_breaks`, `skip_coef_draws`.
- Step 1 (`mod_1_03`, `mod_1_05`, `mod_1_06`): outcome transformation and
  poverty line, LCU/PPP conversion, weather merge, bin breaks, lasso settings,
  covariate and FE assembly before `fit_model()`.
- Step 3 (`mod_3_01`-`mod_3_06`): lever configs (`sp_cfg`, `infra_cfg`, ...)
  built from inputs, model variable list, analysis unit, seed.
- Tables: each `wise_export_table(key, fun = ...)` closure builds a table from
  reactive state inside a module.

If batch reimplements this glue, it drifts again. Closing this gap is the core
of the work.

## 4. Architecture

Four layers, top to bottom.

```
 spec file (YAML)  /  app config JSON
            |
            v
 [L1] run spec: wise_spec  (validate, normalise, hash, expand grid)
            |
            v
 [L2] shared core (package)  <---- used by Shiny modules too
      prepare_* -> step boundaries -> tables_*
            |
            v
 [L3] targets template (inst/batch/): stage-level dedup + caching + crew
            |
            v
 [L4] results store: parquet tables + runs catalogue + manifest
            |
            v
 [L5] (deferred) post-processing: app figures and paper figures from tables
```

### 4.1 L1 - Run spec

One canonical, plain-list description of a single leaf run. It is defined in
the package so modules, config import and batch all use it.

Sections, one per pipeline stage:

| Section | Contents (examples) |
|---|---|
| `source` | connection type and location (no credentials; those come from env vars) |
| `sample` | unit (`hh`/`ind`/`firm`), countries, survey years per country, pooled flag |
| `outcome` | variable, currency, poverty line, transformation |
| `weather` | named variable specs: reference window, aggregation, transformation, binning, breaks |
| `model` | engine, model type, taus, FE, covariate method (user list or lasso + lasso settings), interactions |
| `sim` | historical years, future periods, SSPs, residuals, coefficient uncertainty, baseline survey |
| `policy` | named lever configs (SP regular or shock, infra, digital, labor, education) |
| `seed` | integer, default `WISEAPP_DEFAULT_SEED` |

Functions (names indicative):

- `wise_spec(...)` / `wise_spec_defaults()`: build a spec. Defaults are the
  app's defaults and live here only; modules read them from here too, so an
  untouched UI control and an omitted spec field mean the same thing.
- `wise_spec_validate(spec)`: same rules as the UI (allowed values,
  engine/model-type compatibility, RIF residuals, and so on).
- `wise_spec_hash(spec, stage)`: a hash per stage prefix (`data` = source +
  sample + outcome; `weather` = data + weather; `fit` = weather + model;
  `sim` = fit + sim; `policy` = sim + policy). These keys drive deduplication
  and identify rows in result tables.
- `wise_spec_from_config(json)`: translate an app config export
  (`wise_config_snapshot()`, input-id keyed) into a spec. It lives in the core
  next to the module code that owns those input ids, so renaming an input
  breaks a test rather than silently dropping a setting.
- `wise_spec_to_config(spec)` (later): load a batch spec into the app to
  inspect a run interactively.

### 4.2 Grid authoring (recommended format)

A YAML file with named profiles, axes and crossing rules. It compiles to a
list of run specs. `wise_spec_expand(file)` returns that list as a data frame
(one row per run, columns = profile labels + hashes) so a grid can be checked
before anything runs.

```yaml
base: configs/bfa_baseline.json      # optional app config export
seed: 20240101

profiles:
  weather:
    t_r_12m:
      t: {ref_start: 1, ref_end: 12, transformation: none}
      r: {ref_start: 1, ref_end: 12, transformation: none}
    t_r_3m_bins:
      t: {ref_start: 1, ref_end: 3, transformation: binned, n_bins: 10}
      r: {ref_start: 1, ref_end: 3, transformation: binned, n_bins: 10}
  fixed_effects:
    year_admin1: [year, gaul1_code]
  covariates:
    basic: {method: user, vars: [hhsize, urban]}
    lasso: {method: lasso}
  policy:
    none: {}
    cash_20pct: {sp: {type: regular, targeting: poorest, share: 0.2}}

axes:                                  # crossed unless listed under zip
  country: [BFA, MWI, SEN]
  weather: [t_r_12m, t_r_3m_bins]
  model: [{engine: fixest, type: linear}, {engine: rif, taus: [0.1, 0.5, 0.9]}]
  fixed_effects: [year_admin1]
  covariates: [basic, lasso]
  policy: [none, cash_20pct]

exclude:
  - {model.engine: rif, covariates: lasso}
```

Three ways to author, one internal form:

1. YAML grid (main route for papers).
2. App config JSON as `base:`. Explore in the app, export, then vary axes in
   batch.
3. An R list passed to `wise_spec()` (scripting and tests).

### 4.3 L2 - Shared core

Package functions, Shiny-free, one per stage. Each takes the spec section
plus upstream objects and returns plain objects. Module servers are
refactored to call them, so modules keep only UI concerns (reactivity,
progress, async submission, rendering).

| Stage | Core function (indicative) | Wraps |
|---|---|---|
| Data | `wise_prepare_data(spec, cp, metadata)` -> survey frame, selected surveys, selected outcome | sample, outcome, LCU/PPP, bottom-coding |
| Weather | `wise_prepare_weather(spec, data, cp)` -> selected weather, survey-weather frame, breaks | `build_selected_weather()`, `get_weather()`, `merge_survey_weather()` |
| Fit | `wise_fit(spec, weather_data)` -> model fit (incl. lasso selection) | `run_lasso_selection()`, `fit_model()` |
| Sim | `wise_step2_input(spec, fit, weather_data, cp)` -> input list; then `step2_compute()` | glue now in `mod_2_01` |
| Policy | `wise_step3_input(spec, ...)` -> args; then `step3_compute()` and metric decomposition | glue now in `mod_3_0x` |
| Tables | `wise_tables_<stage>(...)` -> named list of tidy data frames | bodies of the `wise_export_table()` closures |

The table builders are the key to parity for outputs: each app export table
and each figure's data source becomes a core function, and the module's
`wise_export_table(fun = ...)` calls it. Batch calls the same function.

Async paths stay app-only. Batch calls `step2_compute()` and
`step3_compute()` serially with `weather_storage = "memory"`.

### 4.4 L3 - targets template

`inst/batch/` holds a template project:

```
_targets.R          # 10 lines: library(wiseapp); wise_targets("spec.yaml")
spec.yaml           # grid
run.R               # tar_make() with crew controller settings
README.md
```

`wise_targets(spec_file, out_dir)` is a target factory in the package. It
builds a DAG with one dynamic branch per unique stage hash, not per run:

```
specs ─> data[data_hash] ─> weather[weather_hash] ─> fit[fit_hash]
                                                      ├─> sim[sim_hash] ─> policy[policy_hash]
                                                      └─> tables_step1
          tables_* at each stage ─> write parquet (per table type)
```

So 3 countries x 2 weather x 2 models x 2 covariates x 2 policies = 48 runs
need only 3 data loads, 6 weather builds, 24 fits and 24 Step 2 runs. Changing
a policy profile reruns only the policy branches. Failures are recorded per
branch (`error = "continue"`) and collected into a failures table.

Laptop settings: `crew_controller_local(workers = n)`. Each worker has its own
DuckDB, so the template sets `WISEAPP_DUCKDB_MEMORY_LIMIT`,
`WISEAPP_DUCKDB_THREADS` and `WISEAPP_THREADS` per worker from one setting
(cores / workers). Weather uses the existing disk cache
(`WISEAPP_WEATHER_CACHE_DIR`) shared across workers.

### 4.5 L4 - Results store

```
out_dir/
├── runs.parquet               # one row per leaf run: run_id, stage hashes, profile labels, flattened spec
├── specs/<run_id>.json        # full normalised spec per run (re-runnable, importable)
├── tables/                    # one parquet dataset per table, partitioned by country;
│   ├── survey_summary/        # full list in batch/docs/tables.md section 3
│   ├── model_terms/
│   ├── annual/
│   ├── summary/
│   ├── decomposition/
│   └── ...
├── failures.parquet           # stage, hash, run_ids affected, classified message
└── manifest.json              # wiseapp version + git sha, R, duckdb, renv.lock hash, data source digest, timestamps
```

Table rules:

- Every table carries the stage hash it depends on (`fit_hash`, `sim_hash`,
  ...), and joins to `runs.parquet` for labels. Tables are not duplicated per
  leaf run: a Step 1 table is stored once per `fit_hash` even if 8 policies
  use that fit.
- Raw values, not display-rounded (same rule as the app's CSV export).
- Long format with stable column names documented in one table catalogue
  (`batch/docs/tables.md`, generated from the core table builders).
- Schema version field in the manifest; table builders own their schema.

### 4.6 L5 - Post-processing (deferred)

Out of scope for v1. The tables are designed so this layer is a pure function
of the tables:

- Reproduce an app figure: `echart_*(table)` or the ggplot reference builder
  on the stored table.
- Paper figures and tables: user code reading the parquet datasets (`arrow`,
  `duckdb`, `polars`).

## 5. Parity strategy

1. **Shared core.** Modules and batch call the same functions (4.3), so the
   main risk shrinks to "did the module pass the same settings".
2. **Spec round-trip tests.** For each step: drive the module with
   `shiny::testServer()` on a fixture, capture `wise_config_snapshot()`,
   convert with `wise_spec_from_config()`, run the core, and compare the module's
   export tables with the batch tables using `identical()` (or a documented
   tolerance where the app itself is nondeterministic, which should be none).
3. **Defaults in one place.** UI controls take their initial values from
   `wise_spec_defaults()`.
4. **Seeds.** Document and reuse the app's seeding per stage (which RNG calls
   happen in which order for lasso, residual draws, policy survey draws and
   shock forecasts). Batch must reproduce the same order; inventory is a
   Phase 0 task.
5. **Real-data parity check.** A `dev/` script runs one BFA spec through the
   headless app (`dev/ui_drive.R` + config import + Export bundle) and through
   batch, then diffs the tables. It runs per release, not in CI.

## 6. Phases

### Phase 0 - Preparation (no app code changes)

Progress (2026-10-19): legacy scripts moved to `batch/legacy/`;
`docs/batch_pipeline.md` marked legacy; input inventory in
`batch/docs/spec_inventory.md`; output table catalogue in
`batch/docs/tables.md` (D1-D4 decided; 19 consolidated result tables
proposed, with a legacy comparison). Scope rule added: aggregate results
only, no observation-level results, no maps, no underlying data. Draft user
README in `batch/README.md`. Seed recommendation (route the session seed to
lasso, K-means bins and display residuals; no change at the default seed) in
`batch/docs/spec_inventory.md` section 6.

Update (2026-10-19, second round): seed change implemented in the app (see
inventory section 6). Table set consolidated to 11 result tables, with
batch-only legacy statistics and per-year decomposition (`batch/docs/tables.md`
sections 3, 5 and D5). Phase 2 gains one app task: split
`weather_effect_data()` out of `echart_weather_effect_plot()`.

Phase 0 complete (2026-10-19). The input inventory and table catalogue moved
to `batch/docs/` as the lasting batch references; this plan stays in
`review/`. The optimization work has landed, so the core extraction can start.

- Move `batch/*` to `batch/legacy/`; mark `docs/batch_pipeline.md` as legacy
  and point it at this plan.
- Inventory per step: every user-facing input -> spec field -> boundary
  argument, with the app default and where the glue lives now. Output:
  `batch/docs/spec_inventory.md`. This becomes the spec schema.
- Inventory of export tables and figure data sources per module (the
  `wise_export_table()` keys plus each `echart_*` input) -> table catalogue
  draft.
- Seed and RNG order inventory (5.4).
- Agree on the timing of app edits with the optimization agent.

### Phase 1 - Spec, runner and Step 0/1 descriptives

- `wise_spec*` functions for the `source`, `sample`, `outcome` and `weather` sections;
  YAML grid compiler; `wise_spec_from_config()` for those sections.
- Core: `wise_prepare_data()`, `wise_prepare_weather()`; table builders for
  survey stats (mod_1_02: summary, missingness, interview dates, location
  coverage) and weather stats (mod_1_05: weather stats table, distributions,
  by-location summaries, historical comparison).
- Refactor `mod_1_01`-`mod_1_05` to call the core.
- `wise_targets()` factory + `inst/batch/` template; results store, runs
  catalogue, manifest, failures table.
- Parity tests for the above; template smoke test on the test fixture.

Progress (2026-10-19): done as planned, with these differences.
- Shared core: `R/fct_step1_data.R` (survey load and preparation, outcome
  data, weather fetch, merge and historical cells) with the control defaults
  in `R/fct_spec_defaults.R`. `mod_1_01` to `mod_1_05` call them. The weather
  controls render byte-identical HTML before and after. The H3 map data and
  location panel join of `mod_1_02` stay in the module (Phase 2 moves the
  panel join when the model needs `loc_id_panel`).
- Tables: `variable_stats`, `interview_dates`, `weather_stats`
  (`R/fct_step1_tables.R`; reference in `batch/docs/phase1_tables.md`). The
  `weather_stats` builder calls the app's `build_weather_stats_table()`
  (survey rows). Schema deviations from the draft are listed in
  `batch/docs/tables.md`. Decisions made while building: a location is
  country + `loc_id` across waves (the panel locations repeat across waves in
  the real data); deciles use `outcome_summary_wide()`'s rule everywhere;
  `wxvar_id` excludes binning; rows with `n = 0` are kept.
- Spec: `R/fct_batch_spec.R` (`wise_spec`, `wise_spec_validate`,
  `wise_spec_resolve`, `wise_spec_ids`, `wise_spec_expand`,
  `wise_spec_from_config`, JSON read and write). Sections `source`,
  `sample`, `outcome`, `weather`, `stats`; later sections are rejected by
  name. Defaults are resolved when the grid is read; `outcome.name` follows
  its rule once the survey is loaded.
- Runner: `R/fct_batch_targets.R` (`wise_targets()`) and `inst/batch/`
  (`wise_batch_template()`). Branches per `data_id` and `wxvar_id`; the
  prepared survey is passed between stages as a file in the targets store
  (`_targets/user/data/`). Branch functions catch their errors and return a
  failure record, so `error = "continue"` is not needed for the branches.
  `targets`, `crew` and `yaml` are in Suggests.
- Tests: spec (`test-fct_batch_spec.R`), tables with module parity
  (`test-fct_step1_tables.R`), end-to-end pipeline on a fixture data folder
  (`test-batch-pipeline.R`). Real data: `dev/batch_parity_bfa.R` (BFA, two
  waves, weather `t` binned and `r` continuous) passes against the module
  servers' tables; it does not use the Export download.
- Open for Phase 2: (1) the data stage must load the H3 files and join the
  location panel (`loc_id_panel`) for clustered inference, which moves that
  block out of `mod_1_02`; (2) `outcome.name` follows its default rule after
  the survey is loaded, so `data_id` does not encode the resolved outcome;
  resolve it at grid time if fit ids need it; (3) the real-data check drives
  the module servers, not the Export download, so the per-release check
  against a headless-app export bundle is still to do; (4) per-stage worker
  controllers for the memory-heavy stages; (5) the pool rule for a
  two-country model (the Phase 1 tables label it `A+B`).

### Phase 2 - Step 1 model fits

- Spec `model` section: all engines and model types, FE, covariates (user list
  and lasso), interactions, taus, pooled samples.
- Core `wise_fit()`; table builders for coefficients, fit stats, headline and
  results tables (mod_1_07, mod_1_08), lasso selection.
- Refactor `mod_1_06`-`mod_1_08`; parity tests.

Progress (2026-10-19): Phase 2 implemented with the scope below.
- Decisions (taken before the work): `outcome.name` and the default model type
  resolve at grid time from the survey columns, so `data_id` and `fit_id`
  encode them; a two-economy model is one pooled fit labelled `A+B` (sorted
  codes); fixest (linear, logistic) and RIF only; interactions and
  `model.policy_vars` wait for Phase 4; one crew controller until Step 2;
  real-data check against the module servers, not the Export download.
- Shared core: `R/fct_step1_model.R` (Lasso, specification, `wise_fit()`,
  `wise_model_from_spec()` for batch), `R/fct_step1_model_tables.R`
  (translated effects and the three table builders), the location panel in
  `R/fct_step1_data.R`. `calc_fit_stats()` and `echart_importance()` split into
  raw data (`fit_stats_raw()`, `importance_shares()`) plus display.
  `mod_1_02`, `mod_1_06` and `mod_1_07` call them; the rendered module output
  (UI strings, coefficients, Lasso selection) is identical before and after.
- Spec: a `model` section (absent = no fit), grid profile groups `model`,
  `fixed_effects` and `covariates`, config import of the Model tab inputs,
  `weather_id` and `fit_id`. Covariates are a flat list (the level follows from
  the variable list); a user list and fixed effects are sorted for hashing.
- Runner: stages `frame` (merged survey-weather frame per `weather_id`) and
  `fit` (per `fit_id`), tables `model_terms`, `model_fit`, `model_vcov`;
  the data stage joins the location panel. A grid without a model gets one
  inert item per stage (a target cannot branch over an empty one). The fit
  objects themselves are not kept: Phase 3 decides whether to persist them or
  refit.
- Tests: `test-fct_step1_model.R` (core, tables, module parity),
  spec section tests, pipeline tests (tables, reuse, failure record, Lasso).
  Real data: `dev/batch_parity_bfa_models.R` (BFA, linear fixest with a user
  covariate list and with Lasso covariates) passes against the module servers:
  Lasso case bit-identical, user list equal to 1e-16 (term order).
- Not done: `weather_effect_data()` (the data step of
  `echart_weather_effect_plot()`) is not split out - it is a chart refactor of
  a 1,200-line function in a protected-looking area, and the stored inputs are
  the ones it reads. Ranger and xgboost engines. The headless-app Export
  bundle comparison (module servers register the same tables).
- Open for Phase 3 and 4: (1) persist or refit the fit for Step 2; (2)
  interactions and `policy_vars` (moderator values go to `model_fit`
  `effect_inputs`); (3) `weather_effect_data()` split; (4) the statistics
  options are part of `data_id`, so editing them reruns fits (tables.md
  section 2 defines it so; a `frame_id` without them would avoid it); (5)
  per-stage crew controllers for Step 2; (6) the Export-bundle check.

### Phase 3 - Step 2 simulation

- Spec `sim` section; core `wise_step2_input()`; tables for aggregates,
  exceedance and return periods, threshold tables, diagnostics (mod_2_02,
  mod_2_03), with full curve data for figures.
- Refactor `mod_2_01` glue; parity tests.

Progress (2026-10-19): Phase 3 implemented with the scope below.
- Decisions (taken before the work): the slim fit (`step2_slim_model_fit()`)
  is persisted per `fit_id` as a qs2 file in the targets store and the sim
  branch reads it, no refit; `weather_effect_data()` stays deferred; the
  statistics options stay in `data_id`; the Step 2 stage gets its own crew
  controller (`sim`, 1 worker by default, `memory = "transient"`); `sim.residuals`
  and `sim.coef_uncertainty` are spec fields at the app defaults and RIF forces
  residuals to `none`; `annual` has one row per member and year, no cap;
  interactions and `policy_vars` wait for Phase 4. The spec does not choose
  climate models: every model of the projection files with full coverage is a
  member, as in the app (the question recommended a member list; the app has none).
- Shared core: `R/fct_step2_input.R` (baseline survey, periods, scenarios,
  residual rule, model snapshot: `wise_step2_input()`) and `R/fct_step2_tables.R`
  (the views of `mod_2_02` as pure functions, the aggregation of a run and the
  table builders). `mod_2_01` builds its worker snapshot and its debugging-path
  call with `wise_step2_input()`, and reads its initial control values from
  `wise_default_sim()`; `mod_2_02` calls the view functions from its reactives;
  `mod_2_03` needed no change (the support summary was already a pure
  function). Rendered module output is identical before and after: the sidebar
  HTML, the async snapshots and sync-call arguments (fixest, RIF,
  historical-only, resampled residuals, several baselines) and every Results
  reactive for six metric, deviation and band settings; the full suite
  passes. Mechanics: a clean worktree of HEAD against the working tree.
- Spec: a `sim` section (absent = no simulation), grid profile group `sim`,
  config import of the Step 2 sidebar inputs, `sim_id`, the baseline survey
  resolved at grid time (the latest wave of each economy).
- Runner: stages `sim` (per `sim_id`) after `fit`; the fit stage keeps the slim
  fit; `wise_batch_sim()` builds the input with `wise_step2_input()`, runs the
  serial `step2_compute()` (weather in memory, no async code) and keeps only the
  tables `annual`, `summary`, `sim_weather`. `wise_batch_controller(sim_workers =)`
  returns a controller group; the sim branches use the `sim` controller when the
  pipeline defines one. Failures are recorded per simulation; lost climate
  models are listed as `partial_simulation_failure`.
- Tests: `test-fct_step2_input.R` (input, module parity), `test-fct_step2_tables.R`
  (module parity of every view for every metric, the three tables),
  `test-fct_batch_spec.R` (sim section), `test-batch-pipeline.R` (fixture with
  CMIP6 files: tables, parity with the core, reuse, failure record, controller).
- Real data: `dev/batch_parity_bfa_sim.R` (BFA, linear fixest with a user
  covariate list, `sim: {}`: 1991-2020 weather, SSP3-7.0 for 2025-2035, 20
  climate models) against the module servers. Batch alone: 26 s for the whole
  pipeline, the Step 2 branch 18 s, R heap peak 1.8 GB, process peak
  resident set 2.6 GB; 5,670 `annual`, 505 `summary` and 48 `sim_weather` rows.
  Results of the comparison: see `batch/docs/phase3_tables.md` notes and the
  report of the session.
- Findings: (1) the ensemble band of `summary` is stored at p10-p90 although
  the pane starts at `none` (D3 names the band p10-p90; `none` has no spread);
  (2) the Results pane aggregates a metric with the metrics of its group, the
  streamed (async) tables and the batch aggregate all metrics in one call; the
  results agree to about 1e-15; (3) the inline Step 2 join in `fct_simulations.R`
  is many-to-many by construction and dplyr warns about it (the app too);
  batch mutes that one warning; (4) the batch stage items for survey and frame
  carry file paths, not content stamps, so a rebuilt data file does not rerun
  the stages that read it (the sim items carry size and time stamps).
- Not done: `weather_effect_data()`, the Export-bundle comparison, storing the
  Step 2 run (hundreds of MB per `sim_id`).
- Open for Phase 4: (1) the policy stage needs the Step 2 pipelines: persist
  the run per `sim_id` (0.4-0.6 GB at BFA 2x2) or repeat it; (2) interactions and
  `policy_vars` (the moderator values go to `model_fit` `effect_inputs`); (3)
  `weather_effect_data()`; (4) the Export-bundle check; (5) a `frame_id` without
  the statistics options; (6) content stamps for the earlier stage items.

### Phase 4 - Step 3 policy

- Spec `policy` section, all levers including shock-responsive SP (Phase 2
  fields) and cost-effectiveness; core `wise_step3_input()`; tables for
  results, diagnostics, decomposition (metric-aware), shock summary,
  cost-effectiveness.
- Refactor `mod_3_01`-`mod_3_10` glue; parity tests.

Progress (2026-10-20): Phase 4 implemented with the scope below.
- Decisions (taken before the work): the Step 2 run of a simulation with a
  policy is stored per `sim_id` as a qs2 file in the targets store and read by
  the policy branches (deleted when the `sim_id` leaves the grid;
  `wise_targets(keep_step2 =)` keeps or drops it after the run); interactions
  and `policy_vars` are part of the model section, with the moderator values in
  `model_fit` `effect_inputs`; one `policy_id` per policy profile (all levers
  together); shock-responsive SP and cost-effectiveness are included; the
  decomposition keeps the per-year channel sums and weights and the
  metric-aware rows (long, per metric and channel), and every weather-year
  basis and unit derives from them; Step 3 runs serially under the R default
  generator with the seed of the Step 2 run; the policy branches share the
  `sim` controller (one worker by default).
- Shared core: `R/fct_step3_input.R` (lever configurations from control values,
  `wise_step3_input()`, `wise_policy_configs()` for the spec) and
  `R/fct_step3_tables.R` (the Results-pane views of a policy run as pure
  functions, the diagnostics and cost-effectiveness helpers, and
  `step3_batch_tables()`). `mod_3_01` to `mod_3_05` build their scenario with
  the lever functions, `mod_3_06` the `step3_compute()` arguments and the
  published policy frame, `mod_3_07` (`.wire_results_pane()`) takes its series,
  threshold and paired-effect reactives from the view functions, `mod_3_08` and
  `mod_3_10` call the effectiveness, input-summary and cost-effectiveness
  helpers. Checked before and after the switch: the 25 lever scenarios of the
  five modules for regular and shock-responsive SP, both units and both
  currencies are `identical()`; the Step 3 module tests and the pane
  characterisation tests pass unchanged.
- Spec: a `policy` section (levers `sp`, `infra`, `digital`, `labor`,
  `education`, each a flat list of control ids that starts from the controls'
  initial values; a test compares `wise_default_policy()` with the rendered
  controls), `model.interactions` and `model.policy_vars`, grid profile group
  `policy` (a profile replaces the whole policy) and dotted lever paths as
  axes, config import of the Step 3 controls (`step3-<lever>-<id>`), the Model tab
  interactions and policy scenario, and `policy_id`. Section order is now
  canonical.
- Runner: stage `policy` (per `policy_id`) after `sim`; the sim branch writes the
  Step 2 run when a policy needs it, the fit file also carries the model
  variables; `wise_batch_policy()` builds the lever configurations, runs the
  serial `step3_compute()` and `step3_batch_tables()`. Tables: the policy arm of
  `annual` and `summary`, `decomposition`, `policy_measures`
  (`batch/docs/phase4_tables.md`). Failures per policy; a binary outcome or a
  view that failed for a metric is a `partial_policy_failure`.
- Tests: `test-fct_step3_input.R` (lever configs, spec defaults against the
  rendered controls, module versus spec route), `test-fct_step3_tables.R` (schema,
  the Results pane driven by `shiny::testServer()` against the stored values for
  two metrics, the compact channels), `test-fct_batch_spec.R` (policy and model
  sections, grid, config import), `test-fct_step1_model.R` (interactions and
  policy scenario against the Model tab, moderator rows), `test-batch-pipeline.R`
  (regular and shock policies end to end, reuse, the stored Step 2 run).
- Real data: `dev/batch_parity_bfa_policy.R` (BFA; regular and shock transfers)
  against the module servers (Steps 1 to 3 in one test server). `--fixture` runs
  the same comparison on the small test data folder: all checks pass (paired
  effects and bands, annual effects, adverse years, headline cards, incidence,
  cost-effectiveness, shock summary and rows, to 1e-10). The BFA run itself was
  not possible in the session that implemented the phase (the data folder was
  not reachable); see the report of that session for the status.
- Findings: (1) several controls move after they render (trigger direction from
  the response check, return period from the record length, `trigger_level`
  fallback): batch does not apply them, a spec states the values; (2) the
  Results line of a non-poverty metric is undefined, so the effectiveness and
  reach tables use the outcome's own poverty line, else 3.00; (3) the app labels
  the historical arm with its years, the tables use `Historical`; (4) the app's
  interaction default (`urban`) is not the spec default (none), which keeps the
  ids of earlier phases.
- Not done: the Export-bundle comparison, `weather_effect_data()`, per-stage
  controllers beyond `sim`, content stamps for the earlier stage items.

### Phase 5 - Post-processing and reproducibility package

- Figure reproduction helpers from stored tables.
- Reproducibility package template: pinned `wiseapp` version, `renv.lock`,
  data source digest, spec files, `tar_make()` entry point, README.
- Optional: model and spec selection grids (legacy `02a`/`03a`) as
  post-processing on Step 1 tables.

## 7. Risks and open questions

- **Concurrent app work.** The core refactor touches module servers that the
  optimization agent may be editing. Sequence Phase 1 refactors after that work
  lands, or agree on file ownership.
- **Hidden UI state.** Some module behaviour depends on `renderUI()` timing or
  defaults that are set only in the UI. The inventory must surface these;
  each becomes an explicit spec default.
- **`year` type contract** (AGENTS.md, CR-CQ-07). The core must keep the
  per-stage `year` types exactly as the modules have them.
- **Table size.** Some figure data (per-household or per-draw) may be large.
  Decide per table whether to store full data, quantiles or a sample, and
  document the choice in the catalogue.
- **Memory on a laptop.** Step 2 payloads are hundreds of MB. Use the
  `targets` store format `qs`, keep the worker count low for Step 2/3 branches
  (separate crew controllers per stage), and set `memory = "transient"`.
- **Config JSON versioning.** Input ids are UI details. `wise_spec_from_config()`
  must check `wiseapp_config_version` and the app version, as `.import_validate()` does.
- **Pooled samples** change the data/fit keys (a pool is one "country"). Needs
  a spec rule for pool labels.
- **Databricks / cloud runs** are out of scope for v1. The connection layer
  already supports them, so this is mainly a template variant.
