# Hazard and geospatial data sources

Status: proposal, 2026-11-09. Issues: [#65](https://github.com/worldbank/wise-app/issues/65) (event data as hazard variables), [#53](https://github.com/worldbank/wise-app/issues/53) (sensitivity to weather data source), [#42](https://github.com/worldbank/wise-app/issues/42) (land use variables). Most of the work is upstream in the sibling repo `wise-app-data`; the app needs a small, general hook for each.

## Today

Hazard variables are monthly weather on H3 hexagons: ERA5-Land (historical) and CMIP6 (projections), plus the seasonal forecast pilot (`docs/34_seasonal_forecast.md`). The variable list in the data directory decides what Step 1 offers.

## #53 Alternative weather sources

Test whether the outcome-climate relationship holds with other products.

- **Upstream.** Build CHIRPS (rain) and CHIRTS-ERA5 (temperature) on the same H3 grid and monthly layout as ERA5-Land, with distinct variable names (for example `precip_chirps`). Later CHC-CMIP6 projections to match.
- **App.** Weather variables from several sources are already separate variables, so the model selector works unchanged. Add a "compare sources" view in Step 1: the same specification fitted with each source, coefficient and fit side by side. Warn that Steps 2 and 3 need projections from the same source as the fitted variable.
- **Check.** Start with one country with dense station data and compare coefficients, not only fit.

## #65 Events as hazard variables

Events are discrete (flood, cyclone, conflict, drought, disaster record), not continuous series. Candidate sources are in the issue: GloFAS and Groundsource floods with Fathom projections, IBTrACS cyclones with STORM, ACLED conflict, FAO drought, EM-DAT.

- **Upstream.** Convert each source to a hexagon-month table with an intensity or exposure column (flood depth class, wind speed at the cell, event count) and a flag for months with no event as zero, not missing. Keep historical and projected versions with the same definition.
- **App.** Needs a second variable kind next to weather: no window aggregation by mean, but max, count or exposure within the window, and a binary or intensity form. The window and form steps in `docs/12_weather_measures.md` allow max and sum already, so the first version can reuse them with zero-filled months. Climate scenarios for events (STORM, Fathom) are return-period based, not annual series, which does not fit the Step 2 annual loop; handle events as historical-only until the simulation design for them is written.
- **Priority.** Tropical cyclones and floods first, because they have both historical and projected products. Conflict has no projection, so it fits as a control or moderator, not a simulation driver. Air pollution (ACAG) is continuous and fits the weather pipeline directly.

## #42 Land use variables

Variables such as nearness to forest or water, used as interactions to link resilience to nature.

- **Upstream.** Compute per hexagon: share of land cover classes (forest, cropland, water, built) from a global land cover product, distance to nearest forest or water body, and optionally tree-cover change. Static or yearly; add to the variable list as household-location covariates with labels and a moderator flag.
- **App.** No new code if the variables enter as moderators through the existing interaction selector and as policy-free covariates. Share variables are numeric, so they need the binned-moderator option of `roadmap/model_specification.md` (#62). Policy levers that change land use are out of scope.

## Open questions

- Does the data repo have capacity for all three? Suggested order: #53 (CHIRPS), then #42, then #65 cyclones and floods.
- Hexagon resolution for land cover: use the survey location resolution, not a finer one, to avoid privacy and size problems.
