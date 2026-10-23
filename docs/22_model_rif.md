---
id: rif-model
title: Unconditional quantile regression (RIF)
app_step: 1
depends_on: [notation, framework, outcomes, model-specification, linear-model]
symbols: [y, tau, q_tau, f_Y, beta_tau, W, X, F_hat]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#unconditional-quantile-regression-rif
code: [R/fct_fit_model.R, R/fct_rif_sim.R, R/fct_step1_headline.R, R/fct_results.R]
verified_against: 6529b81
---

# Unconditional quantile regression (RIF)

> The quantile model estimates how a marginal change in weather moves each tenth of the population welfare distribution, using the recentered influence function of Firpo, Fortin and Lemieux [@firpo2009]. It is offered for continuous outcomes. In simulations, each household is given the weather effect estimated at its own position in the baseline distribution, and the result is added to its observed baseline welfare. The estimated curve is a statement about the distribution, not about which households are vulnerable.

## Setup

The model uses the specification, fixed effects, sample and clustering of [20_model_specification](20_model_specification.md). Only the outcome changes. Let $y_i$ be the log outcome and $\tau\in\lbrace 0.1,0.2,\dots,0.9\rbrace $ the quantile grid. Symbols are in [00_notation](00_notation.md).

## Method

### 1. The transformed outcome

For each $\tau$, let $q_\tau$ be the sample $\tau$-quantile of $y_i$ in the estimation sample and let $\hat f(q_\tau)$ be a kernel density estimate of the outcome at $q_\tau$. The recentered influence function is

$$\text{RIF}(y_i;\ q_\tau) = q_\tau + \frac{\tau - \mathbf{1}[y_i \le q_\tau]}{\hat f(q_\tau)} \qquad \text{(1.1)}$$

Its average over the sample equals $q_\tau$. A regression of $\text{RIF}(y_i;q_\tau)$ on covariates therefore estimates the effect of a covariate on the **unconditional** quantile. The transformation takes only two values per quantile: $q_\tau + (\tau-1)/\hat f$ for units at or below $q_\tau$ and $q_\tau + \tau/\hat f$ above it.

Details of the estimate in Eq. (1.1):

- The sample quantile is the type-7 quantile, unweighted, computed on the estimation sample after the complete-case filter.
- The density is a Gaussian kernel estimate on a grid of 1,024 points with the Sheather and Jones bandwidth, and Silverman's rule if the bandwidth search fails. The density at $q_\tau$ is read by linear interpolation.
- A floor keeps the density from vanishing: it is at least 0.1 per cent of the peak density, and 1 per cent of the peak if the interpolated value is missing or not positive.
- The bandwidth and density depend only on $y$, so they are computed once and used for all nine quantiles.

### 2. Regression for each quantile

For each $\tau$ the app estimates the same Model 1, 2 and 3 as in [20_model_specification](20_model_specification.md), with the transformed outcome on the left:

$$\text{RIF}(y_i;\ q_\tau) = W_i^{\prime}\beta_\tau + M_i^{\prime}\theta_\tau + (W_i\otimes M_i)^{\prime}\gamma_\tau + X_i^{\prime}\delta_\tau + \alpha_{g(i),\tau} + \lambda_{t(i),\tau} + \varepsilon_{i\tau} \qquad \text{(2.1)}$$

The nine equations have the same regressors, fixed effects and sample, and are fitted by ordinary least squares in one stacked call. Standard errors are clustered at the location panel for each equation. The weather coefficient $\hat\beta_\tau$ is the approximate effect on the $\tau$-th quantile of the welfare distribution of a small shift in the distribution of weather.

Plotted against $\tau$, $\hat\beta_\tau$ is the **quantile curve**. A flat curve means that weather moves the whole distribution by the same amount. A curve that is more negative at low $\tau$ means that the lower tail falls more than the upper tail.

### 3. Position of a household

Simulation needs a position on the grid for each household. It is the rank of the household's baseline outcome in the estimation sample, clipped to the grid:

$$\tau_i = \min\Big\lbrace \max\big\lbrace \hat F(y_i),\ 0.1\big\rbrace ,\ 0.9\Big\rbrace  \qquad \text{(3.1)}$$

where $\hat F$ is the empirical distribution function of the estimation sample on the model scale (Eq. (4.1) in [00_notation](00_notation.md)). Households below the 10th or above the 90th percentile are treated as being at 0.1 or 0.9.

### 4. Simulated effect of a weather change

Let $W_i^{0}$ be the weather observed at the household's interview and $W_i^{*}$ the counterfactual weather. At each grid point $\tau_k$, the change in the fitted index of Eq. (2.1) is

$$\Delta_{ik} = \hat y_{ik}(W_i^{*}) - \hat y_{ik}(W_i^{0}) \qquad \text{(4.1)}$$

where $\hat y_{ik}$ is the fitted value of the $\tau_k$ equation. The fixed effects and covariates are identical in both terms and cancel. Only the weather terms, and their interactions with moderators, remain. The household's effect is the linear interpolation of $\Delta_{ik}$ between the two grid points that bracket $\tau_i$:

$$\Delta_i = (1-w_i)\ \Delta_{ik} + w_i\ \Delta_{i,k+1}, \qquad w_i = \frac{\tau_i-\tau_k}{\tau_{k+1}-\tau_k},\quad \tau_k\le\tau_i\le\tau_{k+1} \qquad \text{(4.2)}$$

and the simulated outcome is anchored at the observed baseline outcome:

$$y_i^{*} = y_i + \Delta_i \qquad \text{(4.3)}$$

No residual is drawn. The observed $y_i$ already contains the household's own unexplained component, so the residual rules of [30_simulation](30_simulation.md) do not apply. The policy extension of Eq. (4.3) is in [44_decomposition](44_decomposition.md).

## Interpretation

### What the estimation identifies

The coefficient $\hat\beta_\tau$ is a partial effect on a fixed feature of the population distribution, the $\tau$-quantile $q_\tau$ of the whole sample. No household is placed in a group by its own realised welfare, and no effect is estimated inside a group. This distinguishes it from a conditional quantile regression, or from separate regressions by consumption decile. Those approaches select on the outcome, which pushes the estimated effect in one direction. The quantile model does not have that sign restriction. If weather lowered every household's welfare by the same proportion, the whole distribution would shift and $\hat\beta_\tau$ would be flat. If weather compressed the distribution from above, $\hat\beta_\tau$ would be larger in size at high $\tau$. The method reports whichever pattern the data show.

### What the simulation does with the estimate

The simulation does use realised welfare: Eq. (3.1) assigns $\tau_i$ from the household's observed outcome, which is measured after any past weather shock. Two features should be read together.

1. The assignment is a way of interpolating an estimated distributional curve onto households. It is not a claim that a household is vulnerable **because** it is poor. With repeated cross-sections, the data cannot separate "poor households are more vulnerable" from "households whose welfare fell now sit lower".
2. The linear model rests on the same post-shock outcomes. It regresses post-shock log welfare on weather and, with each household's own residual, rebuilds a simulated distribution that starts from the same observed households. It applies one slope to everyone and does not use rank. The quantile model uses the distributional information that the linear model discards. Neither engine observes pre-shock rank.

For a weather-only scenario, $\tau_i$ is fixed and Eq. (4.3) is the interpolated weather effect added to the observed outcome. For aggregates that depend on the shape of the distribution, such as the poverty rate and the Gini index, the non-uniform shift of the estimated curve is what the aggregate measures. The household-level labelling can be imperfect while the aggregate response is still well described.

### Anonymity

The quantile model estimates movements of the **quantiles** of the distribution, not of a fixed set of households. Reading a fall in $q_{0.1}$ as "the same poor households lost this much" assumes that the composition of the lower tail is stable, that is, that weather does not cause large reranking. The distributional reading is licensed. The household-level reading is not.

## Assumptions

- **A1. Local linearity.** The effect of a covariate on the unconditional quantile is well approximated by a linear regression of the transformed outcome. This holds for small shifts and becomes weaker for large ones.
- **A2. Density estimate.** The nonparametric density at each quantile is accurate. It is least reliable at the extremes of the grid.
- **A3. Rank stability.** A household's position in the baseline distribution is informative about the weather sensitivity it will have in the counterfactual. This is a controlled approximation for the marginal weather changes in a stress test. It is weaker for large weather changes that would move many households across the distribution.
- **A4. Smooth curve.** The effect varies smoothly between grid points, so linear interpolation of Eq. (4.2) is adequate.
- **A5. Exogeneity.** As for the linear model: Eq. (3.1) in [01_framework](01_framework.md).
- **A6. Observed baseline.** The observed baseline outcome of each household is the right anchor for the simulation.

## Limitations and what is not modelled

- Households below the 10th and above the 90th percentile are given the effect at the boundary quantile.
- Nothing prevents estimated quantile functions from crossing, so adjacent quantile effects need not be ordered.
- The bandwidth is chosen once for the full estimation sample. It is not adapted to a survey round or a group.
- Standard errors treat the transformed outcome as given, so they ignore the estimation of $q_\tau$ and $\hat f$.
- The nine equations are fitted separately. Cross-quantile covariance is not used in the uncertainty bands ([33_uncertainty](33_uncertainty.md)).
- A weather effect in the simulation is available only for households that have an observed baseline outcome.
- Diagnostics shown for the model use the median equation only.

## In the app

- Step 1 > Model: choose "Unconditional quantile regression (RIF)" when the outcome is continuous. Results shows the quantile curve with its 95 per cent band; Model fit reports fit statistics for each quantile.

User guide: [Unconditional quantile regression](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#unconditional-quantile-regression-rif).

## References

[@firpo2009] for the estimator. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| RIF transformation | (1.1) | `R/fct_rif_sim.R` `compute_rif()`, `compute_rif_multi()` |
| Bandwidth and density, shared across quantiles | (1.1) | `R/fct_fit_model.R` `ENGINE_REGISTRY` (`rif` entry, `prepare_outcome`) |
| Stacked regression for the nine quantiles | (2.1) | `R/fct_fit_model.R` `ENGINE_REGISTRY` (`rif` entry, `fit_one`), `fit_model()` |
| Quantile curve table | (2.1) | `R/fct_rif_sim.R` `build_rif_grid()` |
| Position of a household | (3.1) | `R/fct_rif_sim.R` `predict_rif()` |
| Weather effect at each grid point and interpolation | (4.1) to (4.3) | `R/fct_rif_sim.R` `predict_rif()`, `interpolate_delta()` |
| Test that the effect is flat across quantiles | Interpretation | `R/fct_step1_headline.R` `step1_rif_heterogeneity_p()` |
| Quantile curve figure | (2.1) | `R/fct_results.R` `echart_weather_effect_plot()` |
