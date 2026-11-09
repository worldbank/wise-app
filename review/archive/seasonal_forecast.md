# Seasonal forecast: state at archive

Archived 2026-11-09 from `roadmap/seasonal_forecast.md`. Branch `seasonal-forecast`, not yet merged into `dev`. The build is done. What remains before the PR into `dev` is checking, listed below, and was handed to a new session. Earlier history is in git: `git show 94020d7:roadmap/seasonal_forecast.md` (also `seasonal_forecast_review.md` and `seasonal_forecast_step3_design.md`).

The method is in `docs/34_seasonal_forecast.md`, and shock transfers on a forecast in `docs/43_shock_responsive_sp.md`, Section 7. The data pipeline is in the sibling repo `wise-app-data` (`dev/forecast_plan.md`, issue #83). The ENSO side is in `review/archive/enso.md`.

## State

Built and committed:

- **Step 2.** Reader for the draft-2 schema, one weather state per member, same-window reference years, member placement and skill flags.
- **Results.** In Steps 2 and 3 each chart carries all series, ordered Forecast, Historical (target months), Historical (annual), climate scenarios. Headline cards stay in two groups.
- **Step 3.** All levers and regular transfers run on members and reference years. Every shock-responsive design runs on a forecast window (below).
- **Batch.** `sim.forecast`, the `forecast` table, and the `placement`, `skill`, `season`, `policy_effect` and `shock_window` summary sections.
- **Run click fixed.** The Step 2 and Step 3 Run button is re-rendered after each run, which reset its click count, so a repeated click produced an identical event and was dropped. Manual events now carry a sequence number (`mod_2_01_weathersim.R`, `mod_3_scenario.R`).
- **ENSO on the forecast.** Reference-year labels, outlook line on the placement card, exports and batch tables (`review/archive/enso.md`).

### Shock-responsive transfers on a forecast (2026-11-09)

Every design runs on forecast members and same-window reference years: weather and impact triggers, the national gate, both targeting layers, fixed and loss-linked budgets, and ex-post and anticipatory timing. Method: `docs/43_shock_responsive_sp.md`, Section 7. Decisions:

- **Reference level.** A household's typical welfare for a window is its mean central prediction over the target months of all reference years (`sp_shock_window_plan()`, pooled as one historical pipeline). It serves the impact trigger, the loss-linked budget, the predicted-welfare layer and basis risk. A 1-in-N trigger needs at least N reference years.
- **National gate.** The population share in triggered locations is read per member and per reference year, with the annual rule.
- **Targeting layers.** Worst-affected locations rank one cell per survey round and location by the standard deviation of the window mean over the reference years, and need at least 10 of them (`SP_WINDOW_MIN_REFERENCE_YEARS`); otherwise the run is refused with a message. The predicted-welfare layer uses a household's mean level over its months.
- **Loss-linked budget.** One cell per survey round and location, multiplied by L/12 for a window of L months.
- **Anticipatory.** Ensemble decision rule (`.sp_window_ensemble()`): a location is paid when at least `forecast_member_share_pct` (default 50, new field) of members pass its trigger. Every member and reference year takes that decision as given and scores it with its own weather (hit or false alarm). Reference years use the same decision, so a lower false-alarm cost share among members than among reference years is an information indicator, not skill.
- **Outputs.** Leakage, false-positive and false-negative rates, loss offset, and for an anticipatory design the false-alarm cost share and break-even multiplier, pooled over members and over reference years, in a Step 3 card and the `shock_window` batch rows. They are indicators: the member spread is not calibrated. They stay out of the annual cost, reach and basis-risk tables. Coverage and adequacy of the affected poor are stored (`shock_forecast$reach`) but not shown, because they need a poverty line.
- `.sp_forecast_shock_problem()` is gone: no design is rejected on a forecast. A forecast-off equality run on BFA was not made, because no forecast release exists yet.

Seen in the browser on BFA (run Dec 2026 to Feb 2027, 51 members, 30 reference years, linear model, universal $1 transfer): no JS or output errors in 4 consecutive Step 3 runs. National gate: 49% of members paid, cost $0 to $3.3M. Anticipatory: at 50% of members nobody passes; at 10% every member pays, cost paid before no event 18% for members against 87% for reference years, break-even multiplier 2.43. Ex post with worst-affected locations and a loss-linked budget: cost $0.9M to $17.7M. Earlier, on run 2026-10: the shock card showed 64% of the population in triggered locations for the mean member (33% in a historical year).

The full test suite fails only on `test-deploy-contract.R:76`, which is expected until the manifest is regenerated.

## Decisions to keep

- **Comparator.** The forecast compares with Historical for the same months, not with Historical (annual) or the climate scenarios. Row order and notes steer the reader to that comparison.
- **Annual Historical.** "Annual" means each household in its interview month, not twelve months.
- **The gap between the two Historical series** is a weather effect only, because `int_month` keeps its survey value as a fixed effect. Do not call it full seasonality.
- **Difference views.** Each Historical series is its own baseline, so both sit at zero and the gap is not shown.
- **Member spread** is not a calibrated probability. Shares of members are indicators. There is no return period for the ensemble mean.
- **Forecast values** are published already adjusted; the app never adjusts them again. There is no gap filling.
- **Shock transfers on a forecast.** A member's payment means "if this member's weather happened", not a payment on the forecast, except for the anticipatory design above. Payout figures stay out of the annual cost, reach and basis-risk tables.
- **Forecast-only runs** still show Historical (annual) in charts and tables.
- **Working rules for this branch.** Regenerate `manifest.json` only as the last step before the PR. One PR into `dev`, opened only after the forecast is tested with real data.

## Before the PR into `dev`: checks handed to a new session

1. **Two defects found while extending the smoke, to check by hand.** The smoke stays on the annual path; forecast screens need real data and are checked with `dev/ui_drive.R`.
   - Switching from `tx` to `t` after a full `tx` pipeline and model fit failed at "Weather variable(s) not found in data: t". Setting `t` on a fresh page works. Cause not found (suspect the selector or weather data not reloading after a fit).
   - With the projections flyout open, axe reports `target-size` (serious) on the period checkboxes (`input[value="2025-2035"]` and others).
2. **Shock transfers in the browser, not yet seen:** the impact trigger, the predicted-welfare layer, fewer than 10 reference years, axe on the `forecast_member_share_pct` slider, and whether the loss-linked cost (L/12) looks right against a fixed amount.
3. **Config export and import replay** with real forecast data, including `forecast_member_share_pct`. The restore order of the start radio, which the server re-renders, is untested.
4. **Real-data coverage.**
   - Other countries: 33 are published (COL, DOM, LKA and TJK added 2026-11-05, with `r` at a lowered recent-overlap share of 0.95), and only BFA has been reviewed. MWI has run, unreviewed.
   - 6-month windows. The Continuous form has run in `dev/parity_enso.R --forecast` (BFA, MWI), unreviewed.
   - Levers other than social protection with a forecast.
   - Diagnostics and Decomposition tabs with a shock transfer on a forecast.
   - Pilot parity across engines.
5. **ENSO browser checks** (`review/archive/enso.md`).
6. **Screen-reader check** of the month strip. Arrow keys and focus order are already checked.
7. **Final gates.** Refresh `verified_against` in the methods pages not touched by the ENSO and shock work, then run the full suite, `Rscript dev/docs_check.R` and `Rscript dev/agents_check.R`. Regenerate `manifest.json` last with `Rscript dev/00_make_manifest.R`, then open the PR.

## After the PR

- **Production runs from November 2026.** Status `published` and `experimental` false, so they will show on Posit Connect once this branch is deployed; `schema_version` stays `draft-2`. Skill and climatology files are named per run, through the manifest's `skill_file`. Skill tables add a `window` column (1, 3 or 6); October runs keep the old table and read as single months. The app reads both. The placement card adds the median member against the last 10 reference years.
- **Scientific usefulness (`wise-app-data` gates).** Record results including no-skill cases, then decide to continue, restrict or stop. Skill flags decide what the app shows. Production promotion is a separate approval.
- **Data pipeline items that touch the app.** The November initialization.
- **App hand-off items from `wise-app-data`, to confirm.** Check that the survey's cells are a subset of the run's cells, and warn rather than fail if the historical file changed since the run.
- **Climate scenarios for the target months.** A new Step 2 output, in protected numerics, needing a Decision log entry.
- **Coverage and adequacy of the affected poor for a window,** if wanted (needs a poverty line).
- **Refactor.** A `kind` field on scenarios and tables instead of label parsing. Shared weather helpers between `get_weather()` and `.get_forecast_weather()`, needing parity runs on all engines. `get_weather()` also calls `.get_forecast_weather()` with `weather_consumer = NULL`, which bypasses member streaming; this is harmless at current sizes.
- **Benchmark.** `dev/bench/bench_step2.R` has no forecast option, so the removal of the redundant forecast aggregation is unmeasured. Add a forecast workload before making any speed claim.
- **Hindcast comparator.** Only if placement turns out biased.
- **Subseasonal forecasts (optional, after the seasonal pilot).** ECMWF extended range for a one-month target, with a "Forecast type" toggle at the top of the flyout. It would add daily-based variables, but skill beyond about week two is low and it needs separate data work. Runs already carry `product` and `lead_unit`.

## Not planned

Multi-model weighting (proposed in `wise-app-data` but not approved), daily extremes from the seasonal product, soil moisture and SPEI from forecasts, and probabilistic calibration beyond the published adjustment.
