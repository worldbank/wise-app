---
id: reproducibility
title: Seeds, run provenance and exports
app_step: cross
depends_on: [notation, framework, simulation, policy-framework]
symbols: []
guide: https://github.com/worldbank/wise-app-docs/blob/main/export.qmd
code: [R/utils_math.R, R/fct_provenance.R, R/fct_export.R, R/fct_aggregation.R, R/fct_policy_sim.R, R/fct_step2_compute.R]
verified_against: 8592a9d
---

# Seeds, run provenance and exports

> A result of the app can be repeated. One base seed fixes every random draw, each draw has its own stream so that changing one choice does not change another, and every export carries a record of the settings, the seed and the data source that produced it. This page describes how, at the level of method. The screens are in the user guide.

## Setup

Some parts of the method are random: the choice of residuals in Step 2, the households that gain access to a service in Step 3, the targeting errors of a cash transfer, the forecasts of an anticipatory programme, the folds of the variable selection, and the centres of k-means bins. The app makes all of them functions of one **base seed**, with a default of 123, which the user can change. Two runs with the same data, the same settings and the same seed give the same results.

## Method

### 1. Streams derived from one seed

Each random component has its own stream. The seed of a stream is a hash of the base seed and the labels that identify the component:

$$\text{seed}_k = \Big(h\big(\text{base seed},\ \text{label}_{k,1},\ \text{label}_{k,2},\dots\big) + |\text{base seed}|\Big) \bmod \big(2^{31} - 2\big) + 1 \qquad \text{(1.1)}$$

where $h$ is a hash value computed from the seed and the labels joined as text. The labels name the kind of draw and its context. Some examples:

| Draw | Labels |
|---|---|
| Residuals of a simulation year | "residual" and the simulation year |
| Residual of a household that is not in the estimation sample (original rule) | "original-unmatched", with a choice keyed by the household's identifier |
| Households that gain or lose access to a lever | "policy" and the lever's variable |
| Eligibility and targeting errors of a cash transfer | "policy" and "sp" |
| Forecast, dynamic-targeting and ranking draws of a shock-responsive programme | "policy", the stream and the simulation year (and the survey row or cell) |
| Variable selection (folds, imputations) | "lasso" and the step |

Three properties follow.

- **Independence.** Switching one lever on or off, or adding a scenario, does not change the households chosen for another lever, or the residuals of another year.
- **Shared draws.** The residual draws depend only on the base seed and the year. The historical series, every scenario and every climate model use the same draws ([30_simulation](30_simulation.md)), and the policy arm uses the draws of the baseline ([40_policy_framework](40_policy_framework.md)). Differences between runs come from weather or policy only.
- **Independence from order and chunking.** Draws that are keyed by household, cell and year do not depend on the order of the rows or on how a run is split into chunks. A run on a worker process uses the same random number generator as a run in the main process, so the two agree.

### 2. What else a result depends on

The seed does not fix everything. A result also depends on:

- the data, including the version of the survey, the climate files and the CPI and PPP table;
- the versions of the app and of the packages it uses. The DuckDB version is pinned exactly, because the bundled extensions are built for it;
- the settings in the Step 1, 2 and 3 controls.

Numerical results can differ in the last digits across machines or thread settings. The app does not promise bit-for-bit equality across platforms. It tests that repeated runs with the same inputs give the same results.

### 3. Run provenance

For every step that has results, the app builds one record of what produced them. The record reads the stored result of the step and its settings at the time of the run, not whatever is selected when the record is read. It holds:

- the step and a short **run signature**: a digest of the full list of inputs that the run used, so that two exports can be compared at a glance;
- the random seed and the version of the app;
- the data source, as a type (for example local or a named cloud service) and whether it came from the server configuration or the user interface. Hosts, buckets, paths and credentials are never included;
- the survey version, the outcome, the weather pipeline, the model specification (type, engine, interactions, fixed effects, covariates, selection method, clustering) and the number of observations;
- any **fallback**: a place where the fitted specification differs from the requested one, with the reason.

### 4. Exports and restore

The Export menu offers a full bundle, the configuration alone, the tables alone and the figures alone. The bundle holds:

- a **configuration file** with the version of the file format, the date, the app and R versions, the random seed, the provenance records and the values of the controls. It contains settings and no microdata. Controls that carry no setting (buttons, table selections, map views) are left out;
- every table as a CSV file and every figure as a PNG file;
- a **manifest** that lists every file with its step, format, dimensions and description, and a README that explains the files and the provenance.

To restore an analysis, the app reads a configuration file, checks that it is a configuration of this app and that its format is not newer than the one the app reads, and then sets the controls. A different app version is accepted with a note that settings may differ. The data source must be connected first, because the available surveys and variables come from it.

## Interpretation

- Changing the seed shows how much of a result depends on random draws. Aggregate results should be stable across seeds. If a result changes materially with the seed, the random component (for example, a lever that reaches a small share of units in a small sample) is too large for the question.
- The seed does not make a result correct. It makes it repeatable.
- To repeat an analysis in a new session, export the configuration, record the app version, and reconnect to the same data.

## Assumptions

- **A1. Same inputs.** Repeating a result needs the same data files and the same package versions, in addition to the seed.
- **A2. Stable random number generator.** The random number generator of R, and the functions that draw from it, behave in the same way across the versions used.

## Limitations and what is not modelled

- Bit-for-bit equality across platforms.
- Versioning of the data itself: the provenance record names the survey version and the source type, not a file checksum. Batch runs record file checksums ([52_batch_runs](52_batch_runs.md)).
- Reproducing a run from the exported tables. Tables are results, and not inputs.

## In the app

- Export menu in the top bar: Export all (.zip), Configuration only (.json), Export tables (.zip), Export figures (.zip) and Import configuration.
- The summary cards at the top of each results tab record the settings behind its result.

User guide: [Export and reproducibility](https://github.com/worldbank/wise-app-docs/blob/main/export.qmd).

## References

None. Full entries for other pages are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Base seed and its default | Setup | `R/utils_math.R` `WISEAPP_DEFAULT_SEED`; `R/fct_export.R` `wise_current_seed()` |
| Stream seed from labels | (1.1) | `R/utils_math.R` `wise_seed()` |
| Residual draws by year | Section 1 | `R/fct_aggregation.R` `draw_residuals_vec()`; `R/fct_step2_compute.R` `.step2_run_seed()` |
| Policy draws by lever | Section 1 | `R/fct_policy_sim.R` `apply_policy_to_svy()` |
| Provenance record | Section 3 | `R/fct_provenance.R` `wise_provenance()`, `.provenance_digest()`, `.provenance_model_spec()` |
| Source description without credentials | Section 3 | `R/fct_provenance.R` `.provenance_source_label()`, `.provenance_source()` |
| Configuration snapshot | Section 4 | `R/fct_export.R` `wise_config_snapshot()`, `.export_keep_input()` |
| Import checks | Section 4 | `R/fct_export.R` `.import_validate()`, `wise_config_apply()` |
| Bundle, manifest and README | Section 4 | `R/fct_export.R` `wise_export_bundle()`, `.export_manifest_df()`, `wise_export_readme()` |
