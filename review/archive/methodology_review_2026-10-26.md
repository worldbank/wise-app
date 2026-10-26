# Methodology implementation review

Date: 2026-10-26. Reviewed `dev` at `f92a5e87b1024bf6bbeec49c483cc8d55c144bcd`, including the
pre-existing working-tree changes. References below are to that working-tree snapshot. This review changes only
this report, not the app, methods pages or remediation tracker.

Second pass, same day, against `ad5d665` plus the same working-tree changes (the commits in between touch only
agent instructions and `review/README.md`): every cited code fact was re-read and holds at the cited lines. The
second pass revised the recommended fix for finding 2, widened the weight-alias item and the scope of finding 4,
added an export inconsistency to finding 5 and downgraded the poverty-cutoff tie item. See "Revision notes" at the
end.

## Overall assessment

The app implements a substantial, coherent stress-testing methodology. The methods reference covers the pipeline
well, maps equations to implementation, and generally distinguishes estimated relationships from scenario
arithmetic. The fixed baseline population, weather transformations, climate delta method, paired policy comparisons,
transfer accounting and metric-aware decomposition have identifiable implementation paths and focused tests.

The main weaknesses are specific rather than grounds for replacing the framework: an overstated identification
description, inconsistent RIF covariance assumptions, incomplete climate-coverage validation, two weighting
inconsistencies, and reproducibility metadata/cache defects. These warrant targeted corrections before relying on
the affected outputs. No claim is made here that the issues materially change a particular country's results;
that needs country/specification-specific checks.

## Priority findings

### 1. Identification is described more strongly than the default estimator supports

**Confirmed, high methodological importance; primarily a documentation correction.**
`docs/20_model_specification.md:48` says identification is within an area-by-round cell and that regressors constant
within cells are dropped. `docs/01_framework.md:59-63` likewise describes comparisons within area and round.
However, the default is additive survey-year and administrative-area effects
(`R/fct_spec_defaults.R:120`), combined with `+`, not interacted cell effects
(`R/fct_fit_model.R:38-60`). Area-specific changes across rounds can identify coefficients and confound weather
effects. A synthetic `fixest` probe estimates a coefficient of 1 for a regressor constant within every
area-round cell but varying across those cells.

**Practical change:** describe residual variation after additive area and time effects, explicitly acknowledging
area-specific time-varying confounding. Do not silently change the estimator. If within-cell identification really
is intended, assess an area-by-round specification as a separate methodological decision, with identification/support
diagnostics and numerical parity checks. Add a small specification test distinguishing additive from interacted FE.

### 2. RIF simulation bands do not implement the stated independence of quantile equations

**Confirmed, high priority for RIF uncertainty.** `docs/22_model_rif.md:105` and
`docs/33_uncertainty.md:100-104` say cross-quantile covariance is omitted and equations are independent.
Yet adjacent quantile loadings are added in the same coefficient space
(`R/fct_rif_sim.R:769-785`); aggregation then squares their sum
(`R/fct_aggregation_delta.R:179-189`). This introduces cross-quantile covariance through shared standardized
coefficient shocks. With two scalar unit loadings at a midpoint, the actual variance is 1; independent quantile
blocks give 0.5. Equation (6.1) describes the implemented blend but contradicts the accompanying independence claim.
The existing interpolation test preserves this blend rather than validating independence
(`tests/testthat/test-fct_rif_sim.R:17-50`).

What the code implies is not a deliberate covariance model either. Every equation's deviation is
$\beta_k - \hat\beta_k = L_k z$ with one shared standard-normal $z$, so $\mathrm{Cov}(\beta_k, \beta_l) = L_k L_l'$.
That depends on the column order of the Cholesky factors, and it is close to perfect correlation when $L_k \approx L_l$.
It applies across all nine equations, not only between neighbouring grid points: households at $\tau = 0.1$ and
$\tau = 0.9$ also share $z$.

Independence is not a better target. The nine RIF equations are fitted on the same sample with the same design
(stacked multi-LHS `feols`, `R/fct_fit_model.R:185`), so adjacent quantile estimates are strongly positively
correlated. Treating them as independent would probably make the bands for population aggregates too narrow.

**Practical change, in order:**

1. Correct the documentation now. Replace the independence statements in `docs/22_model_rif.md:105` and
   `docs/33_uncertainty.md:104` with the approximation that is implemented (shared standardised shocks), and say that
   it depends on column order.
2. Preferred fix: estimate the joint cross-equation covariance. Because the equations share the design, the sample
   and the clusters, the stacked cluster sandwich
   $\hat V_{kl} = (\ddot X'\ddot X)^{-1}\big(\sum_p \ddot X_p'\hat e_{kp}\hat e_{lp}'\ddot X_p\big)(\ddot X'\ddot X)^{-1}$
   costs little more than the nine separate ones. Draw from it with one factor of the joint active block, and keep
   the shared draws between baseline and policy. Check first that every equation uses the same estimation rows.
3. Use separate per-quantile blocks (independence) only as a stated fallback, for example as a lower-bound
   sensitivity.

Test the result against Monte Carlo draws from the target joint covariance, including households at
non-adjacent quantiles. The fix moves Step 2 and Step 3 bands for the quantile model, so it needs the
`wise-numeric-change` procedure. The effect on real-data bands has not been measured.

### 3. Climate-member completeness is relative to other members, not the required grid

**Confirmed, high priority when climate coverage is incomplete.** `docs/31_climate_scenarios.md:61` promises every
location-month and selected variable. The check instead sets `n_expected = max(n_rows)` among observed members
(`R/fct_get_weather.R:2053-2070`). If all members lack the same key, they can all pass. Even equal counts do not
establish equal key sets. The subsequent inner join can omit affected weather rows
(`R/fct_get_weather.R:2144-2149`), potentially changing the population represented by a scenario.

**Practical change:** construct the expected location-month keys independently from the requested locations and
period; compare each member's keys and non-missing variables against that grid. Report excluded members and missing
keys. Test common missing coverage and different missing keys with equal row counts, not only a partial member
compared with complete ones. A synthetic replay of the current count check accepted two members with 11 of 12
required monthly keys. Actual missing coverage in supplied climate files was not assessed.

### 4. Two policy outputs mix incompatible weighting units

**Confirmed, medium priority; scope depends on the input weights.** Both cases need a frame with no literal
`weight` column, or with unequal weights. The current harmonised surveys always carry `weight` (see the
weight-alias item below), so the first case only affects user-supplied unweighted inputs. The second case applies
to current data whenever weights are unequal.

- **Cost-effectiveness without survey weights:** the poverty-rate/gap effect is an equal-row statistic when no
  literal `weight` column exists (`R/fct_simulations.R:788-792`; `R/fct_aggregation.R:72-88`), but the represented
  population for household analysis is the sum of household sizes (`R/fct_sp_effectiveness.R:206-219`). Multiplying
  the former by the latter (`:329,362`; caller `R/fct_step3_tables.R:527-530`) does not count people consistently,
  contrary to `docs/45_cost_effectiveness.md:18,30-40`. In a source-only example with household sizes 1 and 9,
  baseline welfare 1 and 3, poverty line 2, and only the first household lifted, the reported count is 5 rather than
  1. A cost of 100 is reported as 20 per person rather than 100. Recompute the scored effect with person weights on
  the same support as costs, or mark person-based scoring unavailable for this case. Do not change every stage's
  weight convention merely to repair this view. Add the unequal-household-size fixture.
- **Sector targets with unequal survey weights:** observed shares initialize the controls using weights
  (`R/fct_policy_sim.R:229-247`), but changed target shares become raw row counts (`:1403-1430`). Thus the slider
  and the applied target use different populations; `docs/41_policy_levers.md:86-92` does not make this distinction
  clear. Apply weighted allocation consistently, or explicitly label and initialize targets as row shares.
  Test achieved shares with skewed weights, allowing an explicit whole-row approximation tolerance.

### 5. Reproducibility records can describe inputs other than those actually used

**Confirmed, medium priority.** Two independent paths need correction:

- **Batch cache invalidation:** survey checksums are calculated in the grid
  (`R/fct_batch_targets.R:203-213`) and written to the new manifest (`:1112-1120`), but the data-stage work item
  carries only the specification and metadata digest (`:249-260`), not those survey checksums. Changing a survey
  file without changing its metadata/specification can therefore leave the data branch and downstream results
  cached while the manifest records the new file hash. A helper probe produced identical data work items after
  changing only the survey SHA. This undermines the input-change guarantee in `docs/52_batch_runs.md:29-33`.
  Include the relevant selected-file fingerprints in each data work item; audit weather/location input dependencies
  too. Add a two-run integration test changing one input file and confirming affected branches rerun.
- **Run seed provenance:** `R/app_server.R:168-194` does not pass a seed to `wise_provenance()`, whose default and
  recorded value are 123 (`R/fct_provenance.R:151-152,175-179`). Imported seeds are applied to computations
  (`R/app_server.R:207-209`; `R/mod_2_01_weathersim.R:1020,1287`), but per-step provenance still reports 123.
  A helper probe with a stored signature seed of 999 returned 123. This contradicts the run-time provenance
  promise in `docs/51_reproducibility.md:57-63`. Capture the actual seed immutably with each result and read it
  there, rather than substituting the current live seed at export. Test a non-default seed and a later seed change.
  The export bundle also contradicts itself: its top-level `random_seed` is the live seed
  (`R/fct_export.R:1489-1491` via `wise_current_seed()`), while each step's provenance record says 123.

The batch finding is confirmed at the work-item dependency level; a complete second `targets` run was not performed.

## Smaller practical corrections

These are confirmed but lower priority than the findings above.

- **Weather support is not fitted-sample support.** The historical-window benchmark is explicitly acknowledged in
  `docs/30_simulation.md:86-91`, so it is not an undocumented implementation error. However,
  `docs/50_assumptions_limitations.md:51` describes an estimation-sample check. The actual reference uses historical
  weather at baseline locations/months (`R/fct_run_simulation.R:796-799`), not fitted observations. In a synthetic
  example, estimation weather `{0,1}`, archive `{0,1,100}`, and scenario 50 produce no archive warning despite
  exceeding all fitted weather. Keep the archive comparison as context, label it accurately, and add a separate
  fitted-sample check if the result is to warn about regression extrapolation. A marginal check still does not
  establish joint weather/moderator support.
- **Strict poverty cutoff in residual variance:** `.headcount_resid_variance()` uses `ecdf(resid)(threshold)`, which
  includes equality (`R/fct_aggregation_delta.R:255-260`), whereas poverty uses strict `<`
  (`R/fct_aggregation.R:74`; `docs/33_uncertainty.md:49`). With prediction 0 on the log scale, line 1 and residuals
  `{0,1}`, it returns variance 0.25 although no draw is poor and the variance is zero. Use the empirical probability
  strictly below the cutoff and test ties. Lowest priority of this list: with continuous residuals and thresholds,
  an exact tie almost never happens, so fix it when the function is next changed.
- **Equations lag the transfer correction:** `docs/44_decomposition.md:74-78` compounds cash through later
  exponential channels, but current code keeps the cash amount outside those exponents
  (`R/fct_policy_metric_decompose.R:218-231,898-928`), consistent with Section 5 of that page. Rewrite Section 4
  with separate non-cash log shift and level cash amount. This is a documentation defect, not evidence that DOC-11
  remains broken. Also correct the stale claim that RIF contrast SEs omit within-equation term covariances
  (`docs/24_model_results.md:45`; full covariance is used in `R/fct_results.R:229-241`).
- **Weight aliases:** `docs/10_data.md:80` promises that the first of `weight`, `hhweight`, `wgt`, `pw` is used by
  every weighted statistic in Steps 2 and 3, and `survey_weight_column()` (`R/fct_incidence.R:29-33`) implements that
  order. Several core consumers still read only a literal `weight` column: the Step 2 and 3 aggregation
  (`R/fct_simulations.R:791`), the cost-effectiveness population (`R/fct_sp_effectiveness.R:213`), the sector shares
  (`R/fct_policy_sim.R:235`) and `default_lcu_poverty_line()` (`R/fct_outcome.R:94`). `run_simulation()` resolves the
  alias (`R/fct_run_simulation.R:532`) but uses it only in a warning. For a survey that has only `hhweight`, the
  headline metrics would be unweighted, while the dropped-share and decomposition paths would be weighted. The
  current harmonised data always carry a `weight` column (confirmed by the maintainer, 2026-10-26), so this is latent
  and low priority. Fix: rename the resolved alias to `weight` once, where the survey is loaded, and test an
  alias-only input end to end. Alternatively, state in `docs/10_data.md` that `weight` is required and drop the alias
  promise.
- **Terminology:** In `docs/45_cost_effectiveness.md:14,24`,
  distinguish annual net person-years from unique people and say effects average years within each member before
  averaging members. In `docs/42_social_protection.md:45`, describe concentration values as random-order sampling
  weights, not final household inclusion probabilities.

## Accepted limitations and uncertainties

The explicitly acknowledged limitations are reasonable for this tool's stated purpose: no growth, migration,
general equilibrium or causal policy identification; no survey-design variance where design variables are absent;
unweighted estimation; fixed climate-template variability; equal climate-member weights; RIF local approximation,
rank clipping and generated-outcome uncertainty; approximate non-smooth metric gradients; iid residual resampling;
and limited empirical tail support. See `docs/01_framework.md:98-113`, `docs/22_model_rif.md:90-107`,
`docs/31_climate_scenarios.md:73-89`, and `docs/50_assumptions_limitations.md:20-93`. These do not by themselves
justify adding complex estimators or new data requirements.

One conditional concern is the currency of shock loss-share budgets: `docs/43_shock_responsive_sp.md:82-86` does not
spell it out, while losses are converted to stored units and costs back to entry currency
(`R/fct_sp_shock.R:1103-1109,1143-1154`). Unequal PPP factors *within the same payout cell* can break a naive
entry-currency reading of the loss-share identity. This is not established as a defect in supported real inputs;
PPP may be constant within each cell. State the currency convention and validate that invariant before changing
the arithmetic. Whole-row weighted targeting can also be coarse with a dominant survey weight; report realized
reach, but the documented one-row tolerance is not itself refuted by a large-weight example.

## Validation and limits

Coverage: all methods topics in `docs/`, their mapped estimation, simulation, policy and aggregation paths, and
relevant tests. Inspection and small R probes confirmed the examples above; no production data or deployment was
used, and no browser workflow was run. This is not an independent re-estimation of the empirical weather response.

Focused tests passed with the project R environment:

```r
devtools::test(
  filter = "^fct.rif.sim$|^fct.sp.effectiveness$|^fct.batch.targets$",
  reporter = "summary"
)
```

The policy review also passed focused shock-correction and regular-SP/lever tests. An initial `Rscript --vanilla`
test attempt could not load dependencies; rerunning without `--vanilla` loaded the project environment and passed
the focused tests above. No full suite, real-data parity, climate-coverage audit or end-to-end batch invalidation
test was run. Passing current tests does not refute cases their fixtures do not exercise.

Recommended order: correct the documentation for identification and RIF covariance (no numbers move); repair
climate completeness and reproducibility; make the sector targets use weights consistently; implement the joint
RIF covariance; normalise the weight aliases; then align the smaller equations and diagnostics. Numerical fixes
should receive failing-before/passing-after tests and the repository's required before/after headline comparisons
before adoption.

## Revision notes

Changes made in the second pass:

- **Finding 2:** the code fact stands. The recommended fix changed from independent per-quantile blocks to a joint
  cross-equation covariance, because the equations share sample and design and so are positively correlated.
  Independence is now a fallback, and a documentation correction comes first. The finding also notes that the
  implied correlation depends on Cholesky column order and applies to all quantile pairs.
- **Weight aliases:** widened from `default_lcu_poverty_line()` to the core Step 2 and 3 aggregation and two policy
  paths, with a single normalisation fix. Latent for current data, which always carry `weight`. Finding 4 now
  states that it depends on this.
- **Finding 5:** added that the export bundle's top-level seed and its per-step provenance disagree.
- **Poverty-cutoff ties:** downgraded to lowest priority.
- **Recommended order:** documentation-only corrections first.

Findings 1, 3 and 4 (sector targets), the batch half of 5, and the remaining smaller items were re-checked and kept
unchanged.
