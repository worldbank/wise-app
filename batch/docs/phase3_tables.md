# Phase 3 tables - column reference

Status: implemented (2026-10-19). Part of `review/batch_pipeline_plan.md`.
These are the three Step 2 tables: `annual`, `summary` and `sim_weather`. The
catalogue of all planned tables is `batch/docs/tables.md`; the builders are in
`R/fct_step2_tables.R`, and the run they describe is made by `step2_compute()`
from the input that `wise_step2_input()` (`R/fct_step2_input.R`) builds, the
function the simulation sidebar calls.

Every table is a parquet dataset in `results/tables/<table>/`, partitioned by
`code`. Values are raw (never rounded). Each row carries `sim_id`; join to
`runs.parquet` for the labels and settings of the runs that use the
simulation.

**App-identical** columns hold the value the app shows, computed by the app's
own function: the annual aggregates (`step2_display_aggregation_suite()`), the
Results views (`pointrange` bands, thresholds, variance components, headline
cards, adverse-year dots, incidence) and the Diagnostics weather-support
summary. A test compares them with the Results and Diagnostics modules on a
fixture, and `dev/batch_parity_bfa_sim.R` compares them with the module
servers on real BFA data.

## Common columns

| Column | Meaning |
|---|---|
| `sim_id` | Stage id (12 hex characters): hash of `fit_id` and the simulation settings that change results. One simulation per `sim_id`, however many runs share it. |
| `code` | Country code of the sample (`BFA+MWI` for a pooled two-economy sample). The partition column. |
| `policy_id` | `NA`: the baseline arm. The policy phase adds rows for the policy arms with their `policy_id`. |
| `scenario` | `Historical`, or the climate scenario and projection period as the app labels them: `SSP3-7.0 / 2025-2035` (`SSP2-4.5`, `SSP3-7.0`, `SSP5-8.5`). |
| `metric` | The aggregation of the household outcome into an annual population value: `mean`, `median`, `total`, `headcount_ratio`, `gap`, `fgt2`, `gini` and, for a welfare outcome, `prosperity_gap` and `avg_poverty`. A binary outcome has `mean` only. |

## What a simulation is

The app's "Run simulation" for the sample and model of the run: the baseline
survey (by default the latest wave of each economy) is predicted under every
weather year of the historical period (`sim.hist_years`) and, for each
projection period and SSP, under the same weather years perturbed by the
change in each CMIP6 climate model (the delta method: additive for
temperature, multiplicative for rain and days). Each combination of scenario,
climate model and weather year yields one population aggregate per metric.

`sim_year` is the **weather year** the aggregate draws on, not a calendar year
of the projection: a projection period of 2025-2035 with historical weather of
1991-2020 has `sim_year` 1991 to 2020 under every member.

Residuals, coefficient uncertainty and the seed follow the spec (`sim.residuals`,
`sim.coef_uncertainty`, `seed`). The poverty line is the outcome's own
(`outcome.poverty_line`; $3.00 a day when it has none), the line the Results
pane starts from, and the kernel bandwidth of the poverty rate is the app's
0.05.

## annual

One row per scenario, metric, member and weather year. This is the
aggregation table of the Results pane with its `value_all` / `value_all_sd`
list columns unnested, so each climate-model member keeps its own value and
standard deviation. Every view that does not need a contrast between scenarios
(exceedance curves, annual distributions, model robustness, trajectories, bands
at other quantiles, deviation from the historical mean or median) is a function
of this table. The per-year coefficient gradients (`F_agg_all`), which only the
delta-method contrasts use, are not stored (decision D2).

| Column | Meaning | Source |
|---|---|---|
| `policy_id` | `NA` (baseline arm). | - |
| `scenario`, `metric` | See above. | app |
| `member` | The climate model (as named in the projection files, for example `AWI_AWI-CM-1-1-MR_r1i1p1f1`; `model_<n>` when the file gives none), or `Historical` for the historical run. | app (`model_id`) |
| `sim_year` | The weather year (integer). | app |
| `value` | The member's annual aggregate in outcome units (back-transformed when the outcome is modelled in logs). | app (`value_all`) |
| `sd` | Delta-method standard deviation of that aggregate: coefficient uncertainty plus residual variance. With `sim.coef_uncertainty: false` it holds the residual variance only. | app (`value_all_sd`) |
| `var_within`, `var_across` | Variance of the year's aggregate within a member (residual and coefficient) and across members. They describe the year, so they repeat on each member row. `var_across` is 0 for the historical run. | app |
| `weighted` | The aggregate uses the survey weights. | app |

The equal-model mean of a year is the mean of `value` over its member rows
(the `value` column of the app's aggregation table).

## summary

The Results views of every metric, at the app defaults (decision D3): outcome
level (no deviation from the historical mean or median), the coefficient band
p10-p90, and the ensemble band p10-p90 across climate models. The Results pane
starts with the ensemble band `none`, which collapses it to the median; the
stored tables use p10-p90 so that the spread between models is kept
(`STEP2_SUMMARY_ENSEMBLE_BAND`). Long form with a `section`.

| Column | Meaning |
|---|---|
| `policy_id`, `scenario`, `metric` | See above. `metric` is `NA` for `incidence`, which is the effect on the outcome, whatever the metric. |
| `section` | What the row describes (below). |
| `measure` | The quantity within the section. |
| `group` | A sub-division of the measure (below), or missing. |
| `return_period` | The return period of an adverse year as the app names it (`1:5`, `1:10`, `1:20`, `1:50`; `1:1` is the median year, `4:5` ... `49:50` the favourable tail); missing outside the return-period sections. |
| `estimate` | The central value. |
| `lo`, `hi` | The lower and upper end of the interval or range of `group`; missing when there is none. |
| `n` | A count (climate models, years, households), where it applies. |
| `text` | The text the app displays for the value (headline cards). |

| `section` | `measure` | `group` | Meaning |
|---|---|---|---|
| `expected` | `expected` | `interannual` | Expected outcome: the equal-model mean of the scenario (`estimate`) with the range of weather years (`lo`, `hi`: the p10-p90 of years within each model, averaged across models). `n` = climate models. The "Expected outcome" point of the Results pane's point-range chart. |
| `expected` | `expected` | `intermodel` | The same `estimate` with the p10-p90 range of the model means (`lo`, `hi`; `lo = hi` for the historical run). |
| `adverse_year` | `adverse_year_outcome` | `coefficient`, `ensemble`, `pooled` | The outcome in an adverse weather year of the `return_period` (rank-interpolated within each model, then the equal-model mean): `estimate`; `lo`, `hi` are the coefficient band (p10-p90 of the coefficient uncertainty), the ensemble band (p10-p90 of the models' values) and the pooled band (both, assuming independence). The historical run has the coefficient band only. `n` = weather years behind the value. The rows of the Results pane's return-period table. |
| `adverse_dot` | `Expected`, `Adverse 1-in-5`, `Adverse 1-in-10`, `Adverse 1-in-20`, `Adverse 1-in-50` | `ensemble` | The values behind the adverse-year dot plot: the central value per scenario with the ensemble band (`lo`, `hi`). Only the decision return periods of the metric, and only those the historical record supports. |
| `uncertainty` | `var_coef`, `var_within`, `var_across` | - | The variance components of the Results pane's uncertainty-sources chart: coefficient (including residual), weather year within models, and between models. Standard deviations are the square roots. |
| `headline` | The card label: `Expected change`, `Adverse weather years`, `Signal vs noise`, `Year-to-year range`, `Simulation years` | `historical`, `focus`, `difference`, `range`, `count` | The headline cards for the focus scenario (the first future scenario; the historical run when there is none): the card's `historical` and `focus` values and their `difference` (`estimate`), the `range` of the card (`lo`, `hi`) and the `count` of simulation years. `text` holds the card's displayed value on the `focus` row. |
| `incidence` | `household_effect` | `decile_1` ... `decile_10` | The mean effect of the scenario on households of each fixed baseline decile of the outcome (weighted, the equal-model mean over climate models and weather years), in outcome units; `n` = households. |

The headline cards compare the first future scenario with the historical run
(`Expected change`, `Adverse weather years`) and describe it (`Signal vs
noise`, `Year-to-year range`); the focus scenario is named in `scenario`.

## sim_weather

The weather the simulation drew on, per scenario. Long form with a `section`.

| Column | Meaning |
|---|---|
| `scenario` | A projection scenario (the historical run is the reference, not a row). |
| `section` | `scenario`, `members` or `support`. |
| `member` | The climate model, for `members` rows. |
| `variable` | The weather variable, for `support` rows. |
| `statistic` | The quantity (below). |
| `value`, `text` | Numeric value, or text for the text statistics. |

| `section` | `statistic` | Meaning |
|---|---|---|
| `scenario` | `period_start`, `period_end` | The projection period. |
| `scenario` | `n_models`, `n_models_requested` | Climate models that ran and models that were requested. They differ when a model was dropped (missing or partial coverage of the weather variables), and the run says so in `failures.parquet`. |
| `members` | `member` | One row per climate-model member (`value` = 1). |
| `support` | `n_reference`, `n_scenario` | Historical values and simulated values of the variable (all members) compared. |
| `support` | `robust_lo`, `robust_hi` | The reference support: the 1%-99% interval of the historical values of the variable (a continuous variable). |
| `support` | `outside_n`, `outside_share` | Simulated values outside the support (or, for a binned variable, in a bin the historical weather never had), and their share. |
| `support` | `warning` | 1 when the share exceeds 5%: the model is extrapolating. |
| `support` | `n_members`, `max_member_share` | Members compared and the largest share outside the support in any one member. |
| `support` | `reference_label`, `warning_rule`, `is_binned` (`text`) | The supported bins of a binned variable, the rule behind `warning`, and whether the variable is binned. |

The support rows are the pooled summary the Diagnostics tab shows. A scenario
without a stored support summary has no `support` rows.

## Notes

- Real-data check (`dev/batch_parity_bfa_sim.R`, BFA, linear fixest with a
  user covariate list, `sim: {}`): the annual values, headline cards,
  return-period values, incidence and weather support equal what the module
  servers register. Annual values of `mean` differ from the Results pane's by
  up to 3e-15 (the pane aggregates a metric with the metrics of its group; the
  batch, like the run's streamed tables, aggregates all metrics in one call);
  `headcount_ratio` is identical.

- A grid with several climate scenarios, periods or residual rules shares the
  fit: the simulations differ in `sim_id` only.
- The tables of a simulation that lost some climate-model members still hold
  the members that ran; `n_models_requested` says how many were asked for and
  `failures.parquet` lists the loss (`partial_simulation_failure`).
- Memory: a Step 2 run holds hundreds of MB. The runner keeps only the tables;
  the run itself is not stored, so the policy phase reads or repeats it.
- `sim_weather` stores the support summary the Diagnostics tab shows. The
  weather densities, simulated weather values and the observed weather input
  are observation level or microdata and are not stored (tables.md section 3.6).
