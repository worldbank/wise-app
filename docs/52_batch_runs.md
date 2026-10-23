---
id: batch
title: Batch runs
app_step: cross
depends_on: [notation, reproducibility, simulation, policy-framework]
symbols: []
guide: https://github.com/worldbank/wise-app-docs/blob/main/export.qmd
code: [R/fct_batch_spec.R, R/fct_batch_targets.R, R/fct_spec_defaults.R, R/fct_step1_tables.R, R/fct_step2_tables.R, R/fct_step3_tables.R]
verified_against: 8592a9d
---

# Batch runs

> A batch run executes Steps 0 to 3 without the interface, over a grid of samples and specifications, and writes aggregate tables. With the same specification and seed it gives the numbers that the app shows for the same settings. This page states what a batch run guarantees and what it leaves out. The specification, the tables and the commands are documented with the batch code, and not copied here.

## Setup

A batch run is defined by a **specification** file and, optionally, a **grid** that varies parts of it. The sections of the file decide how far a run goes: with no model section it produces survey and weather statistics, with a model section the Step 1 model, with a simulation section Step 2, and with a policy section Step 3. Each step needs the one before it.

Where the specification leaves a setting out, the run takes the app's default. The same functions that build the app's input of each step from its controls build it from the specification, so the methods of the pages in this folder apply to a batch run without change.

## Method

### 1. What is guaranteed

- **Same numbers as the app.** For a given specification and seed, the tables hold the numbers that the app shows for the same settings. This is checked against the app's own functions for one country, per release, on real data. It is not part of the automated tests that run on every change, except for a small fixture run.
- **Aggregates only.** Batch tables hold aggregate statistics. They never hold household-level results, maps or microdata.
- **Raw values.** Values are not rounded. Rounding is for display.
- **Reproducibility.** The seed drives every random draw, as in the app ([51_reproducibility](51_reproducibility.md)). A manifest records the versions of the package, R and DuckDB, a hash of the package lock file and a checksum of each local survey file. A check script compares a second machine with the manifest and lists what differs.

### 2. Caching by stage

Each stage of a run (the survey sample, a weather variable, a model fit, a simulation, a policy) has an identifier that is a hash of the parts of the specification it depends on. Runs with equal identifiers share the work, so a grid that varies only the policy runs the survey, the weather, the model and the simulation once. A stage is recomputed if its inputs change, or if a file that it read has been rebuilt. Every table carries the identifier of its stage, which is how results are joined to the settings of the runs that use them.

### 3. Tables

A run produces 11 tables, partitioned by country code, and the run-level files.

| Step | Tables |
|---|---|
| Statistics | variable statistics, interview dates, weather statistics |
| Step 1 | model terms, model fit, model covariance |
| Step 2 | annual, summary, simulated weather |
| Step 3 | the policy arm of annual and summary, decomposition, policy measures |

The baseline arm of the annual and summary tables is stored once for each simulation. The effect of a policy is the policy row minus the baseline row of the same scenario, metric, member and year, or the expected policy rows of the summary. The methods behind the columns are on the pages for each step: [32_metrics](32_metrics.md) and [33_uncertainty](33_uncertainty.md) for the statistics and bands, [44_decomposition](44_decomposition.md) for the decomposition. A few statistics exist only in batch (statistics by location sample, deciles for every variable, indicators).

### 4. Failures

A failed stage does not stop independent runs. It is listed in a failures table with the runs it affects and the reason, and any table that depends on it is not produced. A simulation that finishes without some climate models or scenarios keeps its tables and is flagged as a partial failure. A binary outcome or a logistic model has no policy contrast, so the policy tables are empty and flagged ([40_policy_framework](40_policy_framework.md), Section 4).

## Interpretation

- A batch table is a result of the same method as the app. All assumptions and limitations of the pages in this folder apply ([50_assumptions_limitations](50_assumptions_limitations.md)).
- Read the failures table and the manifest before a table is used. A missing row can mean a failed stage.
- A statistic that exists only in batch has no counterpart on a screen and was not checked against one.

## Assumptions

- **A1. Same data.** A comparison with the app, or with another batch, needs the same data folder and the same package versions.
- **A2. Complete weather.** A simulation uses every climate model that has full coverage of the scenario. There is no choice of models.

## Limitations and what is not modelled

- Random forest and gradient boosting are not available in batch.
- At most two weather variables, and one or two economies.
- Rules that the app applies from the data after its controls appear are not applied. In a policy run, a trigger variable, its direction and its return period must be stated, and a proxy means test needs its variable and cut-off.
- Household-level outputs and maps.

## In the app

Batch runs have no screen. The Export menu can write a configuration file that a batch specification starts from.

User guide: [Export and reproducibility](https://github.com/worldbank/wise-app-docs/blob/main/export.qmd). Batch documentation: [batch/README.md](../batch/README.md), [batch/docs/tables.md](../batch/docs/tables.md) and [batch/docs/spec_inventory.md](../batch/docs/spec_inventory.md).

## References

None. Full entries for other pages are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Specification, defaults, validation | Setup | `R/fct_batch_spec.R` `wise_spec_read()`, `wise_spec_expand()`; `R/fct_spec_defaults.R` `wise_spec_defaults()` |
| Start from an app configuration | Setup | `R/fct_batch_spec.R` `wise_spec_from_config()` |
| Runner and caching by stage | Section 2 | `R/fct_batch_targets.R` `wise_targets()`, `wise_batch_controller()`, `wise_batch_template()` |
| Step 0 and 1 tables | Section 3 | `R/fct_step1_tables.R`; `R/fct_step1_model_tables.R` |
| Step 2 tables | Section 3 | `R/fct_step2_tables.R` |
| Step 3 tables | Section 3 | `R/fct_step3_tables.R` `step3_batch_tables()` |
