---
id: simulation
title: Simulation of welfare under historical and future weather
app_step: 2
depends_on: [notation, framework, weather-measures, linear-model, rif-model, climate-scenarios]
symbols: [i, r, s, m, mu, W, y, Y, omega, T, epsilon]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#simulating-welfare
code: [R/fct_step2_input.R, R/fct_step2_compute.R, R/fct_run_simulation.R, R/fct_simulations.R, R/fct_predict_outcomes.R, R/fct_aggregation.R, R/fct_sim_diag.R, R/fct_sim_compare.R, R/fct_spec_defaults.R]
verified_against: 1ecc93e
---

# Simulation of welfare under historical and future weather

> Step 2 takes the households of one baseline survey, holds everything about them fixed, and re-evaluates the fitted model once for each weather year of a historical window, and once more for each future climate scenario and climate model. The result is a set of annual welfare statistics. Their spread across years shows the effect of weather variability, and their shift between scenarios shows the effect of climate change on today's population.

## Setup

| Choice | Options | Default |
|---|---|---|
| Baseline survey | one or more survey rounds of the Step 1 sample | the latest round of each economy |
| Historical window | first and last year, 1950 to 2025 | 1991 to 2020 |
| Future periods | up to three periods inside 2015 to 2100 | 2025 to 2035 |
| Emissions pathway | SSP2-4.5, SSP3-7.0, SSP5-8.5 | SSP3-7.0 |
| Residual rule | own residual (original), resampled residual | original |
| Coefficient uncertainty | on or off | on, weather terms only |

The run produces one **historical series** and, for each pathway, future period and climate model member, one **future series**. A series has one value of a statistic per simulation year $r$. Symbols are in [00_notation](00_notation.md).

## Method

### 1. Baseline population

The baseline sample $\mathcal{B}$ is the set of households of the chosen survey rounds. A household is kept only if the weather and every variable of the fitted model is observed for it: all weather regressors, the fixed-effect variables, the moderators and the covariates. This keeps Steps 2 and 3 on the population that the model can predict for. The sampling weights of the remaining households are not rescaled, and the number and weight share of households left out is reported with the run.

For every simulation, the household keeps its characteristics $M_i$, $X_i$, its fixed-effect cell (including the survey-round effect of its own round), its weight $\omega_i$ and, in the linear engine, its fitted residual.

### 2. Weather years

Each household $i$ lives in location $\ell(i)$ and was interviewed in calendar month $\mu_i$. For each year $r$ of the historical window, the simulation builds the weather regressors of $i$ as if the interview had taken place in month $\mu_i$ of year $r$, using the same window, aggregation, transformation and bins as in estimation ([12_weather_measures](12_weather_measures.md)):

$$W_i^{(r)} = \Phi\big(\tilde x_{\ell(i),\ (r,\mu_i)}\big) \qquad \text{(2.1)}$$

where $\tilde x$ is the aggregated location weather of Eq. (1.1) in [12_weather_measures](12_weather_measures.md) and $\Phi$ the chosen form (levels, polynomial terms or bin indicators). The simulation grid is therefore every interview month present in the baseline survey crossed with every year of the window. A household with interview month $\mu_i$ appears once per simulation year.

For a future series the weather is built from the same grid. The observed weather of year $r$ is shifted by the climate-model change of its calendar month ([31_climate_scenarios](31_climate_scenarios.md)), giving $W_i^{(r,s,m)}$. The label $r$ is the observed template year. A 30-year window gives 30 simulation years in every scenario, and the sequence of good and bad years is the one of the observed record.

### 3. Prediction

For the linear and logistic engines the model-scale prediction is the fitted model of Model 3 evaluated at the household's own characteristics and fixed effects, with only the weather changed:

$$\hat y_i^{(r)} = \hat f\big(W_i^{(r)},\ M_i,\ X_i,\ \hat\alpha_{g(i)},\ \hat\lambda_{t(i)}\big) \qquad \text{(3.1)}$$

For the quantile model the prediction is Eq. (4.3) of [22_model_rif](22_model_rif.md), with the baseline weather $W_i^{0}$ taken as the weather the household actually experienced at its interview.

### 4. Residual rule and levels

For a log outcome, the retransformed welfare of household $i$ in year $r$ is

$$Y_i^{*(r)} = \exp\big(\hat y_i^{(r)} + e_i^{(r)}\big) \qquad \text{(4.1)}$$

The residual term $e_i^{(r)}$ follows the residual rule. Let $\hat\varepsilon_j$ be the fitted residuals of Model 3 in the estimation sample (observed minus fitted, fixed effects included) and $\hat\sigma^2$ their variance.

| Rule | Residual term | In the app |
|---|---|---|
| Original | $e_i = \hat\varepsilon_{j(i)}$, the residual of the same unit in the estimation sample, matched on survey code, survey name, year and household identifier. If the unit is not in that sample, a residual chosen from the estimation residuals by a fixed function of the unit's identifier. The same value is used in every year. Each household keeps its own unexplained component, so the simulated distribution stays close to the observed one and the coefficient band covers only the change from the weather at the interview. | Offered, default |
| Resample | $e_i^{(r)}$ drawn with replacement from $\lbrace \hat\varepsilon_j\rbrace $, independently across households, locations and years. It adds noise and changes the level and spread of the simulated distribution, so it does not reproduce the observed one ([33_uncertainty](33_uncertainty.md), A7). The coefficient band of a level then uses all covariates and is several times wider than under the original rule. | Offered |
| Normal | $e_i^{(r)} \sim N(0,\hat\sigma^2)$ | Not offered |
| None | $e_i = 0$ | Not offered; used for the quantile model |

The draws are seeded by the run seed and the simulation year only. The historical series, all future scenarios and all climate models therefore use the same residual draws, and differences between series come from weather alone. For the quantile model, no residual is added and the rule is set to "none".

With the original rule and unchanged weather, a household in the estimation sample returns its observed welfare. A binary outcome has no retransformation. The residual is added to the predicted probability on the response scale. Under the original rule the residual is the response residual $y-\hat p$, so household values of a binary outcome can leave $[0,1]$ while the weighted mean is unaffected.

A cash transfer from a policy is added in Step 3 after the residual, as in Eq. (5.2) of [42_social_protection](42_social_protection.md).

### 5. Annual statistics

For simulation year $r$, scenario $s$ and member $m$ (the index $m$ and $s$ are absent for the historical series), the statistic is

$$T^{(r,s,m)} = \mathcal{A}\Big(\big\lbrace (Y_i^{*(r,s,m)},\ \omega_i)\big\rbrace _{i \in \mathcal{B}^{(r)}}\Big) \qquad \text{(5.1)}$$

where $\mathcal{A}$ is a metric of [32_metrics](32_metrics.md) and $\mathcal{B}^{(r)}\subseteq\mathcal{B}$ drops households whose prediction or weight is missing in that year. A missing prediction occurs when a fixed-effect cell is not in the estimation sample. The numbers of dropped household-years are counted and reported.

### 6. Weather support

A simulation extrapolates when the scenario weather lies outside the weather the model was estimated on. The app compares each scenario with a reference built from the historical-window weather at the baseline survey's locations and interview months.

- **Continuous weather.** The reference is the interval between the 1st and 99th percentiles of the reference weather. The share of scenario values outside it is reported for each variable, pooled over the climate models of the scenario.
- **Binned weather.** The reference is the set of bins that occur in the reference weather. The share of scenario values in other bins is reported.

A share above 5 per cent raises a warning.

### 7. Calibration check

The simulated historical statistic, averaged over the years, is compared with the same statistic computed from the observed survey outcome, using the same metric, weights and poverty line. A gap above 10 per cent of the observed level (for levels), or above 2 percentage points (for rates), is flagged. The check is a test of level, not of exact reproduction, because the simulation averages many weather years.

## Interpretation

- The historical series answers: what would welfare of the baseline population be under each weather year of the window? It is not a forecast of the welfare of any year.
- A future series answers the same question in a warmer or wetter world, with the observed year-to-year sequence kept.
- The spread across years is **weather variability**. The shift between the historical and the future series is the **climate signal**.
- With the original residual rule, differences between households are anchored on their observed welfare, so the simulated distribution starts from the observed one.
- The calibration check and the weather-support table should be read before trusting a scenario.

## Assumptions

- **A1. Fixed population.** [01_framework](01_framework.md) A2.
- **A2. Stable response.** [01_framework](01_framework.md) A3, including for weather outside the support.
- **A3. Fixed-effect cells exist.** Every simulated household lies in a cell of the estimation sample.
- **A4. Residual rule.** The unexplained component of welfare is the same in every year (original), or exchangeable across households and years (resample).
- **A5. Template years.** The observed record of the historical window represents the year-to-year variability of the future.
- **A6. Complete data.** Households dropped for missing weather or covariates are like those kept.

## Limitations and what is not modelled

- No growth, demographic change, migration, price change or adaptation.
- No change in the variability of weather beyond what the monthly shift implies ([31_climate_scenarios](31_climate_scenarios.md)).
- The residual rules do not let the unexplained component respond to weather.
- Weights are not rescaled when households are dropped.
- A household appears in the interview months of its own survey only. Weather in other months is not used.
- The historical window may end before the survey year, so the observed weather of the survey year itself need not be among the simulation years.

## In the app

- Step 2 > Simulation settings: baseline survey, historical window, projection periods, scenarios, residuals, coefficient uncertainty. **Run simulation** starts the run.
- Step 2 > Results: annual series, scenario bands, threshold tables. Step 2 > Diagnostics: weather distributions and the sources of uncertainty.

User guide: [Simulating welfare](https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#simulating-welfare).

## References

[@auffhammer2013] for the use of weather variation in economic projections. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Baseline waves and complete cases | 1 | `R/fct_step2_input.R` `step2_baseline_svy()`, `step2_baseline_complete()`, `step2_baseline_run()` |
| Run input and defaults | Setup | `R/fct_step2_input.R` `wise_step2_input()`; `R/fct_spec_defaults.R` `wise_default_sim()`, `WISEAPP_SIM_HIST_RANGE` |
| Simulation grid of months and years | (2.1) | `R/fct_simulations.R` `build_hist_sim_dates()`, `.add_sim_timestamp_fields()` |
| Survey-weather join and prediction | (3.1) | `R/fct_simulations.R` `run_sim_pipeline()`; `R/fct_predict_outcomes.R` `predict_outcome()` |
| Quantile-model prediction | 3 | `R/fct_rif_sim.R` `predict_rif()` |
| Training residuals | 4 | `R/fct_run_simulation.R` `fct_run_simulation()` |
| Residual rules | (4.1) | `R/fct_aggregation.R` `draw_residuals_vec()`; `R/fct_simulations.R` `residual_choices()`, `step2_add_residual_key()` |
| Annual statistics | (5.1) | `R/fct_aggregation_delta.R` `aggregate_pipeline_per_year()` |
| Excluded household-years | 5 | `R/fct_run_simulation.R` `step2_data_quality_notice()` |
| Weather support | 6 | `R/fct_sim_diag.R` `weather_support_reference()`, `weather_support_scenario()`, `weather_support_pool()` |
| Calibration check | 7 | `R/fct_sim_compare.R` `step2_baseline_check()` |
| Orchestration of the run | all | `R/fct_step2_compute.R` `step2_compute()`; `R/fct_run_simulation.R` `fct_run_simulation()` |
