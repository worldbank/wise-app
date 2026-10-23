---
id: linear-model
title: Linear and logistic models
app_step: 1
depends_on: [notation, framework, outcomes, model-specification]
symbols: [y, Y, W, M, X, beta, gamma, delta, alpha, lambda, epsilon, Sigma]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#high-dimensional-fixed-effects-demeaning
code: [R/fct_fit_model.R, R/fct_predict_outcomes.R, R/fct_step1_headline.R, R/fct_aggregation.R, R/fct_results.R]
verified_against: 6529b81
---

# Linear and logistic models

> For a continuous outcome the app fits a linear regression of log welfare with absorbed fixed effects. For a binary outcome it fits a linear probability model or a logistic regression. All three estimate one weather response, shared by all households inside a moderator group. This page states the estimators, how a coefficient is read, and how the fitted model produces predictions in Steps 2 and 3.

## Setup

The regressors, fixed effects and sample are those of [20_model_specification](20_model_specification.md), Model 3. Let $Z_i = (W_i, M_i, W_i\otimes M_i, X_i)$ and let $\phi$ be the stacked coefficients on $Z_i$. Let $\alpha_{g(i)} + \lambda_{t(i)}$ be the fixed effects. Symbols are in [00_notation](00_notation.md).

## Method

### 1. Linear regression with absorbed fixed effects

For a continuous outcome, $y_i = \log Y_i$, and the model is

$$y_i = Z_i^{\prime}\phi + \alpha_{g(i)} + \lambda_{t(i)} + \varepsilon_i \tag{1.1}$$

estimated by ordinary least squares. After the fixed-effect means are removed from every variable, the estimator is

$$\hat\phi = \big(\ddot Z^{\prime}\ddot Z\big)^{-1}\ddot Z^{\prime}\ddot y \tag{1.2}$$

where dots mark the residuals from projecting on the fixed-effect dummies (Eq. (2.1) in [20_model_specification](20_model_specification.md)). Under the exogeneity condition of the framework, $\hat\beta$ is the within-cell partial association between weather and log welfare.

The same estimator is used for a binary outcome, with $y_i\in\{0,1\}$. The coefficients are then changes in the probability of the event (a linear probability model).

### 2. Reading a coefficient

A coefficient on a log outcome is a semi-elasticity. For a change $\Delta w$ in a continuous weather regressor with no polynomial or interaction terms, the proportional change in welfare is

$$\frac{\Delta Y}{Y} = e^{\hat\beta\,\Delta w} - 1 \tag{2.1}$$

For a bin $b$, $100\,(e^{\hat\beta_b}-1)$ is the per cent difference in welfare between bin $b$ and the lowest bin. With a moderator $m$ and an interaction, the slope is $\hat\beta + \hat\gamma m$. With a polynomial, the slope at weather level $w$ is $\hat\beta_1 + 2\hat\beta_2 w + 3\hat\beta_3 w^2$, and the confidence band of the slope uses the full coefficient covariance (Eq. (3.1) in [20_model_specification](20_model_specification.md)).

### 3. Logistic regression

For a binary outcome the user may instead fit a logit:

$$\Pr(y_i = 1 \mid Z_i, g, t) = \Lambda\big(\eta_i\big), \qquad \eta_i = Z_i^{\prime}\phi + \alpha_{g(i)} + \lambda_{t(i)}, \qquad \Lambda(u) = \frac{1}{1+e^{-u}} \tag{3.1}$$

The coefficients are changes in the log-odds. They are estimated by maximum likelihood with the fixed effects included in the index. If a fixed-effect cell has no events (or all events), its observations carry no information and the cell effect is not identified. This is called separation. It can make coefficients very large. If the outcome is not a clean 0/1 indicator, the app fits the linear model instead and records the fallback.

Because the logit is nonlinear, the effect of a weather contrast on the probability depends on the baseline. The app reports a probability change at one reference household, the household whose fitted probability is the sample median:

$$\Delta p = \Lambda\big(\hat\eta_0 + \hat c\big) - \Lambda\big(\hat\eta_0\big) \tag{3.2}$$

where $\hat\eta_0$ is the reference household's fitted index, fixed effects included, and $\hat c$ is the estimated contrast in the index.

### 4. Prediction and retransformation

A prediction of the model-scale outcome for a unit with regressors $Z_i$ is $\hat y_i = Z_i^{\prime}\hat\phi + \hat\alpha_{g(i)} + \hat\lambda_{t(i)}$. Step 2 adds a residual term chosen by the residual rule and returns to levels:

$$y_i^{*} = \hat y_i + \hat e_i, \qquad Y_i^{*} = \exp\big(y_i^{*}\big) \tag{4.1}$$

The residual term $\hat e_i$ is the unit's own fitted residual, a draw from the fitted residuals, a normal draw with the same standard deviation, or zero ([30_simulation](30_simulation.md)). The app applies no smearing correction. With a residual term, the retransformed outcome keeps the dispersion of the data. Without one, $\exp(\hat y_i)$ estimates the conditional geometric mean of welfare (the median if the errors are symmetric) and not its mean, and so understates the mean by an amount that grows with the residual variance.

A fixed effect that is absent from the estimation sample has no estimate. A unit in such a cell has a missing prediction, and the number of such units is counted and reported with the simulation.

### 5. Use in Steps 2 and 3

Step 2 changes the weather regressors and re-evaluates Eq. (4.1) with the fixed effects, covariates and residual of each baseline household unchanged. Step 3 changes the policy variables, and the difference between the two predictions is the policy effect for the linear engine ([40_policy_framework](40_policy_framework.md)). Because $\hat\beta$ is common to all households in a moderator group, a weather change shifts every such household by the same proportion, apart from the interaction terms.

## Interpretation

- Low overall $R^2$ is common in household welfare regressions. The within $R^2$ and the size, sign and stability of the weather coefficients across Models 1 to 3 are more informative ([24_model_results](24_model_results.md)).
- A weather response that looks the same for poor and rich households is a property of the linear model, not a finding. To see whether the response differs along the welfare distribution, use the quantile model ([22_model_rif](22_model_rif.md)).
- Predictions from a linear probability model can fall outside $[0,1]$.

## Assumptions

- **A1. Correct functional form.** The conditional mean of the outcome is linear in $Z_i$, after the chosen polynomial, bin and interaction expansion.
- **A2. Exogeneity.** $\mathbb{E}[\varepsilon_i \mid Z_i, g, t]=0$. Fixed effects remove confounders that are constant within a cell. Confounders that vary within a cell are not removed.
- **A3. Common slope.** One weather slope applies to all households of a moderator group, at every point of the welfare distribution.
- **A4. Fixed-effect cells are stable.** Simulated and policy households are in cells that exist in the estimation sample, and policy changes do not move them to other cells.
- **A5. Stable residual distribution.** The fitted residuals describe the unexplained variation under the counterfactual weather as well.
- **A6. No separation.** For the logit, each fixed-effect cell has both outcomes.

## Limitations and what is not modelled

- No distributional heterogeneity beyond the interactions the user specifies.
- No resilience effect of a transfer through a lower weather sensitivity, unless the user adds an interaction. See [44_decomposition](44_decomposition.md).
- One estimate per coefficient. Heterogeneity across quantiles needs a separate model.
- Sensitivity to extreme outcomes, because the loss is squared.
- No retransformation correction for the mean of a log outcome (Section 4).
- Fixed effects of cells outside the estimation sample are not available.
- No instrumental variables, no panel structure of households, and no household fixed effects: the surveys are repeated cross-sections.

## In the app

- Step 1 > Model: choose Linear regression or Logistic regression. Results show effect curves, the progressive coefficient plot and the regression table; Model fit shows fit statistics and diagnostics ([24_model_results](24_model_results.md)).

User guide: [Model specification and estimation](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#high-dimensional-fixed-effects-demeaning).

## References

[@cameronmiller2015] on clustered inference. Retransformation after a log model is discussed in Duan (1983), *Journal of the American Statistical Association* 78(383), 605-610, which the app does not apply. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Linear and logit estimation with absorbed fixed effects | (1.1), (3.1) | `R/fct_fit_model.R` `ENGINE_REGISTRY` (`fixest` entry), `fit_model()` |
| Fall back from logit to linear | 3 | `R/fct_fit_model.R` `fit_model()` |
| Coefficient reading, contrasts | (2.1) | `R/fct_step1_headline.R` `step1_scenarios()`, `.s1_fixest_scenarios()`, `step1_fmt_effect()` |
| Probability change at the median-risk household | (3.2) | `R/fct_step1_headline.R` `.s1_to_pp()` |
| Slope curve and band for polynomial terms | 2 | `R/fct_results.R` `echart_weather_effect_plot()` |
| Prediction | (4.1) | `R/fct_predict_outcomes.R` `predict_outcome()` |
| Residual rules | (4.1) | `R/fct_aggregation.R` `draw_residuals_vec()` |
| Missing predictions counted | 4 | `R/fct_run_simulation.R` `step2_data_quality_notice()` |
