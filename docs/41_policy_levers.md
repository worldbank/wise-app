---
id: policy-levers
title: Policy levers: access, percent change, travel time and labour market
app_step: 3
depends_on: [notation, policy-framework, data]
symbols: [D, Delta]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#policy-levers
code: [R/fct_policy_registry.R, R/fct_policy_sim.R, R/mod_3_levers.R, R/fct_step3_input.R]
verified_against: 72a2fdb
---

# Policy levers: access, percent change, travel time and labour market

> A lever changes one policy variable of the baseline survey. The kind of change depends on the type of the variable: binary access moves a share of units, a numeric variable changes by a percentage, travel time is scaled or capped, and the labour-market levers shift the employment status and the sector of work. This page defines each change. The cash transfer is on [42_social_protection](42_social_protection.md).

## Setup

### Where the levers come from

Levers are read from the variable list of the data directory. A variable with a policy code is a lever, and an optional policy group places it in a panel of Step 3. The code identifies the lever everywhere in the app, so a renamed variable keeps working. The data page describes the variable list ([10_data](10_data.md)).

The type of the variable decides the control.

| Type of variable | Control | Change |
|---|---|---|
| Binary (access, ownership, completion) | Universal, or a percentage change in access | Section 1 |
| Numeric | Percentage change | Section 2 |
| Travel time to a health facility | Percentage change, or a cap | Section 3 |
| Employment status (employed, self-employed, unemployed) | Percentage-point change in employment | Section 4 |
| Sector of work (agriculture, industry, services) | Target shares of sectors | Section 5 |
| Any other type | No control; the variable is not changed | |

Only the travel-time lever and the two labour-market groups have behaviour that differs from their type. A new special behaviour is a change to the app.

The group of a lever decides the panel: Infrastructure, Digital inclusion, Education or Labour market. A lever of any other group, or with no group, goes to Other policies and runs together with the infrastructure scenario. A data directory with no policy codes gets the levers of the earlier release (electricity, water, sanitation, health access, internet, mobile phone, piped water, water and sanitation together, three levels of education completion, and the labour-market variables). Scenario keys and control names of earlier releases are translated to the current codes when a saved scenario is read.

### Derived variable

If the data directory does not publish the combined variable "improved water and sanitation", the app derives it from its two sources as a three-valued AND: it is 1 if both are 1, 0 if either is 0 (even when the other is missing), and missing otherwise. A published column is never overwritten.

### When a lever acts

A lever acts if three things hold: the variable is in the survey, the variable is in the Step 1 model, and the user moved the lever from its default. The test for "in the model" matches a variable to the names of the model's terms exactly and without regard to case, so one variable name never matches another that starts with the same letters. A term matches if the variable is one of its components, or the variable followed by one of its levels for a categorical variable.

## Method

Let $N_0$ and $N_1$ be the numbers of survey units with value 0 and 1 for a binary variable, not counting missing values. The binary access and employment levers are drawn by weight when the survey has non-constant weights: rows are taken in random order until the cumulative survey weight is closest to the weight the share asks for, so the weighted share moved matches the share entered to within one row's weight. Without usable weights the draw is by rows, with the counts below. The sector lever is weighted in the same way.

### 1. Binary access

The user sets either the universal option or a percentage $p$ with $-20 \le p \le 100$.

$$D_i^{\text{pol}} = \begin{cases} 1 & \text{universal, for every unit with a value} \\\\ \text{1 for } n_+ \text{ units drawn at random from those with } D_i = 0 & p > 0 \\\\ \text{0 for } n_- \text{ units drawn at random from those with } D_i = 1 & p < 0 \end{cases} \qquad \text{(1.1)}$$

with $n_+ = \text{round}(N_0\ p/100)$ and $n_- = \text{round}(N_1\ |p|/100)$ rows (with weights, rows whose weight is closest to $p/100$ of the weight of the group). A missing value stays missing. Units outside the affected group do not change. The draw uses the lever's own seeded stream ([40_policy_framework](40_policy_framework.md)).

### 2. Numeric variable

For a numeric variable the user enters a percentage change $p$ between $-100$ and $+100$:

$$D_i^{\text{pol}} = D_i\ \big(1 + p/100\big) \qquad \text{(2.1)}$$

Every unit changes by the same proportion. There is no random assignment.

### 3. Travel time to a health facility

The user chooses a percentage change or a cap.

$$D_i^{\text{pol}} = \begin{cases} D_i\ \big(1 + p/100\big) & \text{percentage change, } -100 \le p \le 20 \\\\ \min\big(D_i,\ c\big) & \text{cap of } c \text{ minutes, } 15 \le c \le 240 \end{cases} \qquad \text{(3.1)}$$

A cap leaves units already below the cap unchanged.

### 4. Employment status

The user enters a change $\delta$ in the employment rate, in percentage points, between $-20$ and $+20$. Let $N$ be the number of rows in the survey, $N_u$ the number of unemployed rows, $N_w$ the number of working rows and $N_s$ the number of self-employed rows. In the survey files self-employment is a subset of employment, so $N_w$ is the number of employed rows; in a file that keeps the two apart, $N_w$ is their sum. The lever needs the employed and unemployed variables in the model. The self-employment variable is optional and only splits the new jobs.

- **Positive $\delta$.** $n = \min\big(\text{round}(N\ \delta/100),\ N_u\big)$ unemployed rows are drawn at random and become employed. When the self-employment variable is in the model, a share $N_s/N_w$ of them also become self-employed, which keeps the current mix; without it, none is marked.
- **Negative $\delta$.** $n = \min\big(\text{round}(N\ |\delta|/100),\ N_w\big)$ rows are drawn at random from the working rows and become unemployed.

$$n = \min\Big(\text{round}\big(N\ |\delta|/100\big),\ \text{size of the pool the rows are drawn from}\Big) \qquad \text{(4.1)}$$

The change is a share of all rows of the survey (of the total survey weight, when the weights are not constant), so it is a change in percentage points of the employment rate.

### 5. Sector of work

The user sets target shares for industry and for services, as percentages of working units. Agriculture is the remainder, $100 - s_{\text{ind}} - s_{\text{ser}}$ and not below zero. The sliders start at the observed shares of the survey. A target that was not changed from the observed share is left unset and keeps the current size of its sector.

Let $N_w$ be the working population and $n_k$ the current size of sector $k$. Both are survey-weight sums when the survey has non-constant weights, the same weighted shares the sliders start from, and row counts otherwise. The target sizes are

$$n_{\text{ind}}^{*} = N_w \min(s_{\text{ind}}/100, 1), \quad n_{\text{ser}}^{*} = \min\big(N_w\ s_{\text{ser}}/100,\ N_w - n_{\text{ind}}^{*}\big), \quad n_{\text{agr}}^{*} = N_w - n_{\text{ind}}^{*} - n_{\text{ser}}^{*} \qquad \text{(5.1)}$$

With row counts the targets are rounded to whole rows. A sector with $n_k > n_k^{*}$ has a surplus and a sector with $n_k < n_k^{*}$ has a deficit. Workers move only from a sector with a surplus to a sector with a deficit, so no more workers move than the targets require. Sectors are processed in order: agriculture first, then industry, then services. Within a sector, the workers who move are drawn at random, in the same way as the weighted binary and employment draws: rows are taken until the cumulative weight is closest to the weight of the surplus, and the first of them fill the first deficit, so each achieved weighted share is within one row's weight of its target. Rows that do not work are not changed. A moved worker is set to exactly one sector.

## Interpretation

- A lever changes the survey variable. The effect on welfare is the fitted coefficient times that change ([40_policy_framework](40_policy_framework.md)). A lever with a large change in the survey but a small or absent coefficient has a small or zero effect.
- The labour-market levers are changes in composition of the file, not a model of how jobs are created. The employment lever moves rows between statuses. It does not alter earnings except through the coefficients. The sector variables are defined only for the employed, so a model that includes them is fitted on employed people and cannot also estimate employment status; the employment and sector levers therefore need separate models.
- A percentage of non-users is applied to the weighted group when the survey has non-constant weights, so the share of the population moved is the share entered. The Diagnostics tab reports the weighted share reached.

## Assumptions

- **A1. Random assignment.** The units that gain or lose access are drawn at random within the group that can change. Targeting by need or by place is not represented for these levers.
- **A2. The variable is measured as in the survey.** A binary access variable of the survey means the same thing after a change as before.
- **A3. Exact fit of the coefficient.** The policy value is within the range for which the coefficient was estimated ([40_policy_framework](40_policy_framework.md), A5).
- **A4. No linkage between levers.** Each lever is applied independently. A change in employment does not change a sector variable unless the sector lever is also moved, and a change in a lever does not change a variable that is derived from it.

## Limitations and what is not modelled

- Take-up, quality of service and the cost of any lever other than the cash transfer.
- Targeting of access by need, income or place.
- Interaction terms between two levers.
- Whether the change in a variable is feasible. A universal option sets all units to 1 whatever the real constraints.

## In the app

- Step 3 > Infrastructure, Digital inclusion, Education and Other policies: each lever has a Universal checkbox and a slider for the percentage change. The sliders run from $-20$ to $+100$ per cent for binary levers and from $-100$ to $+100$ per cent for numeric levers. Health access has a percentage change from $-100$ to $+20$ per cent or a cap of 15 to 240 minutes.
- Step 3 > Labour market: a slider for the change in employment (percentage points, $-20$ to $+20$) and two sliders for the sector shares of industry and services.
- A lever whose variable is not in the Step 1 model has no control. The panel lists the variables to add back. The Labour market panel also says which control is hidden: the sector sliders need all three of agriculture, industry and services in the model, and the note names the missing ones. A moved lever whose variables are not in the survey or the model is reported when the policy runs (employment needs employed and unemployed; the sector shares need employed and the three sectors), and in a batch run as a partial policy failure. The labour variables are not offered as covariates, because they are flagged as outcomes; add them to the model as moderators of the weather effect ([20_model_specification](20_model_specification.md)).

User guide: [Policy levers](https://github.com/worldbank/wise-app-docs/blob/main/step3.qmd#policy-levers).

## References

None beyond [40_policy_framework](40_policy_framework.md). Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Lever registry from the variable list | Setup | `R/fct_policy_registry.R` `policy_registry()`, `policy_behaviour()`, `policy_slot()` |
| Earlier lever table, special behaviours | Setup | `R/fct_policy_registry.R` `POLICY_FALLBACK`, `POLICY_SPECIAL_BEHAVIOURS`, `POLICY_SLOTS` |
| Earlier keys and control names | Setup | `R/fct_policy_registry.R` `policy_normalise_keys()`, `policy_normalise_stems()` |
| Derived water-and-sanitation variable | Setup | `R/fct_policy_registry.R` `POLICY_DERIVED` |
| Exact matching of a variable to model terms | Setup | `R/fct_policy_sim.R` `.policy_lever_terms()`, `.lever_in_model()` |
| Moved lever, scenario lists | Setup | `R/fct_step3_input.R` `wise_access_config()`, `wise_labor_config()`; `R/fct_policy_sim.R` `.access_cfg_moved_codes()` |
| Binary access | (1.1) | `R/fct_policy_sim.R` `.apply_binary_access()`, `.apply_access_levers()` |
| Numeric percentage change | (2.1) | `R/fct_policy_sim.R` `.apply_numeric_pct()` |
| Travel time | (3.1) | `R/fct_policy_sim.R` `.apply_health_travel()` |
| Employment status | (4.1) | `R/fct_policy_sim.R` `apply_policy_to_svy()` |
| Sector reallocation | (5.1) | `R/fct_policy_sim.R` `apply_policy_to_svy()`, `.labor_sector_shares()`, `.labor_working()` |
| Labour levers that cannot act | Setup | `R/fct_policy_sim.R` `.labor_levers_unavailable()`; `R/fct_step3_async.R` |
| Controls and ranges | In the app | `R/mod_3_levers.R` |
