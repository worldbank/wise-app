# WISE-APP Visualization Redesign: Coding Brief

## How to use this brief

This is the primary handoff for implementation. It contains the required behavior, chart set, shared conventions, unresolved decisions, and acceptance criteria. Use the longer **WISE-APP Results Visualization Improvement Plan** only when a figure needs additional wording, tooltip, diagnostic, or methodological detail.

## Objective

Redesign the Step 2 and Step 3 output tabs so users can quickly understand:

1. The expected welfare outcome.
2. Variation across weather-year realizations.
3. Outcomes in adverse weather years.
4. Distributional incidence.
5. The sources of uncertainty.
6. For Step 3, the paired policy effect and its level and resilience channels.

Use progressive disclosure: decision-relevant results first, technical curves, settings, and detailed tables second.

## Non-negotiable analytical rules

- WISE-APP is a **stress-testing tool, not a forecast**.
- The survey population is fixed. Do not imply population growth, migration, structural change, or evolving future household distributions.
- Projection windows are climate regimes, not a continuous annual socioeconomic path. Never connect separate windows as a forecast trajectory.
- Distinguish:
  - household welfare distributions;
  - annual population aggregates across weather-year draws;
  - climate-model means;
  - coefficient uncertainty.
- Inter-annual variability, inter-model spread, and coefficient uncertainty are different quantities. Never combine them into an unlabeled generic band.
- Metric direction must come from metadata: lower welfare is adverse; higher poverty is adverse.
- Step 3 comparisons are paired by household, climate model, and weather-year draw. Default to **policy minus baseline**.
- OLS has no repositioning channel. RIF may have repositioning and interaction channels.
- Use survey weights consistently and document the aggregation order.

## Required shared infrastructure

Before building charts, implement these reusable services.

### Metric registry

For every metric, store:

- ID and display label.
- Unit and number format.
- Favorable/adverse direction.
- Valid percent or percentage-point transformation.
- Applicable poverty line or threshold.
- Adverse-tail direction.
- Supported engines and uncertainty methods.
- Plain-language definition and caveat.

All cards, charts, tables, tooltips, and exports must use this registry. Do not infer direction from variable names inside plots.

### Canonical summary functions

Create tested functions for:

- Weighted aggregate by climate model and weather-year draw.
- Model mean across weather-year draws.
- Across-model center and interval.
- Historical reference mean or median.
- Return-period threshold.
- Fixed-baseline welfare deciles.
- Paired Step 3 policy effect.
- Level, resilience, and detailed decomposition channels.

Do not pool model-year observations until the intended estimand and model weighting are defined.

### Shared UI components

Build reusable modules for:

- Run-context banner.
- Metric and display controls.
- Headline cards.
- Dot-and-interval plot.
- Paired difference or dumbbell plot.
- Distribution plot with observation-unit subtitle.
- Return-period plot and table.
- Warning/status callout.
- Accessible chart-data table and download.

Separate numerical calculations from plotting.

## Shared page behavior

Each tab should begin with:

1. **Run context:** economy, survey year, historical weather window, SSPs, projection windows, climate-model count, run ID.
2. Label: **Stress-test scenario—not a forecast**.
3. Primary controls: metric, poverty line if relevant, display mode, scenario and period.
4. Collapsed advanced controls: uncertainty coverage, tail settings, smoothing, and technical display options.

Mark results stale if simulation inputs change after a run. Preserve compatible filters across tabs.

Use a single-column primary reading order. Use small multiples rather than overlays when more than three scenario-period series are selected.

# Step 2 Results

## S2-1. At a glance

Show four to six cards for a selected focus scenario-period:

- Historical expected outcome.
- Scenario expected outcome.
- Change from historical.
- Adverse 1-in-10-year outcome.
- Climate-model range.
- Number of models and weather-year draws.

Note that the population and non-weather characteristics are fixed.

## S2-2. Expected outcome by scenario

Use a horizontal dot-and-interval chart:

- Row: scenario × projection window.
- Dot: expected annual aggregate.
- Thick interval: inter-model range of model-level means.
- Historical: neutral row or reference line; no inter-model interval.
- Coefficient interval: optional thin whisker, off by default.

Subtitle: **Dots show expected annual outcomes; intervals show disagreement across climate models.**

## S2-3. Annual aggregate distribution

Use violin, box-and-dot, or quantile-dot plots:

- Observation: one annual aggregate for the fixed population under one weather-year draw.
- Historical: grey.
- Future: SSP color.
- Facet by period when necessary.

Title must say **Distribution of annual [metric] across simulated weather years**. Do not call it a household welfare distribution.

## S2-4. Adverse-year outcomes

Use a return-period dot plot:

- Rows: Expected, adverse 1-in-5, 1-in-10, 1-in-20; include 1-in-50 only if methodologically supported.
- X-axis: outcome level or change from historical.
- Color: SSP; facet: period.
- Interval: inter-model spread at the threshold.

Select the adverse tail from the metric registry. Retain the full exceedance curve only as an advanced view.

## S2-5. Distributional incidence

Default to an effect-by-baseline-decile chart:

- Deciles 1–10 based on weighted observed baseline welfare.
- Y-axis: household-level simulated welfare effect.
- Zero line.
- One focus scenario-period or small multiples.

Explain flat OLS profiles when they follow mechanically from the specification. For RIF, disclose rank stability and interpolation.

An optional household welfare distribution may show historical versus one clearly defined scenario summary. State whether it represents expected conditions or an adverse return period.

## S2 table

Default columns:

| Scenario and period | Expected | Adverse 1-in-5 | Adverse 1-in-10 | Adverse 1-in-20 | Change from historical |
|---|---:|---:|---:|---:|---:|

Put both tails, coefficient uncertainty, pooled uncertainty, extrema, and counts in an expandable technical table.

# Step 2 Diagnostics

## D2-1. Weather support

Show one panel per weather variable:

- Step 1 regression input: grey reference distribution.
- Full historical archive: optional outline.
- Future scenarios: SSP-colored outlines or facets.
- Use common bins or bandwidth and normalize each distribution separately.
- Display sample sizes and the share outside the regression support and a robust support interval.

Title: **Weather inputs and Step 1 model support**.

Warn that out-of-support weather requires extrapolation. The plotted weather variable and temporal transformation must match the actual Step 1 regressor or be explicitly labeled as a precursor.

## D2-2. Sources of variation and uncertainty

Default to separate aligned SD bars for:

- Inter-annual weather variability.
- Inter-model climate spread.
- Coefficient uncertainty.

Do not stack SDs. Optionally show approximate variance shares using squared components, with covariance or decomposition assumptions disclosed.

## D2-3. Climate-model robustness

Default to a model-level dot, box, or beeswarm plot:

- Each point: one climate model’s mean across weather-year draws.
- Show across-model center and interval.
- Historical appears once.

Keep weather-year trajectories as an advanced view. Facet projection windows and never connect across windows. Label historical weather-year draws accurately.

# Step 3 Results

Default to **paired policy minus baseline**. Offer **Outcome levels** as an alternate display.

Encoding:

- SSP: color.
- Baseline: open neutral marker.
- Policy: filled marker.
- Policy effect: scenario-colored point around zero.
- Historical: neutral reference shown once.

Do not overlay baseline and policy ribbons by default.

## S3-1. At a glance

Cards:

- Expected paired policy effect.
- Policy-adjusted outcome with baseline context.
- Effect in an adverse 1-in-10 year.
- Level effect.
- Resilience effect.
- Program cost and beneficiaries when applicable.

## S3-2. Expected policy effect

Default: zero-centered dot-and-interval plot of paired effects by scenario-period.

Alternate: baseline-policy dumbbell chart with offset intervals and the difference labeled.

Paired-effect intervals must retain baseline-policy covariance.

## S3-3. Annual policy-effect distribution

Plot policy minus baseline for each matched model and weather-year draw. Use a zero-centered violin, box, or quantile-dot plot.

Alternate outcome-level view may show baseline and policy outlines in separate scenario-period panels.

## S3-4. Adverse-year policy effect

Use paired effects at Expected, 1-in-5, 1-in-10, and 1-in-20 adverse thresholds. Document whether the effect compares equal-probability quantiles or the same baseline weather event.

Keep full baseline-policy exceedance curves advanced and limited to one scenario-period per panel.

## S3-5. Distributional incidence

Plot policy minus baseline by fixed baseline welfare decile. Optionally add transfer or coverage by decile.

## S3 table

Default columns:

| Scenario and period | Expected baseline | Expected policy | Policy effect | Adverse 1-in-10 effect | Adverse 1-in-20 effect |
|---|---:|---:|---:|---:|---:|

Include detailed baseline, policy, paired differences, uncertainty, and counts in the technical download.

# Step 3 Diagnostics

## D3-1. Policy construction

Show user input, derived quantity, and realized value separately. Include active levers, targeting rule, error rates, random seed, changed population share, and reconciliation status.

For cash transfers, show:

- Annual budget.
- Eligible and actual recipients.
- Annual transfer per recipient.
- Daily per-capita welfare equivalent.
- Realized inclusion and exclusion errors.

## D3-2. Treatment assignment

Use a weighted eligible/not-eligible × treated/not-treated matrix, or status bars for baseline covered, newly covered, still uncovered, and lost coverage.

## D3-3. Manipulated variables

Table columns:

| Variable | Lever | Baseline | Policy | Change | Units changed | Weighted share changed |
|---|---|---:|---:|---:|---:|---:|

Use type-specific before/after charts:

- Continuous: common-bin histograms, density outlines, or ECDFs.
- Binary: labeled coverage bars.
- Categorical: grouped category-share bars.

Treat policy-adjusted simulated welfare separately from raw survey welfare.

## D3-4. Covariate support

Compare policy-adjusted covariates with Step 1 training support. Flag out-of-range numeric values and absent or rare categories. State that support overlap does not establish policy realism or causal validity.

# Step 3 Decomposition

## C3-1. Headline decomposition

Use a waterfall or two-part bar:

- Level effect.
- Resilience effect.
- Total effect.

Do not mix log points and percent on one axis. Show a reconciliation status.

## C3-2. Decomposition summary

Hierarchical rows:

- Total.
- Level.
  - Cash transfer.
  - Covariate shift.
- Resilience.
  - Repositioning, RIF only.
  - Interaction.

The total SE must preserve cross-channel covariance. Hide shares of total when the denominator is near zero or channels offset.

## C3-3. Channels by baseline decile

Default bars: level and resilience by decile, with a total marker. Advanced mode expands to four technical channels. Use diverging or grouped bars when signs differ.

## C3-4. RIF weather-sensitivity curves

RIF only:

- Facet by weather term.
- X-axis: baseline welfare quantile.
- Y-axis: coefficient with explicit unit.
- Show grid estimate points, interpolation, zero line, and optional interval.
- Use plain-language term labels and state reference categories.

For OLS, replace the chart with an explanation of constant coefficients and interaction-based resilience.

## C3-5. Channels across climate scenarios

Small multiples for level, resilience, and total:

- Point: mean channel effect.
- Box or interval: weather-year variation for weather-sensitive channels.
- Optional thin whisker: inter-model spread.
- Level effect: point only when constant across weather-year draws.
- Never connect projection windows.

# Visual and accessibility rules

- Historical: neutral grey.
- SSPs: stable colorblind-safe palette.
- Baseline/policy: open versus filled shape, not color alone.
- Decomposition channels: separate mechanism palette; do not reuse SSP colors.
- Include metric and unit on every axis.
- Use sentence-case titles and subtitles defining the observation unit.
- Prefer direct labels; separate legends by scenario, policy status, and interval type.
- Provide an accessible table and downloadable data for every chart.
- Test keyboard use, contrast, narrow screens, and 200% zoom.

# Decisions requiring owner sign-off

The coding agent must not choose these silently:

1. Across-model center: mean or median.
2. Equal model weighting or pooled model-year weighting.
3. Exact construction of inter-annual intervals across models.
4. Treatment of 1-in-50 results with approximately 30 weather years.
5. Step 3 return-period effect: equal-probability quantiles or same weather event.
6. Weather and covariate support-warning thresholds.
7. Log-effect conversion to percent and level effects.
8. RIF extrapolation beyond the estimated quantile grid.
9. Retention and labeling of approximate Step 3 coefficient bands.
10. Validity of variance shares when covariance is omitted.

CMIP6 model intervals must be labeled as **ensemble spread**, not probabilities that the future lies within the range.

# Implementation order

## Phase 1: Shared contracts and quick clarity

- Metric registry and canonical summary functions.
- Run banner, stale-state behavior, dynamic units and labels.
- Headline cards and simplified tables.

## Phase 2: Core results

- Step 2 expected outcomes, weather-year distribution, and return-period plot.
- Step 3 paired-effect, annual-effect, and adverse-year plots.

## Phase 3: Diagnostics and decomposition

- Step 2 support and uncertainty diagnostics.
- Step 3 policy construction and covariate diagnostics.
- Decile incidence and decomposition views.

## Phase 4: Advanced views and hardening

- Exceedance curves, RIF coefficient curves, detailed model views.
- Exports, accessibility, visual regression tests, and performance tuning.

# Definition of done

A figure is complete only when:

- Its estimand and aggregation order are documented.
- Values reconcile with its table and existing validated outputs.
- Units, direction, transformations, and tail come from the metric registry.
- Uncertainty type and coverage are visible.
- Loading, empty, unavailable, stale, and error states exist.
- OLS/RIF conditional behavior is correct.
- It passes numerical, no-op, visual, responsive, and accessibility tests.
- Its data and metadata are downloadable.
- Its wording is reflected in the user guide.

Minimum invariant tests:

- A no-op policy gives zero paired effects and identical outcome levels.
- Historical results have no inter-model spread.
- Level plus resilience equals total on the model scale.
- Changing interval coverage does not change central estimates.
- Binary and sector shares remain valid.
- Projection windows are never rendered as a continuous forecast.

---
*This document was generated by mAI.*