# Continuous RONI: Phase A report

Status: Phase A complete. Outcome (b), diagnostic only, was approved and built on `dev`; the predictor was not started. Current state and open items are in `roadmap/enso_predictor.md`, "State and decisions".

Addendum after the report: the same diagnostic was prototyped on VNM (7 waves). Mean welfare against exposure RONI gives Spearman rho 0.59 (Historical annual) and 0.60 (SSP), slope +0.055 $/day per RONI unit, and a monotone phase ordering (El Nino 16.62, Neutral 16.57, La Nina 16.51 $/day). The $3 headcount is nearly flat (rho -0.29). BFA is near zero (about 0.03). The same-window series and the forecast point could not be built for VNM because the forecast pipeline stopped on missing forecast predictor months (since fixed: coastal locations without weather are no longer required). This does not change the recommendation, because the inference question in A2 is unchanged.

This report merges four investigations (A1 data, A2 identification and inference, A3 simulation paths, A4 diagnostic). Each ran as a read-only worker; the detailed reports and scripts are in the session scratchpad (`A1_data_feasibility.md`, `A2_identification.md`, `A3_simulation_paths.md`, `A4_diagnostic.md`). The findings below come from those reports and have not all been re-verified by a second reader.

## A1. Data feasibility

- `metadata/enso.csv` has 928 monthly rows with no gaps: CPC observed 1950-01 to 2026-09, one ERA5 month, and six forecast months. The `source` column is the only marker separating observed from forecast.
- Observed CPC RONI covers every survey interview and all lag months 0 to 12 for all 72 surveys, with no missing months. No new upstream data preparation is needed.
- Each CPC value is a centred 3-month mean, so lag 0 includes the following month. Only lags of 2 or more are fully before the interview.
- `enso_year_labels` does not filter on `source`, so it would read forecast and ERA5 months as observed. A household-level build needs an explicit CPC-only guard.
- Household exposure is buildable from the interview timestamp, but needs a timestamp-keyed join, not the location-keyed weather lag machinery. Interview month is not imputed upstream; 0.13% of rows across all surveys lack it.
- The existing exposure-weighted RONI (`roni_exp`) is one value per simulation year and is not household-level exposure. It is reusable for diagnostics only.

## A2. Identification and inference

The app's fixed effects are survey year and first-level region, additive. It has no interview-month control, and standard errors cluster on the location panel.

- **Support is thin in small surveys.** BFA has 2 waves, 18 interview year-months and 3 ENSO episodes. MWI has 40 year-months and 5 episodes; VNM has 53 and 8.
- **BFA's RONI variation is mostly between waves.** After survey-year fixed effects, 4 to 5% of lag 0-0 and lag 1-3 variance remains (25% for lag 0-12). In MWI and VNM, 62 to 82% of the lag 1-3 variance remains.
- Year-month fixed effects absorb RONI exactly, as for any global monthly predictor. A calendar-month effect alone leaves most variance, but with only one wave it would equal a year-month effect and absorb everything. A single-wave survey was not tested.
- **Overlap with local weather is not the binding problem.** VIF is mostly below 1.1; the exception is BFA lag 0-12 against the temperature term (VIF 1.78).
- **Geography matters at location level.** Region fixed effects absorb almost none of the within-wave RONI variation (at most 1%), but 47 to 55% of it in BFA is between location panels, because enumeration areas are visited in specific months.
- **Location clustering is not adequate for a shared global monthly exposure.** For BFA lag 1-3, standard errors are about 2.0 times larger when clustering on interview year-month, 2.0 to 4.1 times larger under Newey-West, and 4.2 to 6.5 times larger under a moving-block bootstrap. Monthly RONI has lag-1 autocorrelation 0.97, which gives an effective number of independent periods below 1 for BFA and about 2 for MWI and VNM.
- In VNM, lag 1-3 is significant under the app's clustering (t about -2.4), but the year-month SE is 1.8 times larger and the bootstrap interval includes zero.
- Caveats from the worker: only one lag configuration was run; IRN's Step 1 run did not finish; the bootstrap is unstable with two waves.

## A3. Simulation paths

| Path | Supportable | What it needs |
|---|---|---|
| Historical, lags crossing years | Yes | Observed-only (CPC) months and a coverage check. Step 3 stops on any NA exposure that Step 2 tolerates. |
| Future scenarios from template years | Yes, as an assumption | A "none" perturbation method for RONI, RONI kept out of `delta_vars`, and wording that scenarios hold ENSO at the template sequence (consistent with D8). |
| Seasonal forecast | Gate | Existing checks already block it; add a RONI-specific message and a test. |
| Step 3 static policy | Yes, main effect only | `fit_model` must not interact RONI with moderators, and RONI must be excluded from shock triggers. |
| Uncertainty | Yes, if in `weather_terms` | Otherwise `attach_active_mask` cancels its coefficient uncertainty silently. Standard-error fallbacks hard-coded to location clustering would silently undo any better inference. |
| RIF engine | Gate for a first version | Not traced end to end. |

Cache and identity: RONI would need the ENSO table hash added, only when RONI is selected, to the Step 1 fit signature, Step 2 live and stored signatures, a worker snapshot recheck, the prepared-weather and weather-store signatures, provenance and exports for Steps 1 to 3, and the batch spec and digest. Two existing gaps: `WISEAPP_WEATHER_DATA_VERSION` is undocumented and defaults to "unknown", and the batch `metadata_digest` deliberately excludes ENSO. Adding a RONI row to the weather list would also change the ENSO label window and make the relevance check correlate RONI with itself; both need exclusions. Protected areas touched: Step 2 numerics (`fct_step2_run.R`, `fct_step2_compute.R`), async code, and the exported contract surface. A silently dropped collinear RONI term in fixest needs an explicit check.

## A4. Continuous-RONI diagnostic

Feasible and small. `enso_year_labels()` already returns the continuous exposure `roni_exp`, and `enso_attach_labels()` already carries it onto result rows.

- Annual and same-window series must stay separate (BFA ranges: annual -1.09 to 1.21, same-window -1.36 to 1.83).
- SSP scenarios reuse the historical ENSO sequence, so they are a shifted copy and must not be pooled as new observations.
- Forecast members share one outlook RONI (about 3.1 in the prototype, far above the historical maximum). They can appear only as a separate strip and never in a fit or correlation.
- Placement: the Step 2 "ENSO exposure years" card, and the Step 3 ENSO section. Files: `R/fct_enso.R`, `R/fct_step2_compare.R`, `R/mod_2_02_results.R`, `docs/35_enso.md`, with tests in `test-fct_enso.R`.
- On the BFA prototype the descriptive Spearman correlations are about 0.02 (n = 30 per series), consistent with the existing phase table.
- Labelling: the relationship between ENSO exposure and local-weather-mediated simulated outcomes, not an independently estimated ENSO effect, and a flat result does not mean no ENSO effect. No p-values or bands.
- No numeric change, so no Decision log entry.

## A5. Recommendation

**Recommend (b): diagnostic only, with D7 standing for estimation in the current build.**

Reasons:

1. The argument that reopened D7 is partly right. RONI does vary within survey years, and in multi-wave surveys (MWI, VNM) most of it survives the actual fixed effects. For BFA, the default test case, 75 to 95% of lag 1-3 and lag 0-0 variance is absorbed or sits between two waves of opposite sign.
2. The inference problem is not yet solved. Every time-aware SE is larger than the app's, by 2 to 6 times in BFA, and the effective number of independent periods is about 2 or fewer. A coefficient reported under location clustering would overstate precision. A defensible alternative needs a design decision of its own (A3 shows the SE fallbacks are hard-coded in five places).
3. The cost is high and sits in protected areas: a new weather-row type, a perturbation method, signature and provenance changes across Steps 1 to 3, batch changes, and a numeric Decision log entry, all for a predictor that two of the four simulation paths must gate or treat as an assumption.
4. The diagnostic answers the second question in the brief at low cost and without changing any number.

What would change this recommendation: a multi-wave target survey where the time-aware intervals exclude zero and are stable across lag windows, plus approval of a specific inference treatment (year-month clustering is the simplest candidate).

If you prefer to keep the predictor option open, a middle path is to build the diagnostic now and write the predictor plan as a separate roadmap item gated on the inference decision.

## Open items

- `R/fct_enso.R` change committed separately as `1801344` (unrelated bug fix).
- A2 did not report the t and r coefficients from the RONI-augmented BFA run, and did not test a single-wave survey.
- A3 did not trace the RIF engine end to end.
