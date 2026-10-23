---
id: model-results
title: Reading the Step 1 results
app_step: 1
depends_on: [notation, outcomes, model-specification, linear-model, rif-model]
symbols: [beta, gamma, Sigma, tau, y, Z]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#interpreting-the-results-tab
code: [R/fct_step1_headline.R, R/fct_step1_model_tables.R, R/fct_results.R, R/fct_results_table2.R, R/mod_1_07_results.R, R/mod_1_08_modelfit.R]
verified_against: 6529b81
---

# Reading the Step 1 results

> The Results and Model fit tabs turn the fitted coefficients into numbers a reader can use: a headline effect for each weather variable, effect curves with confidence bands, a comparison across the three specifications, and fit statistics. This page defines each of them. All are computed from the coefficients and their covariance matrix, so figures, cards and tables show the same numbers.

## Setup

The results are computed from Model 3 ([20_model_specification](20_model_specification.md)), with the covariance matrix $\hat V$ clustered by location panel, unless stated otherwise. For the quantile model, each quantile has its own $\hat\phi_\tau$ and $\hat V_\tau$. Symbols are in [00_notation](00_notation.md). Let $Z$ be the design vector (regressors, interactions and covariates) and let $\hat\phi$ be the stacked coefficients.

## Method

### 1. Translated effects

A coefficient on a log outcome, a probability or a level is shown on the scale a reader expects:

| Outcome | Reported as | Value for a model-scale effect $c$ |
|---|---|---|
| Continuous, log scale | per cent change | $100\ (e^{c}-1)$ |
| Binary | percentage points | $100\ c$ for a linear probability model; $100\ \Delta p$ of Eq. (3.2) in [21_model_linear](21_model_linear.md) for a logit |
| Other (not logged) | raw units | $c$ |

A 95 per cent interval is $\hat c \pm 1.96\ \widehat{se}$ on the model scale, transformed in the same way. For the logit, the endpoints of the interval for the index are transformed to probabilities, so the interval is not symmetric and respects the bounds of a probability.

### 2. Headline contrast

For each weather variable the app computes one contrast. The contrast is the difference between two design vectors $Z^{\text{hi}}$ and $Z^{\text{lo}}$ for a reference household, so that

$$\hat c = d^{\prime}\hat\phi, \qquad \widehat{se} = \sqrt{d^{\prime}\hat V d}, \qquad d = Z^{\text{hi}} - Z^{\text{lo}} \qquad \text{(2.1)}$$

- **Continuous weather:** one standard deviation above the sample mean, against the mean. With polynomial terms, $d$ includes the squared and cubic terms at those two values.
- **Binned weather:** the highest bin against the reference (lowest) bin.
- **Reference household:** the sample-average household. For a binary outcome it is the household whose fitted risk is the sample median, which avoids a profile with a probability close to zero.
- **Moderators:** one contrast per value of the moderator. A binary moderator takes its two values. A numeric moderator with more than five distinct values is shown at its mean and at one standard deviation above and below.

For the quantile model the contrast is computed at $\tau=0.1$, $0.5$ and $0.9$ from the equation of that quantile. Its standard error combines the term variances without covariances between terms, a stated approximation.

### 3. Effect curves

**Continuous weather.** The figure shows the marginal effect of weather over a grid of 100 values from the smallest to the largest weather value in the sample. For a variable entered as a polynomial, with moderator value $m$:

$$\hat m(w) = \big(\hat\beta_1 + 2\hat\beta_2 w + 3\hat\beta_3 w^2\big) + \big(\hat\gamma_1 + 2\hat\gamma_2 w + 3\hat\gamma_3 w^2\big)\ m \qquad \text{(3.1)}$$

The 95 per cent band is $\hat m(w)\pm 1.96\sqrt{g(w)^{\prime}\hat V g(w)}$, where $g(w)$ collects the derivative weights of Eq. (3.1) on all coefficients. The curve is a slope, not a predicted level. A rug of observed values and the sample mean are drawn for reference.

**Binned weather.** The figure shows each bin coefficient with its interval, relative to the omitted lowest bin. With a moderator, the coefficients of each moderator group are shown side by side.

**Quantile model.** The figure shows $\hat\beta_\tau$ for each $\tau$ with a 95 per cent band built from the per-quantile standard errors. With polynomial terms, the plotted effect at each $\tau$ is the marginal effect at the mean weather, $\sum_p p\ \bar w^{\ p-1}\hat\beta_{p,\tau}$, with a standard error from the full covariance of the terms.

### 4. Comparing specifications

The table lists the weather coefficient in Models 1, 2 and 3. The robustness verdict compares the fixed-effects model (or Model 1 if Model 2 is not available) with Model 3. Two estimates $a$ and $b$ **agree** if they have the same non-zero sign and

$$|\hat a - \hat b| \le 1.96\sqrt{se_a^2 + se_b^2} \qquad \text{(4.1)}$$

The verdict is "Robust" if they agree, "Sensitive" if the sign holds but they do not agree in size, and "Not robust" if the sign changes. For the quantile model the comparison is made at the median.

### 5. Heterogeneity screens

- **Moderator.** The p-value tests whether the contrast differs between the first and last value of the moderator. For the linear and logistic models it uses the exact covariance of the difference of the two contrasts. For the quantile model it uses the contrasts' standard errors as if independent.
- **Across quantiles.** For the quantile model, a Wald statistic tests whether the weather effect is the same at all nine quantiles. The test stacks the nine transformed outcomes in one regression with quantile-specific weather coefficients and common controls and fixed effects, clustered so that the stacked copies of a household are not treated as independent. It is an approximation to the exact comparison.

### 6. Shape of the response

For binned weather, the app reports the bin with the largest effect and the first bin above the reference whose interval excludes zero. For a quadratic with no moderator, it reports the turning point when it falls inside the observed range:

$$w^{*} = -\frac{\hat\beta_1}{2\hat\beta_2} \qquad \text{(6.1)}$$

as a peak if $\hat\beta_2<0$ and a trough otherwise. For polynomials it also reports the contrast between the median and the 95th percentile of weather.

### 7. Fit statistics and diagnostics

The Model fit tab reports, for Model 3, the number of observations and:

- **Linear model:** $R^2$, adjusted $R^2$ and within $R^2$. **Quantile model:** $R^2$ and within $R^2$ for each quantile. The within $R^2$ is the share of the variation of the outcome, after the fixed effects are removed, that the regressors explain:
$$R^2_{\text{within}} = 1 - \frac{\sum_i \hat{\ddot e}_i^{\ 2}}{\sum_i \ddot y_i^{\ 2}} \qquad \text{(7.1)}$$
- **Logistic model:** McFadden $R^2 = 1 - \ell\ell/\ell\ell_0$, with $\ell\ell_0$ the log-likelihood of a model with only a constant, and the Akaike criterion.

Diagnostic figures use the median quantile equation for the quantile model:

- residuals against fitted values with a smooth line, and a normal quantile plot of residuals; for a binary outcome, binned means of residuals by decile of the predicted value;
- residuals against each weather variable;
- **relative importance** of each term, as the share of the sum of squared standardised coefficients:

$$s_j = 100\ \frac{\big(|\hat\phi_j|\ \mathrm{sd}(Z_j)\big)^2}{\sum_k \big(|\hat\phi_k|\ \mathrm{sd}(Z_k)\big)^2} \qquad \text{(7.2)}$$

where $\mathrm{sd}(Z_j)$ is the standard deviation of the design column in the estimation sample. The 15 largest shares are shown. Fixed effects are not included.

## Interpretation

- A weather coefficient that shrinks from Model 1 to Model 2 was driven by place and time confounding. One that survives into Model 3 is robust to the observed household characteristics.
- The headline contrast is conditional on the reference household and on the chosen contrast. A different contrast, such as a larger weather change, can give a different per cent effect for a nonlinear specification.
- A low overall $R^2$ is not a problem in itself. Weather effects are identified from within-cell variation, where a low within $R^2$ is normal.
- The importance shares compare terms on one scale. If weather terms rank far below household characteristics, simulated climate effects in Steps 2 and 3 will be small, whatever their significance.
- Many bins and moderators are tested at once. A consistent pattern across adjacent bins is more convincing than a single significant bin.

## Assumptions

- **A1. Large-sample inference.** Normal intervals are adequate. With few location panels they may be too narrow.
- **A2. Representative reference household.** The sample-average (or median-risk) household is a meaningful point at which to report a nonlinear effect.
- **A3. Independent terms in quantile contrasts.** Covariances between terms of a quantile equation, and between quantile equations, can be ignored in the headline intervals.

## Limitations and what is not modelled

- Multiple testing is not corrected.
- In-sample fit statistics do not measure out-of-sample accuracy.
- Effect figures for logit models are shown at one baseline risk.
- The robustness verdict uses sign and a simple interval overlap rule, not a formal test.
- Diagnostics for the quantile model cover only the median quantile.
- Tree-based models do not have these cards ([23_model_ml](23_model_ml.md)).

## In the app

- Step 1 > Results: headline cards, effect curves, progressive coefficient plot and the regression table with a download button.
- Step 1 > Model fit: the model summary, fit statistics, residual panels, importance and the raw model output.

User guide: [Interpreting the Results tab](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#interpreting-the-results-tab); [Interpreting the Model fit tab](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#interpreting-the-model-fit-tab).

## References

[@cameronmiller2015] for cluster-robust inference. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Scale of the reported effect | 1 | `R/fct_step1_headline.R` `.s1_scale()`, `step1_fmt_effect()` |
| Contrasts and moderator levels | (2.1) | `R/fct_step1_headline.R` `step1_scenarios()`, `.s1_fixest_scenarios()`, `.s1_rif_scenarios()` |
| Logit translation | 1 | `R/fct_step1_headline.R` `.s1_to_pp()` |
| Marginal effect curve | (3.1) | `R/fct_results.R` `echart_weather_effect_plot()` |
| Combined standard error of quantile terms | 3 | `R/fct_results.R` `.rif_combined_se()` |
| Robustness verdict | (4.1) | `R/fct_step1_headline.R` `.s1_stability_card()` |
| Heterogeneity across quantiles | 5 | `R/fct_step1_headline.R` `step1_rif_heterogeneity_p()` |
| Turning point and bin pattern | (6.1) | `R/fct_step1_headline.R` `.s1_turning_point()`, `.s1_bin_pattern()` |
| Fit statistics | (7.1) | `R/fct_results.R` `fit_stats_raw()`, `.fit_stat_values()`, `calc_fit_stats()` |
| Importance | (7.2) | `R/fct_results.R` `importance_shares()`, `echart_importance()` |
| Residual panels | 7 | `R/fct_results.R` `echart_residual_panels()` |
| Regression tables and downloads | 4 | `R/fct_results_table2.R` `make_regtable_specs_df()`; `R/fct_step1_model_tables.R` `step1_model_tables()`, `model_terms_table()`, `model_fit_table()`, `model_vcov_table()` |
