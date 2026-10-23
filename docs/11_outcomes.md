---
id: outcomes
title: Outcomes and poverty lines
app_step: 1
depends_on: [notation, data]
symbols: [Y, y, z, pi, omega]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#welfare-outcome
code: [R/fct_outcome.R, R/fct_results.R, R/fct_spec_defaults.R, R/fct_step1_data.R, R/fct_policy_sim.R]
verified_against: 6529b81
---

# Outcomes and poverty lines

> The outcome is the quantity whose weather response the model estimates. A continuous outcome such as welfare is modelled in logs. A binary outcome, such as being poor, is modelled as it is. This page fixes how each outcome is built, in which currency it is expressed, and where the default poverty line comes from.

## Setup

Outcomes come from the variable list. Each outcome has a type (continuous or binary) and units (a currency, or none). The app adds one outcome of its own: **poor**, an indicator that welfare is below a poverty line. It is offered whenever welfare is available. Outcomes are listed with welfare first, poor second, and the others after.

Symbols follow [00_notation](00_notation.md): $Y_i$ is the outcome level, $y_i$ the model-scale outcome, $z$ the poverty line and $\pi_i$ the 2021 conversion factor from PPP dollars to local currency.

## Method

### 1. Monetary and other outcomes

An outcome is **monetary** if it is welfare or poor, or if its units are local currency. Only monetary outcomes have a currency choice and a poverty line. Other outcomes keep the units of the variable list and have no poverty line.

### 2. Model scale

A continuous outcome is modelled in logs and a binary outcome as it is (Eq. (1.3) in [00_notation](00_notation.md)). The log is applied to every outcome of continuous type, monetary or not. It requires $Y_i > 0$. Estimated effects on a log outcome are semi-elasticities, so a coefficient $b$ means a change of $100(e^{b}-1)$ per cent in the outcome.

### 3. Currency

The stored monetary values are in 2021 PPP dollars ([10_data](10_data.md)). The user chooses the currency in which the outcome is modelled:

$$y_i = \begin{cases} \log Y_i^{\text{PPP}} & \text{currency PPP (default)} \\ \log\big(\pi_i\, Y_i^{\text{PPP}}\big) & \text{currency LCU (2021 prices)} \end{cases} \tag{3.1}$$

For a log outcome, the LCU choice adds $\log \pi_i$ to $y_i$. If $\pi_i$ is constant within a fixed-effect cell, the fixed effects absorb it and the weather coefficients are unchanged (A2 in [00_notation](00_notation.md)). The currency choice then sets only the units of the poverty line and of predicted and simulated levels.

### 4. The poverty indicator

The poor outcome compares welfare with the line in the currency of the line. With a line $z$ in PPP dollars:

$$\text{poor}_i = \mathbb{1}\big[Y_i^{\text{PPP}} < z\big] \tag{4.1}$$

With a line in local currency, the comparison is made on the stored PPP value, after the line is divided by the unit's own conversion factor:

$$\text{poor}_i = \mathbb{1}\big[Y_i^{\text{PPP}} < z^{\text{LCU}}/\pi_i\big] \tag{4.2}$$

This is the same test as $\pi_i Y_i^{\text{PPP}} < z^{\text{LCU}}$. The indicator is never converted to local currency.

### 5. Default poverty line

The line starts at the following values, which the user may change.

- **PPP:** $3.00$ per person per day, in 2021 PPP dollars.
- **LCU:** the weighted 20th percentile of welfare in local currency in the loaded surveys,
$$z^{\text{LCU}}_{\text{default}} = \hat Q^{\,\omega}_{0.20}\big(\pi_i Y_i^{\text{PPP}}\big) \tag{5.1}$$
rounded to two decimals. The weights are the survey weights as supplied. Surveys of all selected rounds and countries are pooled. If the percentile cannot be computed, the line is $1.00$.

A monetary outcome other than poor also carries a line, which Step 2 and Step 3 use for poverty-type metrics. It starts at the same default.

### 6. Direction

Each outcome is marked "higher is better" or "lower is better". Poor and the poverty-type metrics are lower-is-better. Every other continuous outcome is higher-is-better. A binary outcome takes the direction given in the variable list, and has no direction if the list gives none. The direction is used only to colour and word results.

## Interpretation

- Modelling welfare in logs and then evaluating the poverty rate in Step 2 uses the full distribution of simulated welfare. Modelling the poor indicator directly estimates only the effect of weather on the probability of being poor. See [21_model_linear](21_model_linear.md).
- A 20th-percentile line in local currency makes the headline poverty rate about 20 per cent by construction in the pooled sample. It is a relative line.
- Changing the poverty line after the model is fitted changes Step 2 metrics, but not the model, unless the outcome is poor.

## Assumptions

- **A1. Positive outcome.** A continuous outcome is strictly positive, so that its log exists. Welfare satisfies this by the bottom-coding in [10_data](10_data.md).
- **A2. Line fixed.** The poverty line is the same for every household and every simulation year. It is not adjusted for inflation or growth in simulated years.
- **A3. Log-linear response.** Weather acts proportionally on a continuous outcome (see [21_model_linear](21_model_linear.md)).

## Limitations and what is not modelled

- Relative and absolute lines are not combined. Only one line is used per run.
- Non-monetary continuous outcomes such as a count of days cannot be zero, because of the log. They must be recoded in the data.
- Household composition and economies of scale are not adjusted; welfare is as supplied per person.
- No equivalence scale or price differences within a country are applied.

## In the app

- Step 1 > Outcome: choose the outcome, currency and poverty line. **Outcome stats** shows summary statistics, distributions by round, and the share of units with a non-missing outcome by location.

User guide: [Welfare outcome](https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#welfare-outcome).

## References

World Bank Poverty and Inequality Platform methodology for the welfare floor. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| List of outcomes with the added poor outcome | 1 | `R/fct_outcome.R` `filter_outcome_vars()` |
| Monetary outcome test | 1 | `R/fct_outcome.R` `is_monetary_outcome()` |
| Log transform for continuous type | 2 | `R/fct_outcome.R` `outcome_transform()` |
| Currency and model scale | (3.1) | `R/fct_results.R` `outcome_level_scale()`, `outcome_to_model_scale()`, `prepare_outcome_df()` |
| Poor indicator and LCU line conversion | (4.1), (4.2) | `R/fct_results.R` `prepare_outcome_df()`, `.povline_to_ppp()`; `R/fct_step1_data.R` `wise_outcome_data()` |
| Default lines | (5.1) | `R/fct_outcome.R` `default_lcu_poverty_line()`; `R/fct_spec_defaults.R` `wise_default_poverty_line()` |
| Weighted percentile | (5.1) | `R/fct_policy_sim.R` `.sp_welfare_quantile()` |
| Direction | 6 | `R/fct_outcome.R` `outcome_direction()`, `build_selected_outcome()` |
