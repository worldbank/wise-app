---
id: shock-sp
title: Shock-responsive cash transfers: triggers, payments and basis risk
app_step: 3
depends_on: [notation, policy-framework, social-protection, simulation, climate-scenarios, metrics]
symbols: [omega, T, r, m, s]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#shock-responsive-sp-future-release
code: [R/fct_sp_shock.R, R/fct_policy_sim.R, R/fct_policy_metric_decompose.R, R/fct_step3_input.R, R/mod_3_01_sp.R]
verified_against: 1ecc93e
---

# Shock-responsive cash transfers: triggers, payments and basis risk

> A shock-responsive programme pays only when a trigger fires. The trigger is set on the historical record and applied unchanged to every climate scenario, so under a changing climate the programme fires more or less often and its bill moves with it. This page defines the triggers, who is paid, how much, and the outputs: how often the programme pays, what a year costs, and how well payments match the losses the model predicts.

## Setup

The programme uses the same static eligibility and targeting errors as a regular transfer ([42_social_protection](42_social_protection.md), Sections 1 and 2). The static rule says who can be paid. The trigger and the layers below decide who is paid in each simulated year.

A **cell** is a survey round, a survey location and an interview month. A **cell-year** is a cell in one simulation year of one scenario and one climate model. Triggers are evaluated for each cell-year. Two households of one location interviewed in different months can therefore differ in a year. The thresholds come from the historical simulation of Step 2 and do not change under a climate scenario. Under a scenario, the same thresholds are applied to the shifted weather ([31_climate_scenarios](31_climate_scenarios.md)).

The programme is paid after the event (ex post) or, optionally, before it on a forecast (anticipatory). Payments enter the policy arm as a per-row transfer in each simulated year, added to predicted welfare as in Eq. (5.1) of [42_social_protection](42_social_protection.md).

## Method

### 1. Trigger

The trigger reads one variable $x_{c,r}$ in cell $c$ and year $r$. It is one of the following.

- **A weather variable.** Any continuous weather variable of the run, in the units of the model: its physical unit, a deviation from the normal, or a standardised anomaly. A binned variable is used through its continuous version.
- **An impact on welfare**, computed from the central predictions of Step 2, without residual draws. It is read for the whole country, for a first or second administrative level, or for a survey location (months pooled). It always fires on high values.
  - *Loss.* Minus the survey-weighted mean of $Y_i/\bar Y_i - 1$ over the households of the unit and year, in per cent. $Y_i$ is predicted welfare in the year and $\bar Y_i$ is the mean of the household's predictions over the historical years (its typical level).
  - *Poverty rate.* The weighted per cent of households with predicted welfare below the trigger's own poverty line.
  - *Number of poor.* The weighted number of those households.

  A poverty measure below the national level is missing if the unit has fewer than 30 sampled households in the year.

The threshold is either a value entered by the user, or a **return period**: the 1-in-$N$ level of the cell's own historical record. For a trigger that fires above its threshold, with $N_{\text{tail}} = N$ (or $2N$ if the trigger fires at either extreme, because each tail then has half the probability):

$$\xi_c = Q_{1-1/N_{\text{tail}}}\big(\lbrace x_{c,r}\rbrace _{r \in \text{hist}}\big) \qquad \text{(1.1)}$$

where $Q_q$ is the sample quantile of type 7. A trigger that fires below uses $Q_{1/N_{\text{tail}}}$. A cell supports a 1-in-$N$ trigger only if its historical record has at least $\lceil N_{\text{tail}}\rceil$ finite years, as in the return-period rule of Step 2. A cell with a shorter record never fires. The run stops if no cell supports the trigger. For an impact metric, a cell whose threshold equals its lowest historical value is treated as having no adverse tail and never fires.

The trigger fires for a cell-year when

$$F_{c,r} = \mathbf{1}\big[x_{c,r} \ge \xi_c\big] \ \text{(above)}, \qquad \mathbf{1}\big[x_{c,r} \le \xi_c\big] \ \text{(below)}, \qquad \mathbf{1}\big[x_{c,r} \ge \xi_c^{\text{high}}\ \text{or}\ x_{c,r} \le \xi_c^{\text{low}}\big] \ \text{(either)} \qquad \text{(1.2)}$$

A missing value, or a cell without a threshold, does not fire. Before choosing a weather trigger, the user can see a **response check**: the households' modelled loss by decile of the weather variable over the historical years. It suggests whether losses concentrate at high values, low values or both, and flags a variable with no clear response as a weak trigger.

### 2. Payout scope

Let $\pi_{j}$ be the survey-weighted population of a cell-year, and let $\rho_r$ be the share of the population in cells where the trigger fires in year $r$:

$$\rho_r = \frac{\sum_{c}\pi_{c,r}\ F_{c,r}}{\sum_{c}\pi_{c,r}}, \qquad G_r = \mathbf{1}\big[\rho_r > 0 \ \text{and}\ \rho_r \ge k/100\big] \qquad \text{(2.1)}$$

The scope sets who is paid in year $r$:

| Scope | Paid in year $r$ |
|---|---|
| Local | Households of cells where the trigger fires. |
| National gate, triggered cells | Households of cells where the trigger fires, but only in years with $G_r = 1$. |
| National gate, all targeted households | Every eligible household, in years with $G_r = 1$. Requires $k > 0$. |

The national share $k$ is between 0 and 100 per cent. With $k = 0$, the national gate with triggered cells is the same as the local scope.

### 3. Layers of dynamic targeting

Two optional layers narrow the scope further. A household is paid only if it passes the static rule, the scope and every layer.

**Worst-affected locations.** In each year, the triggered cells are ranked from the most severe to the least. Severity is the depth beyond the threshold in units of the cell's historical standard deviation of the trigger variable. For an impact trigger it is the cell's modelled loss, and for an anticipatory design it is a random draw, so that the order carries no information on the realised event. Cells are paid in this order while the population of the cells ranked before them is below a share $g$ of the year's triggered population:

$$\text{cell } j \text{ is paid} \iff \sum_{j' \text{ ranked before } j}\pi_{j'} < g\sum_{j'}\pi_{j'} \qquad \text{(3.1)}$$

A share of 100 per cent keeps all triggered cells. This layer is not offered together with the national gate that pays all targeted households.

**Predicted welfare.** The programme pays a household if its predicted welfare in the year is at or below a cut-off, the survey-weighted $q$-th percentile of the households' typical level $\bar Y_i$. This is an oracle: the model's own prediction of welfare in that year. Errors are applied to it. A household below the cut-off is dropped with the exclusion probability, and one above it is added with the inclusion probability. The draws are seeded by the survey row and the year, and shared by all scenarios and climate models.

### 4. Amount and budget

A **fixed amount** pays each paid household the amount of one payment times the number of payments per activation, as the transfer-first rule of a regular programme ([42_social_protection](42_social_protection.md), Eq. (3.1)). The amount is the same in every cell.

A budget **linked to modelled loss** pays, in a cell-year, a share $\lambda$ of the modelled loss of the households that are eligible and in scope. A household's loss is the shortfall of its predicted welfare from its typical level, $L_i = \max(\bar Y_i - Y_i, 0)$, with gains counted as zero. The budget of the cell-year is split equally among the households on the amount basis of the programme:

$$v_i = \frac{1}{s_i^{\text{share}}}\ \frac{\lambda\ \sum_{l \in c}\omega_l\ L_l}{\sum_{l \in c}\omega_l / s_l^{\text{share}}} \qquad \text{(4.1)}$$

where the sums are over the paid households of the cell-year and $v_i$ is the daily gain of household $i$. The cost of the cell-year is then $\lambda$ times its modelled loss, in annual terms.

An optional **annual cap** limits the total cost of a year. If transfers in a year would cost more than the cap net of administration, every payment of that year is scaled down in the same proportion:

$$\phi_r = \min\Big(1,\ \frac{\text{cap}\ (1 - a_{\text{adm}})}{C_r^{\text{transfer}}}\Big), \qquad v_i \leftarrow \phi_r\ v_i \qquad \text{(4.2)}$$

with $C_r^{\text{transfer}}$ the transfer cost of the year (Eq. (4.1) in [42_social_protection](42_social_protection.md)).

### 5. Timing

**Ex post.** A delay of $w$ weeks at a loss of $\ell$ per cent of effectiveness per week reduces the welfare effect of every payment to the factor $d = \max(0, 1 - w\ell/100)$. It reduces welfare only. Cost does not change.

**Anticipatory.** The programme pays on a forecast of the trigger. In a cell-year in which the realised trigger passes (an event), the forecast fires with probability POD, the probability of detection. In a cell-year without an event, it fires with probability FAR, the false-alarm rate:

$$\Pr(\text{forecast fires}) = \begin{cases} \text{POD} & F_{c,r} = 1 \\\\ \text{FAR} & F_{c,r} = 0 \end{cases} \qquad \text{(5.1)}$$

The draws are seeded and keyed by the unit at which the trigger is read: the survey cell, the administrative area, the whole country for a national impact trigger, or the year for a national gate. A payment made before an event that occurs (a hit) has a welfare effect multiplied by $m$, the effectiveness multiplier. A payment made with no event (a false alarm) has a multiplier of 1. Cost is never multiplied:

$$\mu_i = \begin{cases} m & \text{hit} \\\\ 1 & \text{false alarm} \\\\ d & \text{ex post} \end{cases}, \qquad \text{welfare gain} = \text{transfer} \times \mu_i \qquad \text{(5.2)}$$

### 6. Outputs

For each scenario, over all climate models and years:

- **Activation.** The share of model-years in which any household is paid.
- **Annual cost.** The mean, median and coefficient of variation of the total cost (transfers plus administration) of a year, and the 1-in-20 cost, the 95th percentile of annual cost, shown if there are at least 20 model-years.
- **Basis risk.** A cell-year has a **loss event** if the mean modelled change in welfare of its households, relative to their typical level, is at or below $-\vartheta$ per cent, with $\vartheta$ the loss-event share (default 10):

$$\text{event}_{c,r} = \mathbf{1}\big[\bar\Delta_{c,r} \le -\vartheta/100\big], \qquad \bar\Delta_{c,r} = \frac{\sum_{i \in c}\omega_i\ (Y_i/\bar Y_i - 1)}{\sum_{i \in c}\omega_i} \qquad \text{(6.1)}$$

A cell-year is paid if any of its households is in the final scope. With $\pi$ the population in each kind of cell-year (paid or not, event or not), the false-positive rate is the population of paid cell-years without an event over the population of cell-years without an event, and the false-negative rate is the population of unpaid cell-years with an event over that of cell-years with an event:

$$\text{FPR} = \frac{\pi_{\text{paid, no event}}}{\pi_{\text{paid, no event}} + \pi_{\text{unpaid, no event}}}, \qquad \text{FNR} = \frac{\pi_{\text{unpaid, event}}}{\pi_{\text{unpaid, event}} + \pi_{\text{paid, event}}} \qquad \text{(6.2)}$$

The loss event only scores the programme. It changes no payment and no welfare result, so the share can be changed after a run.

- **Leakage.** The share of spending that goes to cells without a loss event.
- **Share of loss offset.** Total payments over total modelled loss, with the same weights, in welfare units.
- **Cap.** The share of model-years in which the annual cap binds.
- **Coverage and adequacy of the affected poor.** Over household-years with a loss event for households poor at baseline: the share that were paid, and the payments as a share of the modelled loss.
- **Anticipatory design.** The share of cost that is paid before no event, and the break-even multiplier, the value of $m$ at which the welfare effect of the payments equals what the same trigger, scope and budget rule pays ex post:

$$m^{*} = \max\Big(\frac{V^{\text{ex post}} - V^{\text{false}}}{V^{\text{hit}}},\ 0\Big) \qquad \text{(6.3)}$$

where $V^{\text{hit}}$ and $V^{\text{false}}$ are the weighted values of payments made before an event and with none, and $V^{\text{ex post}}$ is the weighted value that the ex-post design pays after its delay. The app also reports the multiplier at which the effect per unit of spending matches.
- **Climate-adjusted cost.** The change in activation and in mean cost of each climate scenario against the historical record.

## Interpretation

- Because the thresholds are fixed on the historical record, a scenario shows how the programme would respond to a changed climate. A rise in activation or in cost is a rise in the bill for a rule that was set today.
- A high false-positive rate means spending in places and years without a modelled loss. A high false-negative rate means losses that the trigger misses. Their balance depends on the trigger, the threshold and the scope.
- The loss event and the modelled loss are predictions of the model. They are not observed losses, and they inherit its assumptions ([40_policy_framework](40_policy_framework.md)).
- A trigger on an impact metric reads the model's own prediction. It is therefore a design in which the programme knows the modelled loss, with no information lag.

## Assumptions

- **A1. Thresholds fixed at the historical record.** The rule does not adapt to the climate scenario.
- **A2. A sufficient historical record.** A return-period trigger rests on the historical years of each cell. A 1-in-20 level from 30 years rests on very few years.
- **A3. The model predicts losses.** Modelled loss, the loss event and the predicted-welfare layer use the central predictions of the model, without residuals.
- **A4. Perfect delivery within scope.** Everyone in scope receives the payment in full, subject to the targeting errors and the dynamic-targeting errors entered by the user.
- **A5. Forecast skill is an input.** POD, FAR and the multiplier are entered by the user and are not estimated.

## Limitations and what is not modelled

- Delays in payment other than the single effectiveness factor, and the cost of financing the programme.
- Basis risk with respect to observed losses. Only modelled loss is used.
- The response of rank-based repositioning in the quantile model to the shock payment: the repositioning effect is computed from the static transfer only, not from the payment made in a year ([44_decomposition](44_decomposition.md)).
- Changes in household behaviour from an expectation of payment.
- Differences among climate models in forecast skill.
- Variation between random draws. Targeting errors, forecast hits and false alarms, and the errors of the predicted-welfare layer are drawn once per run from the run seed. The bands of Step 3 do not include this variation. On BFA (SSP3-7.0 2025 to 2035, a cash transfer of 60 per person on a 1-in-5 return-period trigger, targeting the poorest 30 per cent, 20 seeds), the mean annual cost and the average effect on mean welfare varied by about 1.1 per cent between seeds (standard deviation of the cost 0.47 million on 42.3 million), the effect on the poverty rate by about 17 per cent of its small value (-0.0003), and the activation frequency not at all. The forecast and predicted-welfare layers were not switched on in that run, so their share is not measured.

## In the app

- Step 3 > Social protection > Programme type: choose a shock-responsive programme. Trigger settings set the weather variable or impact metric, the threshold or return period, the scope, layers, budget rule, cap, and timing.
- Step 3 > Social protection (preview card): expected activation and annual cost on the historical record before the run.
- Step 3 > Diagnostics and Cost-effectiveness: the run outputs of Section 6.

User guide: [Shock-responsive SP](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#shock-responsive-sp-future-release).

## References

None beyond [40_policy_framework](40_policy_framework.md). Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Checks of a specification | Section 1 | `R/fct_sp_shock.R` `.sp_shock_problem()`, `.sp_timing_problem()`, `.sp_dyn_problem()` |
| Thresholds from the historical record | (1.1) | `R/fct_sp_shock.R` `sp_trigger_thresholds()`, `.sp_group_quantile()` |
| Exceedance of the trigger | (1.2) | `R/fct_sp_shock.R` `.sp_trigger_exceeds()` |
| Impact metrics | Section 1 | `R/fct_sp_shock.R` `.sp_impact_plan()`, `.sp_impact_column()`, `sp_shock_reference()` |
| Response check | Section 1 | `R/fct_sp_shock.R` `sp_response_check()` |
| Payout scope and national gate | (2.1) | `R/fct_sp_shock.R` `.sp_trigger_scope()`, `sp_trigger_state()` |
| Dynamic targeting layers | (3.1) | `R/fct_sp_shock.R` `.sp_dyn_plan()`, `.sp_dyn_scope()`, `.sp_trigger_severity()` |
| Fixed amount | Section 4 | `R/fct_sp_shock.R` `.sp_dynamic_per_household()`, `sp_shock_plan()` |
| Budget linked to loss | (4.1) | `R/fct_sp_shock.R` `.sp_shock_loss_share_transfer()` |
| Annual cap | (4.2) | `R/fct_sp_shock.R` `.sp_shock_apply_cap()` |
| Timing, forecast | (5.1), (5.2) | `R/fct_sp_shock.R` `.sp_timing_plan()`, `.sp_forecast_fire()`, `.sp_timing_effect()` |
| Transfer and state of one pipeline | Section 4 | `R/fct_sp_shock.R` `sp_shock_pipeline_state()`, `sp_shock_pipeline_transfer()` |
| Welfare effect of the dynamic transfer | (5.2) | `R/fct_sp_shock.R` `sp_dynamic_effect()`; `R/fct_policy_metric_decompose.R` `.policy_annual_channel_block()` |
| Annual cost and activation | Section 6 | `R/fct_sp_shock.R` `sp_shock_annual()` |
| Basis risk and rescoring | (6.1), (6.2) | `R/fct_sp_shock.R` `.sp_shock_basis()`, `sp_shock_pipeline_rows()`, `sp_shock_rescore()` |
| Summary across scenarios | Section 6 | `R/fct_sp_shock.R` `sp_shock_summary()`, `sp_shock_climate_cost()` |
| Break-even multiplier | (6.3) | `R/fct_sp_shock.R` `sp_shock_summary()` |
| Coverage and adequacy of the affected | Section 6 | `R/fct_sp_shock.R` `sp_shock_reach()` |
| Preview before the run | Setup | `R/fct_sp_shock.R` `sp_shock_preview()` |
| Eligibility written for the programme | Setup | `R/fct_policy_sim.R` `apply_policy_to_svy()` |
