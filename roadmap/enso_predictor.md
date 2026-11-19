# Continuous RONI in WISE-APP

Status: Phase A done (report in `roadmap/enso_predictor_report.md`). Outcome (b) chosen: diagnostic only, built on `dev` for Step 2 and Step 3. The predictor is not built; see "State and decisions" at the end.

Task: assess whether the prepared monthly ENSO data can support RONI as an optional model predictor, and implement a defensible, bounded version only if the evidence supports it. Separately, assess a continuous-RONI diagnostic for the existing simulated results.

Follow AGENTS.md and the relevant skills (`wise-numeric-change`, `wise-verify`, `wise-ui-check` if implementing). Do not commit, push, deploy or upload.

## Objective

Two questions, kept apart:

1. **Observed welfare association.** How does household welfare vary with continuous ENSO exposure during the months before interview, conditional on the selected controls?
2. **Existing simulation diagnostic.** How do outcomes already simulated from local weather vary across the full range of ENSO exposure, rather than only El Nino, La Nina and neutral groups?

The current phase comparisons answer the second question coarsely. They do not estimate an ENSO-welfare relationship from observed welfare. Attribution to food prices or any other mechanism is out of scope.

## Starting point: decision D7

`review/archive/enso.md` (the archived first ENSO version) settled that ENSO is a display label only. D7 rejected RONI in estimation for three reasons: RONI has no local variation, the `year` effect absorbs it, and its sample range (about plus or minus 1) makes extrapolation unsafe (the forecast reaches 3.35).

This task reopens D7 on one specific argument: RONI is monthly, so it varies within a survey year through interview month and lag months. The investigation must show whether that variation survives the actual fixed effects and lag aggregation. If it does not, D7 stands and the report says so. Do not reopen D1 (display label) or D8 (no CMIP6 ENSO table, no ENSO control in Step 2 settings).

## Phase A: investigation (no code changes)

Read: `docs/35_enso.md`, `R/fct_enso.R`, `review/archive/enso.md`, `docs/20_model_specification.md` and the model-fitting code, `docs/12_weather_measures.md`, `docs/30_simulation.md`, `docs/34_seasonal_forecast.md`, `ARCHITECTURE.md`. Inspect `../wise-app-data` as needed, following its instructions, and do not modify it. Never read credentials or `.Renviron`. Real data is read from R through `WISEAPP_DATA_PATH`.

Scratch scripts go in the session scratchpad. The product of this phase is a written report. **Stop after the report and wait for approval before any implementation.**

### A1. Data feasibility

Verify the actual schema, provenance and coverage of the prepared monthly RONI tables, and how the app loads them. Determine:

- Whether observed monthly RONI covers the survey interviews and all required lag months.
- How observed values are distinguished from forecast extensions. Forecast RONI must never be used as observed training exposure.
- Whether interview year and month and the current lag machinery can build household-level RONI exposure.
- What is possible when interview month is unavailable or imputed.
- Whether the existing exposure-weighted RONI calculation can be reused for diagnostics. A simulation-year aggregate is not household-level estimation exposure.
- Whether any new upstream data preparation is needed. Use existing prepared data where possible.

### A2. Identification and interpretation

RONI is global and varies monthly. Survey-year fixed effects do not necessarily absorb its within-year variation, but they may. Evaluate the actual support in representative samples, preferably BFA:

- Distinct interview periods, survey waves and ENSO events represented.
- Variation in lag-aggregated RONI, and what remains after the selected fixed effects and interview-month controls.
- Sensitivity to survey geography being correlated with fieldwork timing.
- Collinearity with the existing local weather predictors.
- The difference between calendar-month, survey-year and year-month effects. With one survey year, calendar-month effects can absorb a global monthly predictor entirely when exposure is set only by interview month.

Households are not independent ENSO information. Exposure is shared by everyone interviewed in the same period, and RONI is serially correlated. Check whether the current location-clustered inference is adequate. Candidate treatments to compare: clustering on interview year-month, and a serial-correlation-robust alternative. Do not present conventional significance claims without a defensible treatment of shared temporal exposure.

Explain the two readings:

- RONI replacing local weather predictors: a broader conditional ENSO-welfare association.
- RONI alongside local weather: an additional association conditional on those weather measures.

Neither is automatically causal.

### A3. Simulation implications

Adding an estimation predictor needs more than a column in the fitting data. For each path, state whether RONI can be supported coherently and what it would take:

- Historical simulations, including lag windows that cross calendar years.
- Future climate scenarios built from historical template years.
- Seasonal forecast windows.
- Step 3 policy simulations and uncertainty calculations.

The forecast ENSO outlook is not a member-aligned RONI trajectory. Do not invent a correspondence between weather ensemble members and ENSO-index members, and do not silently apply one deterministic index path. If a path cannot support the predictor, gate it with a clear reason rather than substituting values. For a first version, the default is to gate the seasonal forecast and Step 3 paths unless the report shows a coherent treatment.

The ENSO tables are currently annotation-only and do not invalidate simulation caches. If RONI becomes a numerical input, trace the changes to data identity, cache invalidation, exported run records and reproducibility. Runs that do not use RONI must keep the annotation-only behaviour.

### A4. Continuous-RONI results diagnostic

Assess a plot or table relating simulated outcomes to continuous, exposure-weighted RONI. Reuse the existing exposure definition, not annual calendar averages. Keep annual results and same-window historical references distinct. Do not treat forecast ensemble members as independent historical ENSO observations. Label it as the relationship between ENSO exposure and local-weather-mediated simulated outcomes, not an independently estimated total ENSO effect. Avoid an elaborate statistical layer.

### A5. Report and recommendation

Return a concise report with concrete evidence from the code and representative data:

- data feasibility, identification limits and inference adequacy;
- per-path simulation support;
- a recommendation: (a) experimental predictor plus diagnostic, (b) diagnostic only, or (c) neither, with D7 standing.

Outcome (b) is an acceptable result, not a fallback. Do not force a predictor through if estimation support or inference is inadequate.

## Phase B: implementation (after approval)

Scope is set by the approved recommendation. If a predictor is approved, expose RONI as an experimental global climate-index predictor, not unqualified among local weather variables:

- Continuous monthly RONI aggregated over a user-selected lag window, linear exposure initially.
- No local-anomaly transformation, since RONI is already a standardized global index. Reuse existing transformations only where meaningful.
- Clear handling of missing months, unsupported specifications and absorbed predictors.
- A warning or diagnostic when temporal support is weak.
- A note that a common coefficient hides ENSO effects that differ across places and seasons.
- No new modelling framework, interaction catalogue or forecast system.

### Verification and deliverables

- Test monthly alignment, lag boundaries, missing coverage, observed/forecast provenance and predictor absorption.
- Test historical and scenario construction, reproducibility and cache identity where affected.
- Show unchanged numerical results when RONI is not selected.
- Follow `wise-numeric-change`: BFA before/after numbers and a Decision log entry in `review/TRACKING.md`.
- Update `docs/35_enso.md` and the other affected methods pages, with `verified_against`. Run `Rscript dev/docs_check.R` and the relevant tests.
- Verify UI changes in the running app (`wise-ui-check`).
- Keep this file's state and decisions current as the work proceeds. When the feature is built, archive it to `review/archive/` per `roadmap/README.md`.
- Final report: data feasibility, identification limits, implementation decision, changes made, verification results, remaining restrictions.

Seek clarification only for consequential choices that cannot be resolved from this brief and existing conventions.

## Delegation plan

Ground rules for every worker: Phase A is read-only apart from scratch files in the session scratchpad. Do not read `.Renviron`, commit or push. Return findings as a file with `file:line` evidence, naming the paths and functions read. Real data is read from R through `WISEAPP_DATA_PATH`. The Phase A report goes to `roadmap/enso_predictor_report.md`. Workers report numbers; the recommendation in A5 stays with the main thread.

### Phase A

- **A1 data feasibility.** Schema, provenance and coverage of the monthly RONI tables; observed versus forecast rows; interview month and lag machinery, including missing and imputed months; reuse of the exposure-weighted RONI calculation; any upstream data needs.
- **A2 identification and inference** (after A1). On BFA: distinct interview year-months, waves and events; lag-aggregated RONI variance before and after the actual fixed effects and interview-month controls; correlation with local weather predictors; SEs clustered on location, on interview year-month, and a serial-correlation-robust alternative.
- **A3 simulation paths.** For historical, scenario, seasonal forecast and Step 3 paths: where an estimation predictor is consumed, whether RONI is supportable (yes, no, gate), what it needs; cache keys, run records and exports.
- **A4 diagnostic.** What a continuous-RONI results diagnostic reuses, where it sits, and a scratchpad prototype on BFA results if feasible.
- **A5 synthesis** (main thread). Merge A1 to A4 into the report, recommend (a), (b) or (c), then stop for approval.

### Phase B (after approval, on a branch off `dev`)

- **(c) neither:** record the evidence that D7 stands in `review/archive/enso.md` and `docs/35_enso.md`; run `Rscript dev/docs_check.R`.
- **(b) diagnostic only:** B1 Shiny-free `fct_*` function and tests; B2 UI card (after B1); B3 docs; B4 `wise-ui-check`.
- **(a) predictor plus diagnostic:** B1 to B4, plus B5 predictor core (lag aggregation, observed-only guard, absorption handling); B6 inference change if A2 shows location clustering is inadequate; B7 path gating and cache and run-record identity; B8 `wise-numeric-change` (BFA before/after, Decision log); B9 regression test that runs without RONI are unchanged. B5 to B7 touch protected areas: run them sequentially, each reviewed before the next.

The earlier open point on `R/fct_enso.R` is resolved: its uncommitted change was an unrelated bug fix, committed separately as `1801344`.

## State and decisions

Decisions:

- **Outcome (b), diagnostic only.** D7 stands for estimation. Reasons are in the report: BFA's RONI variation is mostly between two waves of opposite sign; time-aware standard errors are 2 to 6 times the app's location-clustered ones in BFA; the predictor would touch protected areas and every cache and provenance signature. VNM (7 waves) shows a visible relationship in the diagnostic (Spearman rho about 0.6 for mean welfare), but VNM's lag 1-3 result is not stable under year-month clustering or a block bootstrap, so it does not settle the inference question.
- **The existing phase table stays.** The diagnostic is added below it in the Step 2 "ENSO exposure years" card. Replacing the phase contrast with the diagnostic is a possible follow-up once the diagnostic has been used; it was not done.
- D1, D7 and D8 are unchanged.

Built on `dev`:

- `enso_roni_table()`, `enso_roni_stats()`, `enso_roni_stats_text()`, `ENSO_PHASE_COLOURS` and `.ENSO_RONI_NOTE` in `R/fct_enso.R`; `echart_enso_roni()` in `R/fct_step2_compare.R`; the card block and reactive `enso_roni_rv` in `R/mod_2_02_results.R`; tests in `tests/testthat/test-fct_enso.R`; `docs/35_enso.md` Section 9 and the regenerated `docs/index.yml`.
- Verified: `fct_enso` (405 passes), `fct_step2_compare` (31), `mod_2_02_results` (553), `dev/docs_check.R` and `dev/agents_check.R` clean, and a headless-Chrome run of BFA defaults through Step 1 and Step 2 with no client or server errors.
- No numerical output changes, so no Decision log entry in `review/TRACKING.md` was needed.
- Step 3 (decision: the policy effect, not baseline and policy as two series, because the baseline repeats Step 2): `enso_roni_effect_table()`, `.ENSO_RONI_EFFECT_NOTE` and `enso_roni_key_ui()` (shared with Step 2) in `R/fct_enso.R`; a block under the policy comparison by label and the export "Policy effect against exposure RONI" in `R/fct_echart_builders.R`; `docs/35_enso.md` Section 9.
- A series whose value varies only by rounding (a uniform policy effect, as with a fixed transfer and the mean) is `flat`: no rho or fit line, a sentence instead, and drawn at its mean. Before this, BFA's mean effect showed a rho of -0.05 on noise of 1e-17. The chart has its own rate axis formatter (three decimals), because effects of hundredths of a point folded into one tick label.
- Verified: `fct_enso` (439), `fct_step2_compare` (31), `mod_2_02_results` (553), `mod_3_07_results` (160), docs and agents checks clean; headless Chrome on BFA defaults through Step 3 ($1 transfer) with Mean (flat) and Poverty rate (rho -0.24), the Step 2 chart, and both CSVs in the tables zip; no client or server errors.

What remains:

- Check the cards with VNM data in the running app.
- Same-window series and the forecast strip for VNM: the forecast stopped with "Forecast predictor months are missing for selected locations." Fixed in `.get_forecast_weather()` (`R/fct_forecast_weather.R`): 220 coastal ERA5-Land cells are all NA and absent from the run file, so 54 to 62 locations per VNM wave have no weather; the builder now requires only locations with observed weather (see `docs/34_seasonal_forecast.md` Section 2). Check the VNM ENSO cards with a forecast in the app.
- Regenerate `manifest.json` in the PR into `dev`, as in the other ENSO work.
- Archive this plan to `review/archive/` per `roadmap/README.md` when the work is finished.

Predictor (not started; separate item):

- Gate: choose a time-aware inference treatment first. Year-month clustering is the simplest candidate; a Newey-West or block-bootstrap check is the alternative.
- Cheap experiment before any build: fit VNM with RONI as a predictor and year-month clustered standard errors, and check whether the interval is stable across lag windows.
- If it proceeds, the A3 findings in the report apply: CPC-only guard, a weather row marked as an index, a "none" perturbation method, main effect only in Step 3, forecast and RIF gated, and the ENSO table hash added to signatures only when RONI is selected. Numbers move then, so `wise-numeric-change` applies.
