# ENSO in WISE-APP: ideas and plan

Status: proposal, 2026-11-04. Nothing here is built. The app does not read the ENSO tables yet. Seasonal forecast work is in `roadmap/seasonal_forecast.md`; the upstream tables are described in `wise-app-data` (`dev/enso_plan.md`, README section "`enso.csv` and `enso_forecast.csv`").

## Goal

Let users see how predicted outcomes compare in El Niño and La Niña episodes, in Steps 1 to 3, without adding many outputs or cluttering the current ones. A strong El Niño is under way: `enso.csv` has RONI at 1.69 in August 2026 and a forecast peak of 3.35 in December 2026.

## Summary of the proposal

1. **ENSO is a label on results, never an input to them.** It joins existing outputs on month and year. No simulation output, run signature or protected numeric changes, so a Decision log entry is not needed.
2. **Label each simulated year by the ENSO state of the months its weather came from**, not by calendar year. Those months depend on the interview months and the fitted lag window, so the label is computed per run.
3. **Climate scenarios inherit the labels for free.** Their weather is the observed sequence shifted by a monthly delta, so a template year keeps its real ENSO state.
4. **Few surfaces.** One new Results section (a small table), one toggle on the existing distribution chart, shading on the Diagnostics trajectories, one coverage line in Step 1 and one outlook line with the forecast. Most charts stay as they are.
5. **State the limits next to the numbers.** There are few events per window, and the model only sees ENSO through the selected weather and a response learned mostly from local differences.
6. **No ENSO in estimation and no ENSO control in Step 2 settings.** Weather carries the signal, and selecting years is a view of results, not a run setting (D7, D8).

## Progress

Update this table in the same change as the work, with the commit and what was verified. Record a changed decision in its D section, and a decision taken on an open item under Open decisions.

| Step | State | Commit | Verified |
|---|---|---|---|
| Design and prototype | Done | | Figures below; prototype scripts were not kept |
| Phase 0: `R/fct_enso.R`, tests, fixtures | Done | `enso`, "Add ENSO label helpers for Phase 0" (not pushed) | `devtools::test(filter = "fct.enso")`: 126 pass, 0 fail, 0 skip. Real data, BFA 2021 (survey `weight` by `timestamp` month, one-month lag): 1997 0.69/0.31/0.00 El Niño, 1998 0.31/0.23/0.46 Mixed, 2015 1.00/0/0 El Niño, 2016 0.31/0.23/0.46 Mixed, as in the table above. Window 1 to 6: 6 El Niño / 4 La Niña / 14 Neutral / 6 Mixed; 7 of 30 years change class against the one-month lag |
| Phase 0: requests to `wise-app-data` | Partly done (CMIP6 note) | | |
| Merge `enso` into `seasonal-forecast` | Done | Merge commit on `seasonal-forecast` (not pushed) | `devtools::test(filter = "fct.enso")` on the merged branch: 126 pass, 0 fail, 0 skip |
| Phase 1: load, items 1, 2, 3, 5 | Done | `seasonal-forecast`, "Show ENSO exposure years in Steps 1 to 3 (Phase 1, items 1, 2, 3, 5)" (not pushed) | `devtools::test()`: only `test-deploy-contract.R` fails (manifest lacks `R/fct_enso.R` and the forecast files; settled by the manifest step before the PR). Focused run (`fct.enso`, overview metadata, export wiring, sim and policy compare, diagnostics, step 2 input, batch pipeline): 1201 pass, 0 fail. D1 parity (scratch script, Steps 1 to 3 in `shiny::testServer`, `enso` NULL against loaded, `identical()` and `all.equal(tolerance = 0)` on every registered export table): fixture TST 128 of 128, BFA 128 of 128 identical, `baseline_months` and `hist_sim` equal. UI (`dev/ui_drive.R`): BFA with the file (Step 1 sentence, toggle in Steps 2 and 3, section, Diagnostics bands, no errors), BFA with the file removed (no sentence, toggle or section, no errors), MWI 2019 (all elements, no errors). Loader: `load_overview_metadata()` carries an optional `enso` element; on Databricks the two files join the existing request batch (+2 requests per load, no DuckDB session) |
| Phase 1: items 4, 6 | Done | `seasonal-forecast`, "Add ENSO policy comparison and weather support by exposure (Phase 1, items 4, 6)" (not pushed) | Focused run (`fct.enso`, export wiring, diagnostics, sim and policy compare): 2400 pass, 0 fail. D1 parity (`dev/parity_enso.R`): fixture 128 of 128, BFA 128 of 128 tables identical with and without the ENSO tables; the only extra tables with the file are the six ENSO ones (`enso_exposure_years` and `policy_enso_exposure_years`, by method). UI on BFA (default weather `t` binned, 1991-2020, SSP3-7.0, cash transfer of 1): Step 3 section and sentence render, Diagnostics line renders, `errors` clean. Real-data check of the continuous branch on the saved BFA run (`t` binned and `r` continuous, window months 1 to 12 for `r`): `r` outside the fitted range in 5.2% of Historical values in 7 El Ni\u00f1o years, 3.6% in 9 La Ni\u00f1a years, 4.9% in all years. Not run this stage: the file-removed and MWI browser checks (the new elements use the same `has_enso` and `enso_labels` gates as items 2 and 3, which were checked). Item 6 uses the weather of the survey years at the survey cells as the fitted-sample reference, as the density panel's Model support does; a binned variable is checked on its bins, which the binning leaves almost always inside the sample, so its line reads 0.0% |
| Phase 2: item 7 | Done | `seasonal-forecast`, "Add ENSO outlook and reference-year labels to the forecast window (Phase 2, item 7)" (not pushed) | `devtools::test()`: only `test-deploy-contract.R:76` fails (manifest, settled before the PR). D1 parity with a forecast (`dev/parity_enso.R --forecast`, new mode; Nov to Jan, `t` months 1 to 3, `r` months 1 to 6): BFA 124 of 124, MWI 124 of 124, fixture 128 of 128 tables identical, including `forecast_window_headline_summary`; `hist_sim` equal. BFA and MWI ran before a last wording change to the line ("all members"); the fixture ran after it. The ENSO line stays out of the card's `note`, so the headline export does not change; item 8 owes it to the export. Phase 0 bug fixed: the real `enso_forecast.csv` writes empty values as the text `NA`, so the validator rejected the whole table and the outlook would have read as a later outlook. The run's `init` and `model_id` sit beside `baseline_months` on `hist_sim` (`forecast_run`), outside `fct_run_simulation()`. UI (`dev/ui_drive.R`, app defaults, async path): BFA Steps 2 and 3 and MWI Step 2, line renders, members unlabelled (51 of 51), target-month Historical 30 of 30 labelled, `errors` clean. BFA with both files removed and a forecast: placement card present, no line, toggle or section, no errors. Not run: MWI Step 3 and Step 3 with the files removed in the browser. The line shows only in the level view of Step 2: Step 3 cards have no placement text, and a difference view has no placement card |
| Phase 2: item 8, docs | Not started | | |

Branch plan: Phase 0 is on `enso` (worktree `../wise-app-enso`). When the forecast work is committed, merge `enso` into `seasonal-forecast` and do all later work there, in the main checkout. ENSO and the forecast go to `dev` in one PR. Keep ENSO in its own commits for review.

Rules for every stage after Phase 0: read this whole file and follow `AGENTS.md`. Keep to D1, and prove it with `all.equal(tolerance = 0)` on the Step 2 and Step 3 tables with and without the ENSO file. Check UI changes in the running app with skill `wise-ui-check` on MWI (signal), on BFA (flat) and with the file removed. Stop at the end of the stage and report. Do not push, and regenerate `manifest.json` only as the last step before the PR. Commit only when asked.

## What the data and code show

Figures below were computed on 2026-11-04 from the published tables and `HEAD` at `8e806a7`, with scratch scripts outside the repo.

### The tables

- `metadata/enso.csv`: 927 months from January 1950 to March 2027, columns `timestamp`, `source`, `roni`, `phase`, `phase_agree`. Sources: `cpc` to August 2026, `era5` for September 2026, `forecast` for October 2026 on.
- `metadata/enso_forecast.csv`: 9 models and a `multimodel` row, initialised October 2026, 662 members. Every model and every available lead gives `prob_el_nino = 1`.
- Phase shares over 1991-2020: 26 percent El Niño, 29 percent La Niña, 45 percent neutral (months).
- Largest earlier peaks: 2.40 (1982-83), 2.28 (1997-98), 2.25 (2015-16), 2.12 (1991-92). The forecast of 3.35 is far outside this, but it crosses a data seam: CPC reads 1.69 in August and ERA5 2.53 in September, and upstream notes ERA5 runs up to about 0.3 degC warmer than ERSST in recent events. The app should say "stronger than any event in the record, on this forecast", not quote a precise record margin.

### A simulated year is not a calendar year

A household interviewed in month $\mu$ gets, in simulation year $r$, the weather of month $\mu$ of year $r$ through its lag window (`docs/30_simulation.md`, Eq. 2.1). Three things follow.

- **ENSO events straddle the new year, and simulated years cut them in two.** The BFA 2021 survey ran from October 2021 to July 2022, but simulation year $r$ places January to July and October to December in the same calendar year. Simulation year 1998 is the decay of the 1997-98 El Niño for some households and the onset of La Niña for others.
- **Calendar-year labels are wrong often.** 20 of the 30 default-window years hold two phases, 9 hold three, and 9 contain both El Niño and La Niña months. On BFA 2021 with a one-month lag, a calendar-year majority label agrees with the exposure label in only 18 of 30 years.
- **The label depends on the fitted window.** On BFA 2021, 7 of 30 years change class between a one-month lag and a window of months 1 to 6. On MWI 2019, 12 change. A fixed lookup of "El Niño years" would not be right for every run.

Example, BFA 2021, one-month lag, share of the population-weighted exposure in each phase:

| Sim year | El Niño | Neutral | La Niña | Label |
|---|---|---|---|---|
| 1997 | 0.69 | 0.31 | 0.00 | El Niño |
| 1998 | 0.31 | 0.23 | 0.46 | Mixed |
| 2015 | 1.00 | 0.00 | 0.00 | El Niño |
| 2016 | 0.31 | 0.23 | 0.46 | Mixed |

### Climate scenarios can carry the flag

`enso.csv` cannot be joined to raw CMIP6 months, because free-running models are not synchronised with real events. But the app does not simulate raw CMIP6 months. A future series is the observed record shifted by a monthly climatological change, with `sim_year` as the observed template year (`docs/31_climate_scenarios.md`, Section 3). So SSP template year 1997 is 1997 weather plus a delta, and its ENSO state is known. No CMIP6 ENSO table is needed (decision recorded in `wise-app-data/dev/cmip6_enso_plan.md`). It would only matter if the app simulated changes in ENSO itself.

This also gives a useful reading: "an El Niño like past ones, in a warmer climate". What it does not capture is any change in ENSO frequency, strength or teleconnections.

### Few El Niño interviews, but El Niño weather is mostly covered

All 72 household surveys, by the phase of the interview month, unweighted household counts:

- 13 percent of households were interviewed in El Niño months, 54 percent in La Niña months and 33 percent in neutral months. The 2021-22 EHCVM wave is entirely La Niña.
- 36 of 72 surveys have any El Niño interviews and 14 have a majority.
- 9 of 33 countries have no El Niño interviews at all: AGO, BRA, DOM, GAB, GHA, MMR, MNG, MRT and PER. Peru, the classic ENSO case, has one survey, entirely La Niña.
- Only 1.8 percent of households were interviewed at RONI of 1.5 or more, in 5 surveys (GMB 2015, IND 2009, IRN 2015, IRN 2016, LKA 2016). The highest RONI at any interview is 2.25.

This does not by itself limit the simulation. The model estimates a response to local weather, not to ENSO, so what it needs is variation in weather, and an El Niño year is one more draw of weather. The relevant check is whether the weather of those years lies in the fitted range, not whether interviews fell in El Niño months.

Share of location-months in 1991-2020 outside the 1st to 99th percentile of the sample's weather. Rough check: all country cells, unweighted, in the survey's calendar months, by the phase of the month; `t` over months 1 to 3, `r` over months 1 to 6.

| Phase | BFA `t` | BFA `r` | MWI `t` | MWI `r` |
|---|---|---|---|---|
| El Niño | 4.0% | 1.1% | 1.9% | 1.1% |
| Neutral | 2.3% | 1.0% | 1.6% | 1.5% |
| La Niña | 3.8% | 2.1% | 1.8% | 1.8% |
| RONI of 1.5 or more | 3.9% | 0.3% | 1.9% | 2.3% |

In these two countries, El Niño weather is about as well covered as any other, even though MWI has few El Niño interviews and BFA none in its latest wave. So simulating past El Niño and La Niña years is valid under the app's usual assumptions. This range is loose, because it pools places and seasons, while the model identifies its response within fixed-effect cells. The threats that remain are about the response, not the range:

- **Covariate shocks.** With a `year` fixed effect the response is learned from local differences within a wave. A widespread ENSO drought also moves prices and overwhelms local risk sharing, so the simulated loss may understate it.
- **Season.** One coefficient applies in every season (`docs/34_seasonal_forecast.md`, A4), while ENSO effects are seasonal.
- **Other channels.** Prices, fisheries, health and floods do not pass through monthly local weather.
- **The current event.** A forecast peak of 3.35 has no precedent, so its weather needs the existing support check, not inference from past El Niño years.

### ENSO reaches countries unevenly, and by season

Correlation of country-mean weather with RONI, 1991-2020, per calendar-month-standardised and detrended 3-month season, unweighted cell means. The best of 12 seasons is shown, which inflates these values.

| Group | Examples (temperature r, rainfall r) |
|---|---|
| Strong | COL (0.83, -0.71), ZMB (0.79, 0.47), MWI (0.78, 0.41), PER (0.77, 0.34), TLS (0.77, -0.73), VNM (0.66, -0.74) |
| Weak | BFA (0.34, -0.28), TGO (0.35, -0.27), BEN (0.27, -0.36), MNG (0.23, -0.16) |

Season matters as much as country. For November to January the median absolute correlation across countries is 0.15 for temperature and 0.25 for rainfall, and ZMB goes from 0.79 in January to March to 0.00 in November to January. BFA, the country used so far for all forecast checks, is one of the weakest cases, so a flat ENSO result there is expected and should not be read as a failed feature.

### Prototype on real runs

One batch run per country from an export of `HEAD`: default linear model, `t` over months 1 to 3 and `r` over months 1 to 6, both continuous, 1991-2020, SSP3-7.0 2025-2035, October 2026 run, November to January. Years were labelled afterwards with the exposure rule below, using the union window of months 1 to 6. No test of significance was applied, and this is one specification per country.

| | BFA 2021 | MWI 2019 |
|---|---|---|
| Years El Niño / La Niña / Neutral / Mixed | 6 / 4 / 14 / 6 | 9 / 7 / 13 / 1 |
| Mean welfare, El Niño years | 4.573 | 2.561 |
| Mean welfare, Neutral years | 4.558 | 2.586 |
| Mean welfare, La Niña years | 4.614 | 2.589 |
| Inter-annual standard deviation | 0.063 | 0.029 |
| Poverty headcount, El Niño / Neutral | 0.408 / 0.410 | 0.758 / 0.754 |
| Correlation of mean welfare and exposure RONI | 0.04 | -0.42 |
| Share of inter-annual variance with phase | 0.09 | 0.20 |
| El Niño years among the 6 worst | 1 | 4 (the 4 worst) |
| SSP3-7.0 mean welfare, El Niño / Neutral | 4.411 / 4.396 | 2.483 / 2.507 |

The two results are what the design should convey. In MWI the four worst simulated years are all El Niño, against a base rate of 9 in 30, and the pattern carries to the SSP rows. In BFA there is nothing to see.

Forecast window, labelling reference years by mean RONI of the target months (10 El Niño, 12 La Niña, 8 neutral):

| | BFA | MWI |
|---|---|---|
| Median member, mean welfare | 4.615 | 2.361 |
| Reference mean, all years / El Niño years | 4.776 / 4.792 | 2.365 / 2.388 |
| Reference years at least as adverse as the median member, all | 0 of 30 | 53 percent |
| Same, El Niño years only | 0 of 10 | 2 of 10 |
| Strong years (1991, 1997, 2015) | 4.897, 4.660, 4.790 | 2.425, 2.428, 2.285 |

MWI shows why the comparison is worth having: the forecast looks ordinary against all years but poor against past El Niño years, and the three strong events disagree with each other. In BFA the forecast sits below every reference year while El Niño years look like the rest, so ENSO phase does not account for that gap in the reference record. That gap may come from this default level specification, warming or the window. It is worth a look in the forecast checks, independent of this plan.

Recheck under D3 (2026-11-04, `dev/parity_enso.R --forecast`). The labels depend only on the target months and the fitted window, so BFA and MWI share them: 6 El Niño, 8 La Niña, 12 Neutral and 4 Mixed, against 10, 12, 8 and 0 for the target months alone (that count reproduces with the share rule and no lags). El Niño years: 1991, 1994, 1997, 2002, 2004 and 2015. The three strong years keep their label. The lags pull the window back before onset, so 2006 and 2009 tie at 0.50 and become Mixed, and 2000 and 2017 tie on the La Niña side.

| Median member, mean welfare | BFA 2021 | MWI 2019 |
|---|---|---|
| Value | 4.841 | 2.502 |
| Reference years at least as adverse, all | 1 of 30 | 15 of 30 |
| Same, El Niño exposure years | 1 of 6 | 1 of 6 |

These runs use `hhsize`, `electricity` and `cellphone` with a `gaul1_code` fixed effect. That is not the prototype's model, whose covariates were not kept, so the levels differ from the table above. The MWI reading holds. The BFA result moves with the specification: with the app defaults (BFA 2018 and 2021, `t` binned) the card reads 10 of 10 and 28 of 30, with the median member better than the median year.

## Design decisions

### D1. Annotation only

ENSO joins at display time, from `sim_year`, interview months and the fitted windows. It stays out of `fct_run_simulation()`, the Step 2 and Step 3 aggregation, run signatures, the aggregation cache and the async payload. A refreshed `enso.csv` then cannot invalidate a run. Parity check: Results tables identical with and without the file.

### D2. Exposure-weighted year label

For simulation year $r$, with $w_\mu$ the weighted share of baseline households interviewed in month $\mu$, and $K$ the fitted lag months:

$$s_k(r) = \sum_\mu w_\mu \frac{1}{|K|} \sum_{j \in K} \mathbf{1}\big[\text{phase}(r, \mu - j) = k\big], \qquad \text{RONI}^{\text{exp}}(r) = \sum_\mu w_\mu \frac{1}{|K|} \sum_{j \in K} \text{roni}(r, \mu - j)$$

- Label a year El Niño, La Niña or Neutral if that share is at least 0.5, otherwise **Mixed**.
- With two weather variables, $K$ is the union of their windows, from the smallest `ref_start` to the largest `ref_end`.
- Keep the shares and $\text{RONI}^{\text{exp}}$ in the table, the tooltip and the export, so users can see how clear a label is.
- Near-ties are common (on BFA 2021, 7 to 12 years have a top share within 0.05 of the threshold, depending on the lag), so the label needs its shares beside it. Unrounded shares must be used; rounding to two decimals moved BFA years across the threshold in testing.
- Labels are "El Niño exposure" in text, not "El Niño year", since a simulation year is a composite.

A strength tier (RONI of 1.5 or more) can be derived in the app. Episode rules are not needed: only 7 of 198 non-neutral months in 1991-2020 fall outside a run of five, so the `phase` column is enough and upstream need not publish `episode`.

### D3. One label per sample

| Series | Label |
|---|---|
| Historical (annual) | D2 |
| Climate scenarios | The template year's D2 label |
| Historical (same months as forecast) | D2 with equal weight on the target months as $\mu$, so the fitted window is treated the same way. The reference year is the year the window starts, so November 1997 to January 1998 is 1997 and the event is not split, as in `refyear_<year>` of `.get_forecast_weather()`. Rechecked: see the figures after the forecast window prototype. |
| Forecast members | No per-member label. One outlook for the run, below |

Guard: in window tables `sim_year` is the member index for members, so the join must skip `.step2_is_window_forecast()` rows.

### D4. ENSO outlook for a forecast run

Read `enso_forecast.csv` for the target months. Prefer the row of the same system as the weather run (`ecmwf_51` for SEAS5), so the state describes what is simulated, and fall back on `multimodel`. Show it only when `init_date` equals the run's `init`, because the file keeps only the latest initialisation. Otherwise show the months from `enso.csv` and say it is a later outlook. Probabilities are empty at the first and last lead, so a window reaching those months shows RONI only. Probabilities are shares of members, not calibrated, as for the weather members. The run's model id maps to the source in `ENSO_FORECAST_SOURCES` (`ecmwf_seas51` to `ecmwf_51`); an unmapped model uses `multimodel`.

Item 7 compares the median member with the reference years of the outlook's phase, the phase of at least half of the target months, so a La Niña or Neutral outlook is not set against El Niño years. A Mixed outlook has no comparison.

### D5. Keep the statistics modest

Show counts, means and differences from Neutral, with $n$ always visible. No p-values, no phase-specific return periods or exceedance curves (four to ten years cannot support them) and no causal wording. Hide a phase's comparison below three years. Mixed years stay in all existing results and in the table, but are not compared.

### D6. The file is optional

If either table is missing or malformed, every ENSO element disappears without an error. This matters because `OVERVIEW_METADATA_FILES` entries are required: both metadata loaders fail the whole load on one missing file, and the step is experimental upstream, not part of `all`. So ENSO needs its own soft loader rather than a new entry in that list. It needs both the sequential and the Databricks path. Validate columns, phase values and consecutive months on load.

### D7. ENSO stays out of estimation

Weather already carries the ENSO effect that the model can represent: an El Niño year enters through its local weather. Three ways of adding ENSO to Step 1 were considered and rejected.

- **Niño 3.4 or RONI as a weather variable.** It has no local variation, so it is one time series per country. The `year` fixed effect absorbs it across waves. Within a wave it is identified from a handful of interview months, and it is confounded with seasonality and anything else that moved in those months. In the 2018 and 2021 EHCVM countries only 3 to 7 percent of RONI variance is within waves; single-wave surveys have about 12 distinct months. Dropping the `year` effect would load every national shock onto it. Standard errors would need clustering by month, and Step 2 would then extrapolate to 3.35 from a sample range such as -1.26 to 0.82 (BFA).
- **Weather by ENSO interaction.** Better identified, since local weather varies within a phase, and the question is meaningful: does the same weather do more harm in an El Niño? But phase is often the same as wave, so the term mostly measures a difference between waves. Only 26 of 72 waves have 15 to 85 percent El Niño interviews, and a same-weather response need not differ. It would also change the protected model and simulation path. Keep as an offline robustness check where a wave spans phases (IRN, VNM, IND, COL), and as a test of the stable-response assumption.
- **Training on one phase.** It discards most of the sample, removes the weather variation the response needs, and is impossible for the 9 countries without El Niño interviews. It is the wrong way round: more weather variation is what makes ENSO years valid to simulate.

### D8. No ENSO control in the simulation settings

All years are simulated anyway and labels need no inputs, so a selector in Step 2 settings would add nothing to the run. Filtering the historical years at run time would do harm:

- The window is a contiguous range, and it also sets the climate baseline $P_0$ of the delta method, so a filter would move SSP results.
- Return periods, exceedance curves and the Historical baseline would be rebuilt on 6 to 10 years, and on 3 or 4 strong ones.

Selecting years is a view of existing results: the section table and the toggle in the Results tab. A Results filter that rescales every chart is rejected for the same reason. One addition costs no control: when the window holds few events, the section note says so and names what a wider window adds. The default 1991-2020 has 4 events peaking at 1.5 or more; 1950-2025 has 8. Widening also moves the baseline, as it does today.

## Where it goes

### First version

| # | Surface | Change | Why |
|---|---|---|---|
| 1 | Step 1 Survey stats, under "Timing of interviews" | One sentence per wave: share of households in each phase and highest RONI. Information, not a warning | Shows when the sample was fielded. The chart's table has only `month_num`, so compute from the survey `timestamp`, not from `summarise_interview_dates()` |
| 2 | Step 2 and 3 Results, distribution chart | Pill toggle "Mark ENSO years", default off. Flagged dots get more opacity, a phase colour and a symbol; Neutral and Mixed stay as they are; tooltip gives year, shares and RONI | The existing chart already plots one dot per year. Shared builder `echart_step3_annual_distribution()`, so Step 3 is nearly free. Violins do not change |
| 3 | Step 2 Results, new section after the distribution: "How do outcomes compare in El Niño and La Niña years?" | One `reactable`: rows are series, with columns for $n$ and mean per phase and the difference from Neutral; CSV button. One generated sentence below, for example "4 of the 6 most adverse years were El Niño; 9 of 30 years are" | The direct answer to the question. A table adds one block instead of a chart per phase |
| 4 | Step 3 Results, the same section | Adds Baseline, Policy and effect columns, from the annual pairs in `paired_model_year_effects()` | "Does this policy help more in El Niño years?" is the question a policy reader has |
| 5 | Step 2 Diagnostics, weather-year trajectories | Background bands by label in `echart_timeseries_spaghetti()`, phase in the tooltip | The one chart with a year axis. Shading fits it with almost no cost |
| 6 | Step 2 Diagnostics, weather support section | One line: share of weather outside the fitted support in El Niño and in La Niña years, from the existing `weather_support_*` functions | Weather support, not interview phase, is the check that matters. Needs the rows split by label, which the check does not do today |
| 7 | Forecast cards, target-month group | One line added to the placement text: the outlook (D4) and the median member against the El Niño reference years, with $n$. In the Step 2 and 3 distribution, toggle 2 also marks these years | With El Niño near certain, all reference years are not the fair comparison. It qualifies assumption A5 of `docs/34_seasonal_forecast.md` |
| 8 | Exports and batch | Year label table in the export bundle. Batch: an `enso_years` table keyed by `sim_id` and `sim_year`, and an `enso` section in `summary`. Provenance records the file hash, last `cpc` month and forecast `init_date` | `enso.csv` history is not frozen, so a number needs its table version. Build as a separate target so a refresh does not rerun simulations. Leave the file out of `metadata_digest` |

Total for a user: one new section, one toggle, three short text lines, and shading on a Diagnostics chart.

### Second version, after feedback

- **Forecast flyout outlook.** A phase mark per month on the strip (`forecast_strip_input()`) with the RONI in its tooltip. Left out of the first version because `R/mod_2_01_weathersim.R` is being edited now.
- **Is ENSO relevant here?** In the new section, the correlation of the run's own simulated weather with $\text{RONI}^{\text{exp}}$, so a flat result reads as "ENSO barely reaches this weather in these months" and not as "ENSO is harmless". It could also warn when the fitted window misses the season of strongest response.
- **Exceedance tooltip.** Weather year and label on hover. The rows hold rank and value, so the year has to be carried through.
- **Shock-responsive transfers.** Payout frequency and cost by phase, from `shock_activated` and `shock_total_cost` per year: does the programme pay in El Niño years, and what would one cost?
- **Residuals by phase** in Step 1 Model fit, only when a sample has at least two phases within a wave.

### Later ideas

- **Row-level phase estimate.** Pool household-year rows by the phase of each row's own exposure, then standardise to the survey's interview months: $T_k = \mathcal{A}(\lbrace Y_i^{(r)}, w_i / n_k(\mu_i)\rbrace)$ over the years $r$ of phase $k$ for $\mu_i$. This removes the Mixed class and the split of events across simulation years, and it works for poverty and inequality metrics directly. It needs a new aggregation with its own uncertainty, and a methods review. Not prototyped. Build it only if the year labels prove too coarse.
- **ENSO analogue scenario.** "Past El Niño years" as a selectable series for countries with no forecast (COL, DOM, LKA and TJK now) or beyond the forecast horizon.
- **ENSO composite map.** Mean weather anomaly in El Niño months against neutral months, with `summarise_weather_anomaly_by_loc()` and the MapLibre bridge. Striking, but it adds a view to an already full tab.
- **ENSO-based triggers** for shock transfers. Anticipatory designs are already rejected with a forecast, so this is a policy decision first.
- **Forecast members by own RONI.** Upstream holds it per member. No use while every member is El Niño.

### Left alone on purpose

Adverse-year dots, return-period table and exceedance curves (no conditional tails, D5), uncertainty bars, model coefficients and specification tables, weather maps, decomposition, cost-effectiveness and the Overview tab.

## Wording to carry

These go in the section note, the info popover and `docs/`.

- Labels describe the ENSO state of the months that enter the model for each household. A simulation year is a composite, not a real year.
- Differences reflect only the selected weather variables and months, through the fitted response. Prices, markets, fisheries, health, floods and other ENSO channels are not modelled. A small difference does not mean ENSO has a small welfare effect.
- The model learns from weather, so it can simulate El Niño years it did not observe, as long as their weather lies in the fitted range. Its response comes mostly from local differences, so it may understate a widespread shock.
- Few events fall in a window: 6 El Niño exposure years in 30 and 3 strong ones, for November to January with months 1 to 6. They differ from each other. Past events are not a forecast.
- Climate scenarios keep the observed ENSO sequence. Changes in ENSO under warming are not represented.
- The index is relative Niño 3.4 (RONI). It flags fewer El Niño months than the traditional ONI in recent decades and may differ from figures in the press.

## Implementation plan

### Phase 0: now, no conflict with the forecast work

1. New `R/fct_enso.R`, Shiny-free, with tests in `tests/testthat/test-fct_enso.R`. Proposed functions: `enso_load()` (soft loader, D6), `enso_window()` (union of the fitted windows), `enso_year_labels()` (D2), `enso_sample_coverage()`, `enso_phase_summary()` and `enso_forecast_outlook()` (D4).
2. A small fixture CSV pair and a variant of `batch_fixture_tree()`.
3. Requests to `wise-app-data`, below.

### Phase 1: after the forecast finishes

Merge `enso` into `seasonal-forecast` first (branch plan under Progress). `R/mod_2_02_results.R` and `R/fct_policy_sim_compare.R` will take most of the ENSO changes.

1. Load ENSO once per session and expose it from the Overview API.
2. Items 1, 2, 3 and 5 for Historical and SSP rows.
3. Item 4 (Step 3), then item 6.
4. Check on MWI (signal) and BFA (none) with `dev/ui_drive.R`, including a run with the file removed.

### Phase 2: forecast and outputs

1. Item 7, with the D3 reference labels and the D4 outlook.
2. Item 8: export, batch table, summary section and provenance.
3. New methods page `docs/35_enso.md`, a note in `docs/10_data.md`, `docs/30_simulation.md`, `docs/31_climate_scenarios.md`, `docs/34_seasonal_forecast.md` and `docs/50_assumptions_limitations.md`, `batch/docs/tables.md`, and a contract line in `ARCHITECTURE.md`.

### Checks

- Year labels: hand-worked cases for a window crossing December, two variables with different windows, a pooled multi-wave baseline, a lag reaching before 1950 (label `NA`) and a tie at 0.5.
- `all.equal(tolerance = 0)` on the Step 2 and Step 3 tables with and without ENSO, on BFA and on the fixture: this is what shows D1 holds and no Decision log entry is owed.
- Missing, empty or malformed file on the local path and on a mocked Databricks path.
- Toggle: dot counts unchanged, series ids `draws|<scenario>|<source>` still valid for chart updates, and forecast member rows not labelled.
- Colours against `.ssp_colours`, `.wise_policy` and `.wise_forecast`, with symbols as well as colour, and an axe pass in `tests/e2e/smoke.R`.
- Before the deploy: `Rscript dev/00_make_manifest.R` for the new R file, per the branch rule on doing this last.

## Requests to `wise-app-data`

Done: `dev/cmip6_enso_plan.md` now records that no CMIP6 ENSO table is needed (uncommitted). Still open:

1. Promote observed ENSO into `all`, or at least to the production data root, and add `validate` checks. Once the app reads the files, the schema is a contract. The app's flags do not depend on the forecast pilot, so they work on Posit Connect once the PR is deployed, if the file is on that data root.
2. Correct `dev/enso_plan.md`: it says ONI is published next to RONI, but `enso.csv` has no `oni` column. The app does not need it, though a comparison with press figures would.
3. Fill the probabilities at the first and last lead if possible (already an open item upstream).

## Open decisions

1. **Toggle default.** Decided for now (2026-11-04): off, so the current chart stays unchanged. On would give more visibility while the event is news.
2. **Headline card.** Decided for now (2026-11-04): none in the annual group. One card "El Niño exposure against Neutral" would add visibility at the price of a busier row. Revisit if users miss the section.
3. **Year rule.** Decided for now (2026-11-04): majority share with a Mixed class. The alternative, $\text{RONI}^{\text{exp}}$ at plus or minus 0.5, has no Mixed class but labels a year El Niño on a few strong months.
4. **Release order.** Decided (2026-11-04): together, in one PR with the forecast. Annual flags work on Connect; the forecast stays local only.
5. **Forecast outlook source.** Decided (2026-11-04): the system of the run, as in D4, because it describes what is simulated. The multi-model mean is the fallback. Keep the two published tables: `enso_load()` reads both and they have different shapes (one row per month, and one row per model and month), so merging them upstream would gain nothing.
