---
id: metrics
title: Welfare metrics and how annual results are summarised
app_step: 2
depends_on: [notation, outcomes, simulation]
symbols: [Y, omega, z, T, G, r, m, s]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#interpreting-the-results-tab
code: [R/fct_aggregation.R, R/fct_metric_registry.R, R/fct_sim_compare.R, R/fct_step2_tables.R, R/fct_uncertainty_helpers.R, R/fct_incidence.R, R/fct_simulations.R]
verified_against: 1ecc93e
---

# Welfare metrics and how annual results are summarised

> Each simulation year gives a vector of household welfare values and weights. A metric turns it into one number. This page defines the metrics, how the annual numbers are summarised into an expected value and return-period thresholds, how differences from the historical baseline are formed, and how effects are broken down by baseline welfare decile.

## Setup

Take one simulation year, scenario and member. Let $Y_i$ be the simulated welfare level of household $i$ ([30_simulation](30_simulation.md)), $\omega_i$ its weight, and $\tilde\omega_i = \omega_i/\sum_j \omega_j$ the weight normalised over the valid households of that year. Without weights, $\tilde\omega_i = 1/N$. A poverty line $z$ is set by the user, with the defaults in [11_outcomes](11_outcomes.md). Rows with a missing prediction or weight are excluded.

The metrics offered depend on the outcome.

| Outcome | Metrics |
|---|---|
| Welfare | mean, median, total, poverty rate, poverty gap, poverty severity, Gini, prosperity gap, average poverty |
| Other continuous outcome | mean, median, total, outcome headcount ratio, outcome gap, outcome severity, Gini |
| Binary outcome | mean (a probability) |

## Method

### 1. Definitions

$$\bar Y = \sum_i \tilde\omega_i Y_i, \qquad \text{Total} = \sum_i \omega_i Y_i \qquad \text{(1.1)}$$

The median is the smallest value $Y$ such that the weighted share of households at or below $Y$ is at least one half. Poverty is measured by the Foster-Greer-Thorbecke family [@foster1984]:

$$P_0 = \sum_i \tilde\omega_i\ \mathbf{1}[Y_i < z], \qquad P_1 = \sum_i \tilde\omega_i\ \frac{\max(z-Y_i,\ 0)}{z}, \qquad P_2 = \sum_i \tilde\omega_i\ \Big(\frac{\max(z-Y_i,\ 0)}{z}\Big)^2 \qquad \text{(1.2)}$$

These are the poverty rate, the poverty gap and the poverty severity. The Gini index is computed from households sorted by $Y$, with $F_{(i)} = \sum_{j\le i}\tilde\omega_{(j)} - \tilde\omega_{(i)}/2$ the weighted mid-rank:

$$G = \frac{2\sum_i \tilde\omega_{(i)}\ Y_{(i)}\ F_{(i)}}{\sum_i \tilde\omega_{(i)}\ Y_{(i)}} - 1 \qquad \text{(1.3)}$$

Two further measures do not use the poverty line:

$$\text{Prosperity gap} = \sum_i \tilde\omega_i \max\big(28/Y_i,\ 1\big), \qquad \text{Average poverty} = \sum_{i:\ Y_i>0} \frac{\tilde\omega_i}{Y_i} \qquad \text{(1.4)}$$

The prosperity gap is the average factor by which incomes would have to be multiplied to reach 28 dollars per person per day. The threshold 28 is fixed and is applied to the values as they are. For an outcome in local currency it is not converted. Average poverty is the average number of days needed to earn one dollar. For average poverty the weights are normalised over households with positive welfare.

For a binary outcome, the mean is the weighted share of households with the event.

### 2. Changes from the historical baseline

A result can be shown as a level or as a change from the historical reference $T^{\text{ref}}$:

$$\Delta T^{(r,s,m)} = T^{(r,s,m)} - T^{\text{ref}}, \qquad T^{\text{ref}} = \begin{cases}\text{mean over historical years} \\\\ \text{median over historical years}\end{cases} \qquad \text{(2.1)}$$

The change is absolute (in the units of the metric) for the mean, median, total, prosperity gap and average poverty. It is in percentage points for rates (poverty rate, gap, severity, and a binary mean) and in index points for the Gini index. A percentage change is not computed.

### 3. Expected value and annual spread

For a scenario with $M$ members and $R$ simulation years:

- **Member mean.** $\bar T^{m} = \frac1R\sum_r T^{(r,m)}$.
- **Expected value.** The equal-weight mean of the member means, $\frac1M\sum_m \bar T^{m}$. The historical series has one member.
- **Inter-model band.** Quantiles across the $M$ member means. It is shown only for future scenarios.
- **Inter-annual band.** For each member, the same quantiles across its $R$ annual values, then averaged over members. For the historical series the quantiles are taken over all annual values.

### 4. Return-period thresholds

Annual values are sorted ascending for each member: $v_{(1)}\le\dots\le v_{(n)}$. The value that is exceeded with probability $q$ is read by rank interpolation:

$$k = n(1-q) + \tfrac12, \qquad v(q) = (1-\theta)\ v_{(\lfloor k\rfloor)} + \theta\ v_{(\lceil k\rceil)}, \quad \theta = k-\lfloor k\rfloor \qquad \text{(4.1)}$$

Whether the adverse tail is high or low depends on the metric. For poverty measures, the Gini index, the prosperity gap and average poverty, high values are adverse. For means, medians and totals, low values are adverse. A binary outcome follows the direction given with the outcome. For an adverse event of probability $p$ (one in $1/p$ years), $q=p$ if the adverse tail is high and $q=1-p$ if it is low.

The table reports $p = 0.20,\ 0.10,\ 0.05,\ 0.02$ (labelled 1-in-5, 1-in-10, 1-in-20, 1-in-50 adverse), and $p=0.5$ (the median year, labelled "1:1"). The threshold of a scenario is the equal-weight mean over members of $v^m(q)$. A return period is shown only if every member has at least

$$n \ge \max\Big\lbrace 2,\ \Big\lceil \frac{1}{\min(p,\ 1-p)} \Big\rceil\Big\rbrace  \qquad \text{(4.2)}$$

finite annual values, and the rank $k$ lies inside $[1,n]$. With 30 historical years, the 1-in-50 value is not available.

The **return period of a historical adverse level** $\theta$ under another scenario is read from the pooled model-years:

$$\hat\pi = \frac{\text{number of } \lbrace \text{model-years with } T \text{ at least as adverse as } \theta\rbrace }{\text{number of } \lbrace \text{model-years}\rbrace }, \qquad \text{return period} = 1/\hat\pi \qquad \text{(4.3)}$$

and is infinite if no model-year reaches the level.

### 5. Sources of variation

The breakdown of the variation of a scenario into variances is

$$\sigma^2_{\text{coef}} = \overline{\text{sd}_{m,r}^2}, \qquad \sigma^2_{\text{resid}} = \overline{\text{sd}_{\text{resid},m,r}^2}, \qquad \sigma^2_{\text{annual}} = \frac1M\sum_m \mathrm{Var}_r\big(T^{(r,m)}\big), \qquad \sigma^2_{\text{model}} = \mathrm{Var}_m\big(\bar T^{m}\big) \qquad \text{(5.1)}$$

where $\text{sd}_{m,r}$ is the coefficient standard deviation of the annual value and $\text{sd}_{\text{resid},m,r}$ its residual-draw standard deviation ([33_uncertainty](33_uncertainty.md)). $\sigma^2_{\text{resid}}$ is zero except under the "resample" rule, and $\sigma^2_{\text{model}}$ is zero for the historical series. The four are shown side by side. They are not added. Under "resample" the annual spread $\sigma^2_{\text{annual}}$ also contains the year-to-year noise of the residual draws, not weather alone. The coefficient part follows the reference chosen in Results: it is computed on the series as displayed, so it is the SD of a level, or of a difference from the historical mean or median, and the Diagnostics bar is labelled accordingly.

### 6. Incidence by baseline decile

Households are placed in deciles of the observed baseline outcome, by weighted cumulative share. The deciles are fixed and not re-ranked after simulation. For each household, the simulated welfare level is averaged over years, separately for the historical series and for each member, with no residual term. The effect of a scenario on household $i$ and member $m$ is the difference of these means. The effect for decile $D_k$ is the weighted mean of the household effects, pooled over members:

$$\bar d_k = \frac{\sum_{i\in D_k}\omega_i\ \Delta_i}{\sum_{i\in D_k}\omega_i}, \qquad \Delta_i = \bar Y_i^{\ \text{scenario}} - \bar Y_i^{\ \text{historical}} \qquad \text{(6.1)}$$

### 7. Calibration against the survey

The simulated historical expected value is compared with the same metric computed from the observed survey outcome. See [30_simulation](30_simulation.md), Section 7.

## Interpretation

- The expected value is an average over weather years. The median year of the threshold table is a different summary and need not equal it.
- A 1-in-10 adverse year is the annual value that is as bad as or worse than the rest in one year out of ten, in the simulated record. With 30 years, it rests on three years.
- With 30 years, a 1-in-20 value rests on the two most extreme years. Its sampling error is not in the "Coef" or "Pooled" rows of the threshold table, which hold coefficient and model uncertainty only.
- The 20 members of a future scenario share the same sequence of observed template years, shifted by each model's monthly change. They are not 600 independent years. The variance across members at a return period measures disagreement in the climate signal, not more weather variability.
- Rates are changed in percentage points. A 2 percentage point rise in the poverty rate is not a 2 per cent rise.
- Decile effects show who bears the change, at a fixed ranking by baseline welfare.
- Poverty measures depend on the line. A line in local currency and a line in dollars must match the currency of the outcome.

## Assumptions

- **A1. Fixed weights.** The survey weights describe the baseline population and apply in every year.
- **A2. Valid welfare.** Welfare is positive where the metric requires it (prosperity gap and average poverty use only positive values).
- **A3. Exchangeable years.** The simulated years are equally likely draws of annual weather, so empirical ranks give return periods.
- **A4. Fixed prosperity threshold.** The value 28 is meaningful for the outcome's currency and time basis.

## Limitations and what is not modelled

- Return periods are empirical and bounded by the number of years. No extreme-value model is fitted.
- No weighting of climate models.
- The prosperity threshold is not converted for local-currency outcomes.
- Total uses the survey weights as supplied. It is a population total only if the weights expand to the population.
- Percentage changes of means are not reported.
- Deciles are of the observed outcome, which contains survey noise and past shocks.

## In the app

- Step 2 > Results: choose the metric, the poverty line, a difference from the historical mean or median, and the band widths. The tabs show the expected outcome, annual curves, the return-period table, the sources of uncertainty and the effects by decile.

User guide: [Interpreting the Results tab](https://github.com/worldbank/wise-app-docs/blob/main/step2.qmd#interpreting-the-results-tab).

## References

[@foster1984] on the poverty measures. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Metric functions | (1.1) to (1.4) | `R/fct_aggregation.R` `resolve_agg_fn()` |
| Metrics offered by outcome | Setup | `R/fct_aggregation.R` `hist_aggregate_choices()` |
| Units, direction and change kind | 2 | `R/fct_metric_registry.R` `metric_metadata()`, `.WISE_METRIC_REGISTRY` |
| Historical reference | (2.1) | `R/fct_step2_tables.R` `step2_hist_ref()` |
| Expected value and bands | 3 | `R/fct_step2_tables.R` `step2_pointrange_bands()`, `step2_timeseries_curves()` |
| Rank interpolation and support | (4.1), (4.2) | `R/fct_uncertainty_helpers.R` `rank_interp()`, `adverse_year_support()` |
| Return-period probabilities | 4 | `R/fct_simulations.R` `RP_LOW`, `RP_HIGH` |
| Threshold table | 4 | `R/fct_step2_tables.R` `step2_threshold_table()` |
| Return period of an adverse level | (4.3) | `R/fct_sim_compare.R` `step2_adverse_return_period()` |
| Adverse tail by metric | 4 | `R/fct_metric_registry.R` `metric_metadata()`, `metric_decision_return_periods()` |
| Variance breakdown | (5.1) | `R/fct_step2_tables.R` `step2_variance_breakdown()` |
| Decile incidence | (6.1) | `R/fct_incidence.R` `step2_incidence_by_decile()`, `weighted_baseline_deciles()` |
