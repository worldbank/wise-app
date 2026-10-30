---
id: assumptions
title: Assumptions and limitations in one place
app_step: cross
depends_on: [notation, framework, data, outcomes, weather-measures, model-specification, linear-model, rif-model, ml-models, model-results, simulation, climate-scenarios, seasonal-forecast, metrics, uncertainty, policy-framework, policy-levers, social-protection, shock-sp, decomposition, cost-effectiveness]
symbols: []
guide: https://github.com/worldbank/wise-app-docs/blob/main/index.qmd#limitations
code: []
verified_against: 623ee30
---

# Assumptions and limitations in one place

> Every page lists the assumptions it relies on, numbered A1, A2 and so on. This page collects them by theme, so a reader can see what a result rests on, what the app tests, and what it does not. A result is only as good as the weakest assumption behind it.

## Setup

The app produces three kinds of statements ([01_framework](01_framework.md)): a weather response estimated from data (Step 1), a stress test of a fixed population under other weather (Step 2), and a policy scenario priced with fitted coefficients (Step 3). Each kind rests on a different group of assumptions. The groups below follow that order. Each row names the page and the assumption number, in the form "page A*n*", and says what would break it or what to look at. The app tests very few of these. Where it does, the row says so.

## Identification and data

| Assumption | Where | What to check |
|---|---|---|
| Weather is unrelated to unobserved determinants of welfare, given the fixed effects and controls | [01_framework](01_framework.md#assumptions) A1; [20_model_specification](20_model_specification.md#assumptions) A2; [21_model_linear](21_model_linear.md#assumptions) A2; [22_model_rif](22_model_rif.md#assumptions) A5 | The survey must have enough within-area, within-round variation in weather. The weather statistics and the survey timing in Step 1 show it. Not tested. |
| Interview month and location are correct | [10_data](10_data.md#assumptions) A1 | Coarse geography or no interview month weakens identification and biases weather coefficients toward zero. Not tested. |
| Area weather represents household exposure | [10_data](10_data.md#assumptions) A2 | Weaker for large areas and mobile livelihoods. |
| Deflators and population weights are correct and stable | [10_data](10_data.md#assumptions) A3, A4; [00_notation](00_notation.md#assumptions) A2 | Check the survey list and CPI and PPP table in the data repository. |
| The weather window and the monthly resolution capture the channel | [12_weather_measures](12_weather_measures.md#assumptions) A1, A4 | Compare windows. Not tested. |
| The 1991 to 2020 normal and the bins describe the local climate and the support | [12_weather_measures](12_weather_measures.md#assumptions) A2, A3 | Bins are cut on the pooled reference sample. |
| Missing data are ignorable | [20_model_specification](20_model_specification.md#assumptions) A4; [30_simulation](30_simulation.md#assumptions) A6 | Records with missing variables are dropped, and their number is reported. |
| Positive outcome; fixed poverty line | [00_notation](00_notation.md#assumptions) A1; [11_outcomes](11_outcomes.md#assumptions) A1, A2 | The line is not adjusted for inflation or growth in simulated years. |

## Functional form and estimation

| Assumption | Where | What to check |
|---|---|---|
| Correct specification; the form of weather and moderators approximates the response | [20_model_specification](20_model_specification.md#assumptions) A1; [21_model_linear](21_model_linear.md#assumptions) A1 | Compare Models 1 to 3 and the weather form. |
| Log-linear, proportional response; one slope per moderator group | [11_outcomes](11_outcomes.md#assumptions) A3; [21_model_linear](21_model_linear.md#assumptions) A3 | The quantile model relaxes the common slope. |
| Quantile model: local linearity, a good density estimate, rank stability, smooth curve, an observed baseline anchor | [22_model_rif](22_model_rif.md#assumptions) A1 to A4, A6 | Weaker for large weather changes and at the ends of the quantile grid. |
| Machine-learning models: a representative sample, fixed-effect variables as features, the conditional mean | [23_model_ml](23_model_ml.md#assumptions) A1 to A3 | Tree models do not extrapolate beyond the sample. |
| Errors are independent across location panels, and there are enough panels | [20_model_specification](20_model_specification.md#assumptions) A3, A5; [24_model_results](24_model_results.md#assumptions) A1 | Fewer than about 50 panels may understate uncertainty. |
| Fixed-effect cells in simulation exist in the estimation sample; no separation in a logit | [21_model_linear](21_model_linear.md#assumptions) A4, A6; [30_simulation](30_simulation.md#assumptions) A3 | Units in unseen cells have no prediction. The number is reported. |
| Residual distribution is stable | [21_model_linear](21_model_linear.md#assumptions) A5; [30_simulation](30_simulation.md#assumptions) A4 | The residual rule is a choice. |
| Reported effects at a reference household; independent quantile terms in headline intervals | [24_model_results](24_model_results.md#assumptions) A2, A3 | Nonlinear effects depend on the reference point. |

## Simulation and extrapolation

| Assumption | Where | What to check |
|---|---|---|
| Fixed population, prices, technology and behaviour | [01_framework](01_framework.md#assumptions) A2; [30_simulation](30_simulation.md#assumptions) A1 | Results are stress tests, not forecasts. |
| The estimated response holds for counterfactual weather, including outside the observed range | [01_framework](01_framework.md#assumptions) A3; [30_simulation](30_simulation.md#assumptions) A2 | The weather-support diagnostic flags scenarios outside the 1st to 99th percentile of the weather of the fitted sample (or in a bin the fitted sample does not contain), when more than 5 per cent of the values fall outside. The check is marginal, one variable at a time: it does not establish support for the joint weather and moderator combinations. |
| Climate change enters as a change in monthly weather, applied to the observed record | [01_framework](01_framework.md#assumptions) A5; [30_simulation](30_simulation.md#assumptions) A5; [31_climate_scenarios](31_climate_scenarios.md#assumptions) A1 to A3, A5 | Variance and day-to-day structure are those of the observed record. |
| Equal weights for climate models | [31_climate_scenarios](31_climate_scenarios.md#assumptions) A4 | The spread across models is disagreement, not a probability. |
| Survey weights are fixed; years are exchangeable; thresholds are meaningful for the outcome | [32_metrics](32_metrics.md#assumptions) A1 to A4 | Thirty years support a 1-in-10 return period with three years only. |
| Mean-bias-adjusted forecast weather supports the fitted response, with equally weighted members | [34_seasonal_forecast](34_seasonal_forecast.md#assumptions) A1 to A3 | The experimental local pilot starts with temperature only. Skill is not established; mean adjustment does not calibrate spread or probabilities. Target months have equal weight and form one state per member, not an annual return-period sample. |

## Uncertainty

| Assumption | Where | What to check |
|---|---|---|
| The metric is locally linear in household predictions | [33_uncertainty](33_uncertainty.md#assumptions) A1 | Weakest near thresholds and for the poverty rate. |
| Coefficients are jointly normal; residual and coefficient errors are independent | [33_uncertainty](33_uncertainty.md#assumptions) A2, A7 | Few clusters violate normality. |
| Residual draws under "resample" are independent, homoskedastic and unweighted | [33_uncertainty](33_uncertainty.md#assumptions) A7 | "Resample" changes the level and spread of the simulated distribution, not only its noise. The year spread shows weather-driven variability only, not common non-weather shocks. A per-year value holds one residual realisation; 30-year averages are stable to about 0.2 per cent. |
| The residual is fixed so that unchanged terms cancel | [33_uncertainty](33_uncertainty.md#assumptions) A4 | The restricted scope applies only to the original residual rule for the linear model. |
| Rank stability of the Gini; joint normality of the quantile equations (independent equations only as a fallback); exchangeable models | [33_uncertainty](33_uncertainty.md#assumptions) A3, A5, A6 | |

## Policy

| Assumption | Where | What to check |
|---|---|---|
| Policy coefficients are cross-sectional associations used as scenario inputs, and stay unchanged outside the sample | [01_framework](01_framework.md#assumptions) A4; [40_policy_framework](40_policy_framework.md#assumptions) A2, A5; [44_decomposition](44_decomposition.md#assumptions) A1 | The before-and-after summaries show how far levers move the sample. |
| A lever acts only if its variable is in the Step 1 model | [40_policy_framework](40_policy_framework.md#assumptions) A1 | The app lists levers that cannot act. |
| Weather interactions apply to the weather change from the interview weather | [40_policy_framework](40_policy_framework.md#assumptions) A3; [44_decomposition](44_decomposition.md#assumptions) A2 | Open item in the review tracker. |
| Fixed population and fixed-effect cells under policy | [40_policy_framework](40_policy_framework.md#assumptions) A4 | |
| Levers are random draws, applied independently, with the variable measured as in the survey | [41_policy_levers](41_policy_levers.md#assumptions) A1 to A4 | No targeting by need or place for access levers. |
| Eligibility is fixed, delivery is full, transfers are consumed, administration does not reach households | [42_social_protection](42_social_protection.md#assumptions) A1 to A5 | |
| Triggers are fixed at the historical record; the model predicts losses; forecast skill is an input | [43_shock_responsive_sp](43_shock_responsive_sp.md#assumptions) A1 to A5 | Basis risk is measured against modelled loss. |
| Position in the distribution is fixed from the observed outcome; the channel order is a convention | [44_decomposition](44_decomposition.md#assumptions) A3 to A5 | A different order gives a different split of the same total for a nonlinear metric. |
| Effects are net; one population; fixed line; the programme's own cost only | [45_cost_effectiveness](45_cost_effectiveness.md#assumptions) A1 to A4 | |

## Limitations and what is not modelled

Across the pages, the app does not model the following.

- Economic growth, structural change, migration, ageing and other demographic change.
- General-equilibrium effects: prices, wages and labour demand do not respond to weather or policy.
- Adaptation by households or firms beyond what the survey already contains.
- Weather beyond the regressors: compound events, within-month extremes except through built variables, and extremes that never occurred in the estimation sample.
- Changes in the variance or the temporal structure of weather under climate change.
- Weights on climate models, or a probability for a scenario.
- Take-up, delivery capacity, service quality and the cost of levers other than the cash transfer.
- Behavioural responses to a transfer.
- A policy arm for logistic regression, binary outcomes and machine-learning models.
- A causal reading of any policy lever effect.
- Calibrated seasonal forecast probabilities, proven seasonal forecast skill, or policy simulation for seasonal target windows. The local pilot is experimental DEV data; Step 3 requires rerunning Step 2 with the forecast off.

## In the app

Step 0 to Step 3: assumptions are not shown as one list. Each result tab has summary cards that record the settings behind a result, and the Diagnostics tabs of Steps 2 and 3 show the checks that exist (weather support, calibration against the survey, before-and-after distributions of the policy variables).

User guide: [Overview and limitations](https://github.com/worldbank/wise-app-docs/blob/main/index.qmd#limitations).

## References

See the references cited on each page. Full entries are in [references](references.md).

## Implementation map

This page describes no code of its own. Each assumption is stated on the page named in its row.

| Concept | Equation | Code |
|---|---|---|
| Weather-support diagnostic | | `R/fct_sim_diag.R` |
| Calibration check against the survey | | `R/fct_sim_diag.R` |
| Levers that cannot act | | `R/fct_policy_sim.R` `.access_levers_unavailable()` |
