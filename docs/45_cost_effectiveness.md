---
id: cost-effectiveness
title: Cost-effectiveness of a cash transfer
app_step: 3
depends_on: [notation, policy-framework, social-protection, shock-sp, metrics, decomposition]
symbols: [T, z, omega, Delta]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#interpreting-the-results-tab
code: [R/fct_sp_effectiveness.R, R/fct_step3_tables.R, R/fct_sp_shock.R, R/mod_3_10_cost_effectiveness.R]
verified_against: 72a2fdb
---

# Cost-effectiveness of a cash transfer

> The cost-effectiveness tab divides the annual cost of a cash transfer by the effect that the policy run attributes to it, for the poverty metric chosen in Results. For the poverty rate it reports the cost per net person-year lifted out of poverty in an average year (annual net person-years, not unique people). For the poverty gap it reports the poverty gap closed per dollar. Each is given for an average weather year and for a 1-in-20 adverse year. Metrics that have no per-dollar reading are not scored.

## Setup

The tab joins two results of the same Step 3 run: the **cost** of the programme ([42_social_protection](42_social_protection.md) for a regular transfer, [43_shock_responsive_sp](43_shock_responsive_sp.md) for a shock-responsive one) and the **effect** on the metric of Results, which is the paired difference $\Delta T$ between the policy and baseline series ([40_policy_framework](40_policy_framework.md)). Let $C$ be the annual cost, including administration, in the currency in which the amounts were entered. Let $P$ be the number of people represented by the baseline survey: the sum of the survey weights, or the household members of the households if there are no weights, or the number of rows otherwise. Let $z$ be the poverty line per day in the same currency.

## Method

### 1. Inputs

**Effect.** For the average year, the effect $\Delta T^{\text{avg}}$ is the expected paired effect of the policy on the chosen metric. Years are averaged within each climate member first, then members are averaged with equal weight, with its coefficient standard deviation from the paired contrast ([33_uncertainty](33_uncertainty.md)). For the adverse year, the effect $\Delta T^{\text{adv}}$ is the total effect of the policy in the 1-in-20 adverse year of the baseline, read as in Eq. (5.3) of [44_decomposition](44_decomposition.md). It has no interval, because the uncertainty of its components is not estimated.

**Cost.** For a regular programme, the cost is the same in every year, Eq. (4.1) of [42_social_protection](42_social_protection.md), so the average-year cost and the adverse-year cost are equal. For a shock-responsive programme, the cost differs by year, and it is pooled on the same member-years as the effect. The average-year cost is the equal-weight mean over climate models of each model's mean annual cost. The adverse-year cost applies the same adverse-year ranking as the effect, by rank interpolation between the two baseline years of each model, and averages over models.

### 2. Poverty rate: cost per person lifted

The metric is the poverty rate. The net number of people lifted out of poverty is

$$L = -\ \Delta T\ P, \qquad \text{cost per person lifted} = \frac{C}{L} \qquad \text{(2.1)}$$

The count is net: a household that falls into poverty offsets one that leaves it. Gross movements are not computed. The ratio is reported only if $L \ge 10^{-4}\ P$ (a fall of at least 0.01 percentage points in the poverty rate). A smaller effect would give an extreme ratio, so it is reported as not applicable.

### 3. Poverty gap: gap closed per dollar

The metric is the poverty gap, as a share of the line. The annual value of the change in the aggregate gap, in currency, is

$$V = -\ \Delta T\ z\ P\ 365, \qquad \text{gap closed per dollar} = \frac{V}{C} \qquad \text{(3.1)}$$

It is reported only if $V > 0$. A programme that closes the gap by one dollar for each dollar spent has a ratio of 1. A ratio below 1 means that part of the cost does not reach the poor (leakage, or administration) or that the transfer exceeds what the poor need.

### 4. Intervals

For the average year, the 95 per cent interval is built from the effect plus and minus $1.96$ times its standard deviation. For the gap, the two ends are carried through Eq. (3.1). For the poverty rate, the two ends give two values of $L$, and the interval for $C/L$ is bounded only if the smaller $L$ is at least $10^{-4}\ P$. If the effect interval reaches zero, the app reports the interval as not bounded. The adverse year has no interval.

### 5. Metrics without a per-dollar reading

The mean and the total of welfare are not scored. The transfer is added to welfare, so its gain per dollar is about one minus the administration share, whatever the targeting. Other metrics also have no reading. The app then asks the user to choose the poverty rate or the poverty gap in Results.

### 6. Cost split

For a poverty-based metric, the tab also shows how the cost divides between transfers that reach the poor, transfers that reach people above the line (leakage, Eq. (6.1) of [42_social_protection](42_social_protection.md)), and administration. For a shock-responsive programme, the tab adds the coverage and adequacy of the affected poor, and the cost under each climate scenario against the historical record ([43_shock_responsive_sp](43_shock_responsive_sp.md)).

## Interpretation

- A cost per person lifted is a net quantity for the population as a whole, in a given weather year. It is a ranking device for programme designs under the same assumptions, not a budget.
- The adverse-year ratio uses the effect and the cost of the baseline's 1-in-20 adverse year, so it can differ from the average-year ratio. For a regular programme only the effect differs. For a shock-responsive programme the cost differs as well.
- The effect is the effect of all levers of the run. If any lever other than the cash transfer is moved, the effect cannot be credited to the transfer's cost, and the tab shows every ratio as not applicable. To score a transfer, run Step 3 with the cash transfer alone.
- A poverty line in local currency must be entered in the currency of the outcome.

## Assumptions

- **A1. Effects are net.** People who leave poverty and people who enter it offset one another.
- **A2. The cost is the programme's own.** Only transfers and administration are counted. Costs of financing, delivery capacity or other levers are not.
- **A3. One population.** The number of people lifted is the change in the rate times the population of the baseline survey. The population is fixed.
- **A4. Fixed line.** The poverty line is the one in Results, constant across years and scenarios.

## Limitations and what is not modelled

- Gross movements into and out of poverty.
- The benefits of the transfer other than the change in the chosen metric.
- Uncertainty in the adverse-year ratio.
- Costs of any lever other than the cash transfer.
- A comparison of programmes with different effect on different metrics. Each run is scored on one metric at a time.

## In the app

- Step 3 > Cost-effectiveness: a table of the ratio by scenario and weather year (average or 1-in-20), with the annual cost, the change in the metric and a 95 per cent interval, followed by a chart of the ratio and of the annual cost. A programme with a trigger adds the climate-adjusted cost and the coverage of the affected poor.

User guide: [Interpreting the Results tab](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#interpreting-the-results-tab).

## References

None beyond [40_policy_framework](40_policy_framework.md). Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Effect by scenario, average and adverse year | Section 1 | `R/fct_sp_effectiveness.R` `sp_effect_by_scenario()` |
| Population represented | Setup | `R/fct_sp_effectiveness.R` `.sp_ce_population()` |
| Cost per person lifted and gap per dollar | (2.1), (3.1) | `R/fct_sp_effectiveness.R` `sp_cost_effectiveness()` |
| Near-zero effect rule | (2.1) | `R/fct_sp_effectiveness.R` `SP_CE_MIN_EFFECT` |
| Intervals | Section 4 | `R/fct_sp_effectiveness.R` `sp_cost_effectiveness()` |
| Regular programme cost | Section 1 | `R/fct_step3_tables.R` `step3_cost_effectiveness()`; `R/fct_policy_sim.R` `.sp_transfer_totals()` |
| Shock programme cost on the effect's support | Section 1 | `R/fct_sp_shock.R` `sp_shock_cost_by_scenario()` |
| Climate-adjusted cost | Section 6 | `R/fct_sp_shock.R` `sp_shock_climate_cost()` |
| Cost split and leakage | Section 6 | `R/fct_step3_tables.R` `step3_cost_effectiveness()`, `step3_sp_effectiveness()` |
| Display tables | In the app | `R/fct_sp_effectiveness.R` `.sp_ce_display()`; `R/mod_3_10_cost_effectiveness.R` |
