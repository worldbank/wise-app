---
id: decomposition
title: Decomposition of the policy effect into direct and resilience channels
app_step: 3
depends_on: [notation, policy-framework, linear-model, rif-model, metrics, social-protection]
symbols: [y, W, D, Delta, tau, beta, gamma, delta, T]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#interpreting-the-decomposition-tab
code: [R/fct_policy_decompose.R, R/fct_policy_metric_decompose.R, R/fct_decomposition_summary.R, R/fct_policy_sim.R]
verified_against: 8592a9d
---

# Decomposition of the policy effect into direct and resilience channels

> The effect of a policy on a household is split into a **direct effect**, which raises welfare whatever the weather, and a **resilience effect**, which changes how much weather moves welfare. The resilience effect has two channels, repositioning and interaction. The channels are computed for every household and simulation year, then summarised for each welfare metric in a fixed order. By construction they add up to the simulated policy effect.

## Setup

The decomposition applies to the policy arm of [40_policy_framework](40_policy_framework.md). It needs the linear or the quantile model of Step 1. Machine-learning models, logistic regression and binary outcomes have no policy arm and therefore no decomposition.

Let $y_i$ be the baseline model-scale outcome of household $i$ and $\Delta D_i$ the change of its policy variables. Let $\beta_w(\tau)$ be the coefficient on weather variable $w$, $\delta_v(\tau)$ the coefficient on policy variable $v$, and $\gamma_{wv}(\tau)$ the coefficient on the interaction of $w$ and $v$. For the quantile model these are the coefficient curves of Model 3 across the quantile grid ([22_model_rif](22_model_rif.md)). For the linear model they do not depend on $\tau$. The weather change of a prediction row is

$$\Delta W_{iw}^{(r,s,m)} = W_{iw}^{(r,s,m)} - W_{iw}^{0}$$

the weather of the row minus the weather the household experienced at its interview, as in Eq. (3.1) of [40_policy_framework](40_policy_framework.md). For a binned weather variable, the change is the contrast between the coefficient of the bin of the row and the coefficient of the bin of the interview weather, and a reference bin has coefficient zero.

## Method

### 1. Direct effect

The direct effect does not depend on weather. It is the sum of the cash transfer and the change in the policy variables, each priced at the household's position before the policy:

$$\delta_i^{\text{main}} = \delta_i^{\text{cash}} + \delta_i^{\text{cov}}, \qquad \delta_i^{\text{cov}} = \sum_{v}\delta_v\big(\tau_i^{\text{pre}}\big)\ \Delta D_{iv} \qquad \text{(1.1)}$$

The cash effect is Eq. (5.1) of [42_social_protection](42_social_protection.md): $\log(e^{\hat y_i} + T_i) - \hat y_i$ for a log outcome, and $T_i$ for a level outcome. In a year, it is evaluated against the predicted level of that year. In a programme that pays only after a trigger, the payment of the year is part of the direct effect and is shown as its own channel ([43_shock_responsive_sp](43_shock_responsive_sp.md)).

A policy variable that has no coefficient in the model has no effect. Terms are matched to variables by exact component names.

### 2. Position in the distribution (quantile model)

The quantile model prices a household by its position on the welfare distribution of the estimation sample. With $\hat F$ the empirical distribution function of the outcome in the estimation sample and $\tau_{\min}$, $\tau_{\max}$ the ends of the quantile grid (0.1 and 0.9):

$$\tau_i^{\text{pre}} = \text{clip}\big(\hat F(y_i)\big), \qquad \tau_i^{\text{post}} = \text{clip}\big(\hat F\big(y_i + \delta_i^{\text{main}}\big)\big) \qquad \text{(2.1)}$$

where $y_i$ is the observed baseline outcome and the position after the policy uses the static part of the direct effect (the regular cash transfer and the covariate changes). If the direct effect is zero, $\tau^{\text{post}} = \tau^{\text{pre}}$. For the linear model there is no position and the coefficients are constant.

### 3. Resilience effect

**Repositioning (quantile model only).** If the direct effect moves a household up the distribution, the weather coefficient that applies to it changes too. When poorer households lose proportionally more from the same weather, the transfer protects the household simply by moving it up:

$$\delta_i^{\text{rep}} = \sum_{w}\Big[\beta_w\big(\tau_i^{\text{post}}\big) - \beta_w\big(\tau_i^{\text{pre}}\big)\Big]\ \Delta W_{iw} \qquad \text{(3.1)}$$

It is zero whenever the direct effect is zero, and it is zero for the linear model.

**Interaction.** If the model contains a weather-by-policy interaction, changing the policy variable changes the weather coefficient of the household. This applies to both models. For the quantile model, the interaction coefficient is read at the position after the policy:

$$\delta_i^{\text{int}} = \sum_{w}\sum_{v}\gamma_{wv}\big(\tau_i^{\text{post}}\big)\ \Delta W_{iw}\ \Delta D_{iv} \qquad \text{(3.2)}$$

If the model has no such interaction, the interaction effect is zero and the app warns of it. Cash is not a variable of the model, so a cash transfer has no interaction effect.

The total effect of the policy on household $i$ in a simulation year is

$$\Delta y_i = \delta_i^{\text{main}} + \delta_i^{\text{rep}} + \delta_i^{\text{int}} \qquad \text{(3.3)}$$

which is Eq. (2.2) of [40_policy_framework](40_policy_framework.md) for the row of the year. The linear-model form of Eq. (4.1) in [01_framework](01_framework.md) is the case with constant coefficients and no repositioning.

### 4. Effects in outcome units

The channels are in log points for a log outcome. Averaging log points is not the same as averaging effects on the level. The app therefore converts the channels of each household to outcome units before averaging them, one at a time and in order, against the household's predicted baseline level $B_i$ of that year. With $m = \delta^{\text{main}}$, $\rho = \delta^{\text{rep}}$ and $\iota = \delta^{\text{int}}$:

$$\text{direct} = \big(e^{m} - 1\big)B_i, \quad \text{repositioning} = e^{m}\big(e^{\rho} - 1\big)B_i, \quad \text{interaction} = e^{m+\rho}\big(e^{\iota} - 1\big)B_i \qquad \text{(4.1)}$$

The three channels add up to the total effect $e^{m+\rho+\iota}B_i - B_i$. For a level outcome the channels are the model-scale effects themselves.

### 5. Channels of a welfare metric

A statistic such as the poverty rate or the Gini index is not a mean of household effects. The decomposition therefore evaluates the statistic itself in a sequence of states, adding one channel at a time:

$$T_k = \mathcal{A}\Big(\big\lbrace (Y_i^{(k)},\ \omega_i)\big\rbrace _{i}\Big), \qquad Y_i^{(k)} = \exp\Big(y_i + \sum_{j \le k}\delta_i^{(j)} + e_i\Big) \qquad \text{(5.1)}$$

with the channels in the order $\delta^{(1)} = $ direct effect (static), $\delta^{(2)} = $ payment of a shock-responsive programme (if any), $\delta^{(3)} = $ repositioning, $\delta^{(4)} = $ interaction. The residual term $e_i$ and the weights are those of the baseline run, so every state uses the same households and the same draws. $T_0$ is the baseline value and the last state is the policy value. The contribution of a channel is the difference between a state and the one before it:

$$C_k = T_k - T_{k-1}, \qquad \sum_k C_k = T_{\text{pol}} - T_0 = \Delta T \qquad \text{(5.2)}$$

The resilience effect is the sum of the repositioning and the interaction contributions. The contributions add up to the effect of the policy exactly, because the last state is the policy arm. The app checks this for every model-year, with a relative tolerance of $10^{-8}$, and stops if the last state differs from the policy arm.

**Summaries.** For each scenario, each contribution is averaged over the years of a member and then over the members with equal weight, as in Section 3 of [32_metrics](32_metrics.md). A model-year with a missing state is left out of the expected value, and the number of years left out is reported.

**Adverse years.** The decomposition can also be read in a bad year of the baseline. For return period $1/p$, the years of each member are ranked by the baseline value of the metric, and the baseline value in the adverse year is found by rank interpolation, Eq. (4.1) in [32_metrics](32_metrics.md), between two years $r_{\text{lo}}$ and $r_{\text{hi}}$ with weights $1-\theta$ and $\theta$. Every state is read at the same two years with the same weights:

$$T_k^{\text{adverse}} = (1-\theta)\ T_k^{(r_{\text{lo}})} + \theta\ T_k^{(r_{\text{hi}})} \qquad \text{(5.3)}$$

so the channels in a one-in-ten-year bad year are those of the same years in which the baseline is at its one-in-ten-year level. If one member has no support for the return period, the scenario has no tail result.

**By decile.** Households are grouped by weighted deciles of their observed baseline outcome. The groups are fixed and are not re-ranked after the policy. Each state is evaluated within each group, and the contributions are shown by decile.

### 6. Mechanism diagnostics

For each weather variable (and each bin of a binned variable), the app summarises the weighted mean repositioning and interaction effect per unit of the weather change, the shares of households with a positive or a negative effect, and the mean positions $\tau^{\text{pre}}$ and $\tau^{\text{post}}$. For the quantile model it also shows the fitted weather curve $\beta_w(\tau)$ of Step 1. This curve is not re-estimated for the policy.

## Interpretation

- **A large direct effect and a small resilience effect** is a policy that raises welfare but does not change weather sensitivity, for example an unconditional transfer that is spent on non-agricultural consumption. **A small direct effect and a large resilience effect** would be a policy that reduces sensitivity to weather with little change in average welfare, which the model can show only if the model contains a weather-by-policy interaction.
- The channels describe the model. A resilience effect from repositioning exists because the fitted weather coefficient differs along the distribution. It is not evidence that a transfer changes weather sensitivity in a household.
- For the same policy, the quantile model usually shows a larger resilience effect than the linear model, especially for a cash transfer, because only the quantile model has the repositioning channel.
- The order of channels in Eq. (5.1) is a convention. For a nonlinear metric, another order would split the same total differently. The total does not depend on the order.

## Assumptions

- **A1. Coefficients as scenario inputs.** The coefficients on the policy variables and on their interactions with weather are used as if they were causal ([40_policy_framework](40_policy_framework.md), A2).
- **A2. Anchored weather change.** The resilience channels act on the weather change defined in the Setup and not on the weather level ([40_policy_framework](40_policy_framework.md), A3).
- **A3. Position from the observed outcome.** In the quantile model, the position of a household is set by its observed baseline outcome and by the static part of the direct effect, and not re-evaluated for each year. The payment of a shock-responsive programme does not move it.
- **A4. Interaction at the new position.** The interaction coefficient is read at the position after the direct effect.
- **A5. Fixed order.** The contributions of Section 5 follow the order direct, shock payment, repositioning, interaction.

## Limitations and what is not modelled

- Channels have no uncertainty bands. The decomposition is computed at the central coefficients.
- Machine-learning models, logistic regression and binary outcomes have no decomposition.
- Resilience that works through a variable that is not in the model.
- A complete derivative of the nonlinear model: only the repositioning and interaction channels are included, and not every nonlinear term.
- For the average poverty metric, which uses only positive welfare, the households counted can differ across states. The population is not a fixed eligible subpopulation.
- The effect of a policy on the position of a household in the weather-year distribution of a scenario: positions are fixed from the baseline survey.

## In the app

- Step 3 > Decomposition: "What drives the total policy effect?" shows the headline channels for a scenario, in outcome units, per cent of the baseline or in the units of the metric, and by weather-year basis (average or adverse year). "Who gains, and through which channel?" shows the channels by baseline decile. For the quantile model, panels show the weather-sensitivity curve.
- A banner appears when the model has no weather-by-policy interaction, since the interaction channel is then zero.

User guide: [Interpreting the Decomposition tab](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#interpreting-the-decomposition-tab).

## References

[@firpo2009] for the quantile model on which the repositioning channel rests. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Channel kernel, quantile model | (1.1), (2.1), (3.1), (3.2) | `R/fct_policy_decompose.R` `.compute_rif_channels()` |
| Channel kernel, linear model | (1.1), (3.2) | `R/fct_policy_decompose.R` `.decompose_ols()` |
| Household decomposition entry point | (3.3) | `R/fct_policy_decompose.R` `decompose_policy_effect()`, `.build_decomposition_context()` |
| Covariate changes | (1.1) | `R/fct_policy_decompose.R` `.compute_policy_deltas()` |
| Matching variables to terms | (1.1) | `R/fct_policy_sim.R` `.policy_lever_terms()` |
| Channels per prediction row | Setup, (3.3) | `R/fct_policy_metric_decompose.R` `.prepare_policy_annual_channels()`, `.policy_annual_channel_block()` |
| Outcome-unit channels | (4.1) | `R/fct_policy_metric_decompose.R` `.policy_level_channels()` |
| Cumulative states and contributions | (5.1), (5.2) | `R/fct_policy_metric_decompose.R` `.policy_metric_pipeline()`, `.policy_metric_contributions()` |
| Summary across years and members | Section 5 | `R/fct_policy_metric_decompose.R` `.policy_metric_summary()`, `.policy_metric_decomposition()` |
| Adverse-year read | (5.3) | `R/fct_policy_metric_decompose.R` `.policy_metric_tails()` |
| Decile groups | Section 5 | `R/fct_policy_metric_decompose.R` `.policy_metric_pipeline()`; `R/fct_decomposition_summary.R` `.decomposition_outcome_deciles()` |
| Mechanism diagnostics | Section 6 | `R/fct_policy_metric_decompose.R` `.policy_metric_pipeline()` |
| Outcome-unit summary of channels | (4.1) | `R/fct_decomposition_summary.R` `.decomposition_outcome_channels()`, `.decomposition_outcome_summary()` |
| Check that states end at the policy arm | (5.2) | `R/fct_policy_metric_decompose.R` `.policy_metric_pipeline()` |
