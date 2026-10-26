---
name: add-metric
description: >
  Add a welfare metric (poverty, inequality or other summary) to WISE-APP:
  the registry entry, the aggregation kernel, the delta-method uncertainty, the
  labels and choices in Steps 2 and 3, the metric decomposition, tests and the
  methods page.
when_to_use: >
  When the user wants a new metric in the Results tabs, or asks which parts of
  the app a metric change touches, or why a metric is missing from a view.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[metric id, e.g. 'watts']"
---

# Adding a metric

A metric id (for example `headcount_ratio`, `gini`) runs through the kernel,
the aggregation, the uncertainty code, the Step 2 and Step 3 views and the
decomposition. Method: `docs/32_metrics.md` and `docs/33_uncertainty.md`.
Registry: `R/fct_metric_registry.R`.

Existing metrics must not move: after the change, the numbers of every old
metric are bit-identical (test it). A new metric is new output, not a numeric
change; if you also change an old one, use skill `wise-numeric-change`.

## 1. Specify first

Write down: the formula and its estimand, units (`native_unit`, `format`),
whether it uses the poverty line (`poverty_line`), direction
(`higher_is_better` or `lower_is_better`), how a change is expressed
(`change_kind`: `absolute`, `percentage_points`, `index_points`), the
engines it supports (`ols`, `rif`), the uncertainty sources it has
(`coefficient`, `weather`, `ensemble`) and a caveat sentence for users. Edge
cases: zero or negative welfare, missing weights, empty groups, a poverty
line of `NA`.

## 2. Touch these, in order

1. **Kernel** (when the statistic is computed in the sort-once C++ pass):
   `src/welfare_stats.cpp`, the wrapper and index map in
   `R/fct_aggregation_kernel.R`, then `Rcpp::compileAttributes()` and
   `devtools::document()`; commit `R/RcppExports.R` and `src/RcppExports.cpp`.
   `src/*.o` and `*.so` are git-ignored. `src/` is in the Connect manifest, so
   regenerate `manifest.json` before a deploy. If the metric needs no sort
   (a plain weighted mean of a transform), compute it in R instead and skip
   this step.
2. **Aggregation** (`R/fct_aggregation.R`): the method function, the
   `hist_aggregate_choices()` choices for the outcome type (the label list near
   the "Poverty rate" entry), the method vector of the suite path, and the
   cache keys that list methods.
3. **Registry entry** (`R/fct_metric_registry.R`): all fields above, plus any
   special case in `metric_metadata()` (threshold label, currency basis) and
   `metric_axis_label()`.
4. **Uncertainty** (`R/fct_aggregation_delta.R`): `gradient_for_method()` for
   the coefficient variance, and the method branch of the delta function.
   Without a gradient, remove `coefficient` from the registry `uncertainty`
   field so the app does not show a band it cannot compute.
5. **Views**: labels in `R/fct_sim_compare.R` (the label `switch`),
   `R/fct_policy_sim_compare.R` (the method vector of the policy comparison),
   the Step 2 metric picker in `R/mod_2_02_results.R`, and
   `R/fct_step2_tables.R`, `R/fct_step3_tables.R` for batch tables. Poverty
   specific code (`R/fct_sp_effectiveness.R`, `R/mod_3_10_cost_effectiveness.R`)
   reads `headcount_ratio` on purpose; leave it unless the metric belongs there.
6. **Decomposition**: the metric states in `R/fct_policy_metric_decompose.R`
   must reconcile for the new metric (the "all metrics" test); the RIF engine
   has its own path (`R/fct_rif_sim.R`).
7. **Docs**: a section in `docs/32_metrics.md` (equation, interpretation,
   Implementation map), `docs/33_uncertainty.md` if the uncertainty differs,
   `verified_against`, then `Rscript dev/docs_index.R` and
   `Rscript dev/docs_check.R`. `batch/docs/tables.md` if a table gains values.

Find every list of metric ids with `grep -rn "avg_poverty" R tests` (the
newest metric shows the full set of touchpoints); do not trust this list to be
complete.

## 3. Tests

- Kernel: a hand-computed answer, including empty input, `NA` weights and a
  zero (`tests/testthat/test-fct-aggregation-kernel.R`).
- Aggregation: the same value through `aggregate_*` as through the kernel
  (`test-fct_aggregation.R`).
- Delta method: the analytic standard error matches a Monte Carlo
  (`test-fct_aggregation_delta.R`, the "SE matches MC" pattern).
- Decomposition: the metric appears in `test-fct-policy-metric-decompose.R`
  and reconciles.
- Equivalence: all old metrics unchanged (the characterization tests,
  `test-w3-a-aggregation-characterization.R`).

## 4. Finish

Skill `wise-verify` (filters `aggregation`, `w3`, `policy.metric.decompose`,
`determinism`), drive the new metric in Step 2 and Step 3 (skill
`wise-ui-check`; Results, Diagnostics, the threshold table and a Step 3 paired
view), and say what was not driven.

## Traps

- A metric with `poverty_line = TRUE` needs the line in every code path that
  builds a cache key; a missing line gives a stale or `NA` result.
- Percent change is meaningless for some metrics (`percent_change`); set it
  honestly.
- The registry lists engines and uncertainty sources the UI trusts. A wrong
  entry shows a band or a metric that is not computed.
