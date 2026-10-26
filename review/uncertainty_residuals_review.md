# Review: sources of uncertainty, residual treatment and their presentation (Steps 1 to 3)

First written 2026-10-25 against commit `0f9afde` as a desk review. Extended the same day against commit `2af403d` (branch `dev`): the scope now covers every source of uncertainty the app reports or omits, and each finding has been checked on real data (`WISEAPP_DATA_PATH`, local) with the results recorded under the finding. No code was changed. Methods pages that describe the area: `docs/30_simulation.md` (Section 4), `docs/32_metrics.md` (Section 5), `docs/33_uncertainty.md`, `docs/40_policy_framework.md` (Section 5), `docs/44_decomposition.md`, `docs/45_cost_effectiveness.md`, `docs/50_assumptions_limitations.md`.

## Task for the implementing agent

1. Each finding now carries a status ("Verified", "Partly refuted", "Refuted") with the evidence. Re-run the evidence on your branch before you change code (see Appendix A for how the runs were built). Findings marked "check" have not been verified.
2. Fix only verified findings, in the order of the priority table. Surgical diffs; follow `review/code_hygiene.md`. Every decision is closed (see "Decisions" below); do not reopen them.
3. Update the methods pages that the change touches, including their `verified_against` front matter and Implementation maps (`dev/docs_check.R`, `dev/docs_index.R`). Regenerate `manifest.json` if shipped files change (`dev/00_make_manifest.R`).
4. Tests go in `tests/testthat/test-<R file>.R`. Run the narrow tests for each file touched, then `devtools::test()` before finishing. Do not commit or push unless asked.
5. Record the outcome in `review/REVIEW-2026-10-06-tracking.md`, or keep the status lines of this file up to date.

## Phase plan (implementation, 2026-10-26)

Phase 0 evidence; 1 F0; 2 F8; 3 F2, F1, F9; 4 F3 and F6 (UI, then `tests/e2e/smoke.R`); 5 docs (F4, F5, F7 stale lines, F8 doc lines, F9 if docs only, F10); 6 the two F7 checks; **7 (added 2026-10-26 by the repository owner): remove the unreachable "normal" residual rule** (the `normal` branches of `draw_residuals_vec()`, `predict_outcome()`, `aggregate_with_uncertainty_delta()` and the `step2_compute()` validation, the tests that exercise it, and the docs), with the determinism suite re-run. The app offers only "original" and "resample" (and "none" internally for RIF and demotions); Phase 3 to 6 keep the "normal" branch untouched.

## Decisions (closed 2026-10-25 by the repository owner)

| Finding | Decision |
|---|---|
| F0 | Composite key (columns chosen after checking uniqueness in the real data). Assert that the key is unique in `train_aug`; if it is not, fall back with a warning. Add matched and unmatched household counts to the Step 2 data-quality notice and to the provenance record. |
| F1 | Option (a): a difference from the median historical year adds that reference year's `var_resid` to the contrast variance. `docs/33_uncertainty.md` Section 8 explains why residual variance stays for a difference from the mean and goes for same-year and year-averaged contrasts. |
| F2 | The Diagnostics coefficient bar keeps following the active reference and is labelled by it ("level" or "difference from the historical mean/median"). `var_resid` becomes its own list-column and its own bar; the batch `sd` column is unchanged. |
| F3 | Option (a): remove "Include uncertainty on all covariates" from the Step 2 UI. Keep the batch field `propagate_all_covariate_uncertainty` as an accepted no-op with a deprecation note, so saved configs still load. Explain the rule-dependent level band in the residual-rule popover and the Diagnostics text. |
| F4 | Docs and popover only (`docs/33_uncertainty.md` A7, `docs/50_assumptions_limitations.md`, residual-rule popover). No new residual rule. |
| F7 | Run the 20-seed check of the shock-responsive draws, record the spread, and state in `docs/43_shock_responsive_sp.md` that the bands exclude it. No code change this round. |
| F9 | Closed form `sum(w~_i^2 p_i (1 - p_i))`, with `p_i = P(y_i + e < log z)` from the residual distribution, if it is simple and a test against the Monte Carlo passes; otherwise document the approximation in `docs/33_uncertainty.md` A1. |
| F10 | Docs and the threshold-table popover only. No bootstrap. |

## Assessment in brief

**Is the methodology reasonable?** Yes in its core. The delta method with a clustered covariance, the anchored loading under the "original" residual rule, the block Cholesky of the active covariance, the paired contrasts through the aggregate gradient `F_agg`, the common random numbers across scenarios and arms, and the law-of-total-variance pooling over climate models are all standard and correctly implemented. On real BFA data the analytic coefficient SDs agree with a Monte Carlo over coefficient draws to within 8 per cent for the mean, the poverty rate and the Gini in levels and in most paired contrasts; the worst case is a small poverty-rate contrast, 17 per cent below the Monte Carlo (Appendix B, Table B3). The analytic residual SD under "resample" agrees with a Monte Carlo over residual seeds for the mean and the Gini.

Three defects change reported numbers materially and come before any of the presentation issues:

- **F0.** The "original" rule matches a household to its training residual by `hhid` alone. Household ids repeat across survey rounds and across countries in the real data, so in multi-round samples most baseline households receive another row's residual. In BEN (2018 + 2021) this applies to 87 per cent of the baseline households, and the simulated historical Gini is 0.378 against 0.341 with the household's own residual (observed: 0.343).
- **F8.** For a logistic model the coefficient loading is on the link scale but the gradient treats it as a probability change: the factor `p(1 - p)` is missing. The coefficient SD of a rate is about five times too large (BFA, agriculture employment: 0.50 against 0.10 by Monte Carlo).
- **F1 (revised).** The original claim that contrast bands under "resample" are too wide is mostly refuted: for a year minus the historical mean, the residual noise of the scenario year does not cancel, and the code is right to keep it. It is wrong for the "median" reference, where the reference year's own residual noise is left out (band too narrow by about the square root of 2 under "resample").

**Is it clear?** Partly. The methods pages are precise, but the app labels and some pages describe what is computed in a way that leads a user to the wrong reading: the "coefficient" bar of the Diagnostics includes residual variance and changes with the "difference from" toggle (F2), switching the residual rule changes the coefficient band five-fold (F3), the "Include uncertainty on all covariates" switch has no effect in any Step 2 configuration (F3), and the coefficient popover says the band covers "the model definition process" (F6).

**Is it consistent?** Mostly. Headline cards, paired effects in Step 3 and the cost-effectiveness intervals use the same paired-gradient rule. The inconsistencies found are: the median deviation reference (F1), the residual component inside the "coefficient" variance (F2), the poverty-rate residual variance (F9), and two pages that still say policy coefficients carry no uncertainty after DOC-12 made them part of the bands (F7).

## Map of the sources of uncertainty

| Source | Where it enters | How it is represented | Where the user sees it | Status in this review |
|---|---|---|---|---|
| Coefficient sampling error (Model 3, clustered by `loc_id_panel`) | `compute_chol_vcov()`, `compute_factor_loading()`, `.anchor_design_shift()` (`R/fct_simulations.R`); `aggregate_with_uncertainty_delta()` (`R/fct_aggregation_delta.R`) | Analytic delta method per year, metric and member: `var_coef = ||F'h||^2` | Step 2 coefficient bands, threshold table "Coef" rows, headline card SD, Diagnostics bar; Step 3 policy series and effect bands; cost-effectiveness interval | Sound for linear and quantile models (MC check, Table B3). Wrong scale for logistic (F8). Level band depends on the residual rule (F3) |
| Unexplained welfare (residual) | `draw_residuals_vec()` (`R/fct_aggregation.R`) | "original": own training residual, fixed in every year, no variance. "resample": iid draw from the pooled residuals per household and year, `var_resid = sigma^2 sum(h^2)` | Inside the "coefficient" SD (F2); inside the year-to-year spread under "resample" (F2) | Matching defect (F0); variance is iid and homoskedastic (F4); poverty-rate variance overstated (F9) |
| Weather year (inter-annual) | Simulation grid of the historical window, `build_hist_sim_dates()` | Empirical spread of the annual values across years (30 by default) | Inter-annual band, annual curves, threshold and return-period tables, Diagnostics bar | Sound. The sampling error of a 1-in-20 value read from 30 years is not quantified (F10) |
| Climate model | One pipeline per CMIP6 member; `combine_ensemble_results()` | Empirical spread across members (20 for SSP3-7.0 in BFA), equal weights; pooled with coefficients by the law of total variance | Inter-model band, "Pooled" threshold rows, Diagnostics bar | Sound. Members share the observed template years, so they add no independent weather variability (F10) |
| Scenario (pathway, period, policy design) | User choices | Separate series, not a variance | Scenario rows | Not quantified, documented (`docs/33_uncertainty.md` Limitations) |
| Policy coefficients (Step 3) | `R/fct_policy_loading.R` (DOC-12) | Extra columns in the Cholesky basis of the active block | Step 3 bands and effect intervals | Implemented; two pages still say it is not (F7) |
| Shock-responsive SP stochastic parts (forecast hits and false alarms, welfare-oracle errors) | `sp_shock_plan()` and helpers (`R/fct_sp_shock.R`), seeded | One seeded realisation | Not shown as uncertainty | Check only (F7) |
| Decomposition channels, adverse-year cost-effectiveness | `R/fct_policy_metric_decompose.R`, `R/fct_sp_effectiveness.R` | Central coefficients only | No bands, stated on the pages | Consistent with the docs (`docs/44_decomposition.md`, `docs/45_cost_effectiveness.md`) |
| Step 1 model selection (covariate list, Lasso, functional form, bins) | Step 1 | Not represented | The coefficient popover suggests it is (F6) | Documented as misspecification in `docs/33_uncertainty.md` Limitations; popover wording to fix |

## Summary of how the app works today

- **Coefficient uncertainty**: closed-form delta method. `Var(T) = ||F'h||^2 + sigma_e^2 * sum(h^2)` (`aggregate_with_uncertainty_delta()`, `R/fct_aggregation_delta.R:76`). `F = X L` from the clustered covariance (`compute_chol_vcov()`, `compute_factor_loading()`, `R/fct_simulations.R:130`, `:211`). The fit-time covariance is used first; the fallback chain (`~loc_id`, `HC1`, `iid`) only logs a message.
- **Anchored loading** (`.anchor_design_shift()`, `R/fct_simulations.R:251`): used only for the `"original"` rule; the loading is `x - x0` of the estimation row matched by id (see F0 for how the match is made).
- **Active scope** (`attach_active_mask()`, `R/fct_results.R:412`): restricts the covariance to weather and changed terms. Linear engine: only with `"original"`. RIF: any rule. Because the anchored loading is already zero on unchanged columns, the restriction gives exactly the same variance as the full covariance for every matched household (verified, F3).
- **Residual rules** (`draw_residuals_vec()`, `R/fct_aggregation.R:217`): `original`, `resample`, `normal`, `none`. UI and batch offer `original` and `resample` (`residual_choices()`, `R/fct_simulations.R:1072`; `.SIM_RESIDUALS`, `R/fct_batch_spec.R:216`, consistent). Draws are seeded by `wise_seed(seed, "residual", year)`, so all scenarios, members and policy arms share them (verified: historical and member pipelines have identical row order and length in every year). Residual variance enters the band only for `resample` and `normal`.
- **Contrasts and breakdown**: `step2_contrast_sd()` and `step2_variance_breakdown()` in `R/fct_step2_tables.R`; headline-card SD in `step2_delta_ci()` (`R/fct_sim_compare.R:520`); Step 3 per-year effects in `paired_model_year_effects()` and their summary in `paired_effect_summary()` (`R/fct_sim_compare.R:209`, `:268`).
- **Pooling and tables**: `combine_ensemble_results()` (law of total variance), `step2_threshold_table()` (coefficient SD interpolated at the return period, median across members, pooled with the across-member variance at that return period).

What is sound and should not be changed without cause: the delta-method structure, the anchored loading for `"original"`, the block Cholesky of the active covariance, the common random numbers, the paired-gradient rule for contrasts, the gating of the active scope, and the agreement between `docs/33_uncertainty.md` and the code outside the points below.

## Findings

Priority: P1 changes reported numbers or labels; P2 documentation/clarity; P3 optional method extension.

### F0 (P1, new) The "original" rule matches residuals by household id alone

- **Where**: `.residual_lookup()` (`R/fct_aggregation.R:161`) builds `setNames(.resid, train_aug[[id_col]])`; `draw_residuals_vec()` matches with `match(as.character(id_vec), names(resid_lookup))` (`R/fct_aggregation.R:243-246`); `.anchor_design_shift()` matches the anchor row the same way (`R/fct_simulations.R:256`); `resolve_id_col()` picks the first of `pid`, `hhid`, `fid` (`R/fct_simulations.R:332`). `attach_active_mask()` and `detect_modified_cols()` use the same id (`R/fct_results.R:462-467`).
- **Claim**: `match()` returns the first training row with the same id. When the estimation sample has more than one round, or more than one economy, and ids repeat, a baseline household receives the residual (and the anchor design row) of another row. The "original" rule is then no longer "each household keeps its own unexplained component", unchanged weather no longer returns the observed outcome, and the simulated distribution is mixed with residuals of another round.
- **Status: Verified.**
  - Real microdata (`microdata/hh/*/*.parquet`, all economies): `hhid` values recur across rounds within an economy in 14 economies (IND 161,768 ids; IRN 83,240; GTM 12,849; VNM 11,760; TJK 11,012; BEN 6,994; TGO 5,441; GNB 4,893; CIV 1,254; TCD 740; NER 140; SEN 126; MLI 30; MWI 10), and 41,936 `hhid` values occur in more than one economy.
  - BFA 2018 + 2021 (baseline 2021): ids are unique, every baseline household matches its own 2021 row. No effect.
  - BEN 2018 + 2021 (baseline 2021, same model as Appendix A): every baseline household matches an id, but 87.2 per cent (83.0 per cent of weight) match a different row, mostly the 2018 row with the same id. The residual used differs from the own residual by 0.39 log points at the median (the residual SD is 0.51); the correlation between the two is 0.37.
  - Effect in the real Step 2 pipeline (BEN, historical 1991-2020, average over years): mean 5.495 vs 5.276 with own-row residuals; poverty rate 29.2 vs 26.8 per cent; Gini 0.378 vs 0.341. Observed values: 5.251, 27.3 per cent, 0.343. The calibration check flags the Gini (`step2_baseline_check()`, flag TRUE) but the user is not told why.
- **Implementation status (Phase 1, 2026-10-26): Done in the working tree, not committed.** Key = `code`, `survname`, `year`, then the id (the columns both frames carry); unique in the BFA and BEN estimation samples (`hhid` alone has 6,963 duplicates in BEN). `step2_add_residual_key()` (`R/fct_simulations.R`) adds `.wiseapp_rowkey` to the estimation frame and the baseline survey in `wise_step2_input()` when the rule is "original"; `resolve_id_col()` and `attach_active_mask()` prefer it, so `.residual_lookup()`, `draw_residuals_vec()`, `.anchor_design_shift()`, `predict_outcome()` and the Step 3 residual draw (it reuses the Step 2 `id_vec` and shared context) all use it unchanged. If the key repeats in the estimation sample the frames are left as they were and a warning is raised. Matched and unmatched counts: `sim_summary$residual_match` (provenance record: `residual_matched`, `residual_unmatched`; batch provenance: `n_residual_matched`, `n_residual_unmatched`) and a "Residuals:" notification when any household is unmatched. Real data after the fix, BEN 2018 + 2021, baseline 2021, "original", historical average (mean / poverty rate / Gini): 5.4948 / 0.2916 / 0.3782 before, 5.2755 / 0.2685 / 0.3410 after (observed 5.2510 / 0.2729 / 0.3432; Gini gap 0.002); 7,984 of 7,984 households matched. BFA unchanged to every printed digit (4.3606 / 0.4358 / 0.3725; 7,128 of 7,128 matched).
- **Fix**: match on a key that identifies the estimation row of the baseline household: at least `code`, `year` (or `survname`) and the id. Use the same key in `.residual_lookup()`, `draw_residuals_vec()`, `.anchor_design_shift()`, `attach_active_mask()`/`detect_modified_cols()` and `.policy_metric_residuals()`. Keep the hash fallback for rows without a match. Decided: choose the key columns after checking which of `code`, `year`, `survname` and the id identify a training row uniquely in the real data; assert uniqueness in `train_aug` (fall back with a warning if it fails); add matched and unmatched household counts to the Step 2 data-quality notice and the provenance record. Tests: a training frame with the same `hhid` in two rounds and two economies; the baseline must get its own residual and anchor row. Re-run the BEN check of Appendix A; the simulated historical Gini should be within 0.005 of the observed value. Changes numbers for every multi-round or multi-economy "original" run, so record before/after for BEN in the Decision log.

### F1 (P1, decided) Residual variance in contrasts: partly refuted, one real gap

- **Where**: `step2_contrast_sd()` (`R/fct_step2_tables.R:79-103`); `step2_hist_f_ref()` (`:41-72`); `step2_delta_ci()` (`R/fct_sim_compare.R:520-542`); `paired_model_year_effects()` and `paired_effect_summary()` (`R/fct_sim_compare.R:209-360`). Documented in `docs/33_uncertainty.md` Section 8.
- **Original claim**: the contrast keeps the scenario's full residual variance although the scenario and the historical reference share residual draws, so the contrast band is too wide under "resample".
- **Status: Partly refuted.** Monte Carlo over 150 residual seeds on BFA, "resample", first SSP3-7.0 member against the historical run (Appendix B, Table B2):
  - Year `r` of the scenario minus the historical **mean** over years (what the "difference from the historical mean" view shows): the residual SD of the contrast equals the residual SD of the level (mean 0.059 vs 0.061; Gini 0.0054 vs 0.0055). The residual draw of year `r` is shared with the historical year `r` only, which carries weight `1/R` in the mean, so the noise does not cancel. Keeping the scenario's residual variance is correct (exact value `(1 - 1/R)` times it).
  - Year `r` of the scenario minus one historical year (what the **median** reference uses: `step2_hist_ref()` takes the median value, `step2_hist_f_ref()` the gradient of the year closest to it): residual SD 0.092 for the mean, about `sqrt(2)` times the level, because two independent draws are compared. The code keeps one draw's variance, so this band is too narrow by about `sqrt(2)` in its residual part under "resample".
  - Same-year pairs (Step 3 policy minus baseline, per year): residual SD 0.003 (mean), near zero. `paired_model_year_effects()` uses `f_p - f_b` only, which is correct.
  - Year-averaged shift (headline card, Step 3 average effect): residual SD 0.0005 against a coefficient SD of 0.025 (mean). Dropping the residual part, as `step2_delta_ci()` and `paired_effect_summary()` do, is correct.
- **What remains inconsistent**: (i) the median reference under "resample"; (ii) the fallback in `paired_model_year_effects()` without gradients, `sqrt(b_sd^2 + p_sd^2)`, which treats the arms as independent and includes residual variance (reached only when `F_agg` is missing; with coefficient uncertainty off both SDs are zero, so this is rare); (iii) `docs/33_uncertainty.md` Section 8 gives no reason for keeping the residual variance, which is why the original claim was made.
- **Implementation status (Phase 3, 2026-10-26): Code done in the working tree, not committed; the Section 8 reasoning goes into `docs/33_uncertainty.md` with Phase 5.** `step2_hist_f_ref(ht, "median")` returns the reference gradient with the reference year's `var_resid` as an attribute and `step2_contrast_sd()` adds it. Real BFA, SSP3-7.0, mean, "resample": contrast SD with the median reference 0.0843 coefficient part plus residual 0.0588 (the median reference's residual part was 0.0588 once, now both years' draws are counted: the band grows by the reference year's variance); "original" unchanged (residual 0). The mean reference, same-year and year-averaged contrasts are unchanged, as decided.
- **Decision (closed)**: option (a). For the median reference, add the reference year's `var_resid` (which F2 carries as its own column) to the contrast variance; do it after F2. Add the reasoning above to `docs/33_uncertainty.md` Section 8 (why the residual variance stays for a difference from the mean and goes for paired same-year and year-averaged contrasts). Not chosen: (b) document the gap only.

### F2 (P1) The "coefficient" variance includes residual variance and moves with the display mode

- **Where**: `step2_variance_breakdown()` (`R/fct_step2_tables.R:253-298`, line 259); table builders `R/fct_aggregation.R:879`, `:1038` (`value_all_sd = sds`); `variance_breakdown_rv` in `R/mod_2_02_results.R:1626` (computed on `.contrast_series()`); batch `annual$sd` (`step2_annual_table()`, `R/fct_step2_tables.R:698`).
- **Claim**: `value_all_sd` is `sqrt(var_coef + var_resid)`, and `var_resid` is not stored separately. The breakdown computes `var_coef <- mean(sds_flat^2)`, so under "resample" the "coefficient" bar includes residual variance. The year spread (`var_within`) also contains the year-to-year residual-draw noise, so residual noise appears in two bars.
- **Status: Verified** (BFA, Table B1):
  - Under "resample" the residual part is small for the mean (residual SD 0.060 against a level coefficient SD of 0.526) but larger than the coefficient part for the Gini (0.0061 against 0.0043).
  - The year-to-year SD of the Gini doubles from 0.0025 ("original") to 0.0056 ("resample"); the added part is residual-draw noise, not weather.
  - The Diagnostics popover and footnote do say "plus residual-draw variance when stochastic residuals are enabled" (`R/mod_2_02_results.R:355-389`), so the app discloses the mix. `docs/32_metrics.md` Eq. (5.1) and `docs/33_uncertainty.md` ("three variances are shown side by side") do not.
  - New point: the breakdown is computed on the contrast series, so the "coefficient" bar halves when the user switches Results to "difference from the historical mean" (BFA SSP3-7.0, mean, "original": 0.122 as a level, 0.061 as a contrast). Neither the bar label nor the docs say that the bar depends on that toggle.
- **Implementation status (Phase 3, 2026-10-26): Code done in the working tree, not committed; the docs lines (`docs/32_metrics.md` Section 5, `docs/33_uncertainty.md` Interpretation) go with Phase 5.** The table builders store `var_resid_all` next to `value_all_sd` (`R/fct_aggregation.R`); `step2_variance_breakdown()` returns `var_resid` and a coefficient part without it; `step2_contrast_sd()` reads the stored column; the Diagnostics chart labels the coefficient bar "(level)" or "(difference from historical mean/median)" and adds a "Residual draws" bar when non-zero; popover and footnote say that under "resample" the year bar holds residual noise too. Batch: `annual` gains `sd_resid` (`sd` unchanged), `summary` section `uncertainty` gains `var_resid`; `batch/docs/tables.md` updated. Real BFA, SSP3-7.0 scenario, mean, "resample", SDs (coefficient / residual / year / models): level 0.5429 / 0.0588 / 0.0658 / 0.0768 (before: coefficient bar 0.5461 with the residual inside); difference from the historical mean 0.0585 / 0.0588; from the median 0.0843 / 0.0588. "original": level 0.1222, mean 0.0614, median 0.0594, residual 0.
- **Fix (decided)**: carry `var_resid` as its own list-column next to `value_all_sd`; show a separate residual bar when it is non-zero; say in the Diagnostics text that under "resample" the year spread includes residual-draw noise. The coefficient bar keeps following the active reference and is labelled "level" or "difference from the historical mean/median" accordingly (not chosen: always compute it on the level series). Keep batch tables backward compatible (add a column rather than change `sd`); update `batch/docs/tables.md`, `docs/32_metrics.md` Section 5 and `docs/33_uncertainty.md` Interpretation.

### F3 (P1, decided) The level coefficient band depends on the residual rule; the "all covariates" switch does nothing

- **Where**: `attach_active_mask()` gate (`R/fct_results.R:434-444`); `.anchor_design_shift()` (`R/fct_simulations.R:251-275`); checkbox in `R/mod_2_01_weathersim.R:240-248`.
- **Claim**: under "original" a level band uses the anchored loading `x - x0` (zero at interview weather). Under "resample" (linear engine) it uses the full `x'L`, so the uncertainty of every covariate enters the level band. Switching the rule changes the band although the user thinks they are choosing a residual rule.
- **Status: Verified** (BFA, historical, average over years, Table B1). Level coefficient SD under "original" vs "resample": mean 0.098 vs 0.526 (5.4 times); poverty rate 0.015 vs 0.055 (3.7 times); Gini 0.0016 vs 0.0043. Contrast SDs (difference from the historical mean) are much closer: 0.061 vs 0.083 for the mean.
- **New point, verified**: with "original", the anchored loading is zero on every column that does not change, so `(x - x0)' Sigma (x - x0)` equals the active-block variance exactly. The runs "original" and "original + Include uncertainty on all covariates" gave identical SDs to every printed digit for the mean, poverty rate and Gini (Table B1). With "resample" the switch is ignored by design. So in Step 2 the switch has an effect only for households whose residual is a hash-keyed draw (no matching estimation row); in BFA there are none (all 7,128 baseline households match). In Step 3 the changed columns are in the active block anyway, so the same holds. The popover's description ("more conservative, but inconsistent with the model's own additive-separability assumption") is therefore not what happens.
- **Unmatched households**: 0 per cent in BFA and in BEN (in BEN because of F0, which matches by id regardless of round). After F0 is fixed, unmatched rows should still be rare, because the baseline survey is part of the estimation sample; rows dropped by `fixest` (singletons, missing values) are the main source. Report the count with the run.
- **Implementation status (Phase 4, 2026-10-26): Done in the working tree, not committed.** The "Include uncertainty on all covariates" checkbox and its wiring are gone from `R/mod_2_01_weathersim.R` (the module API keeps `propagate_all_covariate_uncertainty` as `reactive(FALSE)` for Step 3; the stale-run signature and the sync and async inputs no longer read it). The residual-rule and coefficient popovers and the Diagnostics popover explain the rule-dependent level band. Batch: the field is still accepted (`wise_default_sim()`, spec validation, config import of old files) and ignored; `wise_batch_sim()` warns when it is true; `batch/README.md`, `batch/docs/spec_inventory.md` and `R/fct_spec_defaults.R` say it is deprecated. The e2e smoke test had used the checkbox as its `conditionalPanel` check; it now checks that the poverty-line input of the Step 2 Results shows only for a poverty metric. Checked in the running app on real BFA (see the Phase 4 report): control absent, residual bar and labels as designed, no errors.
- **Decision (closed)**: option (a). Keep the rule-dependent level band and explain it in the residual-rule popover and the Diagnostics text. Remove the "Include uncertainty on all covariates" control from the Step 2 UI (`R/mod_2_01_weathersim.R`, config import/export, tests). Keep the batch field `propagate_all_covariate_uncertainty` and `wise_default_sim()` entry as an accepted no-op with a deprecation note, so saved configs and batch specs still load. Not chosen: keep the control with new text; (b) restricted scope under "resample".

### F4 (P2) Residuals are treated as independent and homoskedastic; "resample" moves the point estimates

- **Where**: residual term `sigma_e^2 * sum(h^2)` (`R/fct_aggregation_delta.R:190-197`); `sample(train_aug$.resid, N, replace = TRUE)` (`R/fct_aggregation.R:276`); unweighted model fit; clustering `COEF_VCOV_SPEC = ~loc_id_panel`.
- **Claim**: residuals are correlated within location panels and heteroskedastic, and "resample" ignores both.
- **Status: Verified** (BFA, Model 3 residuals, Appendix B, Table B4):
  - 24 per cent of the residual variance lies between the 555 location panels (26 per cent between location-year cells). The design effect for a weighted mean of residuals is 11.8. A real year with common non-weather shocks of this size would move a national statistic about `sqrt(11.8) = 3.4` times more than the iid draw implies.
  - Residual variance rises from 0.24-0.26 in the lowest two quintiles of the fitted value to 0.42 in the top quintile; 0.26 rural vs 0.31 urban.
  - The model is fitted without survey weights; the weighted mean residual of the baseline households is -0.027, while the pooled draw has mean zero.
  - Consequence for the point estimates: the historical average under "resample" is 4.776 (mean welfare), 40.4 per cent (poverty) and 0.410 (Gini), against 4.361, 43.6 per cent and 0.373 under "original", and against observed values of 4.479, 42.0 per cent and 0.374. The calibration check does not flag any of them (the Gini gap is 9.5 per cent of the observed value, just under the 10 per cent tolerance).
- **Fix (P2 minimum)**: add to `docs/33_uncertainty.md` A7 and to `docs/50_assumptions_limitations.md` that residual draws are iid, homoskedastic and unweighted; that "resample" therefore changes the level and spread of the simulated distribution, not only its noise; and that the year spread under either rule shows weather-driven variability only, not common non-weather shocks. Say in the residual-rule popover that "resample" does not reproduce the observed distribution. **Decision (closed)**: docs and popover only; no cluster-block or stratified resample rule in this round, and no follow-up task logged.

### F5 (P2) The "resample" band is centred on one realisation

- **Where**: `aggregate_with_uncertainty_delta()` returns `value` from one residual draw and adds `var_resid` around it.
- **Status: Verified, small.** Across 150 seeds (BFA, mean welfare): the SD of one year's value is 0.061 (1.3 per cent), and the SD of the 30-year average is 0.011 (0.2 per cent). Poverty rate: 0.0077 and 0.0015. Gini: 0.0055 and 0.0010.
- **Fix**: documentation and tooltip only: a per-year value under "resample" contains one residual realisation; averages over years are stable to about 0.2 per cent. Do not average over draws (it would change the reference numerics of `fct_run_simulation()`).

### F6 (P2) User-facing wording

- **Where**: `R/mod_2_01_weathersim.R:178-253` (residual and coefficient popovers); Diagnostics text in `R/mod_2_02_results.R:345-390`; `docs/30_simulation.md` Section 4; `docs/33_uncertainty.md` Interpretation.
- **Implementation status (Phase 4, 2026-10-26): UI text done in the working tree, not committed; the page lines (`docs/30` Section 4, `docs/33` Interpretation) go with Phase 5.** The "original", "resample" and coefficient popovers use the wording below (the coefficient popover now says that it covers the sampling error of the coefficients for the specified model, not the choice of covariates, Lasso, functional form or bins); the "all covariates" checkbox is gone (F3).
- **Status: Verified** (text read at `2af403d`). Points:
  - "original" is described as "assumes no changes due to changing hazards". Say instead: each household keeps its own unexplained component, the same in every year; the coefficient band then covers only the change from the interview weather.
  - "resample" is "Secondary recommendation: randomly resample residuals from the model." Say: adds residual noise drawn from the pooled estimation residuals, independent of household and location; changes the level and spread of the simulated distribution (F4); the coefficient band then uses all covariates and is several times wider (F3).
  - The coefficient popover says the box "incorporates uncertainty around the model definition process itself". It covers the sampling error of the coefficients for a fixed specification, not the choice of covariates, Lasso selection, functional form or bins. Say so.
  - The "Include uncertainty on all covariates" checkbox has no effect in practice (F3).
  - `docs/33_uncertainty.md` says three variances are shown; after F2 it should list the real components and say which reference the coefficient bar uses.
  - `docs/30_simulation.md` lists "Normal: Not offered" while `draw_residuals_vec()` supports it. Batch validation (`.SIM_RESIDUALS <- c("original", "resample")`) rejects it, consistent with the UI. No change needed.

### F7 (P2) Step 3 consistency

- **Where**: `R/fct_policy_metric_decompose.R:785-814` (`.policy_metric_residuals()`), `R/fct_policy_loading.R`, `R/fct_sim_compare.R:209-360`, `R/fct_step3_tables.R`, `docs/40_policy_framework.md`, `docs/44_decomposition.md`, `docs/50_assumptions_limitations.md`.
- **Status**:
  - **Verified, consistent**: the policy arm uses the same residual draws (`wise_seed(seed, "residual", year)`, same ids and lengths) and the anchored loading extended by the policy columns (DOC-12). The per-year paired effect drops the residual part, which the Monte Carlo of F1 shows is right for same-year pairs; the average effect uses the norm of the mean gradient, also right. The cost-effectiveness interval (`sp_cost_effectiveness()`, `effect_avg_sd` from `paired_summary$coef_sd`) inherits this.
  - **Verified, stale docs**: `docs/40_policy_framework.md` Section 5 says the bands include the sampling error of the policy coefficients (DOC-12, commits `bfebf54`, `d4fcbf1`), but the same page's Limitations ("Uncertainty in the coefficients of the policy variables, in the bands of the policy series (Section 5)") and `docs/50_assumptions_limitations.md` ("Coefficient uncertainty of policy variables in the bands of a policy run") still list it as not modelled. Remove both lines (`docs/50` is `verified_against: 8592a9d`, before DOC-12).
  - **Check (decided)**: shock-responsive programmes draw forecast hits and false alarms and welfare-oracle errors once per seed (`R/fct_sp_shock.R`); the bands do not include the variation between draws, and the pages do not say so. Measure the spread of the average effect and cost over 20 seeds on a BFA shock spec, record it here, and state in `docs/43_shock_responsive_sp.md` that the bands exclude it. No code change this round, whatever the size.
  - **Seed check done (Phase 6, 2026-10-26)**: BFA batch spec (SSP3-7.0 2025-2035, hist 1991-2020, "original"), cash transfer 60 per person, `targeting: exante_poor` at 30 per cent, 5 per cent admin cost, shock trigger = 1-in-5 return period of the continuous temperature; seeds 101 to 120 (`dev/outputs/uncertainty_review/14_shock_seeds.R`, `15_shock_summary.R`). Mean annual cost, historical / SSP3-7.0: 12.04 / 42.25 million, SD between seeds 0.13 / 0.47 million (1.1 / 1.1 per cent; range 40.999 to 43.192 million for the scenario). Average effect on mean welfare, historical / SSP3-7.0: 0.00143 / 0.00502, SD 0.000016 / 0.000056 (1.1 / 1.1 per cent). Effect on the poverty rate (SSP3-7.0): -0.00032, SD 0.000054 (17 per cent of the value). 1-in-20 cost 59.8 million, SD 0.66 million (1.1 per cent). Activation frequency 0.933 / 0.998 in every seed. The inter-model range of the SSP3-7.0 mean effect is 0.0042 to 0.0064, so the seed SD is about 2.5 per cent of that width. Caveat: this spec has no forecast hits or false alarms and no predicted-welfare layer, so only the seeded targeting draws vary; those two layers were not measured. `docs/43_shock_responsive_sp.md` now says the bands exclude this variation. No code change.
  - **Check (Phase 6 result)**: the residual mode demotions (RIF to `none`; missing `train_aug` to `none`, `R/fct_aggregation_delta.R:103-106` and `aggregate_pipeline_per_year()`) are silent. Confirm that the provenance record (`fct_provenance.R`) stores the effective rule, and show it in Step 2 Results when it differs from the request.
- **Implementation status (Phase 6, 2026-10-26): demotion record done in the working tree, not committed.** The RIF demotion happens in `wise_step2_input()`, before the run, so the callers pass the requested rule (`sh$residuals`) and the effective one (`step2_input$residuals`) to `wise_step2_annotate()`; `fct_run_simulation()` is untouched (its result and historical payload names are pinned by `test-step2-contract.R`). The second demotion, a failed `train_aug` precomputation inside `fct_run_simulation()`, is not recorded: it raises a warning and is rare. `sim_summary` holds `residuals_requested` and `residuals_effective`; `wise_provenance()` copies both into the Step 2 record; the run summary card (`R/utils_ui.R`) shows "Residuals applied: none (requested original)" only when they differ (`step2_residual_rule_note()`). Real BFA: linear fit, "original" gives original / original and no note; RIF fit, "original" gives original / none and the note. Checked in the running app on BFA (linear: Step 2 ran, no note, no errors); a RIF run through the UI was not driven. Batch `provenance.parquet` does not carry the rule (not requested). Tests: `test-provenance.R`, `test-fct_step2_input.R`, `test-utils_ui.R`.
- **Fix**: the doc lines above; follow F1 for the median reference.

### F8 (P1, new) Logistic models: the coefficient loading is on the link scale, the gradient on the probability scale

- **Where**: `predict_outcome()` returns probabilities for `feglm` (`type = "response"`, `R/fct_predict_outcomes.R:146-149`); `compute_factor_loading()` builds `F = x'L` from the link-scale design; `gradient_for_method()` with `is_log = FALSE` uses `dw = 1` (`R/fct_aggregation_delta.R`, `gradient_for_method()`), so the chain-rule factor `dp/deta = p(1 - p)` is missing. The rate band uses the identity scale (`apply_band_transform()`, "mean"), so it can leave [0, 1].
- **Status: Verified** (BFA individuals, outcome `agriculture`, logistic, rainfall 12 months, first historical year): app coefficient SD 0.504 for a rate of 0.452; Monte Carlo with link-scale draws `plogis(eta + F z)` 0.103; delta method with the `p(1 - p)` factor 0.114. The band at the default 10/90 quantiles runs from about -0.19 to 1.10.
- **Implementation status (Phase 2, 2026-10-26): Code done in the working tree, not committed; the docs lines are left for Phase 5.** `run_sim_pipeline()` scales the loading rows by `p_i (1 - p_i)` for a `feglm` logit fit (`.logit_link_derivative()`, `R/fct_simulations.R`) and marks the pipeline `logit_link = TRUE` (the field exists only for logistic fits, so other pipelines keep their shape). The two per-year aggregators pass it on and `apply_band_transform()` builds the band of the mean of a binary outcome on the logit scale. With the "original" rule the factor is taken at the simulated prediction (first-order for the anchored difference). Step 3 stays unsupported for logistic outcomes (`.policy_endpoint_status()`). Real BFA, agriculture, first historical year: coefficient SD 0.5036 before, 0.1140 after (Monte Carlo 0.107, delta 0.114); the band at the default 10/90 quantiles went from [-0.194, 1.097] to [0.314, 0.598] (all years: lower 0.308 to 0.318, upper 0.545 to 0.660). Unit test: small `feglm` fixture against a link-scale Monte Carlo (`test-fct_simulations.R`).
- **Fix**: multiply the gradient (or the loading rows) by `p_i (1 - p_i)` for logistic engines, and use the logit band transform for a rate of a binary outcome. Tests: a small `feglm` fixture compared with a Monte Carlo on the link scale. Check the residual rule for binary outcomes at the same time: "original" adds the response residual `y - p` to the predicted probability, so household values leave [0, 1]; the mean is unaffected, but say so in `docs/30_simulation.md`. Update `docs/33_uncertainty.md` Section 2 (the factor `kappa_i` for a logistic model is `p_i(1 - p_i)`).

### F9 (P2, new) The residual variance of the poverty rate is overstated under "resample"

- **Where**: `gradient_for_method()`, `headcount_ratio` branch; bandwidth `b = max(0.05 z, median kappa ||F||)`; residual term `sigma^2 sum(h^2)`.
- **Phase 0 re-check (2026-10-25, `2af403d`, scripts in `dev/outputs/uncertainty_review/`)**: the analytic poverty-rate residual SD reproduces as 0.0097 (every year 0.0089 to 0.0111; Table B1 also says 0.0097), not 0.0177. The Monte Carlo reproduces (0.0078). The overstatement is 1.24 times, not 2.3 times, which is already near the 15 per cent target below. Tables B1, B5 and the F8 logistic check reproduce exactly; the rest of B2 reproduces.
- **Status: Verified, but smaller than first reported** (BFA, "resample"): analytic residual SD 0.0177 against 0.0077 by Monte Carlo over residual seeds (2.3 times; see the re-check above). Mean and Gini agree (0.060 vs 0.061; 0.0061 vs 0.0055). The kernel gradient is a first-order expansion for small shifts; a residual draw is a large shift (SD 0.56 log points), and the bandwidth is tuned to the coefficient loading, not to the residual.
- **Implementation status (Phase 3, 2026-10-26): Done in the working tree (closed form kept), not committed; no `docs/33` A1 note needed beyond the Phase 5 line.** `.headcount_resid_variance()` (`R/fct_aggregation_delta.R`) gives `sum(w^2 p (1 - p))` with `p` from the empirical CDF of the residuals, for `headcount_ratio` under "resample" (the transfer room of DOC-11 is handled). Real BFA: analytic residual SD of the poverty rate 0.00758 (RMS over the 30 historical years; the 20 members of SSP3-7.0 0.00757 to 0.00761) against 0.00778 by Monte Carlo (2.6 per cent below) and 0.00967 before. Unit test against a Monte Carlo.
- **Fix (decided)**: use the closed form `sum(w~_i^2 p_i(1 - p_i))` with `p_i = P(y_i + e < log z)` from the residual distribution (empirical CDF of `.resid`) if it is simple and a test against the Monte Carlo of Table B2 passes (target within 15 per cent of 0.0077 on BFA); otherwise state the approximation in `docs/33_uncertainty.md` A1. The effect on the bands is limited to "resample" runs and to F2's breakdown.

### F10 (P2, new) Return periods and the climate-model spread: what the bands do not include

- **Where**: `step2_threshold_table()` (`R/fct_step2_tables.R:316-440`), `adverse_year_support()` (`R/fct_uncertainty_helpers.R:160-`), `RP_LOW`/`RP_HIGH` (`R/fct_simulations.R:60-64`); `docs/32_metrics.md` Section 4; `docs/31_climate_scenarios.md`.
- **Status: Verified by reading** (no numbers needed).
  - A return-period value is read from the empirical distribution of 30 annual values per member (`min_years = ceiling(1/p)`, so 1-in-20 is the most extreme supported with the default window). The sampling error of that tail estimate is not in the "Coef" or "Pooled" rows; with 30 years a 1-in-20 value rests on the two most extreme years.
  - Future members are the observed template years shifted by each model's monthly change, so all 20 members share the same year-to-year sequence. Pooling 20 members times 30 years is not 600 independent years, and the across-member variance at a return period measures disagreement in the climate signal, not more weather variability. `docs/31_climate_scenarios.md` and `docs/30_simulation.md` A5 state the template-year design; `docs/32_metrics.md` does not draw the consequence for the return-period table.
- **Fix (decided)**: documentation only: add both points to `docs/32_metrics.md` (Return periods) and to the threshold-table popover. No bootstrap.

## Priority table

| ID | Priority | Status | Type | Changes numbers | Decision |
|---|---|---|---|---|---|
| F0 | P1 | Verified | code (residual and anchor key) + run notice | Yes: every multi-round or multi-economy "original" run (BEN Gini 0.378 to 0.341) | Closed: composite key, assert, report counts |
| F8 | P1 | Verified | code (logistic gradient, band) | Yes: logistic coefficient bands about 5 times narrower | None needed |
| F2 | P1 | Verified | code + table schema + labels | Labels and shares in Diagnostics | Closed: bar follows the reference, labelled |
| F1 | P1 | Partly refuted | method (median reference) + docs | Median-reference bands under "resample" only | Closed: (a) add reference `var_resid` |
| F3 | P1 | Verified | UI/docs; remove dead control | No | Closed: (a) remove from UI, batch no-op |
| F7 | P2 | Verified (docs), 2 checks | docs; checks | No | Closed: document and record the seed spread |
| F4 | P2 | Verified | docs | No | Closed: docs and popover only |
| F9 | P2 | Verified | method or docs | Poverty-rate bands under "resample" | Closed: closed form if a test passes, else docs |
| F6 | P2 | Verified | UI text/docs | No | None needed |
| F10 | P2 | Verified by reading | docs | No | Closed: docs and popover only |
| F5 | P2 | Verified, small | docs/UI | No | None needed |

## Verification checklist for the implementer

- Unit tests: residual and anchor matching with ids repeated across rounds and economies (F0); logistic gradient against a link-scale Monte Carlo (F8); the breakdown with a separate residual component (F2); the median-reference contrast (F1); the corrected contrast SD with known `F`, `h`, `sigma`.
- Real-data checks (scratch, not committed; Appendix A): BEN calibration after F0; BFA Tables B1 to B3 after F1, F2, F8, F9; point estimates under "original" must not change for BFA (unique ids).
- Determinism: `test-determinism*` and the seeded residual draws must stay bit-identical for point estimates except where F0 changes the matched residual.
- Batch: `test-fct_step2_tables.R`, `test-fct_step3_tables.R`, `test-batch-pipeline.R`; update `batch/docs/tables.md` if table columns change.
- UI: popovers, the removed or relabelled checkbox, the Diagnostics panel, with `dev/ui_drive.R` (skill `wise-ui-check`).
- Docs: `Rscript dev/docs_check.R`, `Rscript dev/docs_index.R`; bump `verified_against` on `30`, `32`, `33`, `40`, `44`, `50` as touched.

## Out of scope

Misspecification, weather-data error, poverty-line and weight uncertainty (listed in `docs/33_uncertainty.md` Limitations); coefficient uncertainty of tree-based models; cross-quantile covariance for the RIF model (not re-run here); post-selection inference after Lasso (state it, F6, but do not model it); any change to the reference numerics of `fct_run_simulation()` beyond what the findings require.

## Appendix A: how the evidence was produced

All runs used the real data under `WISEAPP_DATA_PATH` on 2026-10-25, commit `2af403d`, `pkgload::load_all()` of the working tree, seed 123. The scripts were scratch files and are not in the repository; the steps below rebuild them.

1. **Data, frame and fit** through the batch pipeline (`wise_targets()`), one spec per run, as in `dev/batch_parity_bfa_sim.R` but without `sim`:
   - BFA and BEN: `outcome: {name: welfare, currency: PPP}`; `model: {covariates: {method: user, vars: [hhsize, electricity, cellphone]}}`; weather profile `t` (months 1-3, binned, 5 bins) and `r` (months 1-12, continuous); fixed effects default (`year`, `gaul1_code`); samples BFA 2018 + 2021, BEN 2018 + 2021.
   - Logistic: `sample: {unit: ind}`, `outcome: {name: agriculture}`, `model: {type: logistic}`, weather `r` (months 1-12, continuous), BFA.
   - The data, frame and fit files are read from `_targets/user/{data,frames,fits}/*.qs2`.
2. **Step 2** in the same process: `step2_baseline_run()` on the latest wave, `wise_step2_input(..., slim = FALSE)`, `step2_compute(.wise_step2_async_normalize_input(input), seed = 123, weather_storage = "memory")`. BFA: historical 1991-2020 and SSP3-7.0 2025-2035 (20 members), three runs: "original", "original" with `propagate_all = TRUE`, "resample". About 10 seconds each.
3. **Aggregation** with `step2_run_aggregates()` (the Results tables at the default poverty line of 3.00 a day) and `aggregate_pipeline_per_year()` where `var_coef` and `var_resid` were needed separately.
4. **Monte Carlo**:
   - Residuals: for 150 seeds, the per-year draw of the app (`withr::with_seed(wise_seed(s, "residual", year), sample(.resid, N, replace = TRUE))`) applied to the historical pipeline and one member, statistics recomputed per year.
   - Coefficients: 400 draws `z ~ N(0, I)`, prediction `exp(y_point + e_original + F z)` with the run's anchored `F_loading`, three years (1991, 2005, 2020), levels and same-year pairs against the first member.
   - Logistic: 2,000 draws, `plogis(qlogis(p) + F z)`.
5. **Residual matching** (F0): own row by `paste(hhid, year)` against the app's `match()` on `hhid`; own-row residuals applied to the run's `y_point` via `svy_row_id`. Data-wide id counts with DuckDB over `microdata/hh/*/*.parquet`.

## Appendix B: results

**Table B1. BFA, historical 1991-2020 (level SDs averaged over years) and SSP3-7.0 2025-2035 (20 members).** `sd_coef` and `sd_resid` are the square roots of the year-averaged `var_coef` and `var_resid` of the historical run; `sd_year` is the SD of the historical annual values; the scenario columns are the root mean square of `value_all_sd` as a level and after `step2_contrast_sd()` with the historical-mean reference; `card_sd` is `step2_delta_ci()`.

| Rule | Metric | Historical value | sd_coef | sd_resid | sd_year | Scenario level SD | Scenario contrast SD | Card SD | Climate shift |
|---|---|---|---|---|---|---|---|---|---|
| original | mean | 4.361 | 0.0978 | 0 | 0.0722 | 0.1222 | 0.0614 | 0.0300 | -0.0964 |
| original | poverty rate | 0.436 | 0.0146 | 0 | 0.0102 | 0.0188 | 0.0097 | 0.0044 | 0.0178 |
| original | Gini | 0.373 | 0.00156 | 0 | 0.00248 | 0.00152 | 0.00149 | 0.00076 | 0.00299 |
| original, all covariates | all three | identical to "original" | | | | | | | |
| resample | mean | 4.776 | 0.5257 | 0.0601 | 0.0809 | 0.5461 | 0.0830 | 0.0251 | -0.1151 |
| resample | poverty rate | 0.404 | 0.0548 | 0.0097 | 0.0099 | 0.0592 | 0.0123 | 0.0040 | 0.0143 |
| resample | Gini | 0.410 | 0.00425 | 0.00613 | 0.00561 | 0.00747 | 0.00620 | 0.00036 | 0.00122 |

Diagnostics breakdown for the scenario, "original", mean, level series: coefficient 0.122, year 0.058, climate models 0.069.

**Table B2. Residual noise under "resample" (BFA, 150 seeds; SD averaged over years where per-year).**

| Quantity | Mean | Poverty rate | Gini |
|---|---|---|---|
| Analytic `sqrt(var_resid)` (app) | 0.0601 | 0.0177 | 0.0061 |
| MC: level of one year | 0.0609 | 0.0077 | 0.0055 |
| MC: scenario year minus historical mean | 0.0591 | 0.0075 | 0.0054 |
| MC: scenario year minus the same historical year | 0.0030 | 0.0023 | 0.0004 |
| MC: scenario year minus another historical year | 0.0925 | 0.0104 | 0.0075 |
| MC: 30-year average shift (scenario minus historical) | 0.0005 | 0.0004 | 0.0001 |
| MC: 30-year average level | 0.0107 | 0.0015 | 0.0010 |

**Table B3. Coefficient uncertainty under "original", anchored loading (BFA, 400 draws).**

| Year | Metric | Analytic level | MC level | Analytic pair | MC pair |
|---|---|---|---|---|---|
| 1991 | mean | 0.0687 | 0.0725 | 0.0269 | 0.0289 |
| 1991 | poverty rate | 0.0116 | 0.0124 | 0.0039 | 0.0041 |
| 1991 | Gini | 0.00131 | 0.00138 | 0.00107 | 0.00106 |
| 2005 | mean | 0.0201 | 0.0207 | 0.0164 | 0.0176 |
| 2005 | poverty rate | 0.0043 | 0.0046 | 0.0021 | 0.0025 |
| 2005 | Gini | 0.00138 | 0.00143 | 0.00038 | 0.00041 |
| 2020 | mean | 0.1418 | 0.1502 | 0.0385 | 0.0407 |
| 2020 | poverty rate | 0.0216 | 0.0232 | 0.0055 | 0.0060 |
| 2020 | Gini | 0.00210 | 0.00222 | 0.00127 | 0.00125 |

For levels the delta method is 3 to 8 per cent below the Monte Carlo, the expected sign for the convexity of `exp()`. For paired contrasts it is within 8 per cent except the 2005 poverty-rate contrast (17 per cent below), where the smoothed indicator meets a small difference. No action needed beyond assumption A1 of `docs/33_uncertainty.md`.

**Table B4. Residual structure, BFA Model 3 (13,779 households, 555 location panels).**

| Statistic | Value |
|---|---|
| Residual variance, pooled / weighted baseline | 0.313 / 0.321 |
| Weighted mean residual of the baseline households | -0.027 |
| Share of residual variance between location panels / location-year cells | 0.240 / 0.262 |
| Design effect of a weighted mean of residuals (clustered vs iid) | 11.8 |
| Residual variance by fitted-value quintile | 0.259, 0.244, 0.291, 0.307, 0.422 |
| Residual variance, rural / urban | 0.259 / 0.310 |
| Calibration (observed vs simulated historical), "original" | mean 4.479 vs 4.361; poverty 42.0 vs 43.6 per cent; Gini 0.374 vs 0.373 |
| Calibration, "resample" | mean 4.479 vs 4.776; poverty 42.0 vs 40.4 per cent; Gini 0.374 vs 0.410 |

**Table B5. BEN 2018 + 2021, baseline 2021, "original", historical 1991-2020 average.**

| Residual used | Mean | Poverty rate | Gini |
|---|---|---|---|
| App (first row with the same `hhid`) | 5.495 | 0.292 | 0.378 |
| Own row (`hhid`, `year`) | 5.276 | 0.268 | 0.341 |
| Observed | 5.251 | 0.273 | 0.343 |
