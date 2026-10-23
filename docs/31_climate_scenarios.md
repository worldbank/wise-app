---
id: climate-scenarios
title: Climate scenarios (monthly delta method)
app_step: 2
depends_on: [notation, data, weather-measures]
symbols: [l, mu, m, v, s, W, x]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#the-delta-method-change-factor-perturbation
code: [R/fct_get_weather.R, R/fct_simulations.R, R/fct_step2_input.R, R/fct_run_simulation.R]
verified_against: 6529b81
---

# Climate scenarios (monthly delta method)

> Future weather is built by shifting the observed monthly weather of each location by the change that each climate model projects for the same calendar month. Temperature-type variables are shifted by a difference and rainfall-type variables are scaled by a ratio. The observed year-to-year sequence is kept. Only the monthly means move.

## Setup

The climate data are monthly values of the same weather variables as the observed data, from CMIP6 climate models, on a grid coarser than the observed data. For each pathway there is one historical experiment (to 2014) and one projection (from 2015). Each model is a **member** $m$; the ensemble holds up to about 30. Pathways are SSP2-4.5, SSP3-7.0 and SSP5-8.5 [@eyring2016]. Symbols are in [00_notation](00_notation.md): $\ell$ location, $\mu$ calendar month, $v$ weather variable, $m$ member.

The user chooses a historical window $P_0$ and one to three future periods $P_s$ (each a span of years, for example 2025 to 2035).

## Method

### 1. Monthly climatology of a climate model

For member $m$, H3 cell $c$ and calendar month $\mu$, the climatology over a period $P$ is the mean of all monthly values in $P$ that fall in month $\mu$:

$$\bar x^{\,m}_{c\mu}(P) = \frac{1}{|P_\mu|}\sum_{h \in P_\mu} x^{\,m}_{ch} \tag{1.1}$$

where $P_\mu$ is the set of months of $P$ with calendar month $\mu$. Two periods are used.

- **Baseline period $P_0$.** The span from the first to the last date of the simulation grid ([30_simulation](30_simulation.md)). With interviews in all months, this is January of the first historical year to December of the last. The baseline pools the monthly values of the historical experiment (to 2014) and of the projection (from 2015) and averages them once. This avoids giving the few projection years too much weight when the window straddles 2015.
- **Future period $P_s$.** From 1 January of the first year to 31 December of the last year of the period chosen by the user.

If the interview months of the baseline survey do not cover all calendar months, $P_0$ starts in the earliest interview month of the first year and ends in the latest interview month of the last year. Calendar months before the first or after the last of these are then averaged over one year fewer.

### 2. Change factor

For each cell, member and month, the change from the baseline to the future period is

$$\Delta^{m}_{c\mu} = \begin{cases} \bar x^{\,m}_{c\mu}(P_s) - \bar x^{\,m}_{c\mu}(P_0) & \text{additive} \\[6pt] \dfrac{\bar x^{\,m}_{c\mu}(P_s) + \varepsilon}{\bar x^{\,m}_{c\mu}(P_0) + \varepsilon} & \text{multiplicative} \end{cases} \tag{2.1}$$

with $\varepsilon = 0.001$ to avoid division by zero in dry months. A variable measured in millimetres or in days uses the multiplicative form. Every other variable, including temperature and standardised indices, uses the additive form.

The change at the location is the population-weighted mean of the cell changes, with the weights and the missing-value rule of Eq. (3.1) in [10_data](10_data.md). If the climate grid is coarser than the survey cells, the survey cells are mapped to their parent climate cell.

### 3. Perturbed monthly series

The observed monthly series of location $\ell$ is changed month by month, using the change of its own calendar month:

$$x^{*m}_{\ell h} = \begin{cases} x_{\ell h} + \Delta^{m}_{\ell\mu(h)} & \text{additive} \\ x_{\ell h}\,\Delta^{m}_{\ell\mu(h)} & \text{multiplicative} \end{cases} \tag{3.1}$$

This is applied to the **raw** monthly series, before any window. The window, aggregation, transformation and form of [12_weather_measures](12_weather_measures.md) are then applied to $x^{*m}_{\ell h}$, separately for each member:

1. the rolling window of Eq. (1.1) in [12_weather_measures](12_weather_measures.md), so that each month in a window is shifted by the change of its own calendar month;
2. the anomaly transformation, relative to the **observed** 1991 to 2020 normal and not to a normal of the projected climate, so a warmer climate appears as a positive anomaly;
3. the bin cut points set at estimation, so that projected values beyond the observed range fall in the outer bins.

### 4. Members and scenarios

A member is used only if it has a change for every location-month of the period and every selected variable. A member with missing coverage is left out with a warning that names it. Each pathway-period-member combination is an independent weather series and gives one simulation series ([30_simulation](30_simulation.md)). All members have equal weight. Members are not selected for skill.

The simulation years of a future series are the years of the historical window. A future period only decides which climatology of the climate model is compared with the baseline.

## Interpretation

- A future series keeps the observed order of wet and dry, hot and cool years of the historical window. Its monthly means are those of the future climate according to member $m$.
- Differences between members are differences in the projected change, not in the weather sequence.
- Near-term periods (to 2035) differ little between pathways. Pathways diverge toward mid-century.
- A multiplicative change cannot make rainfall negative. A very large ratio in a dry month can produce a large absolute change.
- Because the baseline of the climate model is taken over the same window as the observed record, the change is internally consistent. A short window gives a less stable model climatology than a 30-year window.

## Assumptions

- **A1. Credible change signal.** The climate models give a credible change in the monthly mean, even where they are biased in level.
- **A2. Additivity and proportionality.** Temperature-type changes are the same in all weather years of a month, and rainfall-type changes are proportional.
- **A3. Observed record as template.** The variability of the historical window represents the variability of the future.
- **A4. Equal member weights.** Each retained member is equally informative.
- **A5. Consistent baseline.** The climate-model baseline period matches the window of the observed record.

## Limitations and what is not modelled

- Variance scaling: the year-to-year variance of the future series is that of the observed record.
- Quantile mapping: changes in the shape of the distribution, in extremes beyond the mean shift, and in the frequency of wet and dry days are not represented.
- Changes in autocorrelation, seasonality of variability, and compound events.
- Bias correction beyond the delta method, and spatial detail finer than the climate grid, except through the observed record.
- Changes within a future period: each period uses a single mean climatology.
- Weights for model skill or independence.
- Only the weather variables that the model uses are perturbed.

## In the app

- Step 2 > Simulation settings: historical window, projection periods (up to three) and pathways. The Diagnostics tab compares the weather distribution of each scenario with the weather used in estimation.

User guide: [The delta method](https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#the-delta-method-change-factor-perturbation).

## References

[@eyring2016] for CMIP6; [@auffhammer2013] for the use of climate-model changes in economic analysis; [@burkedykema2015] for using the full ensemble; [@c3satlas2024] for the data source. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Baseline and future period of the run | 1 | `R/fct_step2_input.R` `wise_step2_input()`, `.step2_valid_future_period()` |
| Climate-model monthly climatology | (1.1) | `R/fct_get_weather.R` `get_weather()` (internal `.cmip6_h3_monthly`) |
| Change factor and population-weighted location change | (2.1) | `R/fct_get_weather.R` `get_weather()` (internal `.make_delta_exprs`) |
| Additive or multiplicative rule | (2.1) | `R/fct_simulations.R` `build_perturbation_method()` |
| Perturbed monthly series, window, anomaly, bins | (3.1) | `R/fct_get_weather.R` `get_weather()` (internal `.make_perturb_exprs`), `.apply_transformations()`, `.apply_binning()` |
| Exclusion of incomplete members | 4 | `R/fct_get_weather.R` `get_weather()` |
| Scenario keys by pathway, period, member | 4 | `R/fct_run_simulation.R` `fct_run_simulation()` |
