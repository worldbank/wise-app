# Phase 4 tables - column reference

Status: implemented (2026-10-20). Part of `review/batch_pipeline_plan.md`.
These are the Step 3 policy tables: the policy arm of `annual` and `summary`,
the `decomposition` and `policy_measures`. The catalogue of all tables is
`batch/docs/tables.md`; the builders are in `R/fct_step3_tables.R`, the run
they describe is made by `step3_compute()` from the input that
`wise_step3_input()` and `wise_policy_configs()` (`R/fct_step3_input.R`) build,
the glue the Step 3 lever modules and `mod_3_06` call.

Every table is a parquet dataset in `results/tables/<table>/`, partitioned by
`code`. Values are raw (never rounded). Policy rows carry `sim_id` and
`policy_id`; join to `runs.parquet` for the labels and settings of the runs that
use the policy.

**App-identical** columns hold the value the Step 3 Results pane, Diagnostics,
Decomposition and Cost-effectiveness tabs compute, by the same functions: the
aggregation of the policy arm (`step2_run_aggregates()`), the paired effects,
the threshold table with its baseline-anchored tails
(`step3_threshold_table()`), the headline cards (`step3_headline_cards()`), the
metric decomposition (`.policy_metric_decomposition()`), the compact channels
and the incidence. `test-fct_step3_tables.R` compares them with the pane driven
by `shiny::testServer()` on a fixture run, and `dev/batch_parity_bfa_policy.R`
compares them with the module servers on real data.

## Common columns

| Column | Meaning |
|---|---|
| `sim_id` | Stage id of the simulation the policy starts from (the Step 2 run, stored once for all its policies). |
| `policy_id` | Stage id (12 hex characters): hash of `sim_id` and the `policy` section. `NA` is the baseline arm, which is the Step 2 result and is stored once per `sim_id` with the simulation (`annual`, `summary`). |
| `code` | Country code of the sample (`BFA+MWI` for a pooled two-economy sample). The partition column. |
| `scenario` | `Historical`, or the climate scenario and projection period as the app labels them (`SSP3-7.0 / 2025-2035`). The app labels the historical arm with its years; the tables use `Historical` throughout (the years are in `runs`). |
| `metric` | The aggregation of the household outcome (`mean`, `median`, `total`, `headcount_ratio`, `gap`, `fgt2`, `gini`; for a welfare outcome also `prosperity_gap` and `avg_poverty`). Every metric is stored (decision D3). |
| `member` | The climate model, or `Historical`. |
| `sim_year` | The weather year the aggregate draws on (as in `annual` of the baseline arm). |

## What a policy run is

The app's Step 3 "Run simulation" for the configured levers: the lever settings
change the survey covariates (or add a cash transfer) of the baseline survey of
the Step 2 run, and the policy effect is added to the stored baseline
predictions of every member and weather year (the analytic correction of
`apply_policy_delta_to_baseline()`). The baseline arm is the Step 2 result
unchanged. A shock-responsive transfer is paid per prediction row inside that
correction, from the trigger evaluated on the historical thresholds.

The Results pane's controls are stored at their initial values, except the
bands: the coefficient band and the ensemble band are p10-p90 (the pane starts
at `none` for the ensemble, which has no spread to keep), the deviation is
`none` (levels), and the poverty line is the run's own line when it has one,
else $3.00 a day (the pane's initial value). A policy contrast for a binary
outcome or a logistic model is not defined (the app shows "unavailable"); such a
run writes no policy rows and is listed in `failures.parquet` as a
`partial_policy_failure`.

The seed of the policy draws (targeting errors, forecast draws, dynamic
targeting) is the spec's `seed`, the seed of the Step 2 run, and the run uses the
R default random number generator.

## annual (policy arm)

Same columns and grain as the baseline arm (`batch/docs/phase3_tables.md`),
for the policy pipelines: one row per scenario, metric, member and weather year.
The policy values are the aggregates of the corrected predictions, with the
residual rule and seed of the baseline run. The effect of the policy on a
member-year is the policy `value` minus the baseline `value` of the same
scenario, metric, member and year.

For a shock-responsive program the table also holds the per member-year rows of
the run (the app's `policy_shock_annual` export) as metrics `shock_<column>`,
with `value` the column and `sd`, `var_within`, `var_across`, `weighted` missing:

| `metric` | Meaning |
|---|---|
| `shock_activated` | 1 when any household is paid in that member-year (the program pays), else 0. |
| `shock_exposed_share` | Share of the represented population in a location whose trigger passed. |
| `shock_transfer_cost`, `shock_admin_cost`, `shock_total_cost` | Net transfers, administration and the total cost of the member-year, in the entry currency of the outcome. |
| `shock_pop_tp`, `shock_pop_fp`, `shock_pop_fn`, `shock_pop_tn` | Population weight of locations that are true or false positives or negatives (paid and with a loss event, paid without, not paid with, neither). The loss event is `policy.sp.loss_event_pct`. |
| `shock_spend_total`, `shock_spend_no_event` | Spending in all locations and in locations without a loss event (the basis of leakage). |
| `shock_loss_value`, `shock_paid_value` | Modelled loss and payments in the same units and weights (the share of loss offset). |

The activation frequency, cost distribution, basis risk and leakage of
`policy_measures` (`shock_summary`) are functions of these rows.

## summary (policy arm)

Long form with a `section`, in the columns of the baseline arm (`scenario`,
`metric`, `section`, `measure`, `group`, `return_period`, `estimate`, `lo`, `hi`,
`n`, `text`). The sections of the policy arm start with `policy_`:

| `section` | `measure` | `group` | Meaning |
|---|---|---|---|
| `policy_expected` | `effect` | `intermodel` | Expected policy effect (policy minus baseline, the equal-model mean over climate models of each model's mean over weather years, on matched support): `estimate`; `lo`, `hi` are the p10-p90 of the model means. `n` = climate models. |
| `policy_expected` | `effect` | `coefficient` | The same `estimate` with the p10-p90 band of the coefficient uncertainty of the paired contrast (baseline-policy covariance kept). |
| `policy_expected` | `effect` | `interannual` | The same `estimate` with the p10-p90 range of weather years within models, averaged across models. |
| `policy_expected` | `effect` | `range` | The same `estimate` with the full range of the model means (minimum, maximum), as the headline robustness card uses it. |
| `policy_expected` | `baseline`, `policy` | `level` | The matched endpoint levels: equal-model mean of the baseline and of the policy arm. |
| `policy_adverse` | `Adverse 1-in-5`, `1-in-10`, `1-in-20`, `1-in-50` | `effect`, `baseline`, `policy` | The baseline-anchored adverse-year values (the metric decomposition's tails: each model's baseline adverse year, with the policy and the baseline state read in that year, then the equal-model mean). `return_period` = the number of years; `text` = the reason when the support is unavailable (`estimate` missing). |
| `policy_threshold` | The estimate (`Single historical estimate`, `Equal-model mean`, `Coef P10`, `Coef P90`, `Ensemble P10`, `Ensemble P90`, `Pooled P10`, `Pooled P90`) | `Baseline`, `Policy` | The return-period table behind the advanced risk view: the outcome in an adverse year of the `return_period` (`1:5` ... `1:50`, `1:1`, favourable tail), for the baseline and the policy arm, with the coefficient, ensemble and pooled bands (as in the baseline `adverse_year` section). `n` = years; `text` = status of the baseline-anchored value. |
| `policy_adverse_dot` | `Expected`, `Adverse 1-in-5` ... | `baseline`, `policy`, `effect` | The values behind the adverse-year dot plot: baseline and policy value with the ensemble band (`lo`, `hi`) and their difference. Only the decision return periods of the metric that both arms support. |
| `policy_headline` | The card label (`Expected policy effect`, `Adverse-year policy effect`, ...) | `card_<k>_value`, `card_<k>_note` | The headline cards for the focus scenario (the first future scenario): the displayed value (`text`) and note. On `card_1_value`, `lo` and `hi` are the 95% interval of the effect from the coefficient uncertainty; `n` = households represented (value) or the prediction count (note). |
| `policy_incidence` | `household_effect` | `decile_1` ... `decile_10` | The mean effect of the policy on households of each fixed baseline decile, for the weather-year basis in `return_period` (`mean`, `adverse_5`, `adverse_10`, `adverse_20`), in outcome units; `metric` is `NA`; `n` = climate models. |

## decomposition

The per-year tables the app's decomposition views reduce (decisions D4 and D5).
Every average of the Decomposition tab, for every weather-year basis (mean and
the 1-in-5, 1-in-10 and 1-in-20 adverse years) and in absolute units or per cent
of the baseline, is rebuilt from these rows with the app's functions
(`.compact_future_decomp()`, `.compact_future_decile_summary()`,
`.policy_metric_summary()`, `.policy_metric_tails()`). Long form: one row per
member, year, group and channel.

| Column | Meaning |
|---|---|
| `source` | `compact` (the channel sums of the run, outcome-scale and log-scale channels) or `metric` (the metric-aware states and contributions, one decomposition per metric). |
| `scenario`, `member`, `sim_year` | As above. The historical run has `member` `Historical`. |
| `metric` | The metric of a `metric` row; `NA` for `compact`. |
| `group` | `all` (the whole population) or `decile_1` ... `decile_10` (fixed baseline welfare deciles; 1 is the poorest). |
| `channel` | For `compact`: `delta_total`, `delta_main`, `delta_sp`, `delta_main_covar`, `delta_res`, `delta_res1`, `delta_res2`, `delta_sp_shock` (log-scale effects), `baseline_y_point`, `baseline_level` (the baseline prediction), `lvl_main`, `lvl_res1`, `lvl_res2`, `lvl_total`, `lvl_sp_shock` (effects in outcome units). For `metric`: the five cumulative states `baseline`, `after_static_main`, `after_main`, `after_repositioning`, `policy` and the contributions `main`, `sp_shock`, `repositioning`, `interaction`, `resilience`, `total`, all in the metric's own units. |
| `value` | The channel's average: `sum / weight` for `compact` (missing when the weight is 0), the metric value for `metric`. |
| `sum`, `weight` | The weighted sum and the weight behind a `compact` value (the population represented in a `decile` group is `n_units`); missing for `metric`. Averages over years or members are weighted averages of these, as in the app. |
| `n_units` | `compact` decile rows: the weighted population of the decile. `metric` rows: retained prediction rows of the member-year (or of the decile). |

Direct effect is `main` (the static covariate effect, with the cash transfer);
`resilience` is `repositioning` plus `interaction`; `sp_shock` is the
shock-responsive transfer. `total` is `policy - baseline`; the columns
reconcile (`main + sp_shock + repositioning + interaction = total`).

## policy_measures

Small measure tables of the run. Long form with a `section`.

| Column | Meaning |
|---|---|
| `section` | What the row describes (below). |
| `scenario`, `metric` | Where the section has them; missing otherwise. |
| `measure` | The quantity: a column of the app's table. |
| `group` | The row of the app's table (its label), or missing. |
| `value` | The number. |
| `text` | A note or status, where the app has one. |

| `section` | Contents |
|---|---|
| `transfer` | The transfer summary of Diagnostics: annual cost of the cash transfer across the represented recipients (and administration and total when an administration share is set) and the annual transfer per recipient household or unit. For a shock program: the annual means over the historical years. |
| `sp_effectiveness` | Cost and targeting effectiveness (`sp_effectiveness()`): annual cost per person, administration share, realised inclusion and exclusion error, coverage of the poor, leakage to the non-poor and adequacy for poor recipients. `group` = the kind (`money`, `percent`); `text` = the app's note. The poverty line is the outcome's own line, else $3.00 a day (the Results line is not defined for a non-poverty metric). A shock program describes a year in which every eligible household is paid. |
| `reach` | The population reached by any policy lever: `share`, `people` and `households`. |
| `components` | The table of policy components (one per lever touched): sample units affected or covered, population represented, share of the population, realised cost and households represented. `group` = the component. |
| `treatment` | The eligibility-by-treatment matrix of the cash transfer: sample units, population represented, population share and households per coverage status (`group`). |
| `input_diagnostics` | Before and after summary of every covariate the policy changed: units changed, baseline and policy mean and spread. `group` = the variable. |
| `cost_effectiveness` | The cost-effectiveness table of the cash transfer for every metric (`metric`), scenario and weather basis (`group` = `Average year` or `1-in-20 year`, and the measure): `cost` (annual cost), `amount` (net people lifted, or annual value of the change), `value` (the ratio), `lo`, `hi` (95% interval of the average year), the `poverty_line` and `admin_share` used; `text` = `ok`, `not_applicable` or `unavailable`. A metric without a per-dollar reading (the mean of a non-money outcome, a run with other levers than the transfer) has `not_applicable`. Rows exist only when a cash transfer with spending is configured. |
| `shock_summary` | Shock-responsive programs: by scenario the number of member-years, activation frequency, mean, median and 95th percentile annual cost, transfer and administration cost, false-positive and false-negative rate of the trigger, leakage share, cost variation, share of modelled loss offset, share of years in which the cap binds and, for an anticipatory design, the false-alarm cost share and the break-even effectiveness multipliers. Scored with `policy.sp.loss_event_pct`. |
| `shock_climate_cost` | The program's bill under each scenario against history: activation frequency, mean and 95th percentile cost, and their change against the historical run. |
| `shock_affected_poor` | Coverage (share of loss-event household-years of the baseline poor in which the household was paid) and adequacy (payments as a share of the modelled loss) of the shock-affected poor, by scenario, at the outcome's poverty line (else $3.00). |

## Notes

- Real-data check: `dev/batch_parity_bfa_policy.R` (BFA, linear fixest with a
  user covariate list, Step 2 defaults, a regular cash transfer to the poorest
  30 percent and a shock-responsive one on a 1-in-5 temperature trigger) compares
  the stored values with the module servers' exports. The result of the last
  run is in the plan's Phase 4 note.
- A policy-only change (a new profile, another amount) reruns only the policy
  branches: the simulation and the fits are reused. The stored Step 2 run is in
  `_targets/user/sims/` (hundreds of MB per simulation); `keep_step2 = FALSE`
  of `wise_targets()` removes it after the run.
- The policy tables of a run with a lever whose variable is not in the model
  are the tables of a run with no effect for that lever, as in the app, which
  only shows the levers whose variable the model contains.
- Not stored: the household-level policy frame, before/after histograms of the
  policy variables (observation level), the coefficient gradients of the paired
  contrasts (decision D2: views that need a contrast with coefficient
  uncertainty are in `summary`), and charts.
