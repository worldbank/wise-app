# Seasonal forecast: remaining work

Updated 2026-11-04. Branch `seasonal-forecast`, not yet merged into `dev`. This file holds the current state, the decisions to keep and what remains. It replaces the earlier plan, `seasonal_forecast_review.md` and `seasonal_forecast_step3_design.md`. Their history is in git: `git show 94020d7:roadmap/seasonal_forecast.md` (or the other file names).

The method is in `docs/34_seasonal_forecast.md`, and shock transfers on a forecast in `docs/43_shock_responsive_sp.md`, Section 7. The data pipeline is in the sibling repo `wise-app-data` (`dev/forecast_plan.md`, issue #83).

## State

Built and committed:

- **Step 2.** Reader for the draft-2 schema, one weather state per member, same-window reference years, member placement and skill flags.
- **Results.** In Steps 2 and 3 each chart carries all series, ordered Forecast, Historical (Nov - Jan), Historical (annual), climate scenarios. Headline cards stay in two groups.
- **Step 3.** All levers and regular transfers run on members and reference years. Shock-responsive transfers run in the first version below.
- **Batch.** `sim.forecast`, the `forecast` table, and the `placement`, `skill`, `season`, `policy_effect` and `shock_window` summary sections. The `shock_window` rows run end to end in `test-batch-pipeline.R` (fixture, trigger of 0 so every member pays; partial triggering is covered by unit tests only).
- **Run click fixed.** The Step 2 and Step 3 Run button is re-rendered after each run, which reset its click count, so a repeated click produced an identical event and was dropped. Manual events now carry a sequence number (`mod_2_01_weathersim.R`, `mod_3_scenario.R`). Verified on BFA: 4 of 4 Step 2 and 3 of 3 Step 3 consecutive runs started.
- **Shock transfers, forecast off.** BFA batch tables (regular and return-period shock transfer) at `0d914ea` and at the current code are equal at `tolerance = 0` in all 11 tables (`decomposition` differs in row order only).
- **ENSO on the forecast.** Reference-year labels, outlook line on the placement card, exports and batch tables; open items in `roadmap/enso.md`, Still open.
- **Shock card on BFA.** Seen in the browser: 64% of the population in triggered locations for the mean member (33% in a historical year), cost of the window $2.44M ($0.25M to $3.29M). The maximum matches the annual cost in a paying year ($3.3M, 3.3M households at $1). Not separated: households against people in the 64%.

Checked in the running app on BFA (shock card and annual cost table included, 2026-11-04), run 2026-10, November to January, with SSP3-7.0 and the default model. MWI has had the Step 2 ENSO elements checked in the browser and a Steps 1 to 3 parity run (`dev/parity_enso.R --forecast`), which is not a review of its results. The full test suite fails only on `test-deploy-contract.R:76`, which is expected until the manifest is regenerated.

## Decisions to keep

- **Comparator.** The forecast compares with Historical for the same months, not with Historical (annual) or the climate scenarios. Row order and notes steer the reader to that comparison.
- **Annual Historical.** "Annual" means each household in its interview month, not twelve months.
- **The gap between the two Historical series** is a weather effect only, because `int_month` keeps its survey value as a fixed effect. Do not call it full seasonality.
- **Difference views.** Each Historical series is its own baseline, so both sit at zero and the gap is not shown.
- **Member spread** is not a calibrated probability. Shares of members are indicators. There is no return period for the ensemble mean.
- **Forecast values** are published already adjusted; the app never adjusts them again. There is no gap filling.
- **Shock transfers on a forecast.** A member's payment means "if this member's weather happened", not a payment on the forecast. The aim is consistency with the annual case, sharing code and adjusting only for the window.
  - First version: a weather trigger with a value or a return period from the reference years, one trigger per survey round and location for the whole window, paid once, ex post, local, on the `/365` basis.
  - Rejected with a forecast (`.sp_forecast_shock_problem()`): impact triggers, national gates, loss-share budgets, dynamic targeting and anticipatory payments.
  - Payout figures stay out of the annual cost, reach and basis-risk tables.
- **Forecast-only runs** still show Historical (annual) in charts and tables.
- **Working rules for this branch.** Regenerate `manifest.json` only as the last step (item 5) before the PR. One PR into `dev`, opened only after the forecast is tested with real data.

## Before the PR into `dev`, in order

1. **Two defects found while extending the smoke, to check by hand.** The smoke itself stays on the annual path: it runs in about 2 minutes, outside `devtools::test()`, and now covers ENSO. A forecast run is not added to it, because forecast screens need real data and are checked with `dev/ui_drive.R`.
   - Switching from `tx` to `t` after a full `tx` pipeline and model fit failed at "Weather variable(s) not found in data: t". Setting `t` on a fresh page works. Cause not found (suspect the selector or weather data not reloading after a fit).
   - With the projections flyout open, axe reports `target-size` (serious) on the period checkboxes (`input[value="2025-2035"]` and others).
2. **Config export and import replay** with real forecast data. The restore order of the start radio, which the server re-renders, is untested.
3. **Real-data coverage not yet checked.**
   - Other countries: 33 are published (COL, DOM, LKA and TJK added 2026-11-05, with `r` at a lowered recent-overlap share of 0.95), and only BFA has been reviewed. MWI has run, unreviewed.
   - 6-month windows. The Continuous form has run in `dev/parity_enso.R --forecast` (BFA, MWI), unreviewed.
   - Levers other than social protection with a forecast.
   - Diagnostics and Decomposition tabs with a shock transfer on a forecast.
   - Pilot parity across engines.
   - The ENSO browser checks not yet run (`roadmap/enso.md`, Still open).
4. **Screen-reader check** of the month strip. Arrow keys and focus order are already checked.
5. **Final gates.** Refresh `verified_against` in the methods pages not touched by the ENSO work, then run the full suite, `Rscript dev/docs_check.R` and `Rscript dev/agents_check.R`. Regenerate `manifest.json` last with `Rscript dev/00_make_manifest.R`, then open the PR.

## After the PR

- **Production runs from November 2026.** Status `published` and `experimental` false, so they will show on Posit Connect once this branch is deployed; `schema_version` stays `draft-2`. Skill and climatology files are named per run, through the manifest's `skill_file`. Skill tables add a `window` column (1, 3 or 6); October runs keep the old table and read as single months. The app reads both. The placement card adds the median member against the last 10 reference years.
- **Scientific usefulness (`wise-app-data` gates).** Record results including no-skill cases, then decide to continue, restrict or stop. Skill flags decide what the app shows. Production promotion is a separate approval.
- **Data pipeline items that touch the app.** The November initialization.
- **App hand-off items from `wise-app-data`, to confirm.** Check that the survey's cells are a subset of the run's cells, and warn rather than fail if the historical file changed since the run.
- **Climate scenarios for the target months.** A new Step 2 output, in protected numerics, needing a Decision log entry.
- **Shock transfer extensions.** Any of the rejected designs above, if a user need appears.
- **Refactor.** A `kind` field on scenarios and tables instead of label parsing. Shared weather helpers between `get_weather()` and `.get_forecast_weather()`, needing parity runs on all engines. `get_weather()` also calls `.get_forecast_weather()` with `weather_consumer = NULL`, which bypasses member streaming; this is harmless at current sizes.
- **Benchmark.** `dev/bench/bench_step2.R` has no forecast option, so the removal of the redundant forecast aggregation is unmeasured. Add a forecast workload before making any speed claim.
- **Hindcast comparator.** Only if placement turns out biased.
- **Subseasonal forecasts (optional, after the seasonal pilot).** ECMWF extended range for a one-month target, with a "Forecast type" toggle at the top of the flyout. It would add daily-based variables, but skill beyond about week two is low and it needs separate data work. Runs already carry `product` and `lead_unit`.

## Not planned

Multi-model weighting (proposed in `wise-app-data` but not approved), daily extremes from the seasonal product, soil moisture and SPEI from forecasts, and probabilistic calibration beyond the published adjustment.
