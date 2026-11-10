# Model specification options

Status: proposal, 2026-11-09. Issues: [#62](https://github.com/worldbank/wise-app/issues/62) (more interaction variables), [#48](https://github.com/worldbank/wise-app/issues/48) (interact a group of fixed effects), [#55](https://github.com/worldbank/wise-app/issues/55) (lagged weather), [#54](https://github.com/worldbank/wise-app/issues/54) (displaced weather), [#57](https://github.com/worldbank/wise-app/issues/57) (crop season reference period). All extend the Step 1 specification (`docs/20_model_specification.md`, `docs/12_weather_measures.md`) and flow into Steps 2 and 3 through the weather regressors and the factor loading.

## Current limits

- Interactions: only non-numeric moderators are offered, pairwise with each weather term, set in `R/mod_1_06_model.R` (`interaction_mode = "pairwise"`).
- Weather window: a month range before the interview (`k = a..b`), one window per variable, same in every location. Crop calendars are not used (`docs/12_weather_measures.md`, limitations).
- Weather is merged at the interview hexagon only.

## Proposed changes

1. **Interactions (#62).** (a) Allow a numeric moderator by binning it into quantile groups at selection time, using the same bin machinery as weather bins, so Steps 2 and 3 see a factor. (b) Allow several moderators at once. Before enabling, check three downstream places: the factor loading and delta-method gradients (`docs/33_uncertainty.md`), the Step 3 decomposition into main and resilience effects (`docs/44_decomposition.md`), and policy levers that share a variable with an interaction.
2. **Fixed-effect interactions (#48).** The issue has no text. Proposal: offer "fixed effect by moderator" (for example region by year) as an advanced option, passed to the `fixest` formula. Ask the author for the use case first; it changes the absorbed dimensions and the Step 2 prediction path.
3. **Lags (#55).** Smallest design: a second window per weather variable, labelled "previous year", that reuses the month-offset logic with an offset of 12 months. The net effect is the sum of the terms; the delta method already handles a linear combination. Leads for placebo tests are the same code with a negative offset and are shown in the model card only, never used in simulation. Forecast runs need every lag month inside the run's context or forecast months (`docs/34_seasonal_forecast.md`); a previous-year lag will usually fail that check, so the option must be disabled there with a message.
4. **Displaced weather (#54).** Use the H3 parent lookup already in `.h3_resolution()` and the merge in `R/fct_data_weather.R`. Add a spatial scale setting per weather term: own hexagon, parent at resolution r (a coarser cell), or national mean as a diagnostic. Needs a decision on weighting (area or population), naming of the regressors, and how two scales of one variable enter together (the app currently builds no joint terms between variables).
5. **Crop season (#57).** Two routes. Simple: a user-chosen calendar window (start and end month, possibly spanning the year end), anchored to the survey year instead of the interview month. Full: a per-location season from a crop calendar layer. See `roadmap/hazard_data.md` for the data.

## Upstream data

- Crop calendar (for example a global crop calendar by admin unit or a 0.5 degree grid) mapped to the H3 level of the weather file, needed only for the full route in item 5.
- No new weather columns for items 1 to 4: lags and displacement read the existing monthly H3 weather. Confirm the weather file keeps enough history before the first survey year for 12-month lags.

## Order

Interactions (1), then lags (3), then crop season simple route (5), then displacement (4). Item 2 waits for the author's answer.

## Checks

Each option moves model outputs by design, so skill `wise-numeric-change` applies to the first release of each. Default specifications must stay bit-identical.
