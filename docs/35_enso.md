---
id: enso
title: ENSO labels on results
app_step: 2
depends_on: [notation, data, simulation, climate-scenarios, seasonal-forecast]
symbols: [mu, r, m]
guide: https://github.com/worldbank/wise-app-docs
code: [R/fct_enso.R, R/fct_forecast_window.R, R/fct_forecast_placement.R, R/fct_overview_metadata.R, R/fct_batch_targets.R, R/mod_2_02_results.R, R/fct_policy_sim_compare.R]
verified_against: ce7a573
---

# ENSO labels on results

> ENSO is a label on results, never an input to them. Each simulated year is labelled by the El Niño-Southern Oscillation state of the months that enter the model for its households, so users can compare outcomes in El Niño and La Niña exposure. No simulation output depends on the label, and the results are the same with and without the ENSO tables.

## Setup

Two optional tables describe ENSO. The first gives, for each month from 1950, the relative Niño 3.4 index (RONI) and a phase: El Niño, La Niña or neutral. Its months come from observations and then, for the latest months, from a forecast. The second gives, for the latest forecast initialisation, the RONI, the phase and the share of members in each phase by system and month, with a multi-model row. If either table is missing or malformed, its ENSO elements disappear without an error.

Symbols are in [00_notation](00_notation.md): $r$ simulation year, $\mu$ calendar month, $m$ forecast member.

## Method

### 1. Label of a simulation year

A simulation year is not a calendar year. A household interviewed in month $\mu$ receives, in year $r$, the weather of the months its fitted lag window reaches back to ([30_simulation](30_simulation.md), Section 2). ENSO events straddle the new year, so one simulation year can hold the decay of an event for some households and the next phase for others. The label therefore follows the months the model reads.

Let $\pi_\mu$ be the weighted share of baseline households interviewed in month $\mu$, and $K$ the set of fitted lags in months. With several weather variables, $K$ runs from the smallest first lag to the largest last lag. The exposure share of phase $k$ and the exposure RONI are

$$s_k(r) = \sum_\mu \pi_\mu \frac{1}{|K|} \sum_{j \in K} \mathbf{1}\big[\text{phase}(r, \mu - j) = k\big] \qquad \text{(1.1)}$$

$$\text{RONI}^{\text{exp}}(r) = \sum_\mu \pi_\mu \frac{1}{|K|} \sum_{j \in K} \text{RONI}(r, \mu - j) \qquad \text{(1.2)}$$

A year is labelled El Niño, La Niña or Neutral when one phase has a share of at least one half, and **Mixed** otherwise, which includes a tie at one half. Shares are not rounded before the comparison. A year whose lags reach outside the table has no label. The label depends on the interview months and the fitted window, so it is computed for each run and is not a fixed list of years. The app writes "El Niño exposure", not "El Niño year", because a simulation year is a composite.

### 2. Climate scenarios

A future series is the observed record shifted by a monthly change ([31_climate_scenarios](31_climate_scenarios.md), Section 3), so its simulation year is an observed template year. A scenario year carries the label of its template year. No ENSO table for climate models is needed.

### 3. Forecast target months

Historical for the same months has its own labels: (1.1) and (1.2) with equal weight $\pi_\mu$ on the target months, so the fitted lags are treated as they are for a household. The reference year is the year the window starts, as for the same-window reference of [34_seasonal_forecast](34_seasonal_forecast.md), Section 4: November 1997 to January 1998 is 1997, and the event is not split.

A member has no label. Its year index is not a year, and every member of a run shares one outlook.

### 4. Outlook of a forecast run

The outlook is the RONI, the phase and the share of members of each target month. It uses the system of the weather run, so it describes what is simulated, and falls back on the multi-model row. It applies only when the initialisation of the table equals that of the run, because the table keeps the latest initialisation only. Otherwise the months come from the monthly table, and the app says it is a later outlook. The share of members is empty at the first and last lead, and a window reaching those months shows the RONI only.

The phase of the outlook is the phase of at least half of the target months; otherwise it is Mixed. The median member is then compared with the reference years of that phase, by the count of those years at least as adverse as the median member, next to the same count over all reference years. A Mixed outlook, or a phase with fewer than three reference years, has no comparison.

A value above the record is named as stronger than any event in the record, on this forecast. No margin is quoted: the months of the current event cross a change of data source, which affects the size of the gap.

### 5. Comparing outcomes by label

Each series is averaged over its climate models by simulation year, so a year counts once. The comparison then gives, for each label, the number of years and the mean outcome, and for El Niño and La Niña the difference from Neutral. The difference needs at least three years on both sides. Mixed years stay in every other result and are not compared. For a policy, the same is done for the baseline, the policy and their difference. No test of significance is applied.

### 6. Weather support by label

The share of simulated weather outside the support of the fitted sample ([30_simulation](30_simulation.md), Section 6) is also given for the years of each phase, for a phase with at least three years. This is the check that matters for ENSO years: the model responds to local weather, so it needs variation in weather and not interviews in El Niño months.

### 7. Table versions

The history of the monthly table is not frozen, so an exported or batch result records the version of the ENSO tables: a hash of each table, the last month of the observed source and the forecast initialisation. This record is not part of any run signature, and a refreshed table neither invalidates a run nor reruns a batch simulation.

## Interpretation

Labels describe the ENSO state of the months that enter the model for each household. Differences between labels reflect only the selected weather variables and months, through the fitted response. A small difference does not mean that ENSO has a small welfare effect.

ENSO reaches countries unevenly and by season, so a flat result is common where the selected weather in the selected months barely responds to ENSO. It is not a failed result.

Few events fall in a window, and they differ from each other. Past events are not a forecast. The index flags fewer El Niño months than the traditional Oceanic Niño Index in recent decades, so it may differ from figures in the press.

## Assumptions

- **A1.** ENSO affects the simulated outcome only through the selected local weather. It does not enter estimation.
- **A2.** The fitted response holds in El Niño and La Niña years. The model can simulate years it did not observe, as long as their weather lies in the fitted range.
- **A3.** The months of the fitted window, weighted equally, represent the exposure of a household in a year.
- **A4.** A climate scenario keeps the observed ENSO sequence of its template years.
- **A5.** The reference years of the outlook's phase are a fairer comparison for a forecast than all reference years. They qualify A5 of [34_seasonal_forecast](34_seasonal_forecast.md#assumptions), and they are few.

## Limitations and what is not modelled

- Prices, markets, fisheries, health, floods and other ENSO channels do not pass through monthly local weather.
- The response comes mostly from local differences, so it may understate a widespread shock.
- One coefficient applies in every season, while ENSO effects are seasonal.
- Changes in ENSO frequency, strength or teleconnections under warming are not represented.
- Four to ten years of a phase support no phase-specific return period, exceedance curve or test.
- A forecast event beyond the record has no past years like it. Its weather needs the weather-support check, not inference from past events.

## In the app

- Step 1 > Survey stats: a sentence under the timing of interviews gives the share of households interviewed in each phase and the highest RONI at an interview.
- Step 2 and Step 3 > Results: the toggle Mark ENSO years marks draws on the distribution chart, for the annual series and for Historical of the target months.
- Step 2 > Results: the section on El Niño and La Niña years compares outcomes by label. Step 3 adds the policy effect.
- Step 2 > Results: with a forecast, the placement card of the target months gives the outlook and the comparison, in the level view.
- Step 2 > Diagnostics: bands on the weather-year trajectories, and a line on weather support by label.
- Export: the labels, the comparison tables and the outlook; the run record gives the table versions.

## References

None yet.

## Implementation map

| Concept | Equation | Code |
|---|---|---|
| Optional tables and their validation | | `R/fct_enso.R` `enso_load()`; `R/fct_overview_metadata.R` `load_overview_metadata()` |
| Fitted window and interview-month weights | 1.1 | `R/fct_enso.R` `enso_window()`, `enso_month_weights()`, `enso_baseline_months()` |
| Year label, shares and exposure RONI | 1.1, 1.2 | `R/fct_enso.R` `enso_year_labels()` |
| Labels on the annual rows, template years included | | `R/fct_enso.R` `enso_attach_labels()` |
| Labels of the reference years of the target months | 1.1, 1.2 | `R/fct_enso.R` `enso_window_labels()`, `enso_attach_window_labels()` |
| Outlook, its phase and the comparison with reference years | | `R/fct_enso.R` `enso_forecast_outlook()`, `enso_outlook_phase()`, `enso_reference_comparison()`, `enso_placement_text()` |
| Placement card | | `R/fct_forecast_placement.R` `.forecast_placement_text()` |
| Comparison by label | | `R/fct_enso.R` `enso_phase_summary()`, `enso_series_table()`, `enso_policy_table()` |
| Weather support by label | | `R/fct_enso.R` `weather_support_by_phase()` |
| Table versions and exported tables | | `R/fct_enso.R` `enso_provenance()`, `enso_year_table()`, `enso_outlook_table()` |
| Batch labels, apart from the simulations | | `R/fct_batch_targets.R` `wise_batch_enso_source()`, `wise_batch_enso()`, `.batch_enso_inputs()` |
