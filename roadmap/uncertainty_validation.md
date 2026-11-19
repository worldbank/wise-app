# Uncertainty, climate perturbation and validation

Status: proposal, 2026-11-09. Issues: [#63](https://github.com/worldbank/wise-app/issues/63) (uncertainty in predictions), [#56](https://github.com/worldbank/wise-app/issues/56) (climate change perturbation method), [#38](https://github.com/worldbank/wise-app/issues/38) (out-of-sample validation). All three concern how far Step 2 numbers can be trusted. Methods: `docs/33_uncertainty.md`, `docs/31_climate_scenarios.md`.

## #63 Uncertainty

The issue lists the sources: model, parameter, measurement, residual and out-of-sample. The app covers coefficient uncertainty by Cholesky draws with delta-method bands, residual rules (original, resample), model spread across climate models, and diagnostics with support warnings. Gaps named in the issue:

1. **Standard errors.** Clustering is at the survey-location panel. Proposal: a sensitivity table in the model card with clustering at area-month, area and region, so the user sees how much bands move. Conley or Driscoll-Kraay errors need coordinates and a panel structure; consider after the table, only if the spread is large.
2. **Few clusters.** Where a country has fewer than about 30 clusters at the chosen level, warn, and offer a wild cluster bootstrap for the Step 1 table only.
3. **Separation in the UI.** Show weather, coefficient, residual and extrapolation uncertainty as separate stacked parts in the band legend and the export, instead of one band.
4. **Engine coverage.** Validate band coverage by simulation for each supported engine (linear, logistic, quantile): refit on resampled data, compare the share of true values inside the band with the nominal level. Put the script in `dev/` and report in `docs/33_uncertainty.md`.
5. **Design variance.** See `roadmap/estimation.md`.

## #56 Climate perturbation

The issue only says "discuss". Current method: climate-model weather for each scenario and period feeds the fitted response directly, with bias handling documented in `docs/31_climate_scenarios.md`. Options to compare, on one country first:

- Direct use of projected monthly values (current).
- Delta change: add the model's change from its own historical baseline to observed weather, which removes model bias and keeps observed variability.
- Quantile mapping of the projected distribution to observations.

Outputs that move need skill `wise-numeric-change`. Decide the default only after a BFA comparison of the three on headcount in 2050 under one scenario. Record the result in the Decision log.

## #38 Out-of-sample validation

Apply the pipeline to known events (Pakistan floods 2022, El Nino 2024) and compare with observed macro outcomes. Proposal:

1. **Hindcast mode.** Fit on surveys that predate the event, simulate the event year's weather, compare predicted welfare change with published poverty or consumption changes. A script in `dev/` first (like `dev/parity_enso.R`), an app view only later.
2. **Within-survey validation.** Cheaper and available now: leave-one-year-out or leave-one-region-out fits, comparing predicted and observed headcount. Report in the model card.
3. **Skill reporting.** The forecast pilot already reports skill flags (`R/fct_forecast_skill.R`); reuse the layout.

## Upstream data

- For #38: event surveys and external reference series (national poverty estimates, damage assessments) per case. Pakistan needs a pre-2022 survey with matching weather.
- For #56: climate-model baseline period (1991-2020) weather for every model, in the same H3 layout as the projections.
- For #63: none.

## Order

#63 items 1 and 3, then #38 item 2, then #56 comparison, then hindcasts.
