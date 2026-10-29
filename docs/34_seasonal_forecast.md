---
id: seasonal-forecast
title: Seasonal forecast scenario (design, not yet computed)
app_step: 2
depends_on: [notation, data, weather-measures, simulation]
symbols: [l, mu, m, v, s, W, x]
guide: https://github.com/worldbank/wise-app-docs
code: [R/utils_forecast_ui.R, R/mod_2_01_weathersim.R]
verified_against: d09a4ac
---

# Seasonal forecast scenario (design, not yet computed)

> **Status: design only.** The app shows the forecast controls, but no forecast data is published and no simulation run uses the forecast. This page records the decisions made so far so that the method can be reviewed before it is built. Equations and limitations will be completed and verified against the code when the forecast is wired in.

> A seasonal forecast is one more weather state, next to the historical record and the climate scenarios. It describes one dated target window, for example November to January, by the members of a forecast ensemble. The fitted model, the residual treatment and the metrics are the ones used for every other scenario.

## Setup

The forecast comes from a seasonal prediction system run once a month. Each run gives monthly values for the next six months for every **member** $m$ of an ensemble (51 members for ECMWF SEAS5). The pilot covers monthly mean temperature for one country. Symbols are in [00_notation](00_notation.md): $\ell$ location, $\mu$ calendar month, $v$ weather variable, $m$ member.

The question the scenario answers is conditional: what does the fitted model imply for the target window if weather in each location follows member $m$, holding the survey's other characteristics fixed? It is not a forecast of welfare or poverty.

## Method

### 1. Forecast weather in the app's units

The data pipeline, not the app, puts the forecast on the scale of the observed weather. For member $m$, location $\ell$, forecast run $r$ and valid month $t$:

$$\tilde x^{\ m}_{\ell t} = \bar x^{\text{obs}}_{\ell\mu(t)} + \left(x^{\ m}_{\ell t} - \bar x^{\text{fc}}_{\ell\mu(t)}\right) \qquad \text{(1.1)}$$

where $x^{\ m}_{\ell t}$ is the raw forecast, $\bar x^{\text{fc}}_{\ell\mu}$ is the mean of the forecast system's own past forecasts for the same run month, lead and calendar month, and $\bar x^{\text{obs}}_{\ell\mu}$ is the observed monthly mean over the same years. The adjustment removes the mean bias of the forecast system and keeps each member's departure from it. It does not correct the spread, reliability or skill of the forecast. Reference years are fixed in the pipeline, so the historical window chosen in Simulation settings does not change the forecast.

### 2. Predictors for the target window

For a target month $t$, each lagged predictor of the fitted model is built from the same window of months before $t$ as in estimation, with the same aggregation (see [12_weather_measures](12_weather_measures.md)). Months before the forecast starts are observed values. Months after it starts are the forecast values of the same member. The longest reach-back among the fitted predictors sets how many earlier months the strip in the app shows.

Observed weather ends before the most recent months. A target window is available only when every month its predictors need is either observed or forecast. The rule for the gap is not settled.

### 3. One state per member

Each member gives one complete weather state for the target window. Everything after the weather step runs as for a climate scenario. Results are first aggregated within a member and then summarised across members. The spread across members is weather uncertainty; it is kept apart from the uncertainty in the estimated coefficients.

## Interpretation

The band across members shows how much the forecast weather moves the model's outcome. It is not a calibrated probability. A forecast with no skill for the season and lead still produces a band, so the app must say where skill is weak.

## Assumptions

- **A1.** The additive adjustment (1.1) is enough to put the forecast on the scale of the observed weather. Amplitude is not corrected.
- **A2.** The fitted relationship between weather and the outcome holds for forecast weather as it does for observed weather.
- **A3.** Member order carries no meaning; members are equally weighted.

## Limitations and what is not modelled

- Only the variables the monthly product provides: mean, minimum and maximum temperature and rainfall. Daily extremes, soil moisture and drought indices are not available from it.
- One forecast system. No weighting or blending of systems.
- Skill is unproven for most seasons and leads. A backtest against held-out observations is planned before any season is shown without a warning.
- Welfare responses are conditional on the fitted model; no adaptation within the target window.

## In the app

- Step 2 > Seasonal forecast: include the forecast, choose the run, the length of the window (1, 3 or 6 months) and the start month on the strip. The forecast is unavailable, with a reason, when the country has no forecast or the fitted model uses a variable the forecast does not provide.

User guide: [wise-app-docs](https://github.com/worldbank/wise-app-docs).

## References

None yet. Entries will be added with the backtest. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Forecast controls, window and lag text | 2 | `R/utils_forecast_ui.R` `.step2_forecast_window()`, `.step2_forecast_lag_text()` |
| Reach-back of the fitted predictors | 2 | `R/utils_forecast_ui.R` `.step2_forecast_lag()` |
| Variables the forecast provides | 1 | `R/utils_forecast_ui.R` `.step2_forecast_unsupported()` |
| Forecast scenario name and run signature | 3 | `R/utils_forecast_ui.R` `.step2_forecast_display_key()`, `.step2_forecast_signature()` |
