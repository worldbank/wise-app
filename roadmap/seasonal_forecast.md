# Seasonal forecast: remaining work

Updated 2026-11-04. Branch `seasonal-forecast`, not yet merged into `dev`. This file holds the current state, the decisions to keep and what remains. It replaces the earlier plan, `seasonal_forecast_review.md` and `seasonal_forecast_step3_design.md`. Their history is in git: `git show 94020d7:roadmap/seasonal_forecast.md` (or the other file names).

The method is in `docs/34_seasonal_forecast.md`, and shock transfers on a forecast in `docs/43_shock_responsive_sp.md`, Section 7. The data pipeline is in the sibling repo `wise-app-data` (`dev/forecast_plan.md`, issue #83).

## State

Built and committed:

- **Step 2.** Reader for the draft-2 schema, one weather state per member, same-window reference years, member placement and skill flags.
- **Results.** In Steps 2 and 3 each chart carries all series, ordered Forecast, Historical (Nov - Jan), Historical (annual), climate scenarios. Headline cards stay in two groups.
- **Step 3.** All levers and regular transfers run on members and reference years. Shock-responsive transfers run in all designs (see "Full shock transfers on a forecast").
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
  - First version: a weather trigger with a value or a return period from the reference years, one trigger per survey round and location for the whole window, paid once, on the `/365` basis. Ex post, local, as a first version; see the extensions below.
  - Extended on 2026-11-09 (see "Full shock transfers on a forecast"): impact triggers, national gates, loss-share budgets, dynamic targeting and anticipatory payments on the ensemble now run on a forecast.
  - Payout figures stay out of the annual cost, reach and basis-risk tables.
- **Forecast-only runs** still show Historical (annual) in charts and tables.
- **Working rules for this branch.** Regenerate `manifest.json` only as the last step (item 5) before the PR. One PR into `dev`, opened only after the forecast is tested with real data.

## Full shock transfers on a forecast: decisions and progress

Decided 2026-11-09. This brings the "Shock transfer extensions" item forward, before the PR. Order of work: gate, window reference level, targeting layers, impact trigger and loss budget, outputs, anticipatory. Each step ships with tests and a Section 7 update in `docs/43_shock_responsive_sp.md`. The forecast-off equality run on BFA is not needed, because no forecast release exists yet (decided 2026-11-09). New window numbers go in the Decision log with BFA headline figures before the PR.

- **D1. Window reference level.** A household's typical welfare for a window is its mean central prediction over the same-window reference years. A member's loss is its window prediction against that mean. It serves the impact trigger, the loss-linked budget, the predicted-welfare layer and basis risk. A 1-in-N trigger is capped by the number of reference years.
- **D2. National gate.** Share of population in triggered locations, read per member and per reference year, with the annual rule `rho >= k`.
- **D3. Dynamic targeting.** Worst-affected locations use the standard deviation of the window-mean trigger over the reference years, with a minimum of 10 reference years (otherwise the layer is rejected with a message). The predicted-welfare layer uses D1.
- **D4. Impact trigger and loss-linked budget.** Both use D1. The loss budget is scaled by L/12 to give the window's cost. Impact thresholds come from reference-year losses, with the annual small-unit and no-adverse-tail rules.
- **D5. Outputs.** Leakage, false-positive and false-negative rates, share of loss offset and adequacy are computed for a window, in a separate window table, labelled as indicators. They stay out of the annual tables.
- **D6. Anticipatory.** Ensemble decision rule: pay a location if at least p% of members trigger it; each member is then the realised outcome, so hits and false alarms are counted across members. Multiplier m and the ex-post benchmark m* still apply. Rates reflect the uncalibrated spread, so they are indicators, not skill. Done last.

Progress:

- [x] D2 gate (2026-11-09). Restriction removed in `.sp_forecast_shock_problem()`; each pipeline has one `sim_year`, so `.sp_trigger_scope()` already reads the share per member and reference year. Unit test added in `test-sp-shock-correction.R` (passes). Not yet run: forecast-off BFA equality, `dev/ui_drive.R` check, `verified_against` refresh.
- [x] D1 reference level (2026-11-09). `sp_shock_window_plan()` pools the reference-year predictions into `plan$reference`; `sp_shock_pipeline_rows()` scores one cell per survey round and location (`.sp_window_cell()`). Window cell and reach data go to `shock_forecast$cells` and `$reach`, out of the annual rescoring and reach tables. Nothing new is shown yet (D5). Tests added; `fct_policy_sim`, `sp-shock`, `step3`, `fct_forecast`, batch pipeline pass.
- [x] D3 targeting (2026-11-09). Restriction removed. `.sp_dyn_scope()` ranks one cell per survey round and location for a window and averages a household's level over its months for the welfare layer. `SP_WINDOW_MIN_REFERENCE_YEARS` (10) refuses worst-affected locations with fewer same-window years. Tests added.
- [x] D4 impact trigger and loss budget (2026-11-09). `sp_shock_window_plan()` pools the reference years as one historical pipeline (`.window_unit`), so the impact column and thresholds come from the annual code; `sp_shock_plan()` takes a `record_fn` to reduce the exposure to one record per cell and year after the impact column is attached. The loss budget uses one cell per survey round and location and is multiplied by L/12. Only anticipatory payments are still rejected. Not yet seen with real data: impact thresholds with the real number of reference years, the L/12 cost against the fixed-amount cost.
- [x] D5 outputs (2026-11-09), except coverage and adequacy of the affected poor. `sp_shock_window_summary()` adds leakage, false-positive and false-negative rates and loss offset for members and reference years; they appear in a card in Step 3 and in the `shock_window` batch rows. The reach data is stored in `shock_forecast$reach` but not shown (needs a poverty line; the annual table uses `sp_shock_reach()` with the survey frame). Open: show coverage and adequacy, if wanted.
- [x] D6 anticipatory (2026-11-09). `.sp_window_ensemble()` gives the payment decision (`plan$ensemble`: share of members passing the trigger per survey round and location, paid at `forecast_member_share_pct`, default 50); every member and reference year takes it as given and scores it with its own weather. The historical years use the same decision (an information indicator, not a climatological rule). A new field `forecast_member_share_pct` runs through input, defaults, batch ranges and the Step 3 UI. `.sp_forecast_shock_problem()` is removed: no design is rejected on a forecast now.

Browser check on BFA (2026-11-09, run Dec 2026 to Feb 2027, 51 members, 30 reference years, linear model, universal $1 transfer): no JS or output errors in 4 consecutive Step 3 runs. Seen: national gate (49% of members paid, cost $0 to $3.3M), anticipatory on the ensemble (at 50% of members nobody passes; at 10% every member pays, cost paid before no event 18% for members against 87% for historical years, break-even multiplier 2.43), ex post with worst-affected locations and a loss-linked budget (cost $0.9M to $17.7M). Not checked in the browser: the impact trigger, the predicted-welfare layer, return-period thresholds with fewer than 10 years, axe on the new slider, other countries. Not reviewed: whether the loss-linked cost scale (L/12) looks right against the fixed-amount cost.

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
- **Refactor.** A `kind` field on scenarios and tables instead of label parsing. Shared weather helpers between `get_weather()` and `.get_forecast_weather()`, needing parity runs on all engines. `get_weather()` also calls `.get_forecast_weather()` with `weather_consumer = NULL`, which bypasses member streaming; this is harmless at current sizes.
- **Benchmark.** `dev/bench/bench_step2.R` has no forecast option, so the removal of the redundant forecast aggregation is unmeasured. Add a forecast workload before making any speed claim.
- **Hindcast comparator.** Only if placement turns out biased.
- **Subseasonal forecasts (optional, after the seasonal pilot).** ECMWF extended range for a one-month target, with a "Forecast type" toggle at the top of the flyout. It would add daily-based variables, but skill beyond about week two is low and it needs separate data work. Runs already carry `product` and `lead_unit`.

## Not planned

Multi-model weighting (proposed in `wise-app-data` but not approved), daily extremes from the seasonal product, soil moisture and SPEI from forecasts, and probabilistic calibration beyond the published adjustment.
