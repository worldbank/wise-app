# Step 1, Step 2, and Step 3 Performance Audit and Optimization Recommendations

**Date:** 2026-09-11
**Status:** Audit complete. The implementation scope in the final delivery plan
is approved; all other findings remain proposed.
**Scope:** Step 1 (`mod_1`), Step 2 (`mod_2`), and Step 3 (`mod_3`)
orchestration, their directly associated data preparation, modelling, weather,
simulation, policy, aggregation, decomposition, and diagnostic helpers.
**Audited revision:** `aa42136` on `main`.

## Executive Summary

Step 1 already contains a substantial set of targeted performance improvements,
including shared summary aggregation, load signatures, button-time snapshots,
weather caching, map payload keys, fit-object slimming, and cached model design
matrices. This audit treats those changes as the baseline and does not propose
reimplementing them.

The strongest remaining candidates are:

1. **P2: rewrite sample-density allocation with shared `collapse::GRP()` group
   IDs.** On 451,199 production survey rows and 214,260 H3 mapping rows, the
   candidate was 10.6 times faster than the current implementation while
   matching its output within `1e-12`.
2. **P3: isolate map fit-key reads.** Three map observers currently read and
   write their own reactive keys, scheduling a redundant second observer run.
   This is a small code change with high equivalence confidence.
3. **P8: cache survey-wave metadata per completed survey load.** A production
   scan took 441 ms and allocated 19.6 MB; the result is immutable for a given
   `survey_version()` and is requested by several outputs.
4. **P1: precompute the multi-tau RIF inputs once.** On the production Colombia
   outcome vector, this reduced isolated RIF preparation from 100.9 ms to
   74.4 ms and allocation from 279 MB to 141 MB with exact output parity in the
   benchmark.
5. **P4: project the fit-time `.snap$survey_weather` frame.** This can reduce
   stale-fit memory retention, but only after an explicit retained-column
   contract is established. `model_fit$train_data` must not be removed or
   casually slimmed because Steps 2 and 3 depend on it.

No broad migration from `dplyr` to `collapse`, `data.table`, `kit`, or `vctrs`
is recommended. Each substitution should be made only where isolated evidence
and characterization tests establish both a gain and strict behavioral parity.

## Review Constraints

All recommendations in this document are constrained as follows:

- No changes to UI/UX, input or output IDs, HTML structure, visual layout,
  labels, map controls, or user-visible sequencing.
- Mathematical and logical behavior must remain equivalent, including handling
  of `NA`, `NaN`, `Inf`, factors, empty reactives, duplicate join keys, row
  ordering, and deterministic random-number behavior.
- Existing button-time snapshot behavior must remain intact. Loaded results must
  not begin following unsubmitted sidebar selections.
- Existing downstream contracts with Steps 2 and 3 must remain intact.
- Refactoring is authorized only for the IDs and gates in the final delivery
  plan. All other findings remain audit-only proposals.

## Scope and Runtime Map

The Step 1 server is assembled in `R/mod_1_modelling.R:90-235` and includes:

| Stage | Primary file | Main responsibility |
|---|---|---|
| 1.01 | `R/mod_1_01_sample.R` | Sample and analysis-unit selection |
| 1.02 | `R/mod_1_02_surveystats.R` | Survey loading, H3 mapping, descriptive statistics |
| 1.03 | `R/mod_1_03_outcome.R` | Outcome selection, summaries, distribution and maps |
| 1.04 | `R/mod_1_04_weather.R` | Weather specification |
| 1.05 | `R/mod_1_05_weatherstats.R` | Weather loading, merge, summaries, plots and maps |
| 1.06 | `R/mod_1_06_model.R` | Model configuration and optional LASSO selection |
| 1.07 | `R/mod_1_07_results.R` | Model fit, results, tables and exports |
| 1.08 | `R/mod_1_08_modelfit.R` | Model diagnostics |

The principal computational helpers audited were:

- `R/fct_surveystats.R`
- `R/utils_mod_1_helpers.R`
- `R/fct_outcome.R`
- `R/fct_weatherstats.R`
- `R/fct_get_weather.R`
- `R/fct_model_select.R`
- `R/fct_fit_model.R`
- `R/fct_rif_sim.R`
- `R/fct_results.R`
- `R/fct_results_table2.R`
- `R/fct_step1_headline.R`
- `R/fct_loc_panel.R`
- `R/fct_hexmap.R`
- `R/fct_load_data.R`

## Existing Optimizations to Preserve

The repository already includes optimization work through the current PERF
series. The following mechanisms should be treated as intentional baseline
behavior:

- Survey and weather load signatures and completion generations.
- Shared survey summary aggregation in
  `R/mod_1_02_surveystats.R:120-148`.
- Button-time outcome and weather snapshots.
- Separation of map payload updates from camera-fit keys.
- Slim continuous-weather storage for plotting.
- Conditional, run-time-only LASSO execution.
- Fit-object slimming and the single cached fit-3 design matrix.
- Cached weather retrieval and early release of temporary weather objects.
- `survey_version()` invalidation used by downstream stale tracking.
- Hidden-output behavior required for pipeline/configuration replay.

These mechanisms should not be removed merely to simplify the reactive graph.

## Benchmark Methodology

### Production workload

Production data was read from:

```text
~/Library/CloudStorage/OneDrive-WBG/wiseapp - Documents
```

The primary stress case combined the two Colombia household waves and their H3
mapping files:

```text
microdata/hh/COL/COL_2008_GEIH_GMD_hh.parquet
microdata/hh/COL/COL_2018_GEIH_GMD_hh.parquet
microdata/h3/COL/COL_2008_GEIH_GMD_h3.parquet
microdata/h3/COL/COL_2018_GEIH_GMD_h3.parquet
```

The resulting isolated workload contained:

- 451,199 survey rows;
- 214,260 H3 mapping rows;
- 582 distinct `loc_id` values;
- 53,347 output H3 cells;
- 2 survey waves.

Parquet loading was excluded from the timed expressions. Benchmarks therefore
measure the R-side operation under review rather than OneDrive or DuckDB I/O.
`bench::mark()` medians are reported. These are local development-machine
measurements, not end-to-end Shiny latency measurements.

### Synthetic workloads

Synthetic data was used where production data did not expose a proposed helper
in isolation or where adversarial missing/non-finite values were required.
Synthetic measurements are labeled separately and should not be treated as
production acceptance evidence.

## Bottleneck Inventory and Proposed Interventions

### P1 - Precompute multi-tau RIF inputs

**Priority:** High
**Confidence:** High for the default Step 1 path
**References:** `R/fct_fit_model.R:243-258`, `R/fct_rif_sim.R:40-69`

**Current pattern**

Step 1 constructs nine RIF outcomes. Although the density estimate is already
hoisted, each call to `compute_rif()` independently:

- constructs `!is.finite(y)`;
- subsets the finite outcome vector;
- computes one type-7 quantile;
- interpolates the density at that quantile;
- allocates and fills a result vector.

**Proposed intervention**

For the default nine-tau fit path, compute the finite mask and finite outcome
once, calculate all type-7 quantiles in one call, interpolate all density values
once, and then construct one output vector per tau. Do not construct an `N x 9`
logical comparison matrix unless peak memory proves acceptable. Preserve the
public `compute_rif()` API for arbitrary single taus, custom bandwidths, and
supplied density objects.

**Measured evidence**

Production Colombia `welfare`, 451,199 rows, nine taus:

| Implementation | Median | Allocation |
|---|---:|---:|
| Current repeated calls | 100.9 ms | 279 MB |
| Precomputed candidate | 74.4 ms | 141 MB |

The benchmark outputs were exactly equal with attributes checked.

Synthetic 300,000-row evidence showed a larger timing improvement: 90.4 ms to
47.1 ms, with allocation falling from 184 MB to 93 MB.

**Expected impact**

Moderate improvement to RIF model preparation and a meaningful reduction in
allocation pressure. Full model fitting may dilute the elapsed-time percentage
because the 27 downstream fits remain dominant.

**Equivalence requirements**

- Preserve non-finite filtering and original row alignment.
- Preserve type-7 quantiles and tau ordering.
- Preserve density `n = 1024`, interpolation behavior, density floors, and
  warning frequency.
- Test tied, constant, skewed, very small, and non-finite outcomes.
- Compare fitted coefficients, `rif_grid`, direct/fallback predictions,
  `delta_i`, and `F_loading` within an explicitly declared tolerance.

**Dependencies:** No new package dependency.

### P2 - Replace density allocation grouping passes

**Priority:** High
**Confidence:** Medium-high pending complete edge-case characterization
**References:** `R/fct_surveystats.R:483-530`, caller at
`R/mod_1_02_surveystats.R:93-105`

**Current pattern**

`allocate_units_to_cells()` performs:

- `dplyr::count()` over survey location keys;
- an `inner_join()` to H3 mappings;
- a grouped `mutate()` to compute population totals and allocations;
- a second grouped `summarise()` over H3 cells.

The grouping structure is rebuilt for each stage and the function runs whenever
the density map is recalculated for a wave.

**Proposed intervention**

Use shared `collapse::GRP()` objects for location and H3 groups. Derive survey
location counts, population totals, proportional/equal allocations, and final H3
totals using C-backed grouped operations. Retain the current duplicate-sensitive
inner join and explicitly restore the current output order.

**Measured evidence**

Production Colombia workload:

| Implementation | Median | Allocation |
|---|---:|---:|
| Current `dplyr` path | 434.8 ms | 54.4 MB |
| `collapse::GRP()` candidate | 40.9 ms | 51.7 MB |

This is a 10.6 times isolated speedup. Sorted output matched the current result
within `1e-12`.

A 200,000-row synthetic workload measured 443 ms versus 14.7 ms. The production
result is the more relevant estimate.

**Expected impact**

High for initial density-map construction and repeated wave toggles. Allocation
improvement is modest; this is primarily a CPU optimization.

**Equivalence requirements**

- Preserve character conversion of `year`.
- Preserve duplicate survey rows and duplicate H3 mapping rows.
- Preserve current inner-join multiplicity and unmatched-location behavior.
- Preserve handling of missing, zero, negative, and non-finite `pop_2020`.
- Preserve equal-split fallback and conservation of each location's unit total.
- Characterize `NA` H3 and missing join-key behavior explicitly.
- Compare schema, row ordering, fractional totals, and overlapping-location
  accumulation.

**Dependencies:** `collapse`, already a direct dependency.

### P3 - Prevent map observer self-invalidation

**Priority:** High
**Confidence:** High
**References:**

- `R/mod_1_02_surveystats.R:397-420` (`density_key`)
- `R/mod_1_03_outcome.R:316-373` (`cov_key`)
- `R/mod_1_05_weatherstats.R:1133-1177` (`wxmap_keys`)

**Current pattern**

Each map observer reads a reactive fit key inside `identical(...)` and later
writes that same key. The write invalidates the observer and schedules a second
execution, rebuilding the map payload even though the key then prevents a
second camera fit.

**Proposed intervention**

Use `shiny::isolate()` only around the cached-key read used for comparison. All
real dependencies, including data, version, specification, wave, month, view,
and geometry, must remain ordinary reactive reads.

**Expected impact**

Approximately one avoided payload construction and browser update attempt per
key change. The benefit increases with H3 footprint size.

**Equivalence requirements**

- Verify one observer execution per external invalidation.
- Verify payload and legend updates on every legitimate data/view change.
- Verify camera fitting occurs on the same footprint/selection changes and not
  on recoloring-only changes.
- Verify pan/zoom preservation.

**Dependencies:** No new package dependency.

### P4 - Reduce retained fit-snapshot duplication

**Priority:** High for memory, conditional for implementation
**Confidence:** Medium
**References:** `R/mod_1_05_weatherstats.R:64-72`,
`R/mod_1_07_results.R:156-196`, `R/fct_fit_model.R:1119-1133`

**Current pattern**

The session may retain the live `survey_weather`, `survey_weather_cont`, and
`hist_cells` objects while a fitted model also retains:

- `model_fit$train_data`; and
- `.snap$survey_weather`.

The duplication is most consequential after a new weather load makes the prior
fit stale: both the old fit snapshot and new live data remain reachable.

**Proposed intervention**

Keep `model_fit$train_data` unchanged. Replace only `.snap$survey_weather` with
an explicitly contracted fit-time projection or metadata object containing all
fields needed by Step 1 plots, headlines, diagnostics, provenance, and exports.
Potential fields include selected weather terms, interaction moderators, factor
levels/reference bins, and the original fit-time row count.

**Measured evidence**

The two-wave production Colombia household frame contained 451,199 rows and 76
columns with a logical `object.size()` of 237.6 MB. An illustrative 12-column
projection was 63.7 MB. This is a sizing bound, not a measured RSS reduction:
R column sharing and later mutations determine actual process memory savings.

**Expected impact**

Potentially substantial session RSS reduction, particularly when a stale fit
coexists with newly loaded weather data.

**Equivalence requirements**

`.snap$survey_weather` is currently consumed by:

- `R/fct_provenance.R:148-151`;
- `R/fct_step1_headline.R:125-126`;
- `R/mod_1_07_results.R:442,470,490`;
- `R/mod_1_08_modelfit.R:112,121,265`.

Required tests must cover bin labels and levels, moderator ranges, residual
plots, headline translations, provenance row counts, and export output.

`model_fit$train_data` must retain its current contract. Steps 2 and 3 use it
for training prediction, residual matching, RIF ECDFs and columns, IDs, cluster
fields, active masks, policy corrections, and decomposition. Slimming that
object is not approved by this recommendation.

**Dependencies:** No new package dependency.

### P5 - Cache fit-scoped scenarios and headline results

**Priority:** Medium-high
**Confidence:** Medium-high
**References:** `R/mod_1_07_results.R:610-740`,
`R/fct_step1_headline.R:646-745`, `R/fct_step1_headline.R:1032-1043`

**Current pattern**

Headline cards compute effect scenarios and, for RIF, heterogeneity screens.
The focused table independently calls `step1_scenarios()` for every weather
variable. The headline export calls `step1_headline_table()`, which rebuilds the
complete card derivation instead of formatting the already computed result.

**Proposed intervention**

Create fit-scoped derived values when `model_fit_val()` changes:

- scenarios by weather variable;
- headline card result;
- tabular projection of that result;
- any RIF heterogeneity values used by more than one consumer.

Screen renderers, downloads, and export registration should consume those
values without recalculation.

**Expected impact**

Medium for linear/logistic fits and potentially high for eligible RIF fits,
where the heterogeneity screen performs additional model work.

**Equivalence requirements**

- Invalidate only on a completed fit generation.
- Preserve fit-time snapshot semantics and current error-to-`NULL` behavior.
- Confirm cards, focused table, CSV, and export values remain identical.

**Dependencies:** No new package dependency.

### P6 - Consolidate historical sample-cell scans and joins

**Priority:** Medium
**Confidence:** Medium pending duplicate-key characterization
**Reference:** `R/fct_weatherstats.R:821-868`

**Current pattern**

`join_hist_sample_cells()` scans the survey-weather frame separately to build:

- location-month household counts;
- wave/economy metadata;
- wave-date sample membership.

It then applies an inner join and two left joins to the historical frame.

**Proposed intervention**

Normalize date, year, and month fields once, then use a keyed `data.table`
workflow or reusable composite-key structures for the three survey-side
lookups. Preserve many-to-many behavior where duplicate keys exist.

**Expected impact**

Moderate, increasing with survey rows and historical date range. This should be
benchmarked on production historical weather before selection between
`data.table` and the current implementation.

**Equivalence requirements**

- Preserve duplicate multiplicity and `NA` key behavior.
- Preserve `is_sample`, economy fallback, `n_hh`, and output order.
- Compare exact row counts and values using fixtures with duplicate keys and
  missing dates.

**Dependencies:** `data.table` would become a new direct dependency if selected.

### P7 - Reuse weather plotting frames

**Priority:** Medium
**Confidence:** High
**References:** `R/mod_1_05_weatherstats.R:281-376`

**Current pattern**

Each weather distribution builder and renderer mutates the large
`survey_weather()` or `survey_weather_cont()` frame to recreate `countryyear`.
The merged survey frame already carries `countryyear`, and the repeated mutate
can occur once per plotted weather variable and once again for export builders.

**Proposed intervention**

Use the existing column when present. If a fallback is still required for
standalone callers, build one snapshot-scoped plotting reactive per source
frame rather than mutating separately inside every renderer.

**Measured evidence**

On the full 451,199-row, 76-column production Colombia frame:

| Work | Median | Allocation |
|---|---:|---:|
| Add `countryyear` once | 80.7 ms | 6.89 MB |
| Repeat four times | 348.5 ms | 31.71 MB |

**Expected impact**

Moderate when several weather plots render or exports are generated.

**Equivalence requirements**

Preserve labels, factor levels, outcome transforms, wave-label mapping, and the
separate continuous/binned frames.

**Dependencies:** No new package dependency.

### P8 - Cache survey-wave metadata per completed load

**Priority:** High
**Confidence:** High
**References:** implementation at `R/fct_surveystats.R:414-429`; repeated calls
in `R/mod_1_02_surveystats.R:357-362,467-477`,
`R/mod_1_03_outcome.R:302,429-463`, and
`R/mod_1_05_weatherstats.R:319,369`

**Current pattern**

`survey_wave_list()` selects, converts, deduplicates, labels, and sorts the same
loaded survey frame for several maps and plots.

**Proposed intervention**

Build one reactive wave-metadata value keyed to the completed
`survey_version()`, then pass or expose that value to Step 1 consumers. Do not
key it to the first intermediate `survey_data()` assignment during loading.
The weather map's existing separate `wave_list()` cache should remain tied to
its appropriate source frame.

**Measured evidence**

On 451,199 production Colombia rows, one recomputation took a median 441 ms and
allocated 19.6 MB. Reusing the already built two-row object was effectively
free.

**Expected impact**

High relative to implementation complexity, especially during initial output
rendering when several consumers request the same metadata.

**Equivalence requirements**

- Preserve `NULL` behavior and required-column checks.
- Preserve character conversion of `year`, economy fallback, duplicate labels,
  classes, and ordering.
- Test reloads with changed waves/economy names and identical selections.

**Dependencies:** No new package dependency.

### P9 - Share density allocation and mapped-location count work

**Priority:** Medium
**Confidence:** High
**References:** `R/mod_1_02_surveystats.R:400-439`,
`R/fct_surveystats.R:483-530`

**Current pattern**

After `density_cells(wave)` filters and allocates the survey and map frames, the
observer filters both frames again and performs `distinct()` plus `inner_join()`
solely to count mapped sample locations.

**Proposed intervention**

Return `n_locations` alongside the density cells/payload, or create one
wave-scoped intermediate containing both values. P9 should be implemented with
P2 so the optimized grouped pass supplies all needed outputs.

**Expected impact**

Moderate on large samples and wave toggles; avoids a second scan and join after
the primary allocation.

**Equivalence requirements**

The count must remain the number of unique sampled locations with positive
units and a valid H3 mapping, using the same wave filtering as the displayed
payload.

**Dependencies:** No dependency beyond P2's existing `collapse` use.

### P10 - Replace outcome map grouped copies

**Priority:** Medium-low
**Confidence:** Medium
**References:** `R/fct_outcome.R:465-475`, `R/fct_outcome.R:608-619`

**Current pattern**

Outcome coverage and mean-map helpers create mutated frames and then group and
summarize them. The mean path also filters a temporary numeric column.

**Proposed intervention**

Use `collapse::GRP()` with grouped `fmean()`/`fnobs()`, or a small
`data.table` aggregation if P6 introduces that dependency. Explicitly restore
current row order.

**Expected impact**

Low-to-moderate, mainly for large map inputs.

**Equivalence requirements**

Preserve missing-key groups, unweighted means, non-finite coercion, counts,
factor handling, column types, and ordering.

**Dependencies:** Prefer existing `collapse`; do not add `data.table` solely for
this item.

### P11 - Remove the redundant pre-binning sort

**Priority:** Low-medium
**Confidence:** Medium-high
**Reference:** `R/fct_get_weather.R:805-837`

**Current pattern**

The historical result is sorted at lines 805-811 and the binned subset is
sorted again before `.compute_breaks()`. Equal-frequency calculations sort
through `quantile()`; equal-width and custom breaks use extrema; K-means already
receives the deterministic sorted input from the earlier ordering.

**Proposed intervention**

Remove the second sort after verifying no downstream consumer observes the
intermediate `hist_ref` ordering.

**Expected impact**

Small-to-moderate, proportional to historical rows and binned-variable count.

**Equivalence requirements**

Preserve K-means determinism, `with_seed()` behavior, break values, factor
levels, and returned weather ordering.

**Dependencies:** No new package dependency.

### P12 - Consolidate LASSO candidate-matrix preparation

**Priority:** Low-medium
**Confidence:** Medium
**References:** `R/fct_fit_model.R:414-423`, `R/fct_fit_model.R:437-447`,
`R/fct_fit_model.R:486-509`, `R/fct_fit_model.R:520-527`

**Current pattern**

Candidate columns are scanned separately for numeric type, all missing values,
complete cases, matrix conversion, and constants. The no-missing path creates
and checks another matrix.

**Proposed intervention**

After preserving the current candidate validation rules, construct the numeric
candidate matrix once and derive complete-case, all-missing, and constant masks
from it. Reuse that matrix for `glmnet`.

**Expected impact**

Low-to-moderate setup improvement and lower allocation. Cross-validation will
usually dominate elapsed time.

**Equivalence requirements**

Preserve candidate order, row-dropping messages, forced inclusion/exclusion,
zero-variance handling, deterministic results, and the distinct MI path. Do not
change factor or logical coercion.

**Dependencies:** No new dependency; retain the existing optional
`matrixStats` behavior.

### P13 - Avoid repeated RIF tidy/fallback probing

**Priority:** Low-medium
**Confidence:** Medium-low until numerical characterization
**Reference:** `R/fct_rif_sim.R:168-186`

**Current pattern**

RIF grid construction calls `broom::tidy()` for 27 sub-fits and can probe
several VCV fallbacks after failures.

**Proposed intervention**

Extract each sub-fit coeftable directly using the existing fallback policy,
then construct the tidy-shaped rows and confidence bounds without repeated
broom dispatch.

**Expected impact**

Moderate for RIF result preparation if VCV probing is material.

**Equivalence requirements**

Preserve term order, coefficient names, standard-error convention, confidence
intervals, degrees-of-freedom behavior, and fallback warnings. Direct fixest
coeftables must not be assumed byte-identical to `broom::tidy()`.

**Dependencies:** No new package dependency.

### P14 - Guard mutual-exclusion selectize updates

**Priority:** Low-medium
**Confidence:** Medium-high
**Reference:** `R/mod_1_06_model.R:558-590`

**Current pattern**

Each force-include/exclude observer unconditionally updates the opposite
selectize input. That client update wakes the counterpart observer even when
the effective choices and selection have not changed.

**Proposed intervention**

Compare proposed choices and selected values with the current effective values
before sending `updateSelectizeInput()`.

**Expected impact**

Fewer Shiny messages and reactive flushes. The absolute CPU impact is likely
small, but interaction should become less noisy.

**Equivalence requirements**

Preserve choice ordering, invalid-selection removal, mutual exclusion, selected
value restoration, and dynamic UI reconstruction.

**Dependencies:** No new package dependency.

### P15 - Keep weather map surfaces stable during control changes

**Priority:** Medium-high
**Confidence:** Medium
**References:** `R/mod_1_05_weatherstats.R:912-947`,
`R/mod_1_05_weatherstats.R:1126-1177`,
`R/mod_1_05_weatherstats.R:1251-1309`

**Current pattern**

`output$weather_map_layout` reads map values, wave, and month to build card
headers. Consequently, wave/month changes can rebuild the card and nested map
surface while the independent payload observer also updates the same map ID.
This risks unnecessary MapLibre and DOM lifecycle work.

**Proposed intervention**

Keep each map surface and card structurally stable after weather data loads.
Update only dynamic header text and payload/legend outputs. Existing IDs and
rendered HTML structure must remain unchanged from the user's perspective.

**Expected impact**

Potentially high for map interaction smoothness, but currently unbenchmarked.

**Equivalence requirements**

- Preserve card headers, layout, full-screen behavior, and all IDs.
- Preserve current no-data and historical-view messages.
- Verify camera position and full-screen state survive wave/month/view changes.
- Use browser-level tests or instrumentation; R-only helper tests are
  insufficient for this recommendation.

**Dependencies:** No new package dependency.

### P16 - Consolidate stale-signature observers

**Priority:** Low
**Confidence:** Medium-high
**Reference:** `R/mod_1_07_results.R:61-92`

**Current pattern**

Five observers independently call `.fit_sig_from_live()`. One logical user
change can invalidate more than one upstream reactive, causing repeated list
construction and signature comparison.

**Proposed intervention**

Build one reactive live signature and one observer that compares it with the
stored fit signature. Retain every current dependency, especially
`survey_version()`.

**Expected impact**

Small CPU/allocation reduction and a simpler invalidation graph.

**Equivalence requirements**

Test every stale transition independently and in combined updates. Preserve
`ignoreInit` behavior, completed-fit timing, and the rule that stale remains
true until a successful refit.

**Dependencies:** No new package dependency.

### P17 - Deduplicate population-weight denominators in weather SQL

**Priority:** Low-medium
**Confidence:** Medium
**Reference:** `R/fct_get_weather.R:734-747`

**Current pattern**

Generated population-weighted aggregation SQL emits the non-missing population
denominator twice for each weather variable: once in a condition and once in
the division.

**Proposed intervention**

Generate a single denominator expression and divide through
`NULLIF(denominator, 0)`, or materialize reusable numerator/denominator
expressions in a query stage if DuckDB's plan does not already eliminate the
duplicate work.

**Expected impact**

Low-to-moderate depending on selected weather-variable count and DuckDB's
common-subexpression handling. Inspect `EXPLAIN ANALYZE` before implementation;
the textual duplication may not imply duplicate execution.

**Equivalence requirements**

Verify all-missing values, zero weights, non-finite values, and current
`NA_real_` outcomes. Compare query plans, output types, and numerical values
within the repository's accepted weather tolerance.

**Dependencies:** No new package dependency.

## Prioritized Approval Sets

The findings can be approved independently, but the following groupings minimize
risk and duplicate work.

### Set A - Low-risk reactive and reuse improvements

- P3: isolate map fit-key reads;
- P7: reuse plotting frames;
- P8: cache survey-wave metadata;
- P14: guard selectize updates;
- P16: consolidate stale observers.

### Set B - Density-map compute path

- P2: grouped density allocation;
- P9: share the mapped-location count.

These should be implemented and tested together because both operate on the
same wave-scoped survey/map data.

### Set C - RIF path

- P1: precompute multi-tau RIF inputs;
- P5: cache fit-scoped scenarios/headline results;
- P13: direct RIF coeftable extraction.

P1 can safely precede P5/P13. P13 has the highest numerical-parity risk in this
set and should remain independently reversible.

### Set D - Weather data path

- P6: consolidate historical-cell joins;
- P11: remove the redundant sort;
- P15: stabilize map surfaces;
- P17: simplify weighted SQL after query-plan confirmation.

### Set E - Memory retention

- P4 only, behind a formal retained-snapshot schema and full Step 1 render/export
  regression coverage.

## Dependency Assessment

| Package | Current status | Recommendation |
|---|---|---|
| `collapse` | Direct dependency | Use for P2 and preferably P10. |
| `data.table` | Available locally but not a direct package dependency | Add only if P6 benchmarks faster with exact join parity. |
| `kit` | Not installed in the audited environment | Do not add; no compelling equivalent replacement was identified. |
| `vctrs` | Transitive/available | Do not add directly for these recommendations. |
| `bench` | Development dependency/tooling | Continue using for isolated benchmarks; not required at runtime. |

## Rejected or Deferred Alternatives

The following substitutions were considered but are not recommended:

1. **Grouped weighted quantiles via `collapse::fquantile()`.** The deployed
   grouped behavior does not establish strict parity with the current per-wave
   weighted quantile path.
2. **A general replacement of current summary-statistics code.** Existing
   PERF-40/41/42 work is already specialized and characterized. A tested
   per-column no-matrix alternative improved a synthetic workload only from
   133 ms to 124 ms while allocation remained about 202 MB.
3. **Simple `match()` replacements for weather merges.** Duplicate-key
   multiplicity is part of the current join behavior.
4. **Broad removal of sorting.** Returned row order and deterministic binning
   are observable contracts. Only the specifically identified second
   pre-binning sort is a candidate.
5. **Slimming or removing `model_fit$train_data`.** Step 2 and Step 3 depend on
   its outcome, formula variables, RIF columns, IDs, clusters, and row order.
6. **Broad `kit` replacements.** No `kit` candidate offered a demonstrated
   benefit sufficient to justify a new dependency and semantic review.
7. **Broad `data.table` migration.** It should be considered only for the
   duplicate-sensitive historical weather join after a production benchmark.
8. **Changing eager hidden-output behavior.** Some outputs must remain active
   for configuration replay and programmatic pipeline execution.
9. **Making results follow live selectors.** Outcome, weather, and fit tabs are
   intentionally tied to submitted snapshots.

## Validation Plan for Approved Work

### Common characterization tests

Every approved compute rewrite should test:

- empty input and missing required columns;
- `NA`, `NaN`, `Inf`, `-Inf`, zero, and negative values where applicable;
- factor levels, labels, and reference levels;
- duplicate keys and duplicate rows;
- integer versus character year fields;
- exact schema and row ordering;
- numerical parity under a documented tolerance;
- deterministic output under the existing seed policy.

### Reactive tests

Approved reactive changes should verify:

- exact invalidation counts where possible;
- no missing legitimate dependency;
- no self-invalidating second execution;
- unchanged snapshot and stale-state timing;
- unchanged output IDs and values;
- unchanged map fit/recolor behavior.

### End-to-end gates

Before merging approved changes:

1. Run the complete Step 1 test suite.
2. Run Step 2 and Step 3 contract tests for any fit/snapshot change.
3. Compare production Colombia output frames and plots before and after.
4. Record cold and warm end-to-end Step 1 timings for at least one small and one
   large country workload.
5. Record peak RSS for P4, not only `object.size()`.
6. Check map camera/full-screen behavior manually or with browser automation for
   P3 and P15.

## Baseline Validation Performed

The following targeted tests passed during the audit:

```text
tests/testthat/test-fct_surveystats.R
tests/testthat/test-mod_1_03_outcome.R
tests/testthat/test-mod_1_05_weatherstats.R
tests/testthat/test-fct_rif_sim.R
tests/testthat/test-fct_get_weather.R
tests/testthat/test-make_stats_dt.R
```

The production-data benchmark read source parquet files without modifying or
persisting production data. No application source code was changed as part of
the audit.

## Decision Status

All Step 1 items P1 through P17 remain **proposed**. Implementation should begin
only after explicit approval of individual IDs or one of the grouped approval
sets.

# Step 2 Performance Audit and Optimization Recommendations

## Step 2 Executive Summary

Step 2 is correctly identified as the application's longest and most
memory-intensive stage. Its cost is driven by two multiplicative expansions:

1. Weather retrieval expands each selected survey location over historical and
   future months, SSPs, periods, and available climate models.
2. Simulation joins each weather key back to the fixed survey population and
   retains per-observation predictions plus, when coefficient uncertainty is
   enabled, an `N x P_active` factor-loading matrix.

The existing Step 2 optimization program has already implemented the most
important broad changes: weather caching, DuckDB projection/filtering, wide
climate-reference reuse, serial per-key processing, direct RIF prediction,
compact shared payloads, lazy aggregation, and early release of temporary
frames. Previously rejected experiments were not re-proposed.

The strongest new findings are:

1. **S2-P1: filter `selected_surveys` to the selected Step 2 baseline before
   weather retrieval.** On production Colombia data this reduced a one-SSP,
   one-period fetch from 24.9 seconds to 8.9 seconds and halved weather memory
   from 412.8 MB to 206.7 MB. This is the first recommendation to implement.
2. **S2-P2: project the survey frame before simulation joins.** A representative
   production join fell from 60.5 MB to 16.0 MB and allocated 34.0 MB instead
   of 78.6 MB when unrelated survey columns were excluded.
3. **S2-P3: retain only residual context in `shared_context$train_aug`.** The
   production-sized object fell from 244.5 MB to 34.4 MB for original residuals
   and 3.4 MB for resampling.
4. **S2-P4: stream weather keys from `get_weather()` into the serial simulation
   consumer.** The current function materializes all future member frames before
   the first simulation starts. This is the main architectural route to lowering
   peak RSS, but it requires a new producer/consumer contract and external RSS
   benchmarking.
5. **S2-P5: share immutable key columns across future climate members.** On the
   production Colombia future workload, all 16 members had identical key
   columns. A shared-key representation reduced logical weather size from
   194.6 MB to 68.1 MB, a 65% reduction.
6. **S2-P16/S2-P17: benchmark bounded DuckDB threading and one reusable
   location-month materialization.** These offer the strongest remaining query
   speed potential, but require process-tree RSS and numerical-tolerance gates.
7. **S2-P21: make the unused aggregation weighting arm lazy.** Weighted surveys
   currently compute both weighted and unweighted results even though the UI
   consumes the weighted branch.

S2-P1 through S2-P3 are substantially simpler and should precede streaming,
parallelism, or broad storage changes.

## Step 2 Scope and Runtime Graph

Step 2 is mounted by `R/mod_2_simulation.R:75-159` and consists of:

| Stage | Primary file | Main responsibility |
|---|---|---|
| 2.01 | `R/mod_2_01_weathersim.R` | Configuration, run trigger, simulation state |
| 2.02 | `R/mod_2_02_results.R` | Lazy aggregation, tables, plots and exports |
| 2.03 | `R/mod_2_03_diagnostics.R` | Weather support and simulation diagnostics |

The hot execution path is:

```text
mod_2_01_weathersim_server()
  -> fct_run_simulation()
     -> get_weather()
        -> historical ERA5 query
        -> CMIP6 historical reference
        -> SSP / period / model delta queries
        -> collect all result frames
     -> shared fit/residual/RIF preparation
     -> serial loop over historical and future member keys
        -> run_sim_pipeline()
           -> survey/weather join
           -> fixest or RIF prediction
           -> design matrix and factor loading
           -> compact per-key payload
  -> mod_2_02_results_server()
     -> lazy per-method aggregation and display transforms
  -> mod_2_03_diagnostics_server()
     -> weather payload resolution and diagnostic frames
```

Step 2 consumes the Step 1 selected outcome, weather specification, selected
survey metadata, survey-weather frame, fitted model, stored weather breaks, and
survey version. Step 3 consumes the exact Step 2 baseline survey and compact
historical/scenario pipelines; therefore retained member-specific weather,
alignment IDs, factor loadings, and residual context are downstream contracts.

## Existing Step 2 Decisions to Preserve

The authoritative prior decision record is
`review/step2-optimization-decision-record.md`. The following are current
production defaults and should remain the comparison baseline:

| Setting | Current default |
|---|---|
| `payload_mode` | `"compact"` |
| `weather_storage` | `"memory"` |
| `weather_collect` | `"fast"` |
| `direct_rif_predictions` | `TRUE` |
| `join_cache` | `FALSE` |
| Key execution | Serial |

Already implemented and not re-proposed:

- Pure serial compute boundary in `R/fct_step2_compute.R`.
- Compact payload and shared context in `R/fct_step2_payload.R`.
- Immediate per-key assembly and early local release.
- Remote weather disk cache and projected parquet reads.
- Wide climate-reference materialization.
- Fast and bounded weather collection modes.
- Direct RIF prediction, shared training ECDF, and metadata reuse.
- Shared training prediction/residual preparation.
- Active coefficient masks and one factor-loading matrix per key.
- Lazy Results aggregation and method-aware aggregation cache keys.
- Failure ledger and partial future-member publication semantics.
- Analytic Step 3 policy delta path.

Previously rejected or disabled approaches remain rejected unless new evidence
is produced:

- Survey-side string-key join cache: slower and higher RSS.
- Row-batched RIF prediction: approximately three times slower.
- Reference weather as default: lower memory but approximately 80% slower.
- Shared SSP-wide monthly cache: exceeded memory/vector limits.
- Broad `collapse`/`kit` aggregation substitution: no production runtime gain.
- Captured-closure `mirai` prototype: worker serialization failure.

## Step 2 Production Benchmark Workload

The same production root used for the Step 1 audit was used:

```text
~/Library/CloudStorage/OneDrive-WBG/wiseapp - Documents
```

Targeted Step 2 benchmarks used Colombia's 2018 GEIH household baseline,
selected weather variables `t` and `spei6`, a 1991-2020 historical period, and,
where specified, SSP2-4.5 for 2025-2035.

Relevant dimensions were:

- 231,087 baseline survey rows;
- 76 source survey columns;
- 244,440 weather rows per historical/future member;
- 16 usable future climate members for the selected SSP/period after the
  current incomplete-model filter;
- two selected Step 1 survey waves before baseline filtering.

These are isolated local-data benchmarks. They exclude remote network latency
and do not replace end-to-end process-tree RSS measurements with
`dev/run_step2_benchmark.sh` and `/usr/bin/time -l`.

## Step 2 Bottleneck Inventory and Proposed Interventions

### S2-P1 - Restrict weather retrieval to selected baseline surveys

**Priority:** Critical
**Confidence:** High, with a numerical-tolerance contract
**References:** `R/mod_2_01_weathersim.R:478-486,697-703`,
`R/fct_run_simulation.R:165-182`, `R/fct_get_weather.R:621-731`

**Current pattern**

Step 2 correctly filters `survey_weather()` to the user's selected baseline
wave and passes that filtered frame as `svy`. It nevertheless passes the full
Step 1 `selected_surveys()` table as `ss`. `get_weather()` then loads H3 mapping
rows and computes weather for every selected Step 1 wave, even though rows from
non-baseline waves cannot join the baseline simulation population.

**Proposed intervention**

At button time, derive `ss_baseline` from the exact selected baseline values and
pass it to `fct_run_simulation()`/`get_weather()`. Match on the same baseline
identity currently used by `baseline_svy`: `code|year`. That identity does not
distinguish same-code/same-year survey rounds by `survname` or `source`; changing
it is a separate behavioral decision and must update both frame and metadata
filtering together. Retain `source`, which `get_weather()` uses to construct H3
filenames, plus the other metadata columns consumed downstream. Multi-baseline
selections must retain all selected waves.

**Measured evidence**

Production Colombia, local files, `t` and `spei6`:

| Workload | Full Step 1 surveys | Baseline-only surveys | Change |
|---|---:|---:|---:|
| Historical 1991-2020 | 1.750 s | 1.354 s | 23% faster |
| Historical weather size | 24.3 MB | 12.2 MB | 50% smaller |
| SSP2-4.5, 2025-2035 | 24.887 s | 8.911 s | 64% faster |
| Full weather-result size | 412.8 MB | 206.7 MB | 50% smaller |

The baseline-only future result contained the same 16 future keys, plus the
historical key: 17 total. Values for every common key matched within `1e-12`;
the historical `spei6` maximum difference was `2.22e-16`, attributable to
floating-point aggregation order. Exact byte parity should therefore not be
promised unless query ordering is additionally pinned.

**Expected impact**

Very high for common workflows in which Step 1 loaded multiple survey waves but
Step 2 simulates the latest wave. The gain scales with the number and size of
excluded survey waves and applies before both weather retention and simulation.

**Memory impact**

This reduces weather rows, query intermediates, retained weather, and downstream
join work proportionally. It is the highest-value low-complexity memory change.

**Equivalence requirements**

- Use the exact baseline selection, not merely `max(year)`.
- Reproduce the current `code|year` identity unless the baseline selector and
  `baseline_svy()` contract are intentionally changed together.
- Preserve multi-country and multi-baseline selections.
- Preserve survey `source`, `survname`, and filename construction.
- Test duplicate survey labels and same-year surveys.
- Compare all weather keys, row counts, ordering, bins, and values under the
  accepted weather tolerance.
- Confirm Step 3 uses the same baseline survey and member weather as Step 2.

**Dependencies:** No new package dependency.

### S2-P2 - Project survey columns before every simulation join

**Priority:** Critical for peak memory
**Confidence:** Medium-high after retained-column characterization
**References:** `R/fct_run_simulation.R:295-307`,
`R/fct_simulations.R:535-561,590-755`

**Current pattern**

The shared `svy_prepared` object drops selected weather and outcome columns but
retains every other survey column. Each weather key joins this wide frame to
weather before prediction. `predict.fixest()`, RIF prediction, factor-loading
construction, residual alignment, and Step 3 need a specific subset, not the
entire 76-column production survey frame.

**Proposed intervention**

Build a formal per-engine survey projection before the key loop. Retain:

- weather join keys: `code`, `year`, `survname`, `loc_id`, `int_month`;
- all model formula variables, interaction variables, and fixed effects;
- cluster fields required by uncertainty logic;
- selected ID and weight columns;
- policy fields only if the active Step 2/3 contract requires them in `svy`.

Use that projected frame for `prepare_hist_weather()` and prediction. Keep the
separate raw baseline `svy` contract discussed under S2-P10. `.svy_row_id` is
generated after the projected survey rows are selected; it is not an input
column to retain. RIF prediction still reads outcome/baseline-weather values
from the separate raw baseline via that generated row index, so those columns
may be omitted only from the join projection, not from raw `svy`.

**Measured evidence**

One production Colombia simulation year, representative 10-column projection:

| Join input | Joined object | Median | Allocation |
|---|---:|---:|---:|
| Current 76-column survey | 60.5 MB | 48.5 ms | 78.6 MB |
| Projected 10-column survey | 16.0 MB | 38.2 ms | 34.0 MB |

The candidate reduced joined-frame size 73.6%, allocation 56.7%, and isolated
join time 21%. Exact projection size depends on the selected model.

**Expected impact**

High peak-memory reduction because the wide joined frame currently overlaps
prediction output and design/factor matrices. Moderate CPU reduction per key.

**Equivalence requirements**

- Derive required columns from fitted formulas and metadata, not a hand-written
  example list.
- Preserve factor classes and levels, contrasts, fixed effects, interactions,
  ID matching, weights, clusters, and row order.
- Test OLS, logistic, and RIF engines; categorical weather and moderators;
  policy variables; and missing FE levels.
- Compare predictions, row drops, factor loadings, and Step 3 policy results.

**Dependencies:** No new package dependency. `vctrs` is not required.

### S2-P3 - Compact the retained residual context

**Priority:** Critical for retained memory
**Confidence:** High for Step 2 aggregation; medium-high across all legacy callers
**References:** `R/fct_run_simulation.R:263-278,501-504`,
`R/fct_step2_payload.R:72-136`, `R/fct_aggregation.R:160-188,232-267`,
`R/fct_aggregation_delta.R:351-405`

**Current pattern**

Compact payload mode correctly stores one shared `train_aug` instead of one per
pipeline. However, `precomputed_train_aug` is still the entire fitted training
frame plus `.fitted` and `.resid`. Aggregation consumers use only `.resid` and,
for original residual matching, one ID column. `.fitted` and all other training
columns are unused by compact Step 2 aggregation after the precomputation stage.
Legacy/non-compact callers still receive the full `run_sim_pipeline()`
`train_aug` contract and must remain compatible.

**Proposed intervention**

After residuals and `shared_id_col` are determined, project the compact shared
context to:

- `id_col` plus `.resid` for `residuals = "original"`;
- `.resid` only for `residuals = "resample"` or `"normal"`;
- `NULL` for `residuals = "none"` and the RIF path.

Keep full `mf$train_data` in Step 1's fit object for model and Step 3 needs. This
recommendation concerns only Step 2's retained residual context.

**Measured evidence**

Production-sized Colombia frame, 451,199 rows:

| Retained context | Logical size |
|---|---:|
| Full training augmentation, 78 columns | 244.5 MB |
| ID plus residual | 34.4 MB |
| Residual only | 3.4 MB |

This is an 85.9% reduction for original residuals and 98.6% for resampling.

**Expected impact**

Very high retained-session memory reduction for non-RIF simulations, without
changing the prediction or factor-loading path.

**Equivalence requirements**

- Confirm no active consumer reads `.fitted` or other training columns from the
  compact context.
- Preserve deterministic unmatched-ID fallback, residual variance, normal and
  resampled draws, and duplicate-ID behavior.
- Preserve legacy non-compact `run_sim_pipeline()` compatibility separately.
- Add explicit compact-context schema tests for every residual mode.

**Dependencies:** No new package dependency.

### S2-P4 - Stream weather keys into the serial simulation loop

**Priority:** High architectural memory intervention
**Confidence:** Medium
**References:** `R/fct_get_weather.R:802-811,1165-1237`,
`R/fct_run_simulation.R:165-182,230-258,319-342`

**Current pattern**

`get_weather()` returns a list containing historical weather and every future
member. Only after that full list is materialized does `fct_run_simulation()`
begin its serial key loop. During the run, retained completed pipelines grow
while not-yet-processed weather frames remain in `weather_result`.

The existing loop releases key-local weather promptly, but it cannot release
weather that `get_weather()` has not yet handed over as a monolithic result.

**Proposed intervention**

Add an internal streaming/callback mode to `get_weather()` that:

1. emits historical weather;
2. emits one fully collected future member key at a time in canonical order;
3. invokes the serial simulation consumer immediately;
4. transfers the weather into a retained resolvable representation for Step 3,
   then releases the producer's full frame before collecting the next member;
5. separately returns metadata and failure information.

This should preserve the current fast per-period DuckDB collection strategy.
It is not the rejected reference-storage approach: member data remains in memory
while consumed and no per-member disk reread is introduced.

**Expected impact**

Potentially large peak-RSS reduction for multi-SSP/multi-period runs. Elapsed
time may improve slightly by avoiding list assembly or may regress if query
materializations are rebuilt; production measurement is mandatory.

**Equivalence requirements**

- Preserve canonical member order and names.
- Preserve current partial-failure ledger and group-fatality rules.
- Preserve progress counts, warnings, stored breaks, and deterministic RNG.
- Do not recompute shared DuckDB relations for every emitted member.
- Preserve member-specific retained weather for Step 3, either through S2-P5's
  shared-key representation or an equivalent ownership-safe reference.
- Ensure temporary DuckDB tables live until the final consumer completes and
  are released on success, error, cancellation, and session termination.
- Compare full output structure and serialized values to the current path.

**Dependencies:** No new package dependency. This is an internal API change.

### S2-P5 - Share immutable weather key columns across ensemble members

**Priority:** High retained-memory experiment
**Confidence:** Medium
**References:** future collection at `R/fct_get_weather.R:1165-1212`, retention
at `R/fct_run_simulation.R:471-494,543-563`, resolution helpers at
`R/fct_step2_payload.R:30-51`

**Current pattern**

Every future member data frame repeats `code`, survey `year`, `survname`,
`loc_id`, and `timestamp`. These key columns are invariant within a scenario
and period when all members have the same completed location-month grid, while
only weather value columns differ. This condition is not guaranteed: the
current eligibility rule keeps models with any complete row, so partially
incomplete members may have differing grids.

**Proposed intervention**

Introduce a compact in-memory weather representation containing one shared key
frame and per-member weather-value frames. Resolve a full data-frame view only
at the simulation or diagnostics boundary. Keep an ordinary-frame fallback for
members whose keys or row order differ.

**Measured evidence**

Production Colombia, SSP2-4.5, 2025-2035, `t` and `spei6`:

- 16 future members;
- 244,440 rows per member;
- key columns were exactly identical across all members;
- current member list: 194.6 MB;
- shared-key representation: 68.1 MB;
- logical-size reduction: 65.0%.

The total full `get_weather()` result also includes historical weather and list
metadata, so its end-to-end reduction will be lower than 65%.

**Expected impact**

High retained-memory reduction without reference-mode disk I/O. Reconstruction
may add CPU/allocation at consumer boundaries; combine with S2-P4 so each full
member frame is reconstructed once, consumed, and released.

**Equivalence requirements**

- Validate identical keys and row order before sharing.
- Preserve column order, classes, timestamps, factor levels, and attributes.
- Preserve member-specific values and Step 3 inter-model spread.
- Ensure diagnostics and exports can resolve only requested members/variables.
- Fall back safely when incomplete-model filtering creates non-identical grids.

**Dependencies:** No new package dependency.

### S2-P6 - Bound the Results aggregation cache

**Priority:** High for long-lived sessions
**Confidence:** High
**References:** `R/mod_2_02_results.R:445-559`,
`R/fct_aggregation.R:820-861`

**Current pattern**

The mutable workspace cache retains every visited aggregation method and every
poverty-line/bandwidth variant for the lifetime of the current simulation.
Cached rows include list columns containing all member values, member standard
deviations, and aggregated factor-loading matrices while the original pipelines
remain live.

**Proposed intervention**

Use a small bounded LRU or current-plus-default cache. Retain the active method
and optionally the default `mean`; evict older poverty-line/bandwidth variants.
Expose cache object-size instrumentation in the Step 2 benchmark harness.

**Expected impact**

Potentially high prevention of incremental RSS growth when users explore many
methods or poverty lines. It does not reduce initial simulation peak RSS.

**Equivalence requirements**

- Eviction must never alter active output.
- Recomputed values must match prior cached values and preserve deterministic
  aggregation seeds.
- Test method switching, poverty-line changes, bandwidth changes, export after
  eviction, and stale-result display.

**Dependencies:** No new package dependency.

### S2-P7 - Reuse Results-derived matrices and tables

**Priority:** Medium
**Confidence:** High
**References:** `R/mod_2_02_results.R:829-1031`,
`R/mod_2_02_results.R:1033-1227`,
`R/fct_uncertainty_helpers.R:22-59`

**Current pattern**

Multiple Results reactives independently turn the same cached aggregation rows
into value/SD matrices, contrast-adjusted frames, selected-scenario time series,
all-scenario annual distributions, bands, uncertainty decompositions, and
threshold inputs.

**Proposed intervention**

Create one method/deviation-scoped derived result containing the canonical
historical/scenario long frame and reusable matrices. Apply only lightweight
selection and presentation transforms downstream.

**Expected impact**

Moderate CPU and transient-allocation reduction when Results and Diagnostics
render together or controls change.

**Equivalence requirements**

Preserve selected-scenario filtering, scenario/model order, historical reference
choice, uncertainty-band settings, and all export schemas.

**Dependencies:** No new package dependency.

### S2-P8 - Lazily resolve and cache diagnostic weather subsets

**Priority:** Medium-high
**Confidence:** High
**References:** `R/mod_2_03_diagnostics.R:152-158,195-229,284-328`,
`R/fct_sim_diag.R:414-481`

**Current pattern**

Diagnostics resolves every scenario representative weather frame together. The
density plot, support table, and export paths then separately filter historical
weather and reshape scenario values. In reference mode this can load all
representative RDS frames into one reactive even when the user selected one
scenario and one weather variable.

**Proposed intervention**

Key a diagnostic cache by simulation generation, active scenario selection, and
weather variable. Resolve only requested scenario representatives and immediately
project to keys plus requested weather columns. Reuse one tidy diagnostic frame
for plotting, support summaries, and exports.

**Expected impact**

Medium CPU reduction in memory mode and potentially high RSS/I/O reduction in
reference mode.

**Equivalence requirements**

Preserve all-scenario mode, labels, regression overlays, support thresholds,
warning rules, binned factors, and export rows. Verify reference files are read
once per cache key.

**Dependencies:** No new package dependency.

### S2-P9 - Correct reference-weather store ownership

**Priority:** Medium, correctness/resource hygiene
**Confidence:** High
**References:** `R/fct_run_simulation.R:138-153,593-615`,
`R/mod_2_01_weathersim.R:270-279,803-805`,
`R/mod_2_simulation.R:130-143`

**Current pattern**

Successful reference-mode reruns replace `saved_scenarios` without cleaning the
prior run's weather store. Session and clear cleanup inspect only current
scenarios. Historical-only reference runs also publish a top-level store that
is not reachable through `saved_scenarios`, making orphaned directories
possible.

**Proposed intervention**

Define one run-level store owner and maintain explicit references from every
published result. On successful atomic replacement, clean the superseded store
only when no Step 3 result still owns it. Historical-only runs must either avoid
creating a store or retain it in the owner state for cleanup.

**Expected impact**

Prevents disk growth and stale reference artifacts. It does not improve the
default in-memory mode.

**Equivalence requirements**

- Never remove weather still referenced by Step 3 baseline/policy results.
- Test success, partial failure, total failure, rerun, clear, and session end.
- Test historical-only and future runs.

**Dependencies:** No new package dependency.

### S2-P10 - Remove redundant retained top-level objects after contract audit

**Priority:** Medium retained-memory investigation
**Confidence:** Medium-low until Step 3 ownership is formalized
**References:** `R/fct_run_simulation.R:456-470`,
`R/fct_run_simulation.R:598-613`, Step 3 baseline use at
`R/mod_3_06_policy_sim.R:181-194,265-322`

**Current pattern**

`hist_sim_result` retains `train_data`, `cluster_counts`, `chol_obj`, and full
baseline `svy`, in addition to the Step 1 fit and survey reactives that remain
live. Active Step 2 Results/Diagnostics code does not read `train_data` or
`cluster_counts`; active Step 3 policy code obtains training data and fit
metadata from `model_fit`, but does require the exact baseline survey from
`hs$svy`.

**Proposed intervention**

Create an explicit published-result schema and remove fields proven redundant:

- evaluate dropping top-level `train_data` and `cluster_counts` from compact
  Step 2 results;
- retain `chol_obj` only where Results/Step 3 truly consume it;
- project `hs$svy` only after enumerating all Step 2 incidence and Step 3 policy
  columns, or leave it unchanged initially.

**Expected impact**

Potentially high retained-memory reduction, but lower confidence than S2-P3
because policy features may rely on broad baseline columns.

**Equivalence requirements**

Run complete Step 2 Results/Diagnostics and Step 3 policy/decomposition suites,
including every policy lever. Preserve not only the exact baseline population,
but also policy eligibility and cost columns, weights, policy-modified columns,
and the fields used by Step 3 diagnostics and decomposition.

**Dependencies:** No new package dependency.

### S2-P11 - Eliminate duplicate threshold-table formatting

**Priority:** Low
**Confidence:** High
**Reference:** `R/mod_2_02_results.R:1378-1403,1479-1482`

**Current pattern**

`renderDT()` invokes `threshold_table_df()` once inside `req()` and immediately
again for assignment. The heavy aggregation input is cached, but the formatted
table is built twice.

**Proposed intervention**

Call the builder once, then validate and render the local value.

**Expected impact**

Small CPU/allocation improvement with negligible risk.

**Equivalence requirements**

Preserve empty-state handling, ordering, stale CSV gating, and export output.

**Dependencies:** No new package dependency.

### S2-P12 - Consolidate Step 2 stale-signature observers

**Priority:** Low
**Confidence:** Medium-high
**Reference:** `R/mod_2_01_weathersim.R:610-672`

**Current pattern**

Separate observers for model fit, historical years, climate, baseline survey,
residuals, uncertainty settings, and future periods independently rebuild and
compare the complete live signature.

**Proposed intervention**

Create one reactive live signature and one comparison observer, preserving all
current dependencies and `ignoreInit` behavior.

**Expected impact**

Small CPU/allocation reduction and simpler invalidation behavior.

**Equivalence requirements**

Test every individual control, combined changes, programmatic replay, successful
rerun, failed rerun, and survey-version changes.

**Dependencies:** No new package dependency.

### S2-P13 - Avoid deep copying in the compute boundary before async wiring

**Priority:** Conditional
**Confidence:** Medium
**References:** `R/fct_step2_compute.R:14-29,142-156`

**Current pattern**

`step2_compute()` recursively copies every data-frame column and nested list to
enforce an immutable snapshot. If the current UI is changed to call this boundary
in-process, the original input graph and full copy coexist before weather and
pipeline allocations. The current synchronous UI does not call this function,
so this is not a present production bottleneck.

**Proposed intervention**

Before wiring this boundary into the UI, choose execution-specific snapshot
semantics:

- for a separate worker process, rely on serialization isolation and remove the
  redundant in-worker deep copy;
- for in-process execution, use an explicit immutable input contract and copy
  only known mutable structures.

**Expected impact**

Potentially high reduction of startup peak RSS when async execution is enabled.
No current synchronous-path gain.

**Equivalence requirements**

Preserve the tested non-mutation contract, deterministic signatures, RNG
restoration, event order, and process-local DuckDB/cache initialization.

**Dependencies:** Depends on the eventual async backend; no new dependency is
recommended by this audit alone.

### S2-P14 - Add a measured memory-budget policy for weather collection

**Priority:** Medium operational safeguard
**Confidence:** Medium
**References:** `R/fct_get_weather.R:1165-1212`,
`R/mod_2_01_weathersim.R:750-760`, benchmark harness at
`dev/bench_step2.R:470-861`

**Current pattern**

The application defaults to fast collection and in-memory retention regardless
of estimated workload size. Operators can override storage/collection through
environment variables, but the app has no estimate or guard before a large
multi-SSP/multi-period run.

**Proposed intervention**

Estimate rows and retained bytes from baseline locations, months, periods,
members, weather columns, and active coefficient count before collection.
Select or reject a strategy according to an explicit configurable process-tree
RSS budget. The first strategies should be S2-P1/P2/P3/P4/P5, not automatic
fallback to the known-slower reference mode.

**Expected impact**

Prevents avoidable out-of-memory failures and makes deployment limits explicit.
The estimator itself does not make computation faster.

**Equivalence requirements**

No silent reduction of SSPs, periods, members, uncertainty, or baseline rows.
If a workload cannot fit, fail before computation with the existing selections
unchanged. Calibrate against external process-tree RSS, not `object.size()` or
sampled R RSS alone.

**Dependencies:** No new runtime package dependency.

### S2-P15 - Revisit key-level parallelism only after memory reductions

**Priority:** Deferred experiment
**Confidence:** Low until a worker-safe prototype passes memory gates
**References:** serial enforcement at `R/fct_run_simulation.R:246-258`, pure
boundary at `R/fct_step2_compute.R`, prior requirements at
`review/step2-optimization-decision-record.md:152-159`

**Current pattern**

All keys run serially. This protects memory and deterministic ordering but
leaves CPU parallelism unused during prediction and factor-loading stages.

**Proposed intervention**

Do not parallelize current full key payloads. After S2-P1 through S2-P5 reduce
input and retained memory, benchmark at most two top-level worker-safe key tasks
with:

- explicit serialized ordinary-object inputs;
- worker-owned DuckDB connections;
- deterministic per-key seeds;
- canonical parent-side ordering;
- serialized errors/failure ledger;
- a hard external process-tree RSS budget.

**Expected impact**

Potential wall-clock reduction when per-key prediction dominates. It may still
be a net loss due to serialization and duplicated model/survey memory.

**Equivalence requirements**

Exact result ordering and failure semantics, deterministic repeated runs, no
connection serialization, and process-tree RSS below the configured budget.

**Dependencies:** An async/worker backend may be required, but none should be
selected before the experiment.

### S2-P16 - Benchmark bounded DuckDB thread scaling

**Priority:** High experiment
**Confidence:** Medium
**Reference:** `R/fct_get_weather.R:591-597`

**Current pattern**

Every weather load temporarily forces DuckDB to one thread. This preserves
repeatable floating-point reduction order, but also serializes the largest
spatial joins, grouped population-weighted reductions, rolling windows, climate
deltas, and temporary-table materializations.

**Proposed intervention**

Benchmark opt-in thread counts of 2 and 4 against the one-thread oracle. Retain
one thread as the production default unless a bounded setting passes numerical,
peak-RSS, and deployment CPU-entitlement gates. Explicit output ordering must
remain in every collected relation.

**Expected impact**

Potentially substantial weather-query speedup on large local/cached workloads.
The gain may be negligible for remote-I/O-bound runs.

**Memory impact**

DuckDB can allocate additional per-thread hash, sort, and window state. A faster
run is not acceptable if process-tree RSS exceeds the deployment budget.

**Equivalence requirements**

- Compare every weather field under the accepted numerical tolerance.
- Preserve row ordering, factor/bin levels, model eligibility, and warnings.
- Run repeated identical calls to characterize nondeterministic last-bit drift.
- Measure process-tree RSS externally for threads 1, 2, 4, and DuckDB default.

**Dependencies:** No new package dependency; depends on DuckDB and deployment
CPU/memory limits.

### S2-P17 - Materialize reusable location-month weather once

**Priority:** High experiment for multi-scenario workloads
**Confidence:** Medium
**References:** `R/fct_get_weather.R:733-787,1062-1163`

**Current pattern**

The H3-to-location population-weighted `loc_monthly` relation remains lazy.
Historical rolling weather is materialized, but each SSP-period perturbation can
cause DuckDB to re-plan or re-execute the same H3 join and location aggregation
underneath `loc_monthly`.

**Proposed intervention**

Materialize the projected location-month source once in a temporary DuckDB
table, reuse it for historical rolling weather and all future perturbations,
then release superseded rolled/intermediate tables as soon as the climate
reference and historical output no longer require them.

**Expected impact**

Potentially high for three-SSP/three-period workloads because the expensive
spatial aggregation can be paid once rather than once per future period.

**Memory impact**

Ambiguous. Retaining monthly and rolled materializations together may increase
RSS or DuckDB spill volume. Temporary-table lifetime is central to the design.

**Equivalence requirements**

- Preserve the full timestamp envelope required by every rolling window.
- Preserve weighted-null behavior, ordering, and all historical/future values.
- Compare DuckDB `EXPLAIN ANALYZE`, temporary-table sizes, elapsed time, spill,
  and external peak RSS for one-period and nine-scenario workloads.

**Dependencies:** No new package dependency.

### S2-P18 - Share historical population-weight denominators

**Priority:** Medium
**Confidence:** Medium-high on the historical-only branch
**Reference:** `R/fct_get_weather.R:678-680,733-747`

**Current pattern**

The historical weather relation filters rows to complete selected weather
variables before aggregation. Despite that common completeness mask, generated
SQL repeats the same population-weight denominator for every selected weather
variable and emits each denominator twice within its expression.

**Proposed intervention**

For this historical complete-case relation only, compute one grouped positive
population denominator and reuse it across selected weather numerators. At
minimum, emit each per-variable denominator once through `NULLIF(denominator,
0)`. Retain the current per-variable missingness-aware denominator for future
deltas, where completeness can differ by variable.

**Expected impact**

Moderate with many selected weather variables; low with one or two variables.

**Equivalence requirements**

- Prove the upstream complete-case filter applies to exactly the selected
  variables used by the aggregation.
- Preserve zero/negative/missing population behavior and `NA_real_` outputs.
- Inspect DuckDB's plan because it may already eliminate repeated expressions.
- Do not share denominators across future delta variables without an equivalent
  common missingness guarantee.

**Dependencies:** No new package dependency.

### S2-P19 - Fuse future-model completeness filtering with materialization

**Priority:** Medium-high
**Confidence:** Medium
**Reference:** `R/fct_get_weather.R:1087-1124`

**Current pattern**

The lazy future location-delta relation is first grouped and collected to R to
identify models having at least one complete row. The relation is then filtered
to those model names and materialized, causing another scan of the underlying
delta plan.

**Proposed intervention**

Use one DuckDB CTE, window, or semi-join that computes the current per-model
eligibility flag and materializes only eligible rows. Collect only the small
excluded-model list needed for warnings from that materialization or a related
metadata query.

**Expected impact**

Moderate-to-high for large CMIP6 tables and many periods if the current query
plan executes the H3/delta relation twice.

**Memory impact**

Potentially lower query pressure, provided the implementation does not first
materialize all incomplete rows.

**Equivalence requirements**

- Preserve the current rule: a model is eligible when `n_complete > 0`, not
  only when every row is complete.
- Preserve excluded-model names, warnings, ordering, and returned keys.
- Confirm behavior with partially complete models and variable-specific `NA`s.

**Dependencies:** No new package dependency.

### S2-P20 - Reuse RIF design and fixed-effect indexing

**Priority:** High for RIF workloads
**Confidence:** Medium
**References:** `R/fct_rif_sim.R:72-143,269-377`

**Current pattern**

Direct RIF prediction already constructs baseline and scenario designs from the
first quantile fit, but each of nine quantile models repeats coefficient-column
subsetting and fixed-effect `match()` work. Factor-loading interpolation can
also rebuild quantile/group-specific design matrices.

**Proposed intervention**

For the currently supported ordinary fixed-effect OLS structures:

- validate identical RHS schemas and coefficient order across all quantiles;
- precompute fixed-effect integer indices once per data frame;
- assemble a coefficient matrix and calculate all point predictions with BLAS;
- reuse one scenario design for factor loading only where its measured size
  fits the memory budget; otherwise retain the current streaming loading path.

Any failed validation must use the existing `fixest::predict()` fallback.

**Expected impact**

Potentially high CPU reduction for RIF runs with fixed effects. This is the most
promising RIF-specific follow-up after the already enabled direct prediction.

**Memory impact**

A reusable `N x P` matrix can increase peak RSS. Point-prediction reuse and
factor-loading reuse should be benchmarked as separate variants, with the design
released before another large matrix is allocated.

**Equivalence requirements**

- Preserve coefficient ordering, factor contrasts, unseen-level behavior,
  fixed-effect values, and unsupported-model fallback.
- Compare each tau's baseline/scenario prediction, interpolated delta,
  `F_loading`, and aggregate outputs.
- Test with and without fixed effects and interactions.

**Dependencies:** Existing `fixest` and BLAS only.

### S2-P21 - Make the unused aggregation weighting arm lazy

**Priority:** High for Results latency
**Confidence:** High after consumer verification
**References:** `R/mod_2_02_results.R:481-537,635-640,742-766`

**Current pattern**

Every aggregation method eagerly computes both unweighted and weighted results.
The current UI's `weight_key()` always selects weighted results when a survey
weight exists, so the unweighted branch is built and cached without an active
consumer in normal weighted-survey use.

**Proposed intervention**

Keep the existing two-arm schema but compute each arm lazily on first request.
For the current UI this normally means computing only weighted results. Retain
the unweighted fallback when no weight is available and for any verified export
or compatibility consumer.

**Expected impact**

Up to roughly half of aggregation CPU and transient allocation for weighted
workloads, especially while visiting several methods. Exact gain varies because
weighted and unweighted methods do not necessarily have identical cost.

**Equivalence requirements**

- Search and test all exported and Step 3 consumers before changing eager
  construction.
- Preserve the nested `weighted`/`unweighted` result schema.
- Compare both arms for every aggregation method when explicitly requested.

**Dependencies:** No new package dependency.

### S2-P22 - Reuse method-independent per-year aggregation preparation

**Priority:** Medium-high for exploratory Results use
**Confidence:** Medium
**References:** `R/fct_aggregation.R:763-861`,
`R/fct_aggregation_delta.R:343-405`

**Current pattern**

Each aggregation method and weighting arm repeats year grouping, row slicing,
validity filtering, residual matching/drawing, outcome back-transformation, and
factor-loading slicing before applying its method-specific statistic and
gradient.

**Proposed intervention**

Build a bounded workspace preparation cache containing year row indices,
valid-row masks, normalized weights, and deterministic per-year residual
vectors. Reuse those objects across methods while keeping each method's exact
aggregate and gradient implementation. Do not cache full method-specific
`N x P` matrices.

**Expected impact**

Moderate-to-high during a multi-method Results session; limited benefit if only
the default mean is viewed.

**Memory impact**

Adds O(N) cached vectors per pipeline. It should be paired with S2-P6's bounded
cache policy so reusable preparation does not become another unbounded store.

**Equivalence requirements**

- Preserve year-specific deterministic RNG streams exactly.
- Preserve non-finite filtering, log back-transformation, ID residual matching,
  and weighted formulas.
- Compare every supported aggregation method and residual mode.

**Dependencies:** No new package dependency.

## Step 2 Prioritized Approval Sets

### Set 2A - Immediate measured wins

- S2-P1: baseline-filtered weather retrieval;
- S2-P2: projected survey joins;
- S2-P3: compact residual context;
- S2-P11: single threshold-table build;
- S2-P12: consolidated stale tracking.

These provide the best expected speed/memory return with limited architectural
change. S2-P1 should be implemented first and benchmarked end-to-end before the
others are combined.

### Set 2B - Weather memory architecture

- S2-P4: streaming weather producer/consumer;
- S2-P5: shared immutable member keys;
- S2-P8: lazy diagnostic weather resolution;
- S2-P14: explicit memory budget.

These should be designed together because they define ownership and resolution
of future weather frames.

### Set 2C - Long-lived result memory

- S2-P6: bounded aggregation cache;
- S2-P7: shared Results-derived frames;
- S2-P9: reference-store ownership;
- S2-P10: published-result schema audit.

### Set 2D - Query and RIF experiments

- S2-P16: bounded DuckDB thread scaling;
- S2-P17: materialized location-month weather;
- S2-P18: shared historical denominator;
- S2-P19: fused completeness filtering;
- S2-P20: shared RIF design and fixed-effect indexing.

Each must be benchmarked independently. S2-P16 has the clearest speed potential
but also the clearest reproducibility and memory tradeoff.

### Set 2E - Aggregation throughput

- S2-P21: lazy weighting arms;
- S2-P22: shared method-independent per-year preparation;
- S2-P6: bounded cache policy.

### Set 2F - Deferred parallel throughput work

- S2-P13: copy semantics for async boundary;
- S2-P15: bounded worker experiment.

Do not begin Set 2F until process-tree memory after Sets 2A/2B is known.

## Step 2 Dependencies

No new runtime package is required for S2-P1 through S2-P22.

| Package/tool | Recommendation |
|---|---|
| `collapse` | Do not broaden use without isolated proof; no new Step 2 finding requires it. |
| `kit` | Do not add. |
| `data.table` | Do not add for Step 2 based on current evidence. |
| `vctrs` | Do not add directly. |
| `bench` | Continue as development-only benchmark tooling. |
| `/usr/bin/time -l` | Use for authoritative macOS process peak-RSS measurement. |

## Step 2 Validation Plan

### Numerical and structural parity

- Compare every weather key, member, row count, column type, order, timestamp,
  factor level, and stored break.
- Compare OLS/logistic/RIF predictions, row drops, `svy_row_id`, residual IDs,
  factor-loading matrices, aggregated values, uncertainty components, and
  failure ledgers.
- Preserve member-specific weather and inter-model spread.
- Preserve partial-failure publication and whole-group fatal errors.

### Memory and timing gates

For each approved set, run `dev/run_step2_benchmark.sh` on at least:

- one small and one large country;
- OLS and RIF;
- historical only;
- one SSP/one period;
- three SSPs/three periods;
- coefficient uncertainty enabled and disabled;
- cold and warm weather caches.

Record:

- total, weather, per-key pipeline, prediction, factor-loading, join, and
  aggregation times;
- external parent and process-tree peak RSS;
- weather, pipeline, result, serialized, and deduplicated object sizes;
- cache hit/miss counts and failure-ledger parity.

### UI and downstream gates

- Preserve all Step 2 input/output IDs, HTML structure, tabs, controls, labels,
  maps/plots, and exports.
- Test Step 2 clear, rerun, failed rerun, staleness, and pipeline replay.
- Run full Step 3 policy, diagnostics, decomposition, and export workflows on
  compact results.

## Step 2 Baseline Validation Performed

The following suites passed during this audit:

```text
tests/testthat/test-step2-contract.R
tests/testthat/test-step2-payload.R
tests/testthat/test-step2-compute.R
tests/testthat/test-fct_run_simulation.R
tests/testthat/test-mod_2_02_results.R
tests/testthat/test-mod_2_03_diagnostics.R
```

The production weather benchmarks were read-only. No application source code or
production data was modified.

## Step 2 Decision Status

All Step 2 items S2-P1 through S2-P22 remain **proposed**. No refactoring is
authorized by this audit record. The recommended first approval is Set 2A,
starting with S2-P1 as an independently measured change.

# Step 3 Performance Audit and Optimization Recommendations

## Step 3 Executive Summary

Step 3 is already fast in normal use because the active path does not rerun the
full Step 2 prediction pipeline. It applies policy levers once to the baseline
survey, computes weather-independent policy deltas and the RIF training ECDF
once, then derives policy outcomes analytically from the paired Step 2
pipelines. Existing aggregation and residual caches further limit repeat work.

The remaining opportunities are consequently more about retained memory and
repeated decomposition/diagnostic scans than raw simulation latency:

1. **S3-P1: compact future decomposition payloads.** A production-sized
   household decomposition is about 34.4 MB per simulated year in the current
   21-column schema. An 11-year scenario is about 426.7 MB before additional
   scenarios. The UI needs small scenario/channel and decile summaries, not all
   future household rows indefinitely.
2. **S3-P2: restrict changed-variable detection to policy candidates.** Scanning
   all 74 columns of the 231,087-row Colombia baseline took 125 ms and allocated
   266 MB. Scanning three known candidate columns took 3.3 ms and 10.7 MB.
3. **S3-P3: use a central-value-only decomposition kernel in the policy delta
   path.** The active policy correction extracts only `delta_total`, but the
   current call assembles a full household decomposition frame and, when enabled,
   computes SE vectors that are discarded.
4. **S3-P4/S3-P5: share hazard preparation and diagnostic summaries per
   published run.** These remove repeated full-frame grouping and scans without
   changing the analytic policy contract.

These are optimization recommendations, not evidence that Step 3 needs a broad
rewrite. The existing analytic path, compact Step 2 payload, aggregation cache,
and active coefficient mask should remain the baseline.

The audit also found one non-performance integrity issue: Results exposes stale
state, while Diagnostics and Decomposition can continue displaying and exporting
old policy results without a stale warning. This is recorded separately as
S3-C1 because a complete correction may require an explicitly approved UI
change.

## Step 3 Scope and Runtime Graph

Step 3 is orchestrated by `R/mod_3_scenario.R:99-402` and includes:

| Stage | Primary file | Main responsibility |
|---|---|---|
| 3.01 | `R/mod_3_01_sp.R` | Social-protection configuration and reach preview |
| 3.02 | `R/mod_3_02_infra.R` | Infrastructure policy configuration |
| 3.03 | `R/mod_3_03_digital.R` | Digital-inclusion configuration |
| 3.04 | `R/mod_3_04_labor.R` | Labor-market configuration |
| 3.05 | `R/mod_3_05_education.R` | Education configuration |
| 3.06 | `R/mod_3_06_policy_sim.R` | Policy application, analytic delta, decomposition |
| 3.07 | `R/mod_3_07_results.R` | Paired policy-versus-baseline Results wiring |
| 3.08 | `R/mod_3_08_diagnostics.R` | Policy input, treatment and component diagnostics |
| 3.09 | `R/mod_3_09_decomposition.R` | Channel, decile, RIF and weather-basis decomposition |

The active runtime path is:

```text
mod_3_06_policy_sim_server()
  -> apply_policy_to_svy()
  -> precompute policy covariate deltas and RIF ECDF
  -> apply_policy_delta_to_baseline()
     -> decompose_policy_effect() per historical/future member weather panel
     -> add delta_total to baseline y_point
     -> retain paired Step 2 pipeline structure
  -> decompose_policy_effect() for displayed historical decomposition
  -> decompose_policy_effect() per scenario/year for displayed decomposition
  -> atomically publish policy and decomposition results
mod_3_07_results_server()
  -> cached baseline/policy aggregation
  -> paired annual/tail/headline transforms
mod_3_08_diagnostics_server()
  -> policy input/treatment/component scans
mod_3_09_decomposition_server()
  -> weather-basis and decile/channel summaries
```

## Existing Step 3 Optimizations to Preserve

Already implemented and not re-proposed:

- Active analytic policy-delta path at
  `R/mod_3_06_policy_sim.R:286-322`.
- Weather-independent policy deltas and RIF ECDF computed once per run
  (`PERF-22`) at `R/mod_3_06_policy_sim.R:299-310`.
- Policy pipelines reuse baseline `F_loading`, IDs, residual context, weights,
  and member-specific weather; only `y_point` changes.
- Step 3 per-method aggregation cache (`PERF-31`) at
  `R/fct_policy_sim_compare.R:1349-1489`.
- Early prediction-frame release (`PERF-32`) and per-pipeline residual lookup
  and variance reuse (`PERF-34`).
- Shared canonical Step 2/3 aggregation builder.
- Active coefficient mask and block-Cholesky uncertainty path.
- Atomic publication and stale-result preservation after failed runs.

Inactive or deferred behavior that should not be optimized as if it were the
normal path:

- `resimulate_with_svy()` is an older full re-prediction compatibility path and
  is not called by the active Step 3 server.
- Shock-responsive transfers are currently mapped to regular transfers.
- Recomputing policy-side `F_loading` is explicitly deferred and would change
  the current coefficient-uncertainty approximation.
- Per-year policy delta variation within each future member is explicitly
  deferred; the active policy correction uses member-period hazard values.

## Step 3 Benchmark Context

Targeted production measurements used the Colombia 2018 GEIH baseline with:

- 231,087 survey rows;
- 74 source columns in the loaded production frame;
- a representative OLS policy model with one continuous weather variable and a
  policy interaction.

Step 3 has no working production benchmark fixture in `dev/bench_step2.R`:
`include_step3` exists, but Step 3 timing/RSS fields remain unimplemented. This
is itself addressed in S3-P12.

## Step 3 Bottleneck Inventory and Proposed Interventions

### S3-P1 - Compact future decomposition retention

**Priority:** Critical for memory
**Confidence:** Medium-high after output-contract characterization
**References:** `R/mod_3_06_policy_sim.R:345-411,435-436`,
`R/mod_3_09_decomposition.R:243-256,350-381`

**Current pattern**

For every saved scenario, Step 3 loops over every weather year, computes a full
household-level decomposition data frame, adds scenario/year metadata, then
row-binds all years and scenarios into `decomp_scenarios_rv`. The retained frame
contains household IDs, weights, quantile positions, eligibility, channel
deltas, channel SEs, and derived percentages.

The Decomposition UI uses that object to produce:

- seven weighted channel summaries per scenario/weather basis;
- ten decile/channel summaries for a selected scenario/weather basis;
- a list of available scenario names.

It does not expose or export the full future household-by-year decomposition
frame.

**Proposed intervention**

During the scenario/year loop, immediately derive and retain compact products:

1. weighted channel summary by scenario and simulated year;
2. weighted channel-by-fixed-baseline-decile summary by scenario and year;
3. the small annual total used to choose adverse 1-in-10/1-in-20 years;
4. scenario labels and engine metadata.

Release each full household decomposition before moving to the next year. Keep
the current household-level historical decomposition because Results incidence,
selected historical decile displays, and adverse historical recomputation use
it. If any export is intended to expose future household rows, that contract
must be added explicitly before compaction.

**Measured evidence**

Logical object-size estimate using the current 21-column decomposition schema
and the 231,087-row production baseline:

| Retained decomposition | Rows | Logical size |
|---|---:|---:|
| One year | 231,087 | 34.4 MB |
| One 11-year scenario | 2,541,957 | 426.7 MB |

Multiple scenarios scale this approximately linearly. Construction peak was
higher than final logical size in the synthetic sizing run because each yearly
frame and the bound result coexist transiently.

**Expected impact**

Very high reduction in Step 3 retained and transient memory for future
scenarios. Runtime should also improve by avoiding one giant `bind_rows()`.

**Equivalence requirements**

- Preserve fixed weighted baseline deciles exactly.
- Preserve adverse-year selection using household-weighted `delta_total` and
  current metric direction.
- Preserve channel SE summaries, reconciliation, factor/bin behavior, scenario
  ordering, and empty-result behavior.
- Compare every plot/table/export under mean, adverse 1-in-10 and adverse
  1-in-20 bases for OLS and RIF.
- Preserve the full historical decomposition until its remaining consumers are
  separately compacted.

**Dependencies:** No new package dependency.

### S3-P2 - Restrict changed-variable detection to policy candidates

**Priority:** High
**Confidence:** High
**References:** `R/mod_3_08_diagnostics.R:241-267`,
`R/fct_policy_sim_compare.R:131-148`,
`R/fct_policy_diagnostics.R:38-46,118-121`

**Current pattern**

Diagnostics calls `detect_manipulated_vars()` over the intersection of every
column in the full baseline and policy surveys. The helper applies
`all.equal()` or `identical()` to each column. `policy_component_matrix()` then
calls the same full-frame detector again.

The run already knows the only possible changed fields from the active lever
configuration, model-gated lever columns, and `SP_TRANSFER_COL`.

**Proposed intervention**

Build a conservative candidate list at policy application time and retain it
with the published policy result. Run exact current comparisons only over those
candidate columns. Include the outcome/welfare display column when diagnostics
adds the transfer to it, and keep the full-scan fallback for external callers
that do not supply candidates. This must be an optional narrower diagnostics
API; the generic `detect_manipulated_vars()` contract must continue comparing
arbitrary covariates, interaction variables, and outcomes.

**Measured evidence**

Production Colombia 2018, 231,087 rows and 74 columns:

| Detection path | Median | Allocation |
|---|---:|---:|
| Full shared-column scan | 125.0 ms | 266.4 MB |
| Three conservative candidates | 3.3 ms | 10.7 MB |

On the combined two-wave 451,199-row frame, the full scan took 272 ms and
allocated 520 MB.

**Expected impact**

High allocation reduction and moderate diagnostic latency improvement after
each policy run. It also makes later treatment/component scans easier to share.

**Equivalence requirements**

- Candidate generation must be conservative; a false positive costs only a
  comparison, while a false negative hides a real policy change.
- Preserve factor attributes, `NA` differences, SP-only policies, labor sector
  reallocations, and synthetic welfare changes shown by Diagnostics.
- Keep row-count-mismatch behavior for public/general callers.

**Dependencies:** No new package dependency.

### S3-P3 - Add a central-value-only policy correction kernel

**Priority:** High
**Confidence:** High for current analytic correction
**References:** `R/fct_policy_sim.R:1198-1278`,
`R/fct_policy_decompose.R:467-524,569-595,604-743`

**Current pattern**

`apply_policy_delta_to_baseline()` calls `decompose_policy_effect()` for each
historical/future member weather panel and immediately extracts only
`decomp$delta_total`. The decomposition function nevertheless:

- computes per-channel SE vectors when coefficient uncertainty is enabled;
- constructs all channel, decile, eligibility, and percentage columns;
- returns a full household data frame that is then discarded.

Displayed historical and per-year future decompositions are computed separately
later, so these discarded columns do not supply the Decomposition tab.

**Proposed intervention**

Extract a shared internal channel kernel with a central-only mode that computes
only the vectors needed for `delta_total`. The policy correction path should
always use central-only mode, irrespective of whether displayed decomposition
SEs are enabled. `decompose_policy_effect()` remains the public/full wrapper and
continues producing the current schema and warnings.

**Measured evidence**

Production-sized synthetic OLS fixture, 231,087 households:

| Path | Median | Allocation | Returned object |
|---|---:|---:|---:|
| Full decomposition with SEs | 81.3 ms | 106 MB | 35.3 MB |
| `skip_coef=TRUE`, return total | 66.5 ms | 98.9 MB | 1.8 MB |

This existing-call approximation saved 18% timing. A true central-only kernel
should also avoid constructing the unused full output and zero-SE/channel
vectors, so it may reduce allocation further.

**Expected impact**

Moderate per-member CPU improvement and large transient-output reduction. The
gain multiplies over future climate members.

**Equivalence requirements**

- `delta_total` must be exactly equal to the full decomposition central value.
- Preserve RIF tau clipping/interpolation, log transfers, factor-expanded terms,
  binned weather, interaction matching, and no-interaction warnings.
- Do not change displayed decomposition SEs or the baseline policy
  `F_loading` approximation.

**Dependencies:** No new package dependency.

### S3-P4 - Reuse hazard grouping and compact hazard panels

**Priority:** Medium-high
**Confidence:** Medium
**References:** `R/fct_policy_decompose.R:281-358`, callers at
`R/mod_3_06_policy_sim.R:331-404` and
`R/mod_3_09_decomposition.R:185-238,497-520`

**Current pattern**

Every decomposition call rebuilds location group structures separately for
each weather variable, computes location means or modal bins, and matches those
values back to all baseline households. This repeats across policy correction,
displayed historical decomposition, every future year, and three technical
historical weather bases.

**Proposed intervention**

Create a run-scoped hazard-preparation helper that:

- builds one location grouping per weather panel;
- aggregates all continuous weather variables in one grouped pass;
- retains separate exact modal-bin logic for categorical variables;
- maps the compact location-level values to households once;
- passes `hazard_values` directly into central/full channel kernels.

Cache only compact hazard products for reused historical/adverse panels; do not
retain another full weather frame.

**Expected impact**

Moderate for current common one/two-weather-variable models and higher for many
scenario years or weather variables.

**Equivalence requirements**

- Preserve unweighted location means, alphabetic modal tie-breaking, factor
  levels, missing-location fallback, grand-mean fallback, and row order.
- Keep period-level policy-correction hazards distinct from per-year displayed
  decomposition hazards.

**Dependencies:** Existing `collapse`; no new dependency.

### S3-P5 - Cache published-run diagnostic summaries

**Priority:** Medium-high
**Confidence:** High
**References:** `R/mod_3_08_diagnostics.R:241-400,522-593`

**Current pattern**

`diag_data()` already caches the baseline/policy frames, manipulated variable
names, and transfer totals as a reactive. However, the diagnostics table and
its export independently recompute
`policy_input_diagnostics()` and changed counts over the full baseline/policy
surveys. Treatment and component tables and their exports independently rerun
eligibility, treatment, component, and changed-variable scans.

**Proposed intervention**

On each successful `sim_run_id()`, build one diagnostics payload containing:

- manipulated candidate variables;
- raw input summary and changed counts;
- treatment matrix and explanation inputs;
- component matrix;
- transfer totals;
- minimal per-variable vectors needed by histogram outputs.

Renderers and exports should format or plot that shared payload without rerunning
the household scans.

**Expected impact**

Moderate CPU and allocation reduction when the Diagnostics tab and export bundle
are both used. Low risk because the data are immutable for a published run.

**Equivalence requirements**

- Key the payload to `sim_run_id()` and the snapshotted analysis unit/scenario,
  not live controls.
- Preserve weighted totals, eligibility before errors, realized treatment after
  errors, component overlap, `NA` handling, and output ordering.
- Verify display/export parity and one computation per published run.

**Dependencies:** No new package dependency.

### S3-P6 - Reuse paired Results matrix transforms

**Priority:** Medium
**Confidence:** High
**References:** `R/fct_policy_sim_compare.R:1524-1909,1911-2225`

**Current pattern**

The Step 3 aggregation cache prevents repeated household aggregation, but
pointrange, time-series, exceedance, threshold, adverse, headline, display, and
export reactives repeatedly traverse the same aggregate list-columns and call
`by_model_matrix()`/quantile transforms independently for baseline and policy.

**Proposed intervention**

Create a bounded derived-results object keyed by aggregation method, poverty
line, deviation, coefficient band, and ensemble band. Reuse canonical
model/year matrices and paired-effect frames across plots, tables, headlines,
and exports.

**Expected impact**

Moderate Results-tab responsiveness improvement. No material policy-simulation
speedup. Broad expansion beyond the currently duplicated transforms should be
accepted only after the Step 3 benchmark fixture confirms meaningful render
cost; the primary aggregation cache is already implemented.

**Equivalence requirements**

- Preserve paired baseline-policy covariance and model/year alignment.
- Preserve distinct invalidation for deviation and both uncertainty bands.
- Compare all plots, tables, CSVs, and export-bundle outputs.
- Keep the cache bounded as recommended for Step 2 S2-P6.

**Dependencies:** No new package dependency.

### S3-P7 - Cache adverse historical weather and decomposition bases

**Priority:** Medium
**Confidence:** High
**References:** `R/mod_3_09_decomposition.R:185-241,497-520`,
`R/fct_step2_payload.R:40-69`

**Current pattern**

Mean, adverse 1-in-5, adverse 1-in-10, and adverse 1-in-20 views repeatedly:

- resolve historical weather, including `readRDS()` in reference mode;
- split weather by year;
- split historical pipeline predictions by year;
- recompute annual values and rank years;
- rerun full household decomposition.

The selected view and technical summary table can request overlapping bases.

**Proposed intervention**

For each published policy run, resolve historical weather once, compute the
annual outcome ranking once, cache selected weather row indices for the three
probabilities, and cache full decomposition results for the small set of
historical bases. Reuse them for selected views, technical tables, and exports.

**Expected impact**

Moderate in memory mode and higher I/O improvement in reference mode. At most
four historical decompositions are retained, unlike the much larger future
scenario payload addressed by S3-P1.

**Equivalence requirements**

- Preserve weighted annual outcome ranking, direction, rounding rule, and
  fallback to raw weather.
- Include weather-store signature/owner in a reference-mode cache key.
- Preserve stale/deleted-reference failure behavior.

**Dependencies:** No new package dependency.

### S3-P8 - Debounce and narrow social-protection live preview work

**Priority:** Medium-low
**Confidence:** Medium
**References:** `R/mod_3_01_sp.R:656-781`,
`R/fct_policy_sim.R:204-252`

**Current pattern**

Every targeting, cutoff, error, budget, amount, and payment edit invalidates the
live reach preview. The helper runs eligibility/error assignment and transfer
arithmetic over the complete Step 2 baseline, and some controls emit several
intermediate values while the user is editing.

**Proposed intervention**

Debounce the complete scenario-to-preview calculation, not only its expensive
helper, so the displayed card cannot combine old calculated values with current
labels. Cache baseline-invariant
preparation such as validated welfare, weights, household-size scale, and PMT
proxy vectors. Continue applying targeting errors with the exact run-derived
seed. Do not debounce the final scenario reactive used by the Run button.

**Expected impact**

Improves sidebar responsiveness on large samples; negligible completed-run
speed impact.

**Equivalence requirements**

- Preview and run must remain identical after the debounce settles.
- Memoization keys must include baseline frame identity, complete scenario
  specification, analysis unit, and deterministic seed.
- Preserve universal, ex-ante-poor, PMT, transfer-first, budget-first, weighted
  budget, inclusion/exclusion errors, and deterministic RNG restoration.
- Preserve eager output behavior required for configuration replay.

**Dependencies:** No new package dependency.

### S3-P9 - Consolidate Step 3 stale observers

**Priority:** Low
**Confidence:** High
**Reference:** `R/mod_3_06_policy_sim.R:108-156`

**Current pattern**

Seven observers separately watch Step 2 results, five policy configurations,
and survey version; each reconstructs and compares the complete live policy
signature. A separate observer cascades Step 2 staleness.

**Proposed intervention**

Create one reactive policy signature and one comparison observer, plus the
distinct Step 2-stale cascade if necessary. Preserve the corrected REACT-18
pattern of reading reactive functions on every invalidation.

**Expected impact**

Small CPU/allocation reduction and a simpler graph. Step 3 is already fast, so
this is primarily maintainability work.

**Equivalence requirements**

Test every lever independently, simultaneous edits, survey version, Step 2
rerun/stale transitions, failed policy runs, first run, and successful rerun.

**Dependencies:** No new package dependency.

### S3-P10 - Avoid duplicate weighted decile construction

**Priority:** Low-medium
**Confidence:** High
**References:** `R/fct_decomposition_summary.R:143-202`,
`R/fct_incidence.R:69-113`, callers in
`R/fct_policy_sim_compare.R:1985-1994` and
`R/mod_3_09_decomposition.R:317-401`

**Current pattern**

Weighted baseline welfare deciles are recomputed for Results incidence and for
each decomposition decile view/export, even though baseline survey, outcome,
and weight are fixed for a published run. Scenario decompositions already carry
a stored decile but the helper recomputes/matches from `svy` first.

**Proposed intervention**

Compute one fixed baseline decile vector per published run and pass it to
incidence/decomposition helpers. Use the stored decile only as the current
fallback when ID mapping is unavailable.

**Expected impact**

Low-to-moderate CPU/allocation reduction in Results/Decomposition rendering.

**Equivalence requirements**

Preserve weighted quantile tie behavior, missing weights/outcomes, one-based ID
mapping, and fallback to stored deciles.

**Dependencies:** No new package dependency.

### S3-P11 - Bound the Step 3 aggregation cache

**Priority:** Low-medium
**Confidence:** High
**Reference:** `R/fct_policy_sim_compare.R:1349-1489`

**Current pattern**

The Step 3 cache retains baseline and policy historical/scenario aggregates for
every visited method and poverty-line value until simulation objects change.
Like Step 2, cached list columns can contain model/year values, SDs, and
aggregated loading matrices.

**Proposed intervention**

Use the same bounded current-plus-default or LRU policy recommended by S2-P6.
Coordinate the implementation rather than creating a second cache abstraction.

**Expected impact**

Prevents incremental RSS growth during long exploratory sessions. Negligible
initial-run impact.

**Equivalence requirements**

Preserve paired baseline/policy cache alignment, deterministic recomputation,
active display, exports after eviction, and poverty-line/deviation key rules.

**Dependencies:** No new package dependency.

### S3-P12 - Add a real Step 3 benchmark fixture

**Priority:** Medium measurement infrastructure
**Confidence:** High
**References:** `dev/bench_step2.R:136-142,853-858,967-971`

**Current pattern**

The benchmark harness exposes `include_step3`, but does not construct a policy
fixture and reports Step 3 timing/memory fields as unavailable. Current Step 3
performance decisions therefore rely on isolated helpers, synthetic tests, or
manual runs.

**Proposed intervention**

Extend the development harness with deterministic policy configurations that
exercise:

- one covariate lever;
- social protection with targeting errors;
- combined levers;
- OLS and RIF;
- historical only and multi-member future scenarios;
- coefficient uncertainty enabled and disabled.

Record policy-application, analytic-delta, hazard, historical/future
decomposition, Results aggregation, retained object/serialized size, and
external process-tree RSS separately.

**Expected impact**

No runtime gain, but essential evidence for S3-P1/P3/P4 and for preventing
regressions in a currently fast step.

**Dependencies:** Development tooling only; no new runtime dependency.

### S3-P13 - Build one invariant decomposition context per policy run

**Priority:** High for decomposition-heavy runs
**Confidence:** Medium-high
**References:** `R/fct_policy_decompose.R:93-276,604-716`,
`R/mod_3_06_policy_sim.R:299-404`

**Current pattern**

Every historical, future-member, future-year, and adverse-weather decomposition
recomputes work that is invariant for a published policy run:

- transformed baseline outcome and social-protection main effect;
- RIF `tau_i_pre`, policy-adjusted `tau_i_post`, and term curve subsets;
- OLS coefficients and diagonal standard errors;
- policy main covariate effect;
- covariate and interaction term-name resolution;
- baseline decile ingredients.

Only hazard values and weather-dependent repositioning/interactions vary by
weather panel.

**Proposed intervention**

Build an immutable internal decomposition context after policy deltas are known.
It should contain resolved terms, coefficient/SE vectors or RIF curves,
transformed baseline vectors, invariant main-channel values, fixed baseline
deciles, and optional coefficient-uncertainty state. Pass it to the central-only
kernel (S3-P3) and the full display wrapper.

**Expected impact**

Potentially high for many future years/members and RIF fits. The compute audit
estimates approximately 2x-10x for the decomposition portion, subject to a real
Step 3 benchmark.

**Memory impact**

Retains one O(N x policy-term) context but replaces repeated temporary vectors.
The context should not include duplicated survey or weather frames.

**Equivalence requirements**

- Invalidate on model fit, outcome/transform, policy survey, weather-term list,
  and coefficient-uncertainty setting.
- Preserve `stats::approx()`, factor-expanded term matching, both interaction
  orderings, warnings, and exact central values.
- Do not share weather-dependent hazard or channel vectors across different
  panels.

**Dependencies:** No new package dependency.

### S3-P14 - Evaluate a lazy paired policy-pipeline representation

**Priority:** Medium structural memory experiment
**Confidence:** Low-medium
**References:** `R/fct_policy_sim.R:1223-1278`, paired aggregation in
`R/fct_sim_compare.R:343-382`, and shared aggregation in
`R/fct_aggregation.R:740-862`

**Current pattern**

Each policy member creates and retains a full new `y_point` vector while the
baseline pipeline remains live. Other large objects usually remain shared by R
copy-on-write, but policy outcome vectors still add O(N x members) memory.

**Proposed intervention**

Prototype an internal paired view containing a reference to the baseline
pipeline plus the policy `delta_per_row`. Teach paired aggregation to compute
policy values as baseline plus delta without materializing the full persistent
policy `y_point`. Materialize only for compatibility consumers or exports that
require the current concrete schema.

**Expected impact**

Limited CPU benefit but potentially substantial retained-memory reduction for
large baselines and many members.

**Equivalence requirements**

- Preserve concrete pipeline schema at public boundaries unless all consumers
  are migrated.
- Preserve deterministic residual pairing, row IDs, year slicing, log/level
  scale, policy-baseline covariance, and partial-member behavior.
- Do not remove `F_loading`, weather, or alignment fields.
- Compare serialized export artifacts as well as numeric aggregates.

**Dependencies:** No new package dependency; requires aggregation-contract work.

### S3-P15 - Pre-index simulation rows by year

**Priority:** Medium
**Confidence:** High
**Reference:** `R/fct_aggregation_delta.R:360-404`

**Current pattern**

Per-year aggregation repeatedly evaluates `pipe$sim_year == yr` across all rows,
then creates another validity mask. This performs O(N x number-of-years) logical
scans for every pipeline and method.

**Proposed intervention**

Build ordered row indices once per pipeline using `split()` or a run-length
index, then pass each year's row indices to aggregation. Reuse the same index
across baseline/policy paired arms and aggregation methods where ownership
allows.

**Expected impact**

Estimated 1.2x-2x for long simulation panels; smaller for short historical
ranges.

**Memory impact**

Adds one O(N) integer index/list but avoids repeated N-length logical vectors.
Coordinate with S2-P22 rather than creating duplicate caches.

**Equivalence requirements**

Preserve sorted year order, `NA`-year exclusion, row order within each year,
validity filtering, and `wise_seed(seed, "residual", yr)` derivation.

**Dependencies:** No new package dependency.

### S3-P16 - Index per-model aggregation results by year

**Priority:** Low
**Confidence:** High
**Reference:** `R/fct_aggregation.R:803-833`

**Current pattern**

For every output year, the combination stage scans each model's per-year result
list using `vapply(... identical(x$sim_year, year))` to find the matching row.

**Proposed intervention**

Name or index each model result by `sim_year` once and retrieve by year directly.

**Expected impact**

Small for current 30-year workloads, but nearly free to implement and avoids
quadratic lookup growth with more years/models.

**Equivalence requirements**

Preserve the first-pipeline year grid, missing-model/year behavior, duplicate
year handling, model order, and output row ordering.

**Dependencies:** No new package dependency.

### S3-P17 - Share one typed policy-diff pass

**Priority:** Medium
**Confidence:** Medium-high
**References:** no-op detection at `R/fct_policy_sim.R:256-300`, model gating at
`R/fct_policy_sim.R:510-521`, numeric deltas at
`R/fct_policy_decompose.R:25-55`, diagnostics at
`R/fct_policy_sim_compare.R:131-194`

**Current pattern**

Policy construction, no-op detection, decomposition, and Diagnostics perform
separate baseline/policy comparisons. Model-gated lever selection also scans
survey column names against model terms on every run.

**Proposed intervention**

Resolve model-gated candidate columns once per model signature, then perform one
typed policy-diff pass after `apply_policy_to_svy()`. Return:

- changed columns using current numeric/factor comparison semantics;
- numeric delta vectors for decomposition;
- changed-row counts and candidate metadata for Diagnostics;
- no-op status, including SP-only behavior.

**Expected impact**

Moderate run/diagnostic allocation reduction and removes duplicated logic. This
is a broader version of S3-P2 and should replace, not coexist with, multiple
candidate caches.

**Equivalence requirements**

- Preserve the `1e-10` numeric delta threshold used by decomposition.
- Preserve literal no-op and SP-only scenario rules, factor coercion, `NA`
  changes, row-count mismatch behavior, and model-term substring gating.
- Do not alter seeded policy assignment or labor reallocation order.

**Dependencies:** No new package dependency.

### S3-P18 - Simplify original-residual ID lookup

**Priority:** Low
**Confidence:** High
**Reference:** `R/fct_aggregation.R:232-267`

**Current pattern**

Original-residual lookup converts IDs to character, checks membership in named
residuals, and then performs a second named lookup. This repeats for each
pipeline/method where the shared residual cache is consumed.

**Proposed intervention**

Convert simulation IDs once and use one `match()` into cached training IDs;
apply the existing deterministic unmatched-ID fallback using the match result.

**Expected impact**

Low isolated speed/allocation improvement, estimated around 1.05x-1.2x for this
lookup. It becomes more useful when many aggregation methods are visited.

**Equivalence requirements**

Preserve duplicate-ID first-match behavior, unmatched-ID deterministic fallback,
`NA` IDs, and caller RNG restoration.

**Dependencies:** No new package dependency.

## Step 3 Correctness Finding Outside the Zero-UI Optimization Set

### S3-C1 - Diagnostics and Decomposition do not expose stale state

**Severity:** High integrity risk
**Confidence:** High
**References:** stale state at `R/mod_3_06_policy_sim.R:136-156`; parent wiring
at `R/mod_3_scenario.R:239-309`; Results gating at
`R/fct_policy_sim_compare.R:1214-1220,2134-2137`; Diagnostics exports at
`R/mod_3_08_diagnostics.R:363-405`; Decomposition exports at
`R/mod_3_09_decomposition.R:291-347,538-545`

**Current behavior**

`policy_stale` is passed to Results, which displays stale state and gates stale
exports. Diagnostics and Decomposition do not receive that reactive. After a
policy lever, survey version, model, or Step 2 input changes, those tabs can
continue displaying and exporting the previously published run without a stale
warning while Results correctly identifies it as stale.

**Recommended intervention**

Treat all Step 3 tabs and exports as one atomic published-run contract. Pass the
same stale reactive to Diagnostics and Decomposition, gate their exports with
the same policy used by Results, and identify stale content consistently.

**Constraint note**

Adding a visible stale indicator changes UI behavior and is therefore outside
the original zero-frontend-impact optimization constraint. Export gating alone
would not solve the misleading visible-state issue. This finding requires
separate functional/UX approval rather than implicit inclusion in a performance
implementation set.

**Required tests**

- Change every policy lever and each upstream Step 2 dependency after a
  successful run.
- Confirm Results, Diagnostics, and Decomposition enter stale state together.
- Confirm all three return to fresh only after successful atomic publication.
- Confirm failed reruns preserve old visible results with consistent stale
  indication and export policy.
- Confirm programmatic replay and first-run behavior.

## Step 3 Dependencies

No new runtime package is recommended.

| Package | Recommendation |
|---|---|
| `collapse` | Continue using the existing grouped hazard path; share groups rather than broad rewrites. |
| `kit` | Do not add; no compelling Step 3 replacement was found. |
| `data.table` | Do not add for current Step 3 findings. |
| `vctrs` | Do not add directly. |
| `bench` | Use only for development measurements. |

## Step 3 Prioritized Approval Sets

### Set 3A - Highest-value memory and scan reductions

- S3-P1: compact future decomposition retention;
- S3-P2: candidate-only change detection;
- S3-P3: central-value-only correction kernel;
- S3-P5: shared published-run diagnostic payload.

S3-P2 and S3-P5 should be designed together so candidate metadata feeds every
diagnostic consumer. S3-P3 should be independently parity-tested before S3-P1.

### Set 3B - Decomposition reuse

- S3-P4: shared hazard preparation;
- S3-P7: cached adverse historical bases;
- S3-P10: cached weighted deciles.
- S3-P13: invariant decomposition context.

### Set 3C - UI/reactive and long-session cleanup

- S3-P6: shared Results transforms;
- S3-P8: debounced SP preview;
- S3-P9: consolidated stale observers;
- S3-P11: bounded aggregation cache.

### Set 3D - Measurement

- S3-P12: production Step 3 benchmark fixture.

This should accompany any approved implementation set.

### Set 3E - Structural or shared aggregation experiments

- S3-P14: lazy paired policy pipelines;
- S3-P15: per-year row indices;
- S3-P16: direct model/year lookup;
- S3-P17: shared typed policy diff;
- S3-P18: direct residual ID matching.

S3-P15/S3-P16/S3-P18 overlap the shared Step 2/3 aggregation path and should be
implemented once for both steps. S3-P14 should wait for the production benchmark
fixture and explicit serialized-payload compatibility tests.

## Step 3 Rejected or Deferred Alternatives

1. **Return to full `resimulate_with_svy()`.** The active analytic delta path is
   faster and preserves member-specific weather without refitting/re-predicting
   every model.
2. **Drop member-specific weather from policy pipelines.** This removes genuine
   inter-model policy/weather interaction spread and breaks Step 3 decomposition.
3. **Recompute policy `F_loading` as a performance change.** This is a statistical
   behavior change, not an equivalent optimization, and remains deferred.
4. **Introduce per-year policy deltas as an optimization.** This changes the
   current period-level policy effect approximation and is outside an equivalent
   performance audit.
5. **Parallelize Step 3 immediately.** Current runtimes are already short, while
   serial execution avoids duplicating survey, model, and decomposition memory.
6. **Broadly replace loops with `collapse`, `kit`, or `data.table`.** Most loops
   iterate over a handful of policy/weather terms. The large-row grouped hazard
   operation already uses `collapse`.
7. **Clear stale results eagerly.** Current UX intentionally preserves stale
   results and exports until a successful rerun; compaction must preserve that
   contract.

S3-C1 is not a rejected recommendation. It is intentionally separated because
its complete correction requires explicit approval for visible stale-state
behavior.

## Step 3 Validation Plan

Approved changes should verify:

- exact deterministic policy-survey output and caller RNG restoration;
- identical central policy `y_point`, alignment IDs, residual pairing, weights,
  member-specific weather, and factor-loading reuse;
- OLS and RIF decomposition additivity and current diagonal-SE approximation;
- factor/binned weather, modal ties, missing locations, and interaction terms;
- fixed weighted baseline deciles and adverse-year selection;
- Results, Diagnostics, Decomposition, CSV, figure, and export-bundle parity;
- first run, rerun, failed run, stale transition, and configuration replay;
- Step 2 reference-weather ownership and cleanup when reference mode is used;
- external process-tree RSS and retained/serialized result size.

## Step 3 Baseline Validation Performed

The following suites passed during this audit:

```text
tests/testthat/test-mod_3_07_results.R
tests/testthat/test-policy-sim-compare-agg-cache.R
tests/testthat/test-policy-decomposition-uncertainty.R
tests/testthat/test-policy-lever-activity.R
tests/testthat/test-active-mask.R
```

Targeted production and production-sized benchmarks were read-only. No
application source code or production data was modified.

## Step 3 Decision Status

All Step 3 items S3-P1 through S3-P18 remain **proposed**. No refactoring is
authorized by this audit record. Because Step 3 is already fast, implementation
should prioritize S3-P1 memory compaction and the low-risk S3-P2/S3-P3 scan and
transient-allocation reductions rather than architectural parallelism.

# Approved Implementation and Delegation Plan

**Approval date:** 2026-09-11
**Integration model:** isolated Agent Manager worktrees, dependency-ordered
integration, and a fresh worktree for each post-integration wave.
**Behavior exception:** S3-C1 is explicitly approved, including consistent
visible stale-state treatment and export gating in all Step 3 result tabs.

This section supersedes the earlier per-step decision-status paragraphs only for
the IDs listed below. Passing a local unit test is not sufficient to retain a
change: each batch must also satisfy its stated contract and benchmark gate.

## Authorized Scope

### Step 1

Authorized:

- P1, P2, P3, P5, P6, P7, P8, P9, P11, P14, P15, and P16.

Not authorized in this delivery:

- P4 because retained fit-snapshot compaction requires a broader persisted
  schema decision;
- P10 and P12 because they are outside Sets A-D;
- P13 because direct RIF coeftable extraction has unresolved numerical-parity
  risk;
- P17 because implementation remains conditional on query-plan evidence;
- any rejected or deferred alternative in the Step 1 audit.

### Step 2

Authorized:

- S2-P1 through S2-P12, excluding none;
- S2-P14;
- S2-P21 and S2-P22.

This is Sets 2A, 2B, 2C, and 2E. S2-P6 is shared by Sets 2C and 2E and must be
implemented once as the common bounded-cache policy.

Not authorized in this delivery:

- S2-P13 and S2-P15 async/parallel experiments;
- S2-P16 through S2-P20 query and RIF experiments;
- any rejected or deferred Step 2 alternative.

### Step 3

Authorized:

- S3-P1 through S3-P13 (Sets 3A-D);
- S3-C1, with the UI/export behavior change described in that finding.

Not authorized in this delivery:

- S3-P14 through S3-P18;
- recomputing policy-side `F_loading`, per-year policy deltas, full policy
  resimulation, or immediate Step 3 parallelism;
- any other rejected or deferred Step 3 alternative.

## Delivery Rules

Every implementation agent must:

1. Read the complete finding text, its equivalence requirements, and the relevant
   validation plan before editing.
2. Characterize current behavior in focused tests before a compute or retained-
   schema rewrite. Tests must cover edge cases identified by the audit rather
   than only the happy path.
3. Make the smallest compatible change. Do not add runtime dependencies, rename
   public inputs/outputs, alter serialized contracts, or broaden the assigned
   scope without coordinator approval.
4. Preserve canonical ordering, factor levels, duplicate-key behavior,
   deterministic RNG streams, failure ledgers, stale-result preservation, and
   member-specific weather.
5. Run focused tests and `git diff --check`. Report changed files, commands,
   timing/allocation or RSS measurements, and any residual risk.
6. Stop rather than silently weakening semantics if strict parity fails. A
   benchmark regression, memory-budget breach, or unclear downstream consumer is
   a failed gate, not a reason to change behavior.
7. Leave unrelated worktree changes untouched and do not modify this audit
   report from implementation worktrees.

The coordinator must inspect each batch independently, integrate only passing
batches, rerun cross-step contracts after shared helper changes, and create the
next wave from the newly integrated revision. Later-wave agents must not build on
stale pre-integration branches.

## Dependency Waves

### Wave 0 - Benchmark and Contract Scaffolding

**Batch W0-A: Step 3 benchmark fixture**

- Findings: S3-P12.
- Primary ownership: `dev/bench_step2.R`, `dev/run_step2_benchmark.sh`, and
  benchmark-only helpers/tests.
- Deliverable: a working opt-in Step 3 benchmark that records policy runtime,
  decomposition runtime, retained/serialized sizes, parent/process-tree RSS,
  workload identity, and deterministic output fingerprints.
- Gate: existing Step 2 benchmark modes remain unchanged; a small fixture runs
  without production data; production execution remains read-only.

Wave 0 starts immediately and provides measurement support for later Step 3
batches. It must not modify production simulation behavior.

### Wave 1 - Independent Low-Risk Improvements

These batches can run concurrently from the audited base. W1-B and W1-C have
narrow file overlap with W1-A, so they remain independent review units and
integrate only after W1-A as specified below.

**Batch W1-A: Step 1 reactive and immutable-data reuse**

- Findings: P3, P7, P8, P14, P16.
- Primary ownership: `R/mod_1_02_surveystats.R`,
  `R/mod_1_05_weatherstats.R`, `R/mod_1_06_model.R`,
  `R/mod_1_07_results.R`, `R/fct_surveystats.R`, and focused Step 1 tests.
- Required proof: unchanged IDs/rendered values and snapshots; stale transitions
  remain exact; map payload observers do not self-invalidate; cached metadata is
  invalidated by `survey_version()` only.

**Batch W1-B: Step 1 density path**

- Findings: P2, P9.
- Primary ownership: `R/fct_surveystats.R`, the density/count portions of
  `R/mod_1_02_surveystats.R`, and focused tests/benchmarks.
- Required proof: production-sized output parity within `1e-12`, exact row/key
  order and types, duplicate/missing key coverage, and a material speedup without
  increased peak memory.
- Coordination: W1-A and W1-B both touch survey-statistics files. They remain
  separate review units, but W1-B integrates after W1-A and resolves only narrow
  mechanical conflicts without redesigning W1-A.

**Batch W1-C: Step 1 RIF preparation and result reuse**

- Findings: P1, P5. P13 is explicitly excluded.
- Primary ownership: `R/fct_fit_model.R`, RIF input preparation in
  `R/fct_rif_sim.R`, fit-scoped result code in `R/mod_1_07_results.R`, and
  focused RIF/result tests.
- Required proof: exact tau/order/schema behavior, unchanged fitted values and
  deterministic output, and lower isolated allocation. Do not change tidy/VCV
  extraction.
- Coordination: integrate after W1-A because both touch `mod_1_07_results.R`.

**Batch W1-D: Step 2 immediate measured wins**

- Findings: S2-P1, S2-P2, S2-P3, S2-P11, S2-P12.
- Primary ownership: `R/mod_2_01_weathersim.R`, `R/fct_get_weather.R`,
  `R/fct_run_simulation.R`, `R/mod_2_02_results.R`, and Step 2 contract tests.
- Required proof: baseline-wave filtering is benchmarked independently first;
  joins preserve rows/order/types and duplicate behavior; residual IDs and RNG
  are exact; threshold outputs and stale transitions are unchanged.
- Gate: run the Step 2 contract, payload, compute, simulation, Results, and
  Diagnostics suites plus one cold and one warm benchmark case.

**Batch W1-E: Step 3 diagnostic kernel and published summaries**

- Findings: S3-P2, S3-P3, S3-P5.
- Primary ownership: `R/fct_policy_sim.R`, `R/mod_3_08_diagnostics.R`, and
  focused policy/decomposition tests.
- Required proof: the central-only kernel exactly matches current `delta_total`
  for OLS, logistic, and RIF cases; candidate-only scans preserve diagnostics;
  summaries publish atomically and failed runs preserve prior results.
- Gate: no retained-payload compaction yet. S3-P1 waits for this kernel and its
  characterization tests.

### Wave 1 Integration Order

Integrate and validate W0-A, W1-A, W1-B, W1-C, W1-D, then W1-E. W1-B/W1-C must
be rebased or mechanically reconciled after W1-A. After each Step 1 batch, run
its focused tests; after all Step 1 batches, run the complete Step 1 suite and
Step 2/3 fit-contract tests. Tag or record the integrated revision before Wave 2.

### Wave 2 - Shared Ownership and Memory Architecture

Start fresh Agent Manager worktrees from the integrated Wave 1 revision.

**Batch W2-A: Step 1 weather path**

- Findings: P6, P11, P15. P17 is excluded.
- Primary ownership: `R/fct_weatherstats.R`, the relevant section of
  `R/fct_get_weather.R`, `R/mod_1_05_weatherstats.R`, and weather tests.
- Required proof: duplicate-sensitive joins and returned ordering are exact;
  deterministic bins are unchanged; map camera/full-screen state survives
  controls; no UI IDs or HTML structure change.
- Gate: browser-level map verification is mandatory for P15.

**Batch W2-B: Step 2 weather ownership and bounded collection**

- Findings: S2-P4, S2-P5, S2-P8, S2-P14.
- Primary ownership: `R/fct_get_weather.R`, weather orchestration in
  `R/fct_run_simulation.R`, `R/mod_2_03_diagnostics.R`, compact weather-store
  helpers, and contract tests.
- Deliverable: one documented ownership/resolution contract covering bounded
  producer/consumer flow, shared immutable key columns, lazy diagnostics, and a
  measured memory-budget fallback.
- Required proof: per-member weather remains available to Step 3; key/member
  ordering and failures are exact; external process-tree peak RSS stays within
  the declared budget; compact and reference modes both pass.
- Coordination: W2-A integrates before W2-B because both touch
  `fct_get_weather.R`.

**Batch W2-C: Step 2 retained-result ownership**

- Findings: S2-P6, S2-P7, S2-P9, S2-P10.
- Primary ownership: `R/mod_2_02_results.R`, reference-store lifecycle in
  `R/fct_run_simulation.R`, payload/schema helpers, and Results/contract tests.
- Required proof: cache bounds and eviction are deterministic; shared derived
  frames do not mutate; reference stores outlive every Step 3 reference and are
  cleaned only when safe; removed top-level objects have no consumer.
- Gate: compact/reference payload replay, failed rerun, stale result, export, and
  Step 3 handoff tests all pass.

**Batch W2-D: Step 3 decomposition context**

- Findings: S3-P4, S3-P7, S3-P10, S3-P13.
- Primary ownership: `R/fct_policy_decompose.R`,
  `R/fct_decomposition_summary.R`, `R/mod_3_09_decomposition.R`, and focused
  decomposition tests.
- Required proof: hazard groups, adverse years, weighted deciles, basis columns,
  additivity, and current uncertainty approximation are unchanged. Cached
  contexts are immutable and scoped to exactly one published run.
- Coordination: consume W1-E's published-summary/kernel contracts rather than
  introducing a second representation.

**Batch W2-E: Step 3 reactive consistency and bounded results**

- Findings: S3-P6, S3-P8, S3-P9, S3-P11, and S3-C1.
- Primary ownership: `R/mod_3_01_sp.R`, `R/mod_3_06_policy_sim.R`,
  `R/mod_3_scenario.R`, `R/mod_3_07_results.R`,
  `R/mod_3_08_diagnostics.R`, `R/mod_3_09_decomposition.R`, aggregation-cache
  code in `R/fct_policy_sim_compare.R`, and module tests.
- Required proof: all three tabs enter and leave stale state atomically; stale
  exports are gated consistently; failed reruns preserve old visible results;
  SP preview remains functionally identical; cache bounds do not alter values;
  paired matrix transforms are reused without mutating inputs.
- Gate: module/server tests must cover every lever and upstream dependency plus
  first run, successful rerun, failed rerun, and configuration replay.

### Wave 2 Integration Order

Integrate W2-A before W2-B. W2-C may proceed from the same Wave 1 base but must
be reconciled after W2-B where reference ownership intersects weather storage.
Integrate W2-D before W2-E so stale/export wiring targets the final decomposition
interface. Run the full Step 2 and Step 3 contract suites after every payload,
reference-store, or published-run schema change.

### Wave 3 - Cross-Step Aggregation and Final Compaction

Start fresh worktrees from the integrated Wave 2 revision.

**Batch W3-A: Shared Step 2 aggregation throughput**

- Findings: S2-P21, S2-P22, using the S2-P6 cache policy already integrated by
  W2-C.
- Primary ownership: `R/fct_aggregation.R`, `R/fct_aggregation_delta.R`,
  `R/mod_2_02_results.R`, and aggregation/Results tests.
- Required proof: both weighting arms remain available on demand; all methods
  preserve values, gradients, residual pairing, and per-year RNG exactly;
  preparation caches remain O(N), bounded, and free of method-specific `N x P`
  matrices.
- Gate: test every aggregation method and residual mode in Steps 2 and 3.

**Batch W3-B: Step 3 compact future decomposition retention**

- Findings: S3-P1.
- Primary ownership: `R/mod_3_06_policy_sim.R`, Step 3 payload/decomposition
  helpers and tests, with consumer adjustments only where contract tests prove
  they are required.
- Required proof: displayed channel, scenario, year, model, and decile summaries
  and exports are identical; no downstream code requires discarded household
  rows; atomic publication and stale-result preservation remain intact.
- Gate: demonstrate a substantial retained and serialized-size reduction on an
  11-year production-sized scenario and no process-tree RSS regression. If exact
  consumer parity cannot be established, retain the current payload.

### Wave 3 Integration Order

Integrate W3-A before W3-B so compaction is measured against the final shared
aggregation behavior. Then run the complete Step 1-3 test suite and final
production-sized benchmark matrix.

## Final Acceptance Matrix

The coordinated delivery is complete only when:

- every authorized ID is implemented or explicitly recorded as gate-failed with
  evidence; a gate-failed item is not replaced with a behavior-changing variant;
- `git diff --check` and the complete repository test suite pass;
- cold/warm Step 2 benchmarks and the new Step 3 benchmark record elapsed time,
  allocation, retained/serialized size, and external process-tree RSS;
- one small and one large country, OLS and RIF, historical-only and future
  scenarios, compact and reference weather, and coefficient uncertainty on/off
  are represented in validation;
- production data remains read-only and no benchmark artifact is written into
  the production source;
- Step 1 UI snapshots, Step 2 payload/replay, and Step 3 Results, Diagnostics,
  Decomposition, stale state, and exports pass end-to-end checks;
- no unauthorized audit item, new runtime dependency, or unrelated source
  refactor is included.

Implementation agents return focused worktree changes and evidence to the
coordinator. Integration, conflict resolution, full-suite validation, and final
benchmark comparison remain coordinator responsibilities.

## Implementation Status

### Wave 0 and Wave 1 - Integrated

**Integrated on `dev`:** 2026-09-11
**Status:** Complete and validated; changes remain uncommitted pending the Wave 2
checkpoint decision.

Integrated batches:

- W0-A: S3-P12 Step 3 benchmark fixture;
- W1-A: P3, P7, P8, P14, and P16;
- W1-B: P2 and P9;
- W1-C: P1 and P5;
- W1-D: S2-P1, S2-P2, S2-P3, S2-P11, and S2-P12;
- W1-E: S3-P2, S3-P3, and S3-P5.

Review corrections completed before integration included metadata-cache
generation invalidation, fit-formula projection fallback, authoritative Step 2
survey staleness, current reference-weather resolution, benchmark runtime-option
verification, compact shared-context aggregation, and deployed-path Step 3
kernel parity coverage.

Validation completed after all integrations:

- all focused Step 1 density, reactive, RIF, Step 2 payload/simulation, Step 3
  kernel/diagnostic, and benchmark suites passed;
- the complete repository test suite passed via
  `Rscript -e 'devtools::test(reporter = "summary")'`;
- `git diff --check` passed;
- production data remained read-only.

Wave 2 must start from this exact integrated revision. Because Agent Manager
worktrees are created from committed Git state and do not inherit uncommitted
workspace changes, create an explicit Wave 1 checkpoint commit before launching
W2-A, W2-C, and W2-D as isolated worktrees.
