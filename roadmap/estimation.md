# Estimation engines and survey design

Status: proposal, 2026-11-09. Issues: [#47](https://github.com/worldbank/wise-app/issues/47) (gradient boosting, random forest), [#45](https://github.com/worldbank/wise-app/issues/45) (complex survey design).

## #47 Flexible models

The random forest and gradient-boosted tree code exists (`R/fct_model_fit.R`, `ranger` and `xgboost` in Suggests) but is not offered. The selector lists linear, logistic and quantile models only, and Steps 2 and 3 refuse other engines (`docs/23_model_ml.md`). Turning them on is the `add-model-engine` skill, not new estimation code.

Proposed path:

1. **Step 1 only first.** Offer the engines in the selector with fit diagnostics (out-of-bag error, variable importance, partial dependence of the weather terms). Mark them "not available in Steps 2 and 3" in the model card.
2. **Step 2 simulation.** Predictions are direct (no coefficients), so the delta method of `docs/33_uncertainty.md` does not apply. Uncertainty needs a resampling route: refit on bootstrap samples of survey clusters, or quantile forests for the conditional distribution. This is the main cost; decide before building.
3. **Step 3.** Weather-by-policy effects have no coefficient form, so the main and resilience decomposition (`docs/44_decomposition.md`) needs a counterfactual-prediction definition. Keep the engines out of Step 3 until that is written.
4. **Extrapolation.** Trees predict flat outside the training range, which matters for warming scenarios. Show the share of simulated rows outside the training weather range.

Constraints: protected areas (numerics, async) change only with tests; the engine must be deterministic given a seed (`docs/51_reproducibility.md`).

## #45 Complex survey design

Agreed direction from the issue comments: do not use the design at the estimation stage beyond what exists. Step 1 uses survey weights and clusters errors at the survey-location panel when `loc_id_panel` is present. Add design variance after simulation:

1. **Design-based variance of metrics.** Use `psu` and `strata` (already in the microdata when the survey has them) to compute the sampling variance of the aggregate metrics (headcount, mean, Gini) in Step 2. Point estimates must not change. Implementation can use Taylor linearisation on the influence values already built for the delta method (`R/fct_aggregation_delta.R`), with PSU totals within strata. Avoid adding the `survey` package as a dependency if the influence values suffice.
2. **Absent design variables.** Fall back to the current variance and say so in the card (`wise_user_error()` style notice, no silent switch).
3. **Estimation clustering.** Keep clustering at least as coarse as the weather variation (`loc_id * int_month`). Check coarser options (PSU, region) as a sensitivity in the model card.
4. **Multiple surveys.** When surveys or countries are combined, weights need rescaling (equal per country-year, or by population) and bootstrap resampling must not mix PSUs across survey years. Out of scope until multi-survey simulation is a goal.

## Upstream data

- For #45: confirm which surveys carry `psu` and `strata`, and standardise their names and uniqueness (PSU ids unique within stratum, and across years where panels exist). Add a coverage table to the Step 0 overview.
- For #47: none.

## Decisions needed

- #47: which uncertainty route (bootstrap, quantile forest) before any engine goes into Step 2.
- #45: whether metric variance with design is shown by default or behind an option.
