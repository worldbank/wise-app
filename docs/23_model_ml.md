---
id: ml-models
title: Tree-based models (random forest, gradient boosting)
app_step: 1
depends_on: [notation, framework, model-specification, linear-model]
symbols: [y, W, M, X, Z]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#model-type
code: [R/fct_fit_model.R, R/fct_model_select.R, R/fct_predict_outcomes.R, R/fct_metric_registry.R, R/mod_2_01_weathersim.R, R/fct_policy_decompose.R]
verified_against: 6529b81
---

# Tree-based models (random forest, gradient boosting)

> The estimation code contains a random forest and a gradient-boosted tree model. They are **not offered in the app**: the model selector lists only linear, logistic and quantile models, and Steps 2 and 3 refuse any other engine. This page records what the two models do, so that the limits are clear if they are switched on.

## Setup

The models use the outcome and regressors of [20_model_specification](20_model_specification.md) but no coefficients. Let $Z_i$ be the full vector of features of unit $i$: weather regressors, moderators, covariates and the fixed-effect variables. Symbols are in [00_notation](00_notation.md).

Status in the app:

| Place | Status |
|---|---|
| Step 1 model selector | Not offered |
| Batch run specification | Not accepted (only linear, logistic and quantile models) |
| Step 2 simulation | Blocked with a message |
| Step 3 policy simulation and decomposition | Not available |
| Metric definitions in Steps 2 and 3 | Defined for the linear and quantile engines only |

## Method

### 1. Models and settings

Both models fit the model-scale outcome $y_i$ on $Z_i$ with the same three nested specifications as the linear model: weather terms only, then plus the fixed-effect variables, then plus the covariates. Fixed-effect variables are ordinary features and are not absorbed. Interaction and polynomial terms are passed in the formula but are not needed, because trees learn nonlinearity and interactions.

**Random forest.** The prediction is the average of $B$ regression trees grown on bootstrap samples with random feature subsets:

$$\hat f(z) = \frac{1}{B}\sum_{b=1}^{B} T_b(z) \tag{1.1}$$

The settings are fixed: $B=500$ trees, a minimum of 5 observations per leaf, impurity-based variable importance, a single thread, and a fixed seed. It is available for a continuous outcome.

**Gradient boosting.** The prediction is a sum of shallow trees fitted one after another to the remaining error, with shrinkage $\nu$:

$$\hat f(z) = \sum_{b=1}^{B}\nu\, T_b(z) \tag{1.2}$$

The settings are fixed: $B=500$ trees, depth 6, shrinkage $\nu=0.05$, a minimum of 5 observations per node, no required loss reduction per split, a single thread and a fixed seed. It is available for a continuous outcome and, as a classifier, for a binary outcome.

No hyperparameter is tuned by the app.

### 2. Prediction

The prediction for unit $i$ is $\hat y_i=\hat f(Z_i)$ (for a classifier, the predicted probability of the event). Residuals for the residual rules of [30_simulation](30_simulation.md) are the in-sample differences $y_i-\hat y_i$.

## Interpretation

- A tree-based model can fit a flexible relationship between weather and welfare, including thresholds. Outside the range of the training weather, a tree predicts a constant equal to the value at the edge. It cannot extrapolate a trend to hotter or drier weather than observed.
- There is no coefficient on weather. A partial effect would have to be read from predictions at changed weather, which the app does not do.
- The Step 1 effect cards, the progressive coefficient plot and the specification comparison are not defined for these models. The model-fit card shows only the sample size.

## Assumptions

- **A1. Representative sample.** The relationship learned in the sample holds for the baseline households and weather of the simulation.
- **A2. Fixed-effect variables as features.** Treating area and time as features is an adequate substitute for absorbing them.
- **A3. Conditional mean from the model.** The fitted function estimates the conditional mean of the model-scale outcome.

## Limitations and what is not modelled

- No standard errors and no covariance of parameters, so no coefficient uncertainty in Step 2 bands ([33_uncertainty](33_uncertainty.md)). The delta-method machinery needs a coefficient vector.
- No clustering of the fit or of any uncertainty.
- In-sample residuals are smaller than out-of-sample errors, so residual rules would understate dispersion.
- No fixed-effect structure: a unit from a round or area not present in training has no estimate for it.
- No policy decomposition into direct and resilience effects; the decomposition needs coefficients on policy variables and their interactions ([44_decomposition](44_decomposition.md)).
- No model-selection by cross-validation, and no variable selection by Lasso for the forest or the boosted model.

## In the app

These models cannot be selected. To use one, the model selector, the Step 2 engine check and the Step 3 engine checks would all have to be extended.

User guide: [Model type](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#model-type).

## References

Breiman (2001), "Random Forests", *Machine Learning* 45, 5-32; Friedman (2001), "Greedy function approximation: a gradient boosting machine", *Annals of Statistics* 29(5), 1189-1232. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Random forest settings | (1.1) | `R/fct_fit_model.R` `ENGINE_REGISTRY` (`ranger` entry) |
| Gradient boosting settings | (1.2) | `R/fct_fit_model.R` `ENGINE_REGISTRY` (`xgboost` entry) |
| Engine from model type | 1 | `R/fct_model_select.R` `infer_engine()` |
| Model types offered | Status | `R/fct_model_select.R` `model_type_choices()` |
| Prediction and in-sample residuals | 2 | `R/fct_predict_outcomes.R` `predict_outcome()` |
| Engines in the metric definitions | Status | `R/fct_metric_registry.R` `.WISE_METRIC_REGISTRY` |
| Step 2 engine check | Status | `R/mod_2_01_weathersim.R` `mod_2_01_weathersim_server()` |
| Step 3 engine check | Status | `R/fct_policy_decompose.R` `decompose_policy_effect()` |
