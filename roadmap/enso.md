# ENSO: remaining work

Updated 2026-11-04. Branch `seasonal-forecast`, not yet merged into `dev`; ENSO goes to `dev` in one PR with the forecast. This file holds the state, the decisions to keep and what remains. The method is in `docs/35_enso.md`. The order of the PR is in `roadmap/seasonal_forecast.md`. The upstream tables are described in `wise-app-data` (`dev/enso_plan.md`, README section "`enso.csv` and `enso_forecast.csv`").

The full plan, with the evidence, the prototype figures and the stage-by-stage verification, is in git: `git show 3552240:roadmap/enso.md`.

## State

The first version is built and committed: labels, Step 1 sentence, the distribution toggle in Steps 2 and 3, the comparison sections, Diagnostics bands and weather support line, forecast outlook line, exports, batch `enso_years` and `summary` rows, and the methods page. For a user that is one new section, one toggle, three short text lines and shading on a Diagnostics chart.

Verified at `8639eb2`, with the fixture parity and the smoke rerun after the review fixes of 2026-11-04 (real-data parity not rerun; those fixes touch no simulation path):

- **D1 parity.** `dev/parity_enso.R --forecast`: BFA 124 of 124, MWI 124 of 124 and fixture 128 of 128 tables identical with and without the ENSO tables. The only tables in one run are the ENSO ones.
- **Batch.** `test-batch-pipeline.R` runs without the tables, with them and after a refresh: `annual` is unchanged at `tolerance = 0`, the `sim_tables` branches do not rerun. Real BFA 2021 batch: no failures, card line equal to the app's.
- **Browser.** BFA, MWI 2019 and BFA with the files removed, for Steps 1 and 2 and for the forecast line. BFA Step 3 with the section and the marks.
- **Smoke.** `tests/e2e/smoke.R` loads ENSO tables, turns the toggle on in Steps 2 and 3 and scans both with axe: no violations. Chart marks are drawn on a canvas, which axe cannot read; they carry a symbol as well as a colour.

## Decisions to keep

- **D1. Annotation only.** ENSO joins at display time from `sim_year`, interview months and fitted windows. It stays out of `fct_run_simulation()`, the Step 2 and 3 aggregation, run signatures, the aggregation cache and the async payload, so a refreshed table cannot invalidate a run. No Decision log entry is owed. `dev/parity_enso.R` is the proof; rerun it after any change that touches these paths.
- **D2. Exposure-weighted year label.** A simulated year is a composite of interview months and lags, so calendar labels are wrong (on BFA 2021 a calendar label agrees in 18 of 30 years). Majority share of at least 0.5, otherwise Mixed, on unrounded shares. With several variables the window is the union range. The text says "El Niño exposure", not "El Niño year".
- **D3. One label per sample.** Annual: D2. Climate scenarios: the label of the template year, so no CMIP6 ENSO table is needed (`wise-app-data/dev/cmip6_enso_plan.md`). Historical of the target months: D2 with equal weight on the target months, and the reference year is the year the window starts. Forecast members: no label, one outlook per run.
- **D4. Outlook.** The system of the run (`ENSO_FORECAST_SOURCES`), falling back on `multimodel`, only when `init_date` equals the run's `init`; otherwise the months of `enso.csv`, named a later outlook. The two published tables stay separate: they have different shapes and `enso_load()` reads both. A new forecast system needs a row in `ENSO_FORECAST_SOURCES`, or it uses `multimodel`.
- **D5. Modest statistics.** Counts, means and differences from Neutral, with $n$ visible. No p-values, phase-specific return periods or exceedance curves, and no causal wording. A phase needs three years to be compared.
- **D6. The files are optional.** Missing or malformed tables remove every ENSO element without an error. They are not in `OVERVIEW_METADATA_FILES`, whose entries are required.
- **D7. No ENSO in estimation.** RONI as a regressor has no local variation, is absorbed by the `year` effect and extrapolates to 3.35 from a sample range near plus or minus 1. A weather-by-phase interaction mostly measures a difference between waves, because phase is often the same as wave. Training on one phase removes the weather variation the response needs. Simulating past El Niño years is valid as long as their weather lies in the fitted range, which is why Diagnostics reports weather support by label.
- **D8. No ENSO control in Step 2 settings.** All years are simulated anyway. Filtering years would move the baseline of the delta method and rebuild return periods on a few years. Selecting years is a view of results.
- **Open decisions, settled for now.** Toggle off by default. No headline card in the annual group. Year rule as in D2; the alternative, exposure RONI at plus or minus 0.5, has no Mixed class but labels a year on a few strong months.

## Before the PR into `dev`

- **Browser checks not run.** MWI Step 3 forecast marks; Step 3 with the ENSO files removed; the file-removed and MWI checks of the Step 3 comparison and the weather support line. All use gates already checked in Step 2. Use `dev/ui_drive.R` (skill `wise-ui-check`) on MWI, which has a signal, on BFA, which has none, and with the files removed.
- **Zip downloads.** The new tables were read through the export registry, not downloaded in the browser.
- **BFA forecast position.** It depends on the specification: reference years at least as adverse as the median member are 1 of 30 in the parity run and 28 of 30 with the app defaults. Look at this in the forecast checks; it is not an ENSO defect.

## For the Connect release

- **Request 1 to `wise-app-data`.** Promote observed ENSO into `all`, or at least to the production data root, and add `validate` checks. Without the files on that root the annual flags do not appear on Connect.

## After the PR

Requests to `wise-app-data` that block nothing:

- Correct `dev/enso_plan.md`: it says ONI is published next to RONI, but `enso.csv` has no `oni` column.
- Fill the probabilities at the first and last lead if possible.

Known limits of the first version, to revisit with feedback:

- The ENSO line of the forecast card shows only in the Step 2 level view. Step 3 cards have no placement text and a difference view has no placement card.
- The line makes the placement card taller than its neighbours.
- A binned variable is checked for support on its bins, so its Diagnostics line usually reads 0.0%.

Second version, if feedback asks for it:

- **Forecast flyout outlook.** A phase mark per month on the strip (`forecast_strip_input()`), with the RONI in its tooltip.
- **Is ENSO relevant here?** The correlation of the run's simulated weather with exposure RONI in the section, so a flat result reads as "ENSO barely reaches this weather in these months". BFA is one of the weakest cases and MWI one of the strongest.
- **Exceedance tooltip.** Weather year and label on hover.
- **Shock-responsive transfers.** Payout frequency and cost by phase, from `shock_activated` and `shock_total_cost` per year.
- **Residuals by phase** in Step 1 Model fit, when a sample has two phases within a wave.
- **Offline robustness check** of the weather-by-phase interaction, where a wave spans phases (IRN, VNM, IND, COL). Not an app feature (D7).

Later ideas, not prototyped:

- **Row-level phase estimate.** Pool household-year rows by the phase of each row's own exposure, standardised to the interview months. It removes the Mixed class, needs a new aggregation with its own uncertainty and a methods review. Build it only if the year labels prove too coarse.
- **ENSO analogue scenario.** "Past El Niño years" as a series for countries with no forecast or beyond the horizon.
- **ENSO composite map.** Mean weather anomaly by phase, with `summarise_weather_anomaly_by_loc()`.
- **ENSO-based triggers** for shock transfers. A policy decision first; anticipatory designs are rejected with a forecast.
- **Forecast members by own RONI.** Held upstream; no use while every member is El Niño.

## Left alone on purpose

Adverse-year dots, return-period table and exceedance curves (D5), uncertainty bars, model coefficients and specification tables, weather maps, decomposition, cost-effectiveness and the Overview tab.
