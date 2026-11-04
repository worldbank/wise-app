---
id: seasonal-forecast
title: Seasonal forecast scenario (experimental pilot)
app_step: 2
depends_on: [notation, data, weather-measures, simulation]
symbols: [l, mu, m, v, s, W, x]
guide: https://github.com/worldbank/wise-app-docs
code: [R/utils_forecast_ui.R, R/mod_2_01_weathersim.R, R/fct_forecast_catalogue.R, R/fct_forecast_weather.R, R/fct_forecast_placement.R, R/fct_forecast_window.R, R/fct_forecast_skill.R, R/fct_run_simulation.R]
verified_against: 523a585
---

# Seasonal forecast scenario (experimental pilot)

> **Status: experimental local pilot.** BFA has two draft runs, May and October 2026, prepared for DEV testing. The app reads adjusted forecast weather from the local data root. Skill and scientific usefulness are not established. Draft runs are not offered on Posit Connect.  Step 3 applies static policies to forecast windows; a shock-responsive transfer is blocked with a forecast.

> A seasonal forecast is one more weather state, next to the historical record and the climate scenarios. It describes one dated target window, for example November to January, by the members of a forecast ensemble. The fitted model, the residual treatment and the metrics are the ones used for every other scenario.

## Setup

The forecast comes from a seasonal prediction system run once a month. Each run gives monthly values for the next six months for every **member** $m$ of an ensemble (51 members for ECMWF SEAS5). The pilot covers monthly mean temperature (`t`) and rainfall (`r`) for one country. Symbols are in [00_notation](00_notation.md): $\ell$ location, $\mu$ calendar month, $v$ weather variable, $m$ member.

The question the scenario answers is conditional: what does the fitted model imply for the target window if weather in each location follows member $m$, holding the survey's other characteristics fixed? It is not a forecast of welfare or poverty.

## Method

### 1. Forecast weather in the app's units

The data pipeline, not the app, puts the forecast on the scale of the observed weather. For member $m$, location $\ell$, forecast run $r$ and valid month $t$:

$$\tilde x^{\ m}_{\ell t} = \bar x^{\text{obs}}_{\ell\mu(t)} + \left(x^{\ m}_{\ell t} - \bar x^{\text{fc}}_{\ell\mu(t)}\right) \qquad \text{(1.1)}$$

where $x^{\ m}_{\ell t}$ is the raw forecast, $\bar x^{\text{fc}}_{\ell\mu}$ is the mean of the forecast system's own past forecasts for the same run month, lead and calendar month, and $\bar x^{\text{obs}}_{\ell\mu}$ is the observed monthly mean over the same years. The adjustment removes the mean bias of the forecast system and keeps each member's departure from it. It does not correct the spread, reliability or skill of the forecast. Rainfall (`r`) is adjusted by a ratio instead: the raw value is scaled by the observed over the forecast-system mean for the same calendar month, capped at 1.5 times the cell's largest observed monthly value, with a separate rule where the forecast-system mean is near zero (the manifest's `adjustment_formulas` states it). The manifest names one adjustment per variable (`adjustments`), and the catalogue lists them in variable order, separated by `;`. Reference years are fixed in the pipeline, so the historical window chosen in Simulation settings does not change the forecast.

### 2. Predictors for the target window

For a target month $t$, each lagged predictor of the fitted model uses the same lag window and aggregation as in estimation (see [12_weather_measures](12_weather_measures.md)). A run file carries a complete monthly series per member: `context_months` (12) observed months before initialization, then every forecast lead. Required months up to the run's `observed_through` (the month before initialization) are observed values from the same file; forecast months use the member's values, including the initialization month (lead 1). Observed context months from ERA5-Land-T are preliminary (`source = era5land_t`) and are reported with the run. The longest reach-back among the fitted predictors sets how many earlier months the strip shows, capped at six; the availability check is not capped.

Every target month must lie in the forecast horizon, and every month its fitted predictors need must lie in the run's observed context or forecast months. A multi-month window is available only when all its target months pass this check. There is no gap fill or climatology substitution. With an October 2026 run and 12 context months, every lag up to 12 permits November to March. Both the controls and the weather builder enforce this rule.

### 3. One state per member

Each member gives one complete weather state for the target window. Everything after the weather step runs as for a climate scenario. Results are first aggregated within a member and then summarised across members. The spread across members is weather uncertainty; it is kept apart from the uncertainty in the estimated coefficients.

Every baseline household is evaluated for every target month, regardless of its original interview month. Survey-wave identity and observed welfare stay fixed. Predictors and nonlinear transformations are evaluated month by month, not averaged before prediction. With a target window of $L$ months, each household-month uses its population weight divided by $L$. The member's metric therefore describes the equally weighted mixture of target-month household outcomes, not a metric of each household's averaged welfare. Only then are summaries taken across ensemble members. A single simulation-year anchor identifies the target-window state internally, including a window crossing December; it is not an annual forecast or a return-period sample.

The app validates the catalogue against its run manifest, rejects a missing adjustment declaration, and checks the run file's SHA-256 identity. An invalid run is skipped and reported, not fatal. The run signature includes the member IDs, data version and file hashes so a changed publication cannot silently reuse the same forecast cache identity.

The household's interview month stays its own: `int_month` is a model fixed effect and keeps the survey value, while the weather is joined on the target month. Only the weather moves to the target month, so the seasonal welfare level of each household is unchanged and a target month without interviews is not a problem. Any missing forecast prediction stops the run.

### 4. Same-window reference and placement

The Historical scenario evaluates each household in its own interview month. Its months generally differ from the target months, so a forecast-versus-Historical difference mostly measures seasonality. The forecast is therefore compared with a **same-window reference**: the identical computation (same model, residual treatment, weights, household-month expansion and lag windows) with observed weather for the target calendar months in each year of the Historical period. Each reference year gives one target-window aggregate $R_y$, like a member.

Each member's aggregate $A_m$ is placed in the reference distribution. With $n$ reference years, $p_m$ is the share of reference years at least as adverse as $A_m$ (the adverse side follows the metric), and the member is "about a $1/p_m$-in-years outcome". Return periods beyond $n/2$ (about 1-in-15 for 30 years) are reported as beyond the observed range, not extrapolated. The Results cards report the median member's placement and the share of members worse than the reference 1-in-10 level. There is no return period for the ensemble mean, because averaging pulls it towards the centre. The member share is an indicator, not a probability.

Forecast window views: in Step 2 each Results chart carries the target-month series next to the annual ones, on one outcome axis. The rows run Forecast, Historical for the same months, Historical (annual), then the climate scenarios, so that neighbouring rows are the valid comparisons. The members $\{A_m\}$ compare with Historical for the same months, the reference years $\{R_y\}$ (labelled "Historical (Nov - Jan)"), which have their own baseline: a difference view subtracts the mean or median of $R_y$ from them, and the annual Historical mean or median from the annual series, so both Historical series sit at zero. Step 3 keeps two groups per section, annual and target months. The distribution shows both samples. The adverse levels are the 1-in-$k$ quantiles of $R_y$ (Hazen positions), with one Forecast row: the median member and the band from the 10th to the 90th percentile of the members. The exceedance chart shows the curve of $R_y$ over the whole probability range and marks where the median member, and the members of the selected band, fall on it: the historical return period each lines up with. The mark reads against that curve only, not the annual curves on the same chart. In the uncertainty bars the member spread is an across-member component, as across climate models; one window has no year-to-year component. The cards add $|\bar A - \bar R| / s_R$, with $s_R$ the standard deviation of $R_y$, and $s_A / s_R$. The gap between the two Historical series, in the level view, is the effect of weather in the target months rather than each household's interview months. It is not the full seasonal difference in welfare, because the interview-month fixed effect stays at its survey value, and it is small with anomaly predictors or when interviews fall in the target months.

Skill: a run may publish a hindcast skill table (anomaly correlation, CRPSS, tercile ROC area, a `skill_flag` of `none`, `weak` or `useful`) per initialization month and lead. The thresholds behind the flag are fixed upstream; the app reads and reports the flags. The flyout and the cards name the skill of each target month, worst first, and the basis strip carries a warning unless every target month is `useful`. A run without a skill table says that skill was not assessed.

Season check: the cards warn when fewer than half of an even share of the model's training observations were interviewed in the target months, because the weather response is then applied to months it was barely estimated from. A calendar-month anomaly predictor with interview-month fixed effects is the recommended specification for forecast use.

### 5. Policy under the forecast (Step 3)

The policy effect on a household is a static change of its characteristics or transfer, row-aligned with the Step 2 prediction rows, so the same correction $\Delta_h$ applies to household $h$ in every target month. Each member $m$ gives a baseline aggregate $A_m$ and a policy aggregate $A^{\text{pol}}_m$ over the same $L$ target months and the same weights $w_h / L$; each reference year $y$ does the same, giving $R_y$ and $R^{\text{pol}}_y$. The app reports the median of $A^{\text{pol}}_m - A_m$ and of $R^{\text{pol}}_y - R_y$, and the share of members at or below the baseline 1-in-10 reference level without and with the policy at that one fixed level. The policy has no timing within the window. A shock-responsive transfer takes its triggers from annual weather and is not available with a forecast. The annual groups of Step 3 (weather years, adverse years, exceedance, tables, decomposition) read the annual scenarios only; the target-month group of each section compares baseline and policy for Historical of the same months and for the members.

## Interpretation

The band across members shows how much the forecast weather moves the model's outcome. It is not a calibrated probability. A forecast with no skill for the season and lead still produces a band, so the app must say where skill is weak.

## Assumptions

- **A1.** The additive adjustment (1.1) for temperature, and the capped ratio for rainfall, are enough to put the forecast on the scale of the observed weather. Amplitude is not corrected.
- **A2.** The fitted relationship between weather and the outcome holds for forecast weather as it does for observed weather.
- **A3.** Member order carries no meaning; members are equally weighted.
- **A4.** One weather coefficient applies in every season. The target months may be rare among the training interviews, which the cards flag, and the response there is then an extrapolation across seasons.
- **A5.** The same-window reference years are exchangeable draws of target-window weather, and about 30 of them resolve return periods only up to about 1-in-15.

## Limitations and what is not modelled

- The pilot provides monthly mean 2 m temperature (`t`) and rainfall (`r`). Minimum and maximum temperature (`tn`, `tx`) could be supported after their retrieval, adjustment and validation are added. Models using variables outside the prepared data cannot use the current forecast. Rainfall skill is weak or absent at most leads, so a model with rainfall is flagged by its worst variable. The latest observed context months can be preliminary (ERA5-Land-T, source `era5land_t`) for both variables. Daily extremes, soil moisture and drought indices remain outside the monthly pilot's scope.
- One forecast system. No weighting or blending of systems.
- Skill is unproven for most seasons and leads. A backtest against held-out observations is planned before any season is shown without a warning.
- Welfare responses are conditional on the fitted model; no adaptation within the target window.
- Target months have equal weight, not weight proportional to their number of days. This is a monthly-state summary, not an annual welfare forecast.
- Forecast windows are not annual weather years: the forecast is compared with Historical for the same months, not with Historical (annual) or the climate scenarios, whose outcomes cover the interview months, even where they share a chart. Return periods of the same-month historical years are resolved only up to about 1-in-15. Climate scenarios for the target months are not simulated.
- Step 3 applies static policies to the window and to the reference years. A shock-responsive transfer is not available with a forecast, and the policy-channel decomposition is annual only.

## In the app

- Step 2 > Seasonal forecast: include the forecast, choose the run, the length of the window (1, 3 or 6 months) and the start month on the strip. The forecast is unavailable, with a reason, when the country has no forecast or the fitted model uses a variable the forecast does not provide.

- Step 3: a policy run with a forecast has the same two groups in the cards and in each Results section: all months (Historical and the climate scenarios, baseline and policy) and the target months (Historical for the same months and the forecast members, baseline and policy). The target-month cards give the median policy effect of the members and of the historical years and the share of members worse than the historical 1-in-10 without and with the policy. The exceedance chart places the median member of each arm on the no-policy historical curve of the same months. The ensemble-spread controls set the member band as they set the climate-model band.

- Step 2 > Results: with a forecast, each chart and the return-period table carry both sets of series: "Historical (annual)" and the climate scenarios, and "Historical (Nov - Jan)" and the forecast. A forecast-only run shows the same charts without scenario rows. The headline cards stay in two groups, annual and target months. The cards of the target months show the placement, the shift against the historical spread of the same months and the member range.

User guide: [wise-app-docs](https://github.com/worldbank/wise-app-docs).

## References

None yet. Entries will be added with the backtest. Full entries are in [references](references.md).

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Forecast controls, window and lag text | 2 | `R/utils_forecast_ui.R` `.step2_forecast_window()`, `.step2_forecast_lag_text()` |
| Reach-back of the fitted predictors | 2 | `R/utils_forecast_ui.R` `.step2_forecast_lag()` |
| Predictor-month availability and allowed starts | 2 | `R/utils_forecast_ui.R` `.step2_forecast_months()`, `.step2_forecast_starts()` |
| Variables the forecast provides | 1 | `R/utils_forecast_ui.R` `.step2_forecast_unsupported()`, `.STEP2_FORECAST_VARS` |
| Forecast scenario name and run signature | 3 | `R/utils_forecast_ui.R` `.step2_forecast_display_key()`, `.step2_forecast_signature()` |
| Local run discovery and publication identity | 1 | `R/fct_forecast_catalogue.R` `.forecast_catalogue_runs()` |
| Same-window reference weather (`refyear_<year>` frames) | 4 | `R/fct_forecast_weather.R` `.get_forecast_weather(reference_years = )` |
| Reference pipelines and the interview-month join key | 3, 4 | `R/fct_run_simulation.R` `consume_reference()`, `.step2_forecast_join_keys()` |
| Hindcast skill of the target months | 4 | `R/fct_forecast_skill.R` `.forecast_skill_table()`, `.forecast_skill_summary()` |
| Policy under the forecast: exposure contract for the window, reference pipelines | 5 | `R/fct_policy_metric_decompose.R` `.policy_forecast_window()`, `.validate_policy_annual_exposure()`; `R/fct_policy_sim.R` `apply_policy_delta_to_baseline()` |
| Policy effect: window views, cards, batch rows | 5 | `R/fct_forecast_window.R` `step3_window_views()`, `.step3_window_cards()`; `R/fct_forecast_policy.R` `step3_forecast_policy()`, `step3_forecast_batch_tables()` |
| Member placement in the reference | 4 | `R/fct_forecast_placement.R` `.forecast_placement_stats()`, `step2_forecast_placement()` |
| Cards comparator and training-month warning | 4 | `R/fct_sim_compare.R` `step2_headline_cards()` |
| Forecast window views: the target-month samples through the annual view builders, the Forecast row, the exceedance position, the merged Step 2 charts | 4 | `R/fct_forecast_window.R` `step2_window_series()`, `step2_window_views()`, `.step2_window_adverse_dots()`, `.step2_window_exceedance_position()`, `.step2_window_merge()`; `R/mod_2_02_results.R` (one chart per section in Step 2) |
| Adjusted monthly weather and fitted predictor windows | 2 | `R/fct_forecast_weather.R` `.get_forecast_weather()` |
