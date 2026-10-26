---
id: model-specification
title: Model specification and estimation sample
app_step: 1
depends_on: [notation, framework, outcomes, weather-measures]
symbols: [y, W, M, X, beta, theta, gamma, delta, alpha, lambda, epsilon, Sigma]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#model-specification-estimation
code: [R/fct_model_select.R, R/fct_step1_model.R, R/fct_fit_model.R, R/mod_1_06_model.R, R/fct_model_card.R, R/fct_results.R, R/fct_simulations.R]
verified_against: e577575
---

# Model specification and estimation sample

> Step 1 fits three nested versions of one weather-welfare regression on the same sample. The weather coefficients are identified from residual variation after additive survey-year and area effects. Standard errors are clustered by location panel. Covariates are chosen by the user or by a stability-selection Lasso. This page defines the specification, the fixed effects, the Lasso, the variance estimator and the estimation sample. The estimators for each outcome type are on [21_model_linear](21_model_linear.md) and [22_model_rif](22_model_rif.md).

## Setup

The ingredients of the specification are the outcome $y_i$ ([11_outcomes](11_outcomes.md)), the weather regressors $W_i$ ([12_weather_measures](12_weather_measures.md)), the moderators $M_i$, the fixed effects, and the covariates $X_i$. Symbols are in [00_notation](00_notation.md).

- **Moderators.** Categorical variables flagged in the variable list as eligible for interaction. Numeric variables are not offered. A variable that is also flagged as an outcome, such as the labour status variables, is offered, except the outcome of the run. When the user selects a policy scenario in Step 1, the variables of that policy are added to the moderators and cannot be removed.
- **Fixed effects.** Categorical variables flagged as eligible. The default is the survey year and the first administrative level, where available.
- **Covariates.** Individual, household, firm and area variables, depending on the level of analysis.

## Method

### 1. Three nested models

All three models are fitted to the same sample. Write $W_i \otimes M_i$ for the products of every weather regressor with every moderator.

$$\text{Model 1:}\quad y_i = W_i^{\prime}\beta + M_i^{\prime}\theta + (W_i\otimes M_i)^{\prime}\gamma + \varepsilon_i \qquad \text{(1.1)}$$

$$\text{Model 2:}\quad y_i = W_i^{\prime}\beta + M_i^{\prime}\theta + (W_i\otimes M_i)^{\prime}\gamma + \alpha_{g(i)} + \lambda_{t(i)} + \varepsilon_i \qquad \text{(1.2)}$$

$$\text{Model 3:}\quad y_i = W_i^{\prime}\beta + M_i^{\prime}\theta + (W_i\otimes M_i)^{\prime}\gamma + X_i^{\prime}\delta + \alpha_{g(i)} + \lambda_{t(i)} + \varepsilon_i \qquad \text{(1.3)}$$

Model 1 is the raw association. Model 2 adds the fixed effects and shows how much of the raw association is place and time confounding. Model 3 adds the controls and is the model used for simulation, policy analysis and the effect figures.

With no moderator, $M_i$ and $W_i\otimes M_i$ are absent. With several moderators, the app crosses the weather terms with each moderator separately (a "pairwise" specification): for weather term $w$ and moderators $m_1, m_2$ it forms $w\times m_1$ and $w\times m_2$, and no three-way term. Polynomial and bin terms are crossed with the moderator in the same way. A fully crossed specification exists in the code but is not offered in the app.

A continuous outcome uses linear regression. A binary outcome uses either a linear probability model or a logistic regression, in which case the left side of Eqs. (1.1) to (1.3) is the log-odds of the event. The quantile model replaces $y_i$ by a transformed outcome ([22_model_rif](22_model_rif.md)).

### 2. Fixed effects

Fixed effects are absorbed, not estimated as dummies. For linear models the estimator is equivalent to ordinary least squares on variables from which the fixed-effect means have been removed. Let $\ddot z_i$ denote the residual from projecting $z_i$ on the dummies of all absorbed fixed effects. Then the coefficients solve

$$\ddot y_i = \ddot Z_i^{\prime}\phi + \ddot\varepsilon_i, \qquad Z_i = \big(W_i,\ M_i,\ W_i\otimes M_i,\ X_i\big) \qquad \text{(2.1)}$$

so that the coefficients are identified from the residual variation of $Z_i$ after additive survey-year and administrative-area effects are removed ([01_framework](01_framework.md), Eq. (3.1)). The fixed effects enter as separate terms, $\alpha_{g(i)} + \lambda_{t(i)}$, and are not interacted: there is no area-by-round cell effect. A regressor that is fully explained by the two sets of effects is dropped as collinear, but one that varies across areas and rounds in a way the additive effects cannot absorb is kept, even if it is constant within each area-round cell. Area-specific changes across rounds are therefore not removed, and they can confound the weather coefficients. The default fixed effects are the survey year, shared by all units of a round, and the first administrative level.

> **Specification consideration: area-by-round effects.** For a study where regional shocks or programmes may correlate with weather, consider assessing an area-by-round specification as a sensitivity analysis. It would absorb shocks common to each area-round cell, but would identify weather effects only from variation remaining within those cells after controls. With coarse weather assignment or narrow survey fieldwork windows, that variation may be limited or absent; cell-constant weather terms and controls would be absorbed. This is not the app's current specification or an automatic improvement. A future implementation should check identifying variation, sample support, collinearity and prediction support, and compare coefficients and downstream simulation results on a common sample before adopting it. Neither additive nor interacted effects alone establish causal identification.

Fixed effects fitted on the estimation sample are reused to predict. A unit in a cell that is absent from the estimation sample cannot be predicted with those effects; its prediction is missing ([30_simulation](30_simulation.md)).

### 3. Variance and clustering

Standard errors are cluster-robust. The cluster is the location panel ([10_data](10_data.md)), the level at which weather is assigned. The covariance of the coefficients is the usual cluster sandwich:

$$\hat V = (\ddot Z^{\prime}\ddot Z)^{-1}\Big(\sum_{p}\ddot Z_p^{\prime}\hat e_p\hat e_p^{\prime}\ddot Z_p\Big)(\ddot Z^{\prime}\ddot Z)^{-1} \qquad \text{(3.1)}$$

where the sum runs over the location panels $p$, $\hat e_p$ are the residuals of the units in panel $p$, and the estimation software applies its default small-sample adjustment.

Three further rules apply.

1. **Fit-time estimator first.** The covariance stored at estimation is used for every table, figure and for the coefficient uncertainty of Steps 2 and 3. A confidence interval in Step 1 and a simulation band in Step 2 therefore rest on one covariance matrix.
2. **No location panel.** If the location panel could not be built, the model is fitted with the software's default standard errors, which assume independent errors. This is recorded as a fallback and shown with the results.
3. **Failure of the stored estimator.** If the stored covariance cannot be extracted, the app tries, in order, clustering by location panel, clustering by location, heteroskedasticity-robust standard errors, and independent errors.

### 4. Estimation sample and weights

A unit enters the estimation if no variable of the fullest model is missing: the outcome, the weather regressors, the moderators, the fixed effects, the covariates and the cluster identifier. The three models use this one sample, so that the progressive comparison changes only the specification.

Survey weights are **not** used in estimation. The estimated coefficients describe the average relationship in the sample as drawn. Weights enter when the model is used to compute population statistics in Steps 2 and 3.

### 5. Covariate selection

The user either lists the covariates or lets a Lasso choose them.

**Candidate pool.** A variable is a candidate only if the variable list flags it as an individual, household, firm or area characteristic, it is numeric, it is not an outcome, and is at least 90 per cent complete in every survey round among units with an outcome. Employment and unemployment are defined only for people of working age, so they are judged on people aged 15 and over. Self-employment and the sector of the main job are defined only for the employed, so they are judged on the employed. Weather terms, moderators, their interactions and the fixed effects are never penalised.

**Lasso.** For the linear model, the outcome, the unpenalised terms and the candidates are first residualised on the fixed effects. Let $\tilde y$, $\tilde Z$ and $\tilde X$ be those residualised variables. The Lasso solves an elastic-net problem with mixing weight $\varrho$ ($\varrho=1$ is the pure Lasso and the default) and penalty level $\eta$:

$$\min_{\kappa,\ \delta}\ \frac{1}{2N}\sum_i\big(\tilde y_i - \tilde Z_i^{\prime}\kappa - \tilde X_i^{\prime}\delta\big)^2 + \eta\sum_{j}\Big[\varrho\ |\delta_j| + \tfrac{1-\varrho}{2}\delta_j^2\Big] \qquad \text{(5.1)}$$

with no penalty on $\kappa$. The level $\eta$ is chosen by $k$-fold cross-validation ($k=10$ by default) with the one-standard-error rule: the largest $\eta$ within one standard error of the cross-validated minimum. Predictors are standardised by default. For the logistic model the same problem is solved with the binomial likelihood and the fixed effects are kept in the design instead of being residualised.

**Stability.** The selection is repeated $R$ times ($R=5$ by default), each time with new random cross-validation folds. When the data carry the survey location (`loc_id_panel`), whole locations are assigned to folds, so a held-out fold shares no location with the training folds, in line with the location-clustered standard errors of the final model. Selection ignores survey weights, like the final model. If multiple imputation is switched on (it is off by default), each repetition uses a different imputed data set. A candidate is kept if it is selected in at least half of the repetitions:

$$f_j = \frac{1}{R}\sum_{r=1}^{R}\mathbf{1}\big[\hat\delta_j^{(r)} \ne 0\big], \qquad \text{keep } j \text{ if } f_j \ge 0.5 \qquad \text{(5.2)}$$

Without imputation, units with a missing candidate are dropped for the selection step only. The final model is fitted on its own complete-case sample (Section 4).

The user can force variables in or out. A forced-in variable is always kept and a forced-out variable is removed from the pool. Selected variables are assigned to the individual, household, firm or area group by their flags.

## Interpretation

- Compare the weather coefficients across Models 1 to 3. If they shrink from Model 1 to Model 2, the raw association came from place and time confounding.
- The cluster is the location panel because all units in a panel share the same weather. The effective number of independent observations for weather is closer to the number of panels than to the number of units.
- The Lasso chooses controls for prediction and for the policy analysis. It does not test whether a control is a confounder.

## Assumptions

- **A1. Correct specification of the response.** The chosen form of weather, moderators and controls approximates the true relationship (see [21_model_linear](21_model_linear.md)).
- **A2. Exogeneity of weather timing.** Eq. (3.1) of [01_framework](01_framework.md).
- **A3. Clustering at the panel level is enough.** Errors are independent across location panels. Correlation between neighbouring panels is not modelled.
- **A4. Missing data are ignorable.** Units dropped for a missing variable are like those kept.
- **A5. Few clusters.** The asymptotic cluster covariance is reliable when the number of panels is large. As a rule of thumb, with fewer than about 50 panels it may understate uncertainty.

## Limitations and what is not modelled

- No survey weights in estimation and no design-based variance.
- No spatial correlation beyond the location panel and no serial correlation within a location across rounds.
- No wild-bootstrap or small-cluster correction.
- Lasso selection uses linear residualisation and does not account for the clustering.
- Covariates measured after the weather shock (such as household assets) can be affected by it. Including them changes what the weather coefficient means.
- Interaction terms among moderators are not available in the app.

## In the app

- Step 1 > Model: model type, interaction moderator, **Model settings** (fixed effects, covariate selection, Lasso options), then **Run model**. The model summary card shows the specification, the cluster and the covariate count.

User guide: [Model specification and estimation](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#model-specification-estimation).

## References

[@cameronmiller2015], [@abadie2023] and [@moulton1990] on clustering; [@auffhammer2013] on identification from weather variation. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Specification assembly | 1 | `R/fct_model_select.R` `build_selected_model()`, `model_type_choices()`; `R/fct_step1_model.R` `wise_selected_model()` |
| Pairwise terms and the three formulas | (1.1) to (1.3) | `R/fct_fit_model.R` `fit_model()`, `ENGINE_REGISTRY` |
| Fixed-effect defaults and roles | 2 | `R/fct_spec_defaults.R` `wise_default_fixed_effects()`; `R/fct_model_select.R` `filter_vars_by_role()` |
| Policy-locked moderators | 1 | `R/fct_model_select.R` `get_policy_locked_vars()` |
| Cluster variable | (3.1) | `R/fct_step1_model.R` `wise_cluster_var()` |
| Covariance fallbacks | 3 | `R/fct_results.R` `.fixest_vcov()`; `R/fct_simulations.R` `compute_chol_vcov()` |
| Complete-case sample | 4 | `R/fct_fit_model.R` `fit_model()` |
| Candidate pool (90 per cent complete) | 5 | `R/fct_step1_model.R` `wise_valid_vars()`, `WISE_LABOR_ROW_RULES`; `R/fct_model_select.R` `filter_valid_vars()` |
| Stability Lasso | (5.1), (5.2) | `R/fct_fit_model.R` `run_lasso_selection()`; `R/fct_step1_model.R` `wise_lasso_selection()`, `wise_lasso_covariates()` |
| Lasso defaults | 5 | `R/fct_spec_defaults.R` `wise_default_lasso()` |
| Fit wrapper with snapshot | 1 | `R/fct_step1_model.R` `wise_fit()` |
| Specification summary card | Setup | `R/fct_model_card.R` `model_card_rows()` |
