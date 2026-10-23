---
id: policy-framework
title: Policy scenarios as a change to the simulated population
app_step: 3
depends_on: [notation, framework, linear-model, rif-model, simulation, metrics, uncertainty]
symbols: [D, Delta, T, y, W, tau, omega]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#policy-variables-must-be-in-the-step-1-model
code: [R/fct_policy_sim.R, R/fct_policy_registry.R, R/fct_step3_input.R, R/fct_step3_async.R, R/fct_policy_decompose.R, R/fct_policy_metric_decompose.R, R/fct_policy_sim_compare.R]
verified_against: bfebf54
---

# Policy scenarios as a change to the simulated population

> Step 3 changes the policy variables of the baseline survey, or adds a cash transfer, and re-evaluates the Step 2 simulation under the same weather. The policy series is the Step 2 series plus a household-level correction. It shares the weather, the residual draws and the coefficient uncertainty of the baseline, so the difference between the two is the effect of the policy and nothing else. The effect is a scenario calculation with fitted coefficients, not an estimate of a causal effect.

## Setup

Step 3 starts from a finished Step 2 run. The **baseline arm** is that run, unchanged. The **policy arm** is built from it. A policy scenario is a set of **levers**. A lever is a variable that the data preparation marks as one that a policy can move (access to electricity, a travel time, a level of education), plus the cash transfer, which is not a variable of the model. The levers and how each one changes the survey are in [41_policy_levers](41_policy_levers.md), [42_social_protection](42_social_protection.md) and [43_shock_responsive_sp](43_shock_responsive_sp.md).

The notation of [00_notation](00_notation.md) applies. $D_i$ is the vector of policy variables of unit $i$ and $\Delta D_i$ the change a scenario makes to it.

## Method

### 1. A policy changes the survey

The scenario produces a modified copy of the baseline survey in which only the policy variables differ:

$$\Delta D_i = D_i^{\text{pol}} - D_i \qquad \text{(1.1)}$$

Three rules decide which variables change.

- **Only levers that were moved.** A lever left at its default does not touch the survey. Selecting a group of levers is not an intervention.
- **Only variables of the Step 1 model.** A lever acts only if its variable appears in Model 3, as a covariate or in an interaction. A variable that the model never saw cannot change a prediction, so the survey is not modified for it either. Levers that were moved but cannot act are listed in the run, with the reason (the variable is not in the survey, or not in the model). The cash transfer needs no variable in the model.
- **Random assignment is seeded.** When a lever reaches only a share of the units, the units are chosen at random. Each lever draws from its own random stream, seeded by the run seed and the lever's variable. Re-running the same scenario with the same seed reproduces the same units, and switching one lever on or off does not change the units chosen for another.

The baseline survey is never redrawn. All variation between runs of a scenario is in the policy arm.

### 2. The policy arm

Let $y_i^{(r,s,m)}$ be the model-scale prediction of the baseline arm for unit $i$ in simulation year $r$, scenario $s$ and member $m$ ([30_simulation](30_simulation.md)). The policy arm is not a second simulation. It adds a correction to each prediction of the baseline arm:

$$y_i^{\text{pol},(r,s,m)} = y_i^{(r,s,m)} + \Delta y_i^{(r,s,m)} \qquad \text{(2.1)}$$

The correction is the sum of a main effect and two resilience effects, defined in [44_decomposition](44_decomposition.md):

$$\Delta y_i^{(r,s,m)} = \delta_i^{\text{main}} + \delta_i^{\text{rep}\ (r,s,m)} + \delta_i^{\text{int}\ (r,s,m)} \qquad \text{(2.2)}$$

The main effect does not depend on the simulated weather. The two resilience effects depend on the weather of the prediction row, through the weather change defined in Eq. (3.1).

The statistic of the policy arm is computed from the corrected prediction with the same residual term as the baseline:

$$Y_i^{\text{pol},(r,s,m)} = \exp\big(y_i^{\text{pol},(r,s,m)} + e_i^{(r)}\big), \qquad T_{\text{pol}}^{(r,s,m)} = \mathcal{A}\Big(\big\lbrace (Y_i^{\text{pol},(r,s,m)},\ \omega_i)\big\rbrace _{i}\Big) \qquad \text{(2.3)}$$

Eq. (2.3) is written for a log outcome. A level outcome has no exponential. The policy effect on a statistic is the paired difference $\Delta T^{(r,s,m)} = T_{\text{pol}}^{(r,s,m)} - T^{(r,s,m)}$ of Eq. (3.2) in [00_notation](00_notation.md).

Because both arms use the same predictions, the same weather, the same residual draws and the same coefficient loading, a scenario with no effect gives exactly the baseline series. Differences come only from $\Delta y_i$. The method also avoids simulating every climate model again for each change of a lever.

### 3. The correction is evaluated for each prediction row

The correction is evaluated for each row of the baseline predictions, which is a household in a simulation year, scenario and member. The weather terms act on the change in weather from the weather the household experienced at its interview:

$$\Delta W_i^{(r,s,m)} = W_i^{(r,s,m)} - W_i^{0} \qquad \text{(3.1)}$$

For the linear model, the weather-dependent part of the correction is the fitted weather-by-policy interaction applied to this change. For the quantile model it is the repositioning and interaction effects of [44_decomposition](44_decomposition.md). The cash transfer is added to the predicted welfare level of the same row.

Two features follow.

- If a policy variable interacts with weather, the effect of the policy is the interaction coefficient times the weather change. It is zero at the weather the household experienced and grows with the weather change. The part of the interaction that applies at the weather of the interview itself is part of the main effect, so that main plus resilience is the effect of the policy at the weather of the row (see Assumption A3).
- The prediction row must map exactly to a weather observation of the Step 2 run. If the mapping is missing or inconsistent, the run stops with an error. There is no fallback to period-mean weather.

### 4. Which models and outcomes are supported

| Step 1 model | Step 3 policy arm |
|---|---|
| Linear regression of a continuous outcome | Supported. Main effect and interaction effect. |
| Unconditional quantile regression (RIF) | Supported. Main, repositioning and interaction effects. |
| Logistic regression, or a binary outcome | Not available. The correction is not a validated method on the response scale. |
| Random forest, gradient boosting | Not available. |

The outcome may be in logs or in levels. The policy arm uses the same Model 3 coefficients as the baseline.

### 5. Uncertainty of the policy arm

The central values of the policy series are exact given Eq. (2.1). The coefficient uncertainty of the baseline arm is carried by a factor loading $F_i$ ([33_uncertainty](33_uncertainty.md)), the gradient of the prediction with respect to the coefficients that the band covers. For the linear model the correction $\Delta y_i$ is linear in the coefficients: the policy coefficients times the lever changes, and the weather-by-policy interactions times the weather of the row. The baseline loading is the anchored loading of Eq. (1.2) in [33_uncertainty](33_uncertainty.md), the change from each household's own design. The gradient of the correction is added to it to give the policy arm's loading:

$$F_i^{\text{pol}} = F_i + \nabla_{\beta}\,\Delta y_i \qquad \text{(5.1)}$$

The coefficients of the policy variables are outside the block of weather coefficients and their interactions that the baseline loading covers (unless the Step 2 setting propagates all covariates). They are added as extra columns in the Cholesky basis of the covered block plus the policy coefficients. The leading block of that basis is the baseline's own, so the baseline arm is unchanged, and the covariance between the policy coefficients and the weather coefficients is kept. Two things follow.

- The bands on the policy series and on the effect include the sampling error of the policy coefficients and of the interactions at the weather of the row. A run without a covariate lever (for example a cash transfer only) has the baseline loading, because the cash transfer is a fixed amount.
- For the quantile model the policy arm still reuses the baseline loading, so its bands do not include the sampling error of the policy coefficients.

The band on the effect of the policy is the band of the paired contrast of [33_uncertainty](33_uncertainty.md): the coefficient error that the two arms share cancels, so only the part that differs between arms remains. The cash transfer is a fixed amount and carries no coefficient error.

### 6. Share of the climate loss offset

For a metric with a favourable direction ($d=+1$ if higher values are better, $d=-1$ if lower values are better), the app reports how much of the climate-driven change in a scenario the policy offsets:

$$\phi = \frac{d\ \big(T_{\text{pol}}^{s} - T^{s}\big)}{-d\ \big(T^{s} - T^{\text{hist}}\big)} \qquad \text{(6.1)}$$

where $T^{\text{hist}}$ is the historical baseline value, $T^{s}$ the baseline value under climate scenario $s$ and $T_{\text{pol}}^{s}$ the policy value under the same scenario. The ratio is shown only if climate worsens the metric (the denominator is positive) and the policy improves it (the numerator is positive). Otherwise no ratio is reported.

## Interpretation

- The policy effect is the size of a scenario: the difference between two evaluations of one fitted model at two sets of values of the policy variables. It is not the effect that a programme would have in practice.
- A policy effect is larger the further the policy moves the households from the values in the estimation sample. Where a lever moves most households to values that were rare or absent in the sample, the fitted coefficient is an extrapolation. The before-and-after summaries and distributions in the diagnostics show how far the levers move the sample.
- Combining levers adds their effects in model scale. A term in the model that multiplies two levers is not applied. For attribution, run levers one at a time before combining them.
- A run that changes no variable and adds no transfer is flagged as having no effect, and its policy series equals the baseline series.

## Assumptions

- **A1. Policy variables in the model.** A lever acts only through the Step 1 model. The effect of a lever that the model does not contain is zero by construction.
- **A2. Coefficients as scenario inputs.** The coefficients on policy variables and their interactions with weather are cross-sectional associations ([01_framework](01_framework.md), A4). They are applied as if they were effects of changing the variable.
- **A3. Weather interaction anchored at the interview weather.** The effect of a policy on weather sensitivity is applied to the weather change of Eq. (3.1). The part of an interaction that operates at the weather the household experienced at its interview is part of the main effect, which is evaluated at that weather ([44_decomposition](44_decomposition.md), Eq. (1.2)). Because that weather is fixed for the household, the main effect is the same in every simulation year.
- **A4. Fixed population and cells.** The households, their fixed-effect cells and their residuals are those of the baseline survey. A policy that would move a household to another fixed-effect cell is not represented.
- **A5. Unchanged coefficients.** The estimated relationship does not change when the policy variable changes, including at values outside the estimation support.

## Limitations and what is not modelled

- General-equilibrium effects, such as prices, wages or crowding of services.
- Delivery capacity, service quality, take-up, and the costs of levers other than the cash transfer.
- Behavioural responses to a transfer beyond what the fitted coefficients contain.
- Uncertainty in the coefficients of the policy variables, in the bands of the policy series (Section 5).
- Policy arms for logistic regression, binary outcomes and the machine-learning models.
- A causal reading of any lever effect.

## In the app

- Step 3 > the lever panels (Social protection, Infrastructure, Digital inclusion, Labour market, Education, Other): choose levers. A panel shows its controls only for variables that are in the Step 1 model. Otherwise it lists the variables to add back in Step 1.
- Step 3 > Run: builds the modified survey and the policy arm.
- Step 3 > Results, Diagnostics, Decomposition and Cost-effectiveness: the policy and baseline series side by side, the before-and-after summary of the changed variables, the channels and the cost per outcome gained.

User guide: [Policy variables must be in the Step 1 model](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#policy-variables-must-be-in-the-step-1-model).

## References

[@firpo2009] for the unconditional quantile model used by the quantile engine. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Moved-lever test, lever fields | Section 1 | `R/fct_policy_sim.R` `.access_cfg_moved_codes()`, `has_labor_change()`, `has_sp_change()` |
| Modified survey | (1.1) | `R/fct_policy_sim.R` `apply_policy_to_svy()` |
| Gating by the Step 1 model | Section 1 | `R/fct_policy_sim.R` `.lever_in_model()`, `.policy_lever_terms()`, `.access_levers_unavailable()` |
| Seeded streams per lever | Section 1 | `R/fct_policy_sim.R` `apply_policy_to_svy()` |
| Covariate changes | (1.1) | `R/fct_policy_decompose.R` `.compute_policy_deltas()` |
| Policy arm from the baseline pipelines | (2.1), (2.3) | `R/fct_policy_sim.R` `apply_policy_delta_to_baseline()`; `R/fct_policy_metric_decompose.R` `.apply_policy_annual_pipeline()` |
| Run orchestration | Section 2 | `R/fct_step3_async.R` `step3_compute()`; `R/fct_step3_input.R` `wise_step3_input()` |
| Factor loading of the policy arm | (5.1) | `R/fct_policy_loading.R` `.policy_arm_loading()`, `.policy_loading_terms()`, `.policy_loading_rows()` |
| Correction per prediction row | (2.2), (3.1) | `R/fct_policy_metric_decompose.R` `.prepare_policy_annual_channels()`, `.policy_annual_channel_block()`, `.validate_policy_annual_exposure()` |
| Supported models and outcomes | Section 4 | `R/fct_policy_sim_compare.R` `.policy_endpoint_status()`; `R/fct_policy_metric_decompose.R` `.policy_annual_channel_status()` |
| Run with no effect | Section 2 | `R/fct_policy_sim.R` `.scenario_has_effect()` |
| Before-and-after summaries | Interpretation | `R/fct_policy_sim.R` `.policy_diagnostics_snapshot()` |
| Share of climate loss offset | (6.1) | `R/fct_policy_sim_compare.R` `step3_offset_share()` |
