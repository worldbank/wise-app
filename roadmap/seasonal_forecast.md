# Seasonal forecast scenario: roadmap

Status: Step 2 sidebar scaffold done (`R/utils_forecast_ui.R`, the "Seasonal forecast" flyout in `R/mod_2_01_weathersim.R`). It is not wired to data or to simulation runs. The data pipeline lives in `wise-app-data` (`dev/forecast_pipeline_plan.md`); this file covers the app side and the hand-off between the two.

## Design decisions made

- A forecast is one more weather state next to Historical and the SSPs: one dated target window by ensemble member (51 for SEAS5), not a historical year plus a delta. Everything after the weather step (predictors, model, residuals, metrics, Step 3 levers) is reused.
- Forecast can run in the same simulation as SSPs.
- The forecast is unavailable, with a stated reason, when the country has no forecast data or the fitted model uses a weather variable the forecast does not provide (currently anything other than `t`, `tn`, `tx`, `r`).
- Forecast has its own flyout. Simulation settings holds what applies to every scenario (survey, historical period, residuals, coefficient uncertainty). The historical period also anchors the forecast anomalies.
- The "Include seasonal forecast" checkbox defaults to off, because a run over 51 members adds run time.

## Open question: subseasonal forecasts

Offering a subseasonal product (ECMWF extended range, up to 46 days, issued twice weekly) for a one-month target fits the same flyout and the same downstream machinery. It is worth doing after the seasonal pipeline works, not in parallel.

For: it covers the next four to six weeks, where the seasonal monthly product is weakest; and the daily fields allow `tx35`, `tr`, `rx5day` and `r20`, which the monthly seasonal product cannot give, so fewer fitted models would be blocked.

Against: skill beyond about week two is low, so a one-month mean is a weak signal and the UI must say so. The data work is separate: different dataset, issue dates twice a week, reforecasts for calibration with fewer members and a different hindcast layout, and daily-to-monthly aggregation with partial-month handling.

If adopted, the UI change is small: a "Forecast type" toggle (Seasonal, Subseasonal) at the top of the flyout. Subseasonal fixes the window to one calendar month, the run select lists issue dates, and the strip shows only the month that fits inside the horizon. To keep that door open, forecast runs should carry a `product` field and a lead unit in the data contract and in `.step2_forecast_runs()` now, and the weather builder should key runs by product, run and member.

## Remaining work, in order

1. **Data contract and source.** Finish the `wise-app-data` pipeline (source probe, download, H3 mapping, matching hindcast climatologies, manifests, validation, publication) for one pilot country. Replace the placeholder in `.step2_forecast_runs()` with a read of the published run catalogue for the baseline country. Add `product` to the contract. Gate: two runs coexist and the newest complete run is discoverable.
2. **Backtest the anomaly adjustment** offline (in `wise-app-data`): raw versus anomaly-adjusted versus climatology, by season and lead, with years as the independent samples. Decide the dry-climatology policy for the rainfall ratio. Define which seasons and leads are shown as weak skill in the app, and the wording.
3. **Weather builder.** Add a forecast branch to `get_weather()` (`R/fct_get_weather.R`) that reads the pipeline's forecast weather. Since the 2026-10-29 revision of `wise-app-data/dev/forecast_pipeline_plan.md`, the pipeline publishes values already anchored to the ERA5-Land climate (fixed reference years), so the app does no hindcast arithmetic and the historical-period slider does not affect the forecast. Use observed months before the forecast and earlier forecast months for the lag windows (but see the plan's antecedent-month problem: historical weather currently ends in 2025). Preserve the Step 1 lag and aggregation definitions exactly. Record the latest observed month available at run time and block unsupported windows or apply an explicit, versioned gap policy. Output one weather state per member for the target window only.
4. **Derive the lag length from Step 1.** Replace `.STEP2_FORECAST_LAG` (placeholder of 2 months) with the longest lag the fitted weather variables reach back. Use it for the strip's lag months and for blocking windows whose observed months are not yet released. Also check each fitted variable against what the forecast provides, not only the variable name.
5. **Run integration.** Add a forecast scenario key beside `.step2_scenario_display_key()` and `.step2_scenario_labels()`. Include the forecast inputs and the run, member, target dates and data versions in the simulation signature so stale detection and cache keys cover them. Add the forecast to the worker payload and to `batch/` specs and tables. Aggregate within member before taking quantiles across members, and keep weather uncertainty separate from coefficient uncertainty. This is the point that makes the "Include seasonal forecast" checkbox take effect, and it needs a decision under the numeric-change rules (determinism tests, and a Decision log entry if any existing output moves).
6. **Results and Step 3.** Show the forecast in the Results legend and charts between Historical and the SSPs, with a band across members. Decide how Step 3 baselines and policies treat the forecast state (assumed: the same as an SSP state). Include the forecast in exports and in config import and export (the four `fc_*` inputs should restore, which needs a check with `update*Input`).
7. **Remove the scaffold switch.** Drop the `wiseapp.forecast_scaffold` option and its "Preview only" note once real data is wired, and decide whether the Seasonal forecast button is shown for countries without data or hidden.
8. **Documentation.** A methods page in `docs/` (equations, anomaly adjustment, lag stitching, assumptions, limitations) with `verified_against`, run through `Rscript dev/docs_check.R`. Update `ARCHITECTURE.md` for the new file and the forecast data contract, `DEPLOYMENT.md` for any new data path or variable, and `batch/docs/tables.md` for new table builders.
9. **Verification.** Tests for the weather builder (lead 1, year boundaries, leap-year February, member alignment, no historical-year replication), the run signature and the batch tables. Keyboard and screen-reader check of the month strip (arrow keys move the selection natively, but this has not been verified, nor the focus order inside the flyout). Extend `tests/e2e/smoke.R` with a forecast run on the fixture data. Regenerate `manifest.json` before any deploy.
10. **Subseasonal (optional, after 1 to 9).** Second data product and the "Forecast type" toggle described above.

## Not planned

Multi-model weighting, daily extremes from the seasonal product, soil moisture and SPEI from forecasts, and probabilistic calibration beyond the anomaly adjustment. These are listed as later extensions in `wise-app-data/dev/forecast_pipeline_plan.md`.
