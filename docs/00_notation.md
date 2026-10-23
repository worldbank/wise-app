---
id: notation
title: Notation and conventions
app_step: cross
depends_on: []
symbols: [i, l, g, t, r, mu, s, m, v, tau, Y, y, pi, omega, z, W, M, X, D, beta, theta, gamma, delta, alpha, lambda, epsilon, Sigma, L, F_hat, q_tau, T, Delta]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#high-dimensional-fixed-effects-demeaning
code: [R/fct_results.R, R/fct_outcome.R, R/fct_surveystats.R, R/fct_spec_defaults.R, R/fct_incidence.R, R/fct_simulations.R, R/fct_aggregation.R, R/fct_rif_sim.R, R/fct_loc_panel.R, R/utils_math.R]
verified_against: 6529b81
---

# Notation and conventions

> This page fixes the symbols, indices, units and scales used on every other page of this reference. Read it first. If a symbol appears elsewhere with a different meaning, this page is wrong and should be fixed, not the other page.

## Setup

WISE-APP works with three kinds of objects: a **survey** (people or households observed once, in a survey round), **weather** (monthly series at places), and a **fitted model** that links the two. The indices below name the dimension along which each object varies.

### Indices

| Symbol | Meaning | Notes |
|---|---|---|
| $i$ | Analysis unit | A household by default; an individual or a firm when the level of analysis is changed in Step 1. |
| $\ell$ | Survey location | A place where interviews took place, tied to one or more H3 cells. All units in a location share the same weather. |
| $g$ | Area group | The administrative area used for the area fixed effect. By default the first administrative level (region or province). |
| $t$ | Survey round | A survey wave, identified by its year. Also the index of the time fixed effect. |
| $\mu$ | Calendar month | $\mu \in \{1,\dots,12\}$. $\mu_i$ is the month in which unit $i$ was interviewed. |
| $r$ | Simulation year | The calendar year of the weather that is applied to the baseline population in Step 2. Historical years in the historical window, projected years in a future period. |
| $s$ | Scenario | The historical scenario, or a combination of an emissions pathway (SSP) and a future period. |
| $m$ | Climate model member | One member of the CMIP6 ensemble. Used only for future scenarios. |
| $v$ | Weather variable | One of at most two weather variables chosen in Step 1. |
| $\tau$ | Quantile level | A point of the welfare distribution, $\tau \in (0,1)$. The unconditional quantile regression uses the grid $\tau \in \{0.1, 0.2, \dots, 0.9\}$. |

### Data objects

| Symbol | Meaning |
|---|---|
| $Y_i$ | Welfare **level** of unit $i$ (for example consumption per person per day). |
| $y_i$ | Outcome on the **model scale**: $\log Y_i$ for a continuous outcome, the indicator itself for a binary outcome. |
| $\omega_i$ | Survey sampling weight of unit $i$, as supplied in the data. |
| $z$ | Poverty line, in the same currency as $Y_i$. |
| $W_i$ | Vector of weather regressors of unit $i$ (levels, polynomial terms or bin indicators, see [12_weather_measures](12_weather_measures.md)). |
| $M_i$ | Moderators: the categorical variables that are interacted with weather. |
| $X_i$ | Other covariates (individual, household, firm and area characteristics). |
| $D_i$ | Policy variables: the subset of $M_i$ and $X_i$ that a policy lever changes in Step 3. |
| $N$ | Number of units in the baseline survey sample. |

### Parameters and estimates

| Symbol | Meaning |
|---|---|
| $\beta$ | Coefficients on weather. With bins, one coefficient per non-reference bin. With the quantile model, $\beta_\tau$ depends on the quantile. |
| $\theta$ | Coefficients on the moderators (their main effects). |
| $\gamma$ | Coefficients on weather-by-moderator interactions. |
| $\delta$ | Coefficients on the other covariates. |
| $\alpha_g,\ \lambda_t$ | Area fixed effect and time (survey-round) fixed effect. |
| $\varepsilon_i,\ \hat\varepsilon_i$ | Regression error and its fitted residual. |
| $\hat\Sigma$ | Estimated covariance matrix of the coefficients, clustered by location panel. |
| $L$ | Lower-triangular Cholesky factor, $L L^{\prime} = \hat\Sigma$. |
| $\hat F$ | Empirical distribution function of the model-scale outcome in the estimation sample. |
| $q_\tau$ | The $\tau$-quantile of the outcome distribution. |
| $T$ | A population statistic of welfare, such as the poverty rate. $T^{(r,s,m)}$ is its value for simulation year $r$, scenario $s$ and member $m$. |
| $\Delta$ | A change caused by a policy: policy run minus baseline run, under the same weather. |

A hat marks an estimate ($\hat\beta$). A star marks a counterfactual value ($y_i^{*}$). Superscripts in parentheses, such as $W_i^{(r,s,m)}$, index a simulation draw.

## Method

### 1. Outcome scale and units

Welfare is stored in 2021 international dollars (PPP) per person per day. A local-currency (LCU) outcome multiplies it by the 2021 conversion factor $\pi_i$ (LCU per PPP dollar, taken from the CPI and PPP table that comes with the data):

$$Y_i^{\text{LCU}} = \pi_i \, Y_i^{\text{PPP}} \tag{1.1}$$

Welfare is bottom-coded at the level used by the World Bank Poverty and Inequality Platform when the survey is loaded:

$$Y_i \leftarrow \max\{Y_i,\ 0.28\} \quad \text{(2021 PPP)} \tag{1.2}$$

A continuous outcome is modelled in logs and a binary outcome as it is:

$$y_i = \begin{cases} \log Y_i & \text{continuous outcome} \\ \mathbb{1}[\text{event}] & \text{binary outcome} \end{cases} \tag{1.3}$$

The poverty indicator is the binary outcome $\mathbb{1}[Y_i < z]$, with $Y_i$ and $z$ in the same currency. Predictions are back-transformed with $\hat Y_i = \exp(\hat y_i)$ whenever a level is needed (see [21_model_linear](21_model_linear.md)).

### 2. Reference estimating equation

Every model page is a variant of one equation. For unit $i$ in location $\ell$, area $g$ and survey round $t$:

$$y_i = W_i^{\prime}\beta + M_i^{\prime}\theta + (W_i \otimes M_i)^{\prime}\gamma + X_i^{\prime}\delta + \alpha_{g} + \lambda_{t} + \varepsilon_i \tag{2.1}$$

where $W_i \otimes M_i$ collects the products of each weather regressor with each moderator. The quantile model replaces $y_i$ by a transformed outcome and lets every coefficient depend on $\tau$. The tree-based models do not have this form. Pages that need the exact variant restate it.

The area and time effects in Eq. (2.1) are the default choice (administrative level 1 and survey year). The user may absorb other categorical variables.

### 3. Counterfactual notation

Step 2 applies the fitted model to a fixed **baseline** survey sample while the weather changes. For simulation year $r$, scenario $s$ and member $m$, the counterfactual weather of unit $i$ is $W_i^{(r,s,m)}$ and the model-scale prediction is $y_i^{*(r,s,m)}$. Historical runs have no $s$ or $m$ index and are written $W_i^{(r)}$. The statistic of interest is a weighted function of the back-transformed values:

$$T^{(r,s,m)} = \mathcal{A}\Big(\big\{(Y_i^{*(r,s,m)},\ \omega_i)\big\}_{i=1}^{N}\Big) \tag{3.1}$$

where $\mathcal{A}$ is the rule for the chosen metric (see [32_metrics](32_metrics.md)).

Step 3 changes the policy variables from $D_i$ to $D_i^{\text{pol}}$ and re-evaluates the same prediction. The policy effect on a statistic is

$$\Delta T^{(r,s,m)} = T^{(r,s,m)}_{\text{policy}} - T^{(r,s,m)}_{\text{baseline}} \tag{3.2}$$

with the same weather, the same baseline population and the same coefficient draws in both arms.

### 4. Quantile position

The quantile model needs the rank of a unit in the outcome distribution. The rank of unit $i$ is read from the empirical distribution function of the **estimation sample** on the model scale, clipped to the estimated grid:

$$\tau_i = \min\Big\{\max\big\{\hat F(y_i),\ 0.1\big\},\ 0.9\Big\} \tag{4.1}$$

## Interpretation

- **Weights.** The app uses $\omega_i$ exactly as supplied. It does not rescale household weights by household size. Population statistics in Steps 2 and 3 are weighted by $\omega_i$. The model in Step 1 is estimated without weights (see [20_model_specification](20_model_specification.md)).
- **Log scale.** On the model scale, a difference of $0.10$ in $y_i$ is about a 10 per cent difference in welfare, and exactly $100(e^{0.10}-1) \approx 10.5$ per cent.
- **Location versus location panel.** A location is the unit that shares one weather series. A location panel groups locations of different survey rounds whose H3 cells overlap, so the same place is recognised across rounds. Standard errors are clustered at the location panel (see [20_model_specification](20_model_specification.md)).
- **Dollar sign.** "Dollar" always means 2021 PPP dollar per person per day, unless the outcome currency is set to local currency.

## Assumptions

- **A1. Positive welfare.** After bottom-coding, $Y_i > 0$ for every unit, so the logarithm is defined. This holds by Eq. (1.2) for the monetary outcome; a non-monetary continuous outcome must be strictly positive in the source data.
- **A2. Common deflation.** A conversion factor that is constant within a fixed-effect cell (area by survey round) shifts $\log Y_i$ by a constant that the fixed effects absorb, so the choice between dollars and local currency does not change the estimated coefficients. It does change the units of the poverty line and of predicted levels.

## Limitations and what is not modelled

- Survey design (strata and primary sampling units) is not available for the harmonised surveys, so no design-based variance is computed. Sampling weights are used only in aggregation.
- Prices, wages and the exchange rate are not modelled. Welfare is deflated once, by the data, and kept in 2021 prices.
- Weights are not converted between household level and person level.

## In the app

- Outcome and currency: Step 1 > Outcome.
- Weather regressors: Step 1 > Weather.
- Fixed effects and covariates: Step 1 > Model > Model settings.
- Baseline survey, historical window, scenarios: Step 2 > Simulation settings.
- Policy variables: Step 3, one panel per lever group.

User guide: [Step 1 methodology](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#methodology-detail), [Step 2](https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#methodology-detail), [Step 3](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#methodology-detail).

## References

Full entries are in [references](references.md). Used here: the World Bank Poverty and Inequality Platform methodology for bottom-coding; [@firpo2009] for the unconditional quantile.

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Conversion to local currency and model scale | (1.1), (1.3) | `R/fct_results.R` `outcome_level_scale()`, `outcome_to_model_scale()`, `prepare_outcome_df()` |
| Bottom-coding at 0.28 | (1.2) | `R/fct_surveystats.R` `bottom_code_welfare()`; constant `WISEAPP_WELFARE_FLOOR` in `R/fct_spec_defaults.R` |
| Log transform rule (numeric outcomes are logged) | (1.3) | `R/fct_outcome.R` `outcome_transform()` |
| Survey weight column | weights | `R/fct_incidence.R` `survey_weight_column()` |
| Location panel | cluster | `R/fct_loc_panel.R` `loc_panel()` |
| Coefficient covariance and Cholesky factor | $\hat\Sigma$, $L$ | `R/fct_simulations.R` `compute_chol_vcov()` |
| Aggregate statistic of welfare | (3.1) | `R/fct_aggregation.R` `resolve_agg_fn()` |
| Quantile position clipped to the grid | (4.1) | `R/fct_rif_sim.R` `predict_rif()` |
| Historical simulation dates (month by year) | $r$, $\mu$ | `R/fct_simulations.R` `build_hist_sim_dates()` |
| Default seed | reproducibility | `R/utils_math.R` `WISEAPP_DEFAULT_SEED` |
