# Step 3 (policy) with a seasonal forecast: design note

Date: 2026-11-02. Status: not started; scope decision pending (see "Options"). Companion to `roadmap/seasonal_forecast.md` (plan, item C) and `roadmap/seasonal_forecast_review.md`.

## What Step 3 does with a Step 2 scenario

For each Step 2 pipeline (Historical, each SSP model, and now each forecast member) Step 3 adds the policy's channel changes to the baseline predictions (`.apply_policy_annual_pipeline()` in `R/fct_policy_metric_decompose.R`, called from `R/fct_policy_sim.R`). It needs, per prediction row, an exposure map: which survey row it belongs to, the exact weather it was predicted with, and the simulation year. The policy then changes household characteristics (infrastructure, transfers, education and so on) and the model re-predicts or adds the channel.

## Why a forecast is blocked today

A forecast pipeline expands every household over the target months. Two things differ from the annual contract, and the exposure validator (`.validate_policy_exposure()`-style checks around `R/fct_policy_metric_decompose.R:120-205`) rejects both:

1. **Interview month versus weather month.** The validator compares the exposure table's `int_month` with the survey's `int_month` and also requires it to equal the month of the weather timestamp. For a forecast the survey month is the household's (a fixed effect) and the weather month is the target month. After the 2026-11-02 fix the join key is the weather month and the survey month is restored on the joined frame (`.int_month_svy`), so the two no longer agree by construction.
2. **Weights.** Predictions carry `weight / L` (L target months); the validator requires them to equal the baseline survey weights.

Also annual in nature: the shock-responsive transfer takes its trigger thresholds from the annual historical exposure (`sp_shock_plan()`), and the decomposition and metric tables are indexed by `sim_year` and model.

## What a policy result for a forecast would mean

The same estimand as Step 2, one policy more: for each member (and each reference year), predict every household in every target month with the policy applied, aggregate with `weight / L`, and compare with the same computation without the policy. Report the policy effect (paired difference) under the forecast and under the same-window reference, so the user sees whether the policy helps more in the forecast window than in a typical year. Static levers act identically in every target month; there is no timing within the window.

## Work, by option

Common to all options that run policies on a forecast:

- Exposure schema: record the household's interview month (`int_month_svy`) and a weight scale (`1 / L`) in the exposure table and in the run context; validator compares survey identity on the interview month and weights on the scaled weight; keep the weather-anchor check on the target month. Version the exposure schema.
- Apply the policy to member pipelines and to `reference_pipelines`; carry `forecast`, `training_months`, `skill` through `saved_scenarios_new`.
- Step 3 results: scenario names, palette (already handled), policy-effect view with placement; hide annual adverse-year and return-period views for forecast scenarios (as in Step 2).
- Batch: lift the rejection in `fct_batch_spec.R` and `fct_batch_targets.R`; policy arm of `annual` and `summary` for forecast scenarios; tables doc.
- Tests: exposure validator with forecast rows (accept) and with a tampered month or weight (reject); policy effect equals the direct difference of two runs; static-lever parity on a one-month window against a hand calculation; reference pipelines get the same policy.

Additional for shock-responsive transfers (option B): replace the annual historical trigger with a trigger on the target-window weather. The natural definition uses the same-window reference: a shock occurs when the target-window weather is beyond the reference year at return period N. Needs a new trigger plan, a per-member activation flag, and a decision on cost accounting (a transfer paid once per window or per year).

## Options

| | Scope | Effort | Risk |
|---|---|---|---|
| A (recommended, after real-data acceptance) | Static levers, regular transfers. Shock-responsive stays blocked with a clear message. | Medium | Exposure contract is a protected area: tests above, parity run on BFA with the forecast off must be bit-identical. |
| B | A plus shock-responsive transfers triggered by the same-window reference. | Large | New trigger semantics and cost accounting; more to explain to users. |
| C | Keep Step 3 blocked; document it; revisit after the PR into `dev`. | None | Users must rerun Step 2 without the forecast to use Step 3 (current behaviour). |

Recommendation: C until the real-data acceptance in the plan (item A) passes, then A as a separate PR. B only if a user need appears for forecast-triggered social protection, which is the use case the shock-responsive program was built for, so ask the product owner before building it.
