---
id: uncertainty
title: Uncertainty propagation
app_step: 2
depends_on: [notation, model-specification, linear-model, rif-model, simulation, metrics]
symbols: [Sigma, L, F, h, T, Y, omega, z]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#sources-of-uncertainty-in-simulations
code: [R/fct_aggregation_delta.R, R/fct_aggregation.R, R/fct_simulations.R, R/fct_results.R, R/fct_rif_sim.R, R/fct_step2_tables.R, R/fct_sim_compare.R, R/fct_uncertainty_helpers.R]
verified_against: 8592a9d
---

# Uncertainty propagation

> The app reports four sources of uncertainty: the estimated coefficients, the unexplained part of welfare, the weather year, and the climate model. Coefficient uncertainty is carried through to every metric in closed form with the delta method. The other three are shown as empirical spreads across simulated years and members. This page gives the formulas, the gradient of each metric, the band transforms and the rules for combining them.

## Setup

For a metric $T$ computed on household welfare $Y_i = \exp(y_i)$, the delta method needs three things: the covariance $\hat\Sigma$ of the coefficients, the design row $x_i$ of each household under the scenario, and the derivative of the metric with respect to each household's welfare. Symbols are in [00_notation](00_notation.md). Metric definitions are in [32_metrics](32_metrics.md). Let $\kappa_i = \partial Y_i/\partial y_i$, which is $Y_i$ for a log outcome and $1$ for an outcome in levels, and let $\tilde\omega_i$ be the normalised weights.

| Source | How it is represented |
|---|---|
| Coefficients | Analytic standard deviation of each annual statistic (delta method) |
| Unexplained welfare | A residual rule ([30_simulation](30_simulation.md)). It adds variance only for the random rules |
| Weather year | Empirical spread across the simulated years |
| Climate model | Empirical spread across the members of the ensemble |

## Method

### 1. Factor loading

Let $\hat\Sigma$ be the coefficient covariance of Model 3, clustered by location panel ([20_model_specification](20_model_specification.md)), and $L$ the lower-triangular matrix with $LL^{\prime}=\hat\Sigma$. For household $i$ with non-fixed-effect design row $x_i$, the **factor loading** is $F_i = x_i^{\prime}L$. If the coefficients were perturbed by $z \sim N(0,I)$, the prediction would move by $F_i z$, and

$$\mathrm{Var}(F_i z) = x_i^{\prime}\hat\Sigma\ x_i \qquad \text{(1.1)}$$

which is the usual variance of a linear prediction. The app does not draw $z$. It uses $F$ in the closed form below.

**Anchored loading.** With the "original" residual rule the displayed prediction of a household is its observed outcome plus the change in the fitted value, $y_i^{\text{obs}} + f(x_i) - f(x_i^{0})$, because the household's residual carries $f(x_i^{0})$, the fitted value at the weather of its interview. The observed outcome pins down the part of the level that depends on $x_i^{0}$, so only the change carries coefficient uncertainty and the loading is

$$F_i = (x_i - x_i^{0})^{\prime}L \qquad \text{(1.2)}$$

with $x_i^{0}$ the design row of the household in the estimation sample that its residual is matched to. The band of a level is then zero when the simulated weather equals the weather of the interview, and grows with the distance from it. Using $x_i^{\prime}L$ instead would treat the part of the prediction that the observed outcome already fixes as uncertain, and over-state the band of a level by an order of magnitude when the weather change is small. Households whose residual is not matched to an estimation row (it is a hash-keyed draw) and the other residual rules keep $x_i^{\prime}L$. Paired differences are not affected when the aggregate is linear in the predictions, because $x_i^{0}$ cancels. For a non-linear aggregate of a log outcome the gradient $h_i$ differs between the arms, and the anchored loading is the correct one in $F^{\prime}h$.

### 2. Delta method for a metric

The metric changes with the prediction of household $i$ through the gradient $h_i = (\partial T/\partial Y_i)\ \kappa_i$. Define the gradient of $T$ with respect to the coefficients and the variance:

$$F_{\text{agg}} = F^{\prime}h, \qquad \mathrm{Var}(T) \approx \underbrace{\Vert F_{\text{agg}}\Vert ^2}_{\text{coefficients}} + \underbrace{\sigma_\varepsilon^2\textstyle\sum_i h_i^2}_{\text{residuals}} \qquad \text{(2.1)}$$

The residual term is present only for the "resample" and "normal" rules, with $\sigma^2_\varepsilon$ the variance of the estimation residuals. For the "original" and "none" rules it is zero, because a household's own residual is a fixed shift. The standard deviation is $\mathrm{SD}(T)=\sqrt{\mathrm{Var}(T)}$. Households whose welfare, weight or loading row is not finite are left out of both the gradient and $F$, and counted.

### 3. Gradients of the metrics

| Metric | Gradient $h_i$ |
|---|---|
| Mean | $\tilde\omega_i\ \kappa_i$ |
| Total | $\omega_i\ \kappa_i$ |
| Poverty gap | $-\tilde\omega_i\ \kappa_i\ \mathbf{1}[Y_i<z]/z$ |
| Poverty severity | $-2\ \tilde\omega_i\ \kappa_i\ \max(z-Y_i,0)/z^2$ |
| Poverty rate | $-\tilde\omega_i\ \kappa_i\ \phi\big((z-Y_i)/b\big)/b$ |
| Median | $k_i\ \kappa_i\big/\sum_j k_j$, with $k_i=\tilde\omega_i\ \phi\big((\hat m-Y_i)/b_m\big)/b_m$ |
| Gini | $\tilde\omega_i\ \kappa_i\ (2F_i-1-G)/\bar Y$ |
| Prosperity gap | $-\tilde\omega_i\ \kappa_i\ (28/Y_i^{2})\ \mathbf{1}[0<Y_i<28]$ |
| Average poverty | $-\tilde\omega_i\ \kappa_i/Y_i^{2}$ over households with $Y_i>0$ |

Notes on the table:

- The poverty rate has a jump at the line, so the indicator is replaced by a normal distribution function $\Phi((z-Y)/b)$, whose derivative gives the gradient. The bandwidth is $b=\max\lbrace 0.05\ z,\ \mathrm{median}_i(\kappa_i\Vert F_i\Vert )\rbrace $: at least 5 per cent of the line, and at least the typical prediction uncertainty of a household. A narrower bandwidth would miss households that cross the line when coefficients change.
- The median is the solution of a smoothed equation $\sum_i\tilde\omega_i\Phi((m-Y_i)/b_m)=1/2$. The gradient follows by implicit differentiation. The bandwidth $b_m$ is Silverman's rule of thumb for the welfare values. If the density at the median is not positive, the gradient is set to zero, and the coefficient SD of the median is then zero.
- The Gini gradient holds the ranking of households fixed. It is the derivative that applies when a coefficient change moves welfare levels and leaves the order of households unchanged. A common proportional change of all welfare leaves $G$ unchanged, and the gradient reflects this.
- The prosperity gap and average poverty do not depend on the poverty line.

### 4. Bands

Given the standard deviation, the band for quantiles $q_{lo}, q_{hi}$ (by default 10 and 90 per cent) is symmetric on a scale that respects the support of the metric:

| Metric | Scale | Band |
|---|---|---|
| Poverty rate, gap, severity | logit | $\Lambda\big(\mathrm{logit}(T) + z_q\ \mathrm{SD}/[T(1-T)]\big)$ |
| Median, average poverty | log | $\exp\big(\log T + z_q\ \mathrm{SD}/T\big)$ |
| Mean, total, Gini, prosperity gap | identity | $T + z_q\ \mathrm{SD}$ |

where $z_q=\Phi^{-1}(q)$ and $\Lambda$ is the logistic function. If the SD is zero or missing, the band collapses to the point estimate. If $T$ lies on the boundary of its support (a rate of 0 or 1), the symmetric band on the original scale is used.

### 5. Which coefficients are perturbed

A household's coefficient uncertainty is mostly irrelevant to a change in weather. Write the counterfactual prediction as the observed baseline plus a shift: with a household's own fitted residual held fixed, $y^{*}_i = y_i + (W^{*}_i - W_i)^{\prime}\hat\gamma$, where $\hat\gamma$ collects the coefficients on terms that change. The uncertainty on coefficients of terms that do not change cancels through the residual. The app uses this **additive-decomposition scope** by default.

- **Active coefficients.** Every coefficient whose name involves a weather variable, or involves a variable that the scenario changes, including interactions. Intercepts are excluded. For the linear model the policy arm of Step 3 adds the coefficients on the policy variables to the block as extra columns ([40_policy_framework](40_policy_framework.md), Section 5). For the quantile model it reuses the baseline loading.
- **Block factor.** The loading uses only the active block of the covariance, $F_i = x_{a,i}^{\prime}L_{a}$ with $L_aL_a^{\prime}=\hat\Sigma_{aa}$, a fresh Cholesky factor of that block. Selecting columns of $x_i^{\prime}L$ would give a wrong variance when active and inactive coefficients are correlated.
- **When it applies.** For the linear model, only with the "original" residual rule. For the quantile model, with any residual rule, because the observed baseline outcome plays the role of the fixed residual.
- **Switch.** "Include uncertainty on all covariates" removes the restriction and uses the full covariance.

The restricted variance is not guaranteed to be smaller than the full one, because the covariance between active and inactive coefficients can be negative.

### 6. Quantile model

For the quantile model, $\hat\Sigma_k$ and $L_k$ come from the equation of each quantile $\tau_k$ ([22_model_rif](22_model_rif.md)). The loading of household $i$ is the interpolation between the two grid points around its position $\tau_i$ (Eq. (3.1) in [22_model_rif](22_model_rif.md)):

$$F_i = (1-w_i)\ x_i^{*\prime}L_k + w_i\ x_i^{*\prime}L_{k+1} \qquad \text{(6.1)}$$

with $x_i^{*}$ the design row under the scenario minus the design row at the weather of the interview, as in Eq. (1.2). Households outside the grid take the loading of the boundary quantile, with no extra penalty. The nine equations are treated as independent. There is no residual variance.

### 7. Combining members

For simulation year $r$ and $M$ climate-model members, with member values $T^{m}$:

$$\sigma^2_{\text{within}} = \frac1M\sum_m\big(\mathrm{Var}_{\text{coef}}^{m} + \mathrm{Var}_{\text{resid}}^{m}\big), \qquad \sigma^2_{\text{across}} = \mathrm{Var}_m\big(T^{m}\big), \qquad \sigma^2_{\text{pool}} = \sigma^2_{\text{within}} + \sigma^2_{\text{across}} \qquad \text{(7.1)}$$

This is the law of total variance. The analytic pooled band is $\bar T \pm z_q\ \sigma_{\text{pool}}$, and the empirical model band takes quantiles of the member values. With one member, $\sigma^2_{\text{across}}=0$.

In the return-period table, the pooled standard deviation combines the median coefficient SD across members at the return period with the variance across members of the return-period value ([32_metrics](32_metrics.md)). Inter-annual variation is already inside each annual value and is not added again.

### 8. Paired contrasts

When two results use the same coefficients, their errors are correlated. The standard deviation of a difference is

$$\mathrm{SD}\big(T^{s}-T^{\text{ref}}\big) = \big\Vert F_{\text{agg}}^{s} - F_{\text{agg}}^{\text{ref}}\big\Vert  \qquad \text{(8.1)}$$

and not $\sqrt{\mathrm{SD}_s^2+\mathrm{SD}_{\text{ref}}^2}$. For the difference of year-averaged values, the gradients are first averaged over the years, because the coefficient error is shared by all years and does not shrink with their number. Where a result is shown as a difference from the historical mean, the reference gradient is the average of the historical gradients, and any residual variance of the scenario is kept. The same rule gives the interval of the policy effect in Step 3, where both arms use the same loading ([40_policy_framework](40_policy_framework.md)).

## Interpretation

- A coefficient band answers: how different could this statistic be if the weather coefficients were a little different? It is conditional on the specification.
- The spread across years is not an estimation error. It is the variability that the stress test is designed to show.
- The spread across members measures the disagreement between climate models, not the probability of a scenario.
- The three variances are shown side by side in the Diagnostics tab. They do not add as standard deviations.
- Under the default scope, a band on a level of welfare is narrower than the band of the full prediction, because coefficients on unchanged variables are held at their estimates.

## Assumptions

- **A1. Local linearity.** The metric is well approximated by its first-order expansion in the household predictions. This is weakest near a threshold and for the poverty rate, which also depends on the bandwidth.
- **A2. Gaussian coefficients.** The coefficient estimates are jointly normal with covariance $\hat\Sigma$.
- **A3. Rank stability of the Gini.** Coefficient changes do not reorder households.
- **A4. Cancellation through the residual.** The household's unexplained component is fixed (original rule), and the model is additive in changed and unchanged terms.
- **A5. Independent quantile equations.** The nine quantile equations are treated as independent.
- **A6. Exchangeable members.** Climate models are equally informative and independent.
- **A7. Independent sources.** The residual and coefficient errors are independent, and members' coefficient errors are of similar size.

## Limitations and what is not quantified

- Misspecification of the functional form and omitted variables.
- Error in the weather data, and uncertainty about the interview month and location.
- Poverty-line uncertainty and survey-weight uncertainty.
- The estimation of the quantile density and of the quantiles themselves (the quantile model).
- Cross-quantile covariance, and correlation between the baseline and the prediction of a household in the quantile model.
- Scenario uncertainty: the choice of pathway, horizon and policy design.
- Coefficient uncertainty for non-linear and tree-based models.
- Uncertainty in the bandwidth rules. The poverty rate and the median depend on the smoothing bandwidths.

## In the app

- Step 2 > Simulation settings: **Include coefficient uncertainty**, and **Include uncertainty on all covariates**.
- Step 2 > Results: the width of the coefficient band and of the model band. Step 2 > Diagnostics: the contribution of each source.

User guide: [Sources of uncertainty](https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#sources-of-uncertainty-in-simulations).

## References

[@cameronmiller2015] for the clustered covariance that enters $\hat\Sigma$; [@burkedykema2015] for propagating climate-model uncertainty; [@firpo2009] for the quantile model. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Covariance factor | 1 | `R/fct_simulations.R` `compute_chol_vcov()`, `COEF_VCOV_SPEC` |
| Factor loading | (1.1) | `R/fct_simulations.R` `compute_factor_loading()` |
| Anchored loading | (1.2) | `R/fct_simulations.R` `.anchor_design_shift()` |
| Delta-method aggregation | (2.1) | `R/fct_aggregation_delta.R` `aggregate_with_uncertainty_delta()` |
| Gradients | 3 | `R/fct_aggregation_delta.R` `gradient_for_method()` |
| Bands | 4 | `R/fct_aggregation_delta.R` `apply_band_transform()`; `R/fct_sim_compare.R` `resolve_band_q()` |
| Residual draws | (2.1) | `R/fct_aggregation.R` `draw_residuals_vec()` |
| Active scope and block factor | 5 | `R/fct_results.R` `attach_active_mask()`, `build_active_coef_mask()`, `detect_modified_cols()` |
| Quantile-model loading | (6.1) | `R/fct_rif_sim.R` `interpolate_F_loading()` |
| Pooling members | (7.1) | `R/fct_aggregation.R` `combine_ensemble_results()` |
| Per-model matrices | 7 | `R/fct_uncertainty_helpers.R` `by_model_matrix()` |
| Paired contrasts | (8.1) | `R/fct_step2_tables.R` `step2_hist_f_ref()`, `step2_contrast_sd()`; `R/fct_sim_compare.R` `step2_delta_ci()`, `paired_effect_summary()` |
| Variance breakdown | 7 | `R/fct_step2_tables.R` `step2_variance_breakdown()` |
