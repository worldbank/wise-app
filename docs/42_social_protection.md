---
id: social-protection
title: Regular cash transfers: targeting, amount, cost and reach
app_step: 3
depends_on: [notation, policy-framework, outcomes, metrics]
symbols: [Y, omega, z, T]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#social-protection-cash-transfers
code: [R/fct_policy_sim.R, R/fct_step3_input.R, R/fct_sp_effectiveness.R, R/fct_policy_metric_decompose.R, R/mod_3_01_sp.R]
verified_against: 8592a9d
---

# Regular cash transfers: targeting, amount, cost and reach

> A regular cash transfer pays eligible households the same amount in every simulated year. The app chooses who is eligible, adds targeting errors, sets the amount from a payment or from a budget, and adds the transfer to simulated welfare. It then reports what the programme costs and how well it reaches the poor. A transfer is not a coefficient of the model. It is added directly to welfare.

## Setup

The transfer is a lever of Step 3 ([40_policy_framework](40_policy_framework.md)). It is the one lever that needs no variable in the Step 1 model. A programme is either regular (this page) or shock-responsive ([43_shock_responsive_sp](43_shock_responsive_sp.md)). The two share the rules for eligibility, targeting errors and the amount per payment.

Welfare is a daily per-person amount ([11_outcomes](11_outcomes.md)). Household $i$ has weight $\omega_i$, which counts the people it represents, and size $s_i$ (the number of members). The unit of analysis decides what a row is. The conventions below are for a household analysis. For an individual or firm analysis, $s_i = 1$.

The user enters the amounts in the currency of the outcome, which is 2021 PPP dollars or local currency of 2021. Welfare is stored in 2021 PPP dollars. A local-currency amount is divided by the household's PPP conversion factor before it is added to welfare.

## Method

### 1. Eligibility

Eligibility is decided once, on the baseline survey, and does not change across years. There are three rules.

$$E_i = \begin{cases} 1 & \text{universal} \\\\ \mathbf{1}\big[Y_i^{\text{base}} \le q_p\big] & \text{ex ante: the poorest } p\ \text{per cent} \\\\ \mathbf{1}\big[Q_i = c\big] \text{ or } \mathbf{1}\big[Q_i \le c\big] & \text{proxy means test on a variable } Q_i \end{cases} \qquad \text{(1.1)}$$

- **Ex ante.** $q_p$ is the survey-weighted $p$-th percentile of baseline welfare, with $p$ between 5 and 60 per cent (default 20). "Ex ante" means that the ranking is by baseline welfare, before the policy.
- **Proxy means test.** The user chooses a variable $Q_i$ and a cut-off $c$. If the variable takes exactly the values 0 and 1, a household is eligible if it equals $c$. Otherwise, it is eligible if its value is at or below $c$. A household with a missing value is not eligible. An unusable variable or cut-off makes nobody eligible.

### 2. Targeting errors

Real programmes miss some of the eligible and reach some who are not. Unless targeting is universal, the app applies two errors to the rule of Eq. (1.1). Let $e_{\text{in}}$ be the **inclusion error**, the share of non-eligible units that receive the transfer, and $e_{\text{ex}}$ the **exclusion error**, the share of eligible units that do not receive it. Each is between 0 and 30 per cent (default 10).

The two groups are formed from the eligibility of Eq. (1.1), and the two errors are drawn independently. With survey weights, the target is a share of weight, and not of rows. For the group $G$ (non-eligible for inclusion, eligible for exclusion) and error rate $e$, units are put in random order and the units from the start of the order are flipped, up to the point where the cumulated weight is closest to the target:

$$\text{flip the first } k \text{ units, } k = \arg\min_{j}\Big|\sum_{l \le j}\omega_{(l)} - e\sum_{i \in G}\omega_i\Big| \qquad \text{(2.1)}$$

so that the weighted share of units flipped matches the rate to within the weight of one row. If the weights are all equal or absent, the number flipped is the rate times the number of rows in $G$, rounded.

By default, the units to flip are drawn uniformly. The user can concentrate errors near the cut-off. The probability of being drawn is then proportional to $\exp(-\kappa d_i)$, where $d_i$ is the distance of the unit from the cut-off in percentile rank (0 at the cut-off, at most 1) and $\kappa$ between 0 and 50 sets the concentration. Concentration is available for the ex ante rule and for a continuous proxy variable.

The realised eligibility after errors is $\tilde E_i$.

### 3. Transfer per person

The programme pays an annual amount $A$ to each recipient household, and the welfare of its members rises by a daily amount

$$v_i = \tilde E_i\ \frac{A}{365\ s_i^{\text{share}}} \qquad \text{(3.1)}$$

where $s_i^{\text{share}} = s_i$ if the amount is per household and the amount is shared among its members, and $s_i^{\text{share}} = 1$ if every member receives the amount. The user chooses the basis. A per-person basis exists only for household analysis.

There are two ways to set $A$.

- **Amount first** (default). The user enters the amount $a$ of one payment and the number of payments $n$ per year (2 to 24, default 6), and $A = a\ n$. The amount can also be set from the distribution of welfare: for a percentile $P$ between 1 and 99, $a = 365\ \hat q_{P}/n$, where $\hat q_{P}$ is the survey-weighted percentile $P$ of baseline daily welfare, in the currency of the outcome. The amount is computed once for the run, from the baseline survey. If fewer than 10 usable observations exist, the amount is zero and the run says so.
- **Budget first.** The user enters a total annual budget $B$, of which administration takes a share $a_{\text{adm}}$ first. The remainder is shared among the eligible:

$$A = \frac{B\ (1-a_{\text{adm}})}{D}, \qquad D = \sum_{i:\ \tilde E_i = 1}\frac{\omega_i}{s_i^{\text{share}}} \qquad \text{(3.2)}$$

with $D$ the weighted number of recipient units (without weights, the number of recipient units, or of recipient people for a per-person basis). Dividing by $D$ makes the total paid out equal the net budget when the weights count people.

Both ways give the daily amount of Eq. (3.1), converted to 2021 PPP dollars if the amount was entered in local currency.

### 4. Cost

The annual cost of the transfers is the sum of daily amounts over the people represented, times 365. With survey weights, a household row stands for $\omega_i$ people:

$$C_{\text{transfer}} = 365\sum_i \omega_i\ v_i^{\text{entry}}, \qquad C_{\text{total}} = \frac{C_{\text{transfer}}}{1 - a_{\text{adm}}} \qquad \text{(4.1)}$$

where $v_i^{\text{entry}}$ is the amount in the currency of entry, and $a_{\text{adm}}$ is the administration share of total cost, between 0 and 90 per cent (default 0). Without weights, a household row stands for $s_i$ people. The cost per recipient divides the transfer cost by the weighted number of recipient units.

### 5. Effect on welfare

The transfer is added to the predicted level of welfare of the same household in the same year. For a log outcome, with $\hat y_i$ the model-scale prediction and $T_i$ the transfer in the units of the outcome level, the correction is

$$\delta_i^{\text{cash}} = \log\big(e^{\hat y_i} + T_i\big) - \hat y_i \qquad \text{(5.1)}$$

and a level outcome adds $T_i$ directly. The simulated welfare of the policy arm for a log outcome is then

$$Y_i^{\text{pol}} = e^{e_i}\big(e^{\hat y_i} + T_i\big) \qquad \text{(5.2)}$$

where $e_i$ is the residual term of the run ([30_simulation](30_simulation.md)). The transfer is added to the predicted level before the residual factor, so a residual term scales the transfer by $e^{e_i}$. With no residual term, or for a level outcome, the transfer adds exactly $T_i$. If a household has no finite prediction in a year, the transfer is evaluated at its observed baseline level instead.

For the quantile model, the same correction is the main effect. It also moves the household up the distribution, which changes its weather sensitivity ([44_decomposition](44_decomposition.md)).

### 6. Reach and targeting measures

The Diagnostics tab reports measures of who the programme reaches. "Poor" means baseline welfare below the poverty line $z$ (converted to 2021 PPP for each household if entered in local currency). Let $\pi_i$ be the number of people a row stands for, and $R_i = 1$ if the household receives the transfer.

$$\text{Coverage} = \frac{\sum_i \pi_i\ R_i\ \mathbf{1}[\text{poor}_i]}{\sum_i \pi_i\ \mathbf{1}[\text{poor}_i]}, \qquad \text{Leakage} = \frac{\sum_i \pi_i\ v_i\ R_i\ \mathbf{1}[\text{non-poor}_i]}{\sum_i \pi_i\ v_i\ R_i}, \qquad \text{Adequacy} = \frac{\sum_i \pi_i\ v_i\ R_i\ \mathbf{1}[\text{poor}_i]}{\sum_i \pi_i\ R_i\ \mathbf{1}[\text{poor}_i]\ (z - Y_i^{\text{base}})} \qquad \text{(6.1)}$$

Coverage is the share of the poor who receive a transfer. Leakage is the share of spending that reaches people above the line. Adequacy is the spending on poor recipients as a share of their poverty gap, where 100 per cent closes the gap. The app also reports the realised inclusion error (recipients who are not eligible under the rule of Eq. (1.1), as a share of recipients) and the realised exclusion error (eligible units without a transfer, as a share of eligible units), and the annual cost per person in the population. Measures that need a line are shown as not available when no positive line is set.

## Interpretation

- Cost and welfare effect are computed on the same recipients, so the cost of the programme and its effect on the outcome statistics are consistent.
- The welfare effect of a transfer is mechanical: the transfer is added to welfare. A poverty rate falls when the transfer lifts a household above the line, and by no other channel. Responses such as saving or labour supply are not in the model.
- A transfer is not a variable of the model, so no coefficient links it to weather sensitivity. In the linear model a transfer therefore has no resilience effect. The quantile model has a repositioning effect, because the transfer moves the household along the distribution ([44_decomposition](44_decomposition.md)).
- Leakage and coverage depend on the line. A line in local currency must be in the currency of the outcome.

## Assumptions

- **A1. Eligibility is fixed.** Households eligible in the baseline survey remain eligible in every year and every climate scenario.
- **A2. Full take-up of the rule.** Every household selected receives the full amount, subject to the targeting errors entered by the user.
- **A3. Transfers are consumed.** The transfer adds one for one to daily welfare (Eq. (5.1)), apart from the scaling by the residual factor in Eq. (5.2).
- **A4. Amounts are known.** The transfer carries no coefficient error ([40_policy_framework](40_policy_framework.md), Section 5).
- **A5. Administration is a share of cost.** Administration cost does not reach households.

## Limitations and what is not modelled

- Behavioural responses, general-equilibrium effects of the injection of cash, and inflation.
- Changes in eligibility as welfare changes, or from year to year.
- Delivery failures other than the stated inclusion and exclusion errors.
- A transfer that depends on household size by a schedule. The amount is the same for all eligible households, and is shared by size only when it is per household.
- Tax or financing effects of the programme.

## In the app

- Step 3 > Social protection: choose a regular programme, the targeting rule and its threshold, inclusion and exclusion errors, how errors are concentrated, the basis of the amount, an amount first or a budget first, the number of payments and the administration share. A preview card shows who is reached and what it costs before the run.
- Step 3 > Diagnostics: total cost, cost per recipient, coverage, leakage, adequacy and realised errors.

User guide: [Social protection (cash transfers)](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#social-protection-cash-transfers).

## References

None beyond [40_policy_framework](40_policy_framework.md). Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Eligibility rules | (1.1) | `R/fct_policy_sim.R` `.determine_sp_eligibility()`, `.sp_welfare_quantile()` |
| Targeting errors, concentration | (2.1) | `R/fct_policy_sim.R` `.determine_sp_eligibility()`, `.sp_error_weights()`, `.sp_cutoff_distance()`, `.sp_error_concentration()` |
| Daily transfer per person | (3.1), (3.2) | `R/fct_policy_sim.R` `.sp_transfer_values()`, `.sp_amount_basis()`, `.sp_admin_share()`, `.sp_currency()` |
| Amount from a welfare percentile | Section 3 | `R/fct_step3_input.R` `wise_sp_resolve_amount()`, `wise_sp_config()` |
| Transfer written to the survey | (3.1) | `R/fct_policy_sim.R` `apply_policy_to_svy()` |
| Programme cost | (4.1) | `R/fct_policy_sim.R` `.sp_transfer_totals()`, `.sp_transfer_totals_values()` |
| Effect on predicted welfare | (5.1), (5.2) | `R/fct_policy_metric_decompose.R` `.policy_annual_channel_block()`; `R/fct_policy_decompose.R` `.compute_rif_channels()` |
| Coverage, leakage, adequacy, errors | (6.1) | `R/fct_sp_effectiveness.R` `sp_effectiveness()` |
| Preview of reach and cost | Section 6 | `R/fct_policy_sim.R` `.sp_scenario_reach()` |
