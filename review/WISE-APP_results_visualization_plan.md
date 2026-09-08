# WISE-APP Results Visualization Improvement Plan

## Purpose

This plan provides an actionable redesign specification for the WISE-APP Step 2 and Step 3 results interfaces. It is intended for a design or development agent that may not have access to the earlier discussion. The plan defines the recommended information architecture, figure construction, controls, labels, explanatory notes, and implementation priorities while allowing reasonable flexibility in charting libraries and detailed styling.

The redesign should make the principal findings immediately understandable without removing the analytical depth required by technical users.

## Methodological constraints

All implementation decisions must respect the following constraints.

1. WISE-APP is a stress-testing tool, not a forecasting engine. Avoid language and graphics that imply a continuous economic forecast or a prediction of future poverty.
2. The baseline survey population is fixed. Future scenarios apply climate perturbations to the same households; they do not simulate population growth, migration, structural transformation, or future economic development.
3. A projection window is a climate regime, not a year-by-year socioeconomic trajectory. Do not interpolate continuous paths between projection windows.
4. Historical weather years provide repeated weather realizations. In most Step 2 charts, each simulated observation represents an annual aggregate for the fixed population under one weather-year draw—not an individual household.
5. Climate-model spread, inter-annual weather variability, and coefficient uncertainty are distinct and should not be presented as interchangeable confidence intervals.
6. Indicator direction varies. Higher consumption or income is favorable; higher poverty measures are adverse. Labels and tail calculations must respond to the selected metric.
7. Step 3 baseline and policy outcomes are paired because they use the same households, weather realizations, and simulation structure. Figures should preserve this pairing.
8. OLS and RIF support different interpretations. In particular, the RIF engine permits heterogeneous impacts and a repositioning resilience channel; OLS may impose homogeneous welfare changes unless interactions create heterogeneity.

## Design principles

The results should follow the questions users are most likely to ask:

1. What is the headline result?
2. How do expected outcomes differ across scenarios?
3. How much can annual weather move the outcome?
4. What happens in an adverse weather year?
5. Which parts of the welfare distribution are affected?
6. How uncertain is the result, and why?
7. For Step 3, does the policy raise welfare levels, reduce weather sensitivity, or both?

Use progressive disclosure. The default view should contain decision-relevant results; technical settings, complete probability curves, detailed uncertainty outputs, and large tables should remain accessible under advanced or diagnostic sections.

## Shared page structure

Use the following vertical structure for both Step 2 and Step 3:

1. **Run context banner**
2. **Primary analysis controls**
3. **At a glance**
4. **Expected outcomes**
5. **Weather-year risk**
6. **Distributional effects**
7. **Technical details and downloadable table**
8. **Diagnostics**

Step 3 should add a **Policy channels** section between Distributional effects and Technical details.

### Run context banner

Show a compact, non-editable summary of the completed simulation. Suggested format:

> Fixed population: [economy and survey year] · Historical weather: [start–end] · Climate scenarios: [selected SSPs] · Projection windows: [selected windows] · [N] climate models

Add a short status label: **Stress-test scenario—not a forecast**.

Keep simulation inputs in the sidebar, but distinguish locked run inputs from controls that only alter the presentation. If changing an input requires rerunning the simulation, label it accordingly.

### Primary analysis controls

Place these controls in one compact row above the results:

- Outcome metric or aggregation method.
- Poverty line, only when relevant.
- Display mode: **Outcome level** or **Change from historical**.
- Scenario and projection-window filter.
- Optional geography or subgroup filter if supported.

Place these in a collapsed **Display and uncertainty settings** panel:

- Coefficient uncertainty toggle and coverage.
- Climate-model spread toggle and coverage.
- Rare-tail axis setting.
- Headcount smoothing bandwidth.
- Group ordering and other technical display settings.

Use dynamic labels. Avoid generic phrases such as “Outcome value” when the selected metric is known.

# Step 2: Climate Scenario Results

## Section heading: At a glance

### Figure S2-1. Headline result cards

#### Purpose

Give the user an immediate interpretation of the selected climate scenario and projection window.

#### Construction

Display four to six cards in one responsive row, wrapping to two rows on smaller screens:

1. **Historical expected [metric]**: mean of the annual aggregate under historical weather.
2. **Expected [metric] under [scenario/window]**: mean across the relevant simulated model-year outcomes, following the app’s existing aggregation convention.
3. **Change from historical**: absolute and relative change where meaningful. Use percentage points for rates and percent for level outcomes.
4. **Adverse 1-in-10-year outcome**: the adverse-tail threshold for the selected metric.
5. **Climate-model range**: compact selected quantile range or full range of model-level expected outcomes.
6. **Simulation coverage**: number of climate models and weather-year draws.

Where multiple scenarios are selected, require a single “focus scenario” for the cards or show a compact comparison card rather than duplicating the whole strip.

#### Layout and styling

Use large values, concise titles, and one-line definitions. Historical cards should be neutral grey. Scenario cards should use the scenario color. Do not use red or green as the only indicator of direction.

#### Required note

> Results hold the survey population and non-weather characteristics fixed. Differences reflect simulated weather conditions under the selected climate regime.

## Section heading: Expected outcomes under climate scenarios

### Figure S2-2. Expected outcome by scenario

#### Purpose

Compare the central expected outcome across historical and future climate regimes without combining all uncertainty sources in one nested display.

#### Construction

Use a horizontal dot-and-interval plot.

- Y-axis: one row per scenario × projection window.
- X-axis: selected outcome value or change from historical.
- Dot: expected annual aggregate for that scenario-period.
- Thick interval: selected inter-model quantile range of each climate model’s time-mean aggregate.
- Historical outcome: either its own row or a vertical reference line. If using a row, do not draw an inter-model interval.
- Optional thin coefficient-uncertainty interval: hidden by default and enabled in advanced settings.

If several projection windows are selected, facet by window or group rows with visible spacing. Avoid encoding SSP, period, baseline, and uncertainty using four simultaneous aesthetics.

#### Labels

Suggested heading: **Expected [metric] by climate scenario**

Suggested subtitle:

> Dots show expected annual outcomes; intervals show disagreement across climate models.

The X-axis must include the unit. Examples:

- `Mean consumption, 2021 PPP $/person/day`
- `Poverty rate, % of population`
- `Change in poverty rate from historical, percentage points`

#### Interaction

Tooltips should show the expected value, historical difference, interval definition, number of climate models, and projection window.

#### Required note

> Climate-model spread describes disagreement in expected outcomes across models. It is not the range of outcomes across individual weather years.

## Section heading: Variation across weather years

### Figure S2-3. Distribution of annual aggregate outcomes

#### Purpose

Show how much the population aggregate varies from one weather-year realization to another within each climate regime.

#### Construction

Use a compact violin plot, density plot, or box-and-dot plot. Select the form that performs reliably in the chosen Shiny charting library.

- Each underlying observation must be an annual aggregate for the fixed survey population.
- For future scenarios, preserve climate-model structure. Preferred options are:
  - pooled model-year observations with a clearly stated definition;
  - one compact distribution per climate model with model summaries layered; or
  - distributions of within-model annual deviations plus a separate between-model display.
- Show the historical distribution in grey.
- Show future scenarios using the shared SSP palette.
- Add a vertical reference line for the historical expected outcome.

Use small multiples when more than two or three scenario-period combinations are selected. Do not overlay many opaque densities.

#### Labels

Heading: **Distribution of annual [metric] across simulated weather years**

Subtitle:

> Each observation represents the aggregate outcome for the same baseline population under one simulated weather year.

Do not title this “welfare distribution,” which could be mistaken for the distribution across households.

#### Required note

> This chart shows variation across annual weather realizations, not variation across households and not a continuous forecast over calendar time.

## Section heading: Risk in adverse weather years

### Figure S2-4. Return-period dot plot

#### Purpose

Provide an accessible default view of severe but plausible weather-year outcomes.

#### Construction

Use a dot-and-interval chart.

- Rows: Expected, adverse 1-in-5, adverse 1-in-10, adverse 1-in-20, and optionally adverse 1-in-50.
- X-axis: outcome level or deviation from historical.
- Dot color: SSP scenario.
- Facet: projection window when multiple windows are selected.
- Interval: selected inter-model quantile range at each threshold.
- Historical thresholds: neutral grey comparison dots or a separate first facet.

Determine the adverse tail automatically:

- Lower tail for welfare, income, consumption, wages, or other outcomes where higher is better.
- Upper tail for poverty, deprivation, losses, or other outcomes where higher is worse.

If direction cannot be inferred safely, require metadata or an explicit configuration rather than guessing.

#### Labels

Heading: **Outcome in adverse weather years**

Use plain-language row labels such as **Adverse 1-in-10 year**, not probability ratios such as `1:10`.

Add an inline definition:

> An adverse 1-in-10-year outcome is reached or exceeded in the unfavorable direction in approximately one out of ten simulated weather years under the selected climate regime.

#### Advanced companion figure

Retain the complete exceedance-probability curve under **Advanced risk curve**. Default it to the adverse tail, limit or facet the number of overlaid scenarios, and translate probabilities into return periods in tooltips. Rename “Logit probability axis” to **Expand rare-event tails**.

## Section heading: Who is affected?

### Figure S2-5. Welfare effect by baseline decile

#### Purpose

Show whether climate-related welfare changes are concentrated among poorer or richer households.

#### Construction

Default to a decile chart:

- X-axis: baseline welfare decile, 1 poorest to 10 richest.
- Y-axis: mean simulated change in welfare or another explicitly defined household-level effect.
- Bars or dots: effect for each decile.
- Zero reference line.
- Scenario selection: one focus scenario, with optional side-by-side comparison or small multiples.
- Intervals: show coefficient uncertainty only if valid for the derived decile estimate; otherwise omit rather than imply unsupported precision.

Offer an advanced percentile curve for RIF models where the estimated quantile structure supports it. Do not interpolate a highly detailed curve beyond the model’s effective quantile resolution without visibly indicating smoothing or interpolation.

#### Labels

Heading: **Simulated welfare effect by baseline welfare decile**

Subtitle:

> Households remain grouped by their observed baseline welfare; decile 1 is the poorest.

#### Engine-specific note

For OLS results, state when homogeneous model effects mechanically produce a flat or nearly flat incidence profile. For RIF, note that heterogeneous effects reflect estimated distributional gradients and the rank-stability assumption.

### Optional Figure S2-6. Household welfare distribution

Use a density, histogram, or quantile-function view of household welfare under historical and selected scenario conditions. Show the poverty line when relevant. Keep this secondary because it answers a different question from Figure S2-3.

Heading: **Welfare distribution of the fixed baseline population**

State exactly how weather years and climate models are summarized—for example, whether the chart uses an expected scenario, a selected adverse year, or a pooled distribution. Never leave this ambiguous.

## Section heading: Detailed results

### Table S2-1. Return-period summary

The default table should contain:

| Scenario and period | Expected | Adverse 1-in-5 | Adverse 1-in-10 | Adverse 1-in-20 | Change from historical |
|---|---:|---:|---:|---:|---:|

Use consistent units and decimal precision. Allow users to expand a **Technical table** containing both tails, coefficient uncertainty, pooled standard errors, ensemble extrema, and observation counts.

Rename `Obs` to **Weather years per climate model** or another exact description. Label pooled uncertainty explicitly as relying on an independence assumption.

# Step 3: Policy Scenario Results

## Purpose and relationship to Step 2

Step 3 should inherit the Step 2 visual grammar, chart order, metric definitions, scenario colors, return-period conventions, and advanced controls. However, simply adding a second “Policy” series to every Step 2 chart creates duplicate points, intervals, ribbons, and curves. The current interface demonstrates this problem: baseline and policy uncertainty layers overlap, while the policy effect—the main quantity of interest—is visually secondary.

The primary Step 3 estimand should therefore be the **paired policy effect**:

$$
\Delta_{s,p,m,t} = Y^{\text{policy}}_{s,p,m,t} - Y^{\text{baseline}}_{s,p,m,t},
$$

where scenario $s$, projection period $p$, climate model $m$, and weather-year draw $t$ are held identical. Preserve this pairing in calculations, summaries, intervals, tooltips, and downloads.

Every main Step 3 figure should offer two coordinated display modes:

- **Policy effect** — policy minus paired baseline; recommended default.
- **Outcome levels** — baseline and policy shown together for users who need absolute context.

Do not compute the uncertainty of the policy effect by treating baseline and policy as independent. Use paired differences wherever the simulation output permits. If a displayed policy-series coefficient band is only an approximation based on baseline factor loadings, disclose that limitation directly beside the relevant control.

## Step 3 shared controls and visual encoding

Place the following controls above the first result:

- Metric or aggregation method.
- Poverty line when applicable.
- Display: **Policy effect / Outcome levels**.
- Effect unit: **Original unit / Percent or percentage-point change**, where valid.
- Scenario and projection-window filter.
- Focus scenario for cards and dense figures.

Place these under **Display and uncertainty settings**:

- Inter-model interval toggle and coverage.
- Coefficient uncertainty toggle and coverage.
- Baseline visibility toggle in Outcome levels mode.
- Rare-tail expansion and return-period controls.
- Advanced smoothing or table options.

Use this consistent encoding throughout Step 3:

- SSP scenario: color, using the Step 2 SSP palette.
- Baseline: open circle and neutral grey treatment.
- Policy: filled diamond or filled circle with a dark outline.
- Baseline-policy connection: thin neutral line or arrow.
- Policy effect: scenario-colored point relative to a zero line.
- Historical climate: neutral grey reference shown once.

Policy status should not be encoded primarily as red versus grey because SSP already uses color and red can imply that a beneficial policy is adverse. Shape and fill should carry baseline-policy status. Include a compact global legend near the first figure and keep the same symbols throughout the tab.

## Section heading: At a glance

### Figure S3-1. Policy result cards

#### Purpose

Summarize the magnitude, direction, tail protection, and cost of the selected policy for one focus scenario and projection window.

#### Construction

Show four to six responsive cards:

1. **Expected policy effect on [metric]**: mean of paired policy-minus-baseline differences.
2. **Policy-adjusted expected [metric]**: absolute policy outcome, with the baseline value in smaller text.
3. **Effect in an adverse 1-in-10 weather year**: policy-minus-baseline difference evaluated consistently at the selected return-period definition.
4. **Level effect**: direct main effect from transfers and covariate shifts.
5. **Resilience effect**: weather-sensitivity effect from repositioning and interactions.
6. **Program scale**: annual cost and beneficiary count when available.

For rates, report percentage-point effects. For welfare levels, show the original unit and an optional percent effect. Use language such as **improvement**, **reduction**, or **increase** only after applying metric-direction metadata.

#### Required note

> Effects compare policy and baseline outcomes for the same households, climate model, and weather realization. They are simulated model effects, not causal impact estimates.

## Section heading: Does the policy improve expected outcomes?

### Figure S3-2A. Policy effect by climate scenario — default

#### Purpose

Make the policy effect directly visible without duplicating the full baseline and policy uncertainty structure.

#### Construction

Use a zero-centered horizontal dot-and-interval plot.

- Y-axis: scenario × projection window.
- X-axis: paired policy-minus-baseline effect.
- Dot: mean paired effect across the relevant model-year outcomes.
- Thick interval: selected inter-model range of each model’s mean paired policy effect.
- Optional thin interval: coefficient uncertainty for the paired effect, only where it is correctly derived and clearly identified.
- Vertical zero line: no policy effect.
- Historical effect: include once as a neutral row if analytically useful; otherwise keep it as a reference in the details table.

If metric direction differs, retain signed effects in the original unit. Optionally add a secondary **Improvement** display that reorients the sign so positive always means favorable, but label this transformation prominently and retain actual signed values in tooltips and downloads.

#### Heading and subtitle

Heading: **Policy effect by climate scenario**

Subtitle:

> Points show the average paired policy effect; intervals show how that effect differs across climate models.

#### Required note

> Inter-model intervals describe variation in the simulated policy effect across climate models. They are not confidence intervals for causal policy effectiveness or implementation performance.

### Figure S3-2B. Baseline and policy outcome levels — alternate

#### Purpose

Provide absolute outcome context while preserving the pairing.

#### Construction

Use a horizontal dumbbell chart.

- One row per scenario × projection window.
- Baseline: open neutral marker.
- Policy: filled marker using the scenario color.
- Connector: thin line from baseline to policy.
- Label the paired difference beside the policy marker when space allows.
- Optional inter-model intervals: use narrow, offset intervals for baseline and policy; do not place wide translucent bands on top of one another.
- Coefficient intervals: hidden by default. If enabled, use thin whiskers rather than another filled layer.

For many scenario-period combinations, facet by period. Do not duplicate the historical point for every policy/scenario combination.

Heading: **Baseline and policy-adjusted outcomes**

Subtitle:

> Connected points use the same simulated climate and weather conditions; their separation is the modeled policy effect.

## Section heading: How does policy affect weather-year variability?

### Figure S3-3A. Distribution of paired annual policy effects — default

#### Purpose

Show whether the policy effect is stable across ordinary and adverse weather-year realizations.

#### Construction

Adapt the Step 2 annual aggregate distribution figure to plot paired differences rather than two overlapping outcome distributions.

- Each observation: policy aggregate minus baseline aggregate for the same scenario, climate model, and weather-year draw.
- Display: violin, density, boxplot, or quantile-dot plot.
- Zero reference line.
- One panel per scenario × projection window, or small multiples when more than three combinations are selected.
- Optional marker for the average paired effect.
- Optional interval showing the across-model distribution of model-level mean effects, clearly distinguished from the model-year distribution.

Heading: **Distribution of annual policy effects across weather years**

Subtitle:

> Each observation compares policy and baseline for the same weather-year realization and fixed survey population.

This figure is preferable to overlaid baseline and policy densities because it directly reveals the policy effect and avoids obscuring two similar distributions.

### Figure S3-3B. Baseline and policy annual outcome distributions — alternate

When users select Outcome levels, show baseline and policy distributions using outlines rather than two opaque fills:

- Baseline: neutral grey outline or light fill.
- Policy: scenario-colored outline with limited transparent fill.
- Use one scenario-period per panel.
- Add vertical lines for baseline and policy expected outcomes.
- Maintain identical scales and smoothing for the paired distributions.

Heading: **Annual baseline and policy outcomes across weather years**

Required note:

> These are distributions of annual population aggregates, not distributions of household welfare.

## Section heading: Does the policy protect against adverse weather years?

### Figure S3-4. Policy effect at return-period thresholds

#### Purpose

Show how much the policy changes expected, moderately adverse, and severe annual outcomes.

#### Default construction

Use a dot-and-interval chart of paired policy effects.

- Rows: Expected, adverse 1-in-5, adverse 1-in-10, adverse 1-in-20, and optionally adverse 1-in-50.
- X-axis: policy-minus-baseline effect in the selected metric.
- Color: SSP.
- Facet: projection window.
- Zero line: no effect.
- Interval: inter-model range of paired effects at the threshold.

The threshold pairing rule must be explicit. Prefer comparing policy and baseline at the same probability level within each climate model. If instead the policy value is evaluated at the baseline-defined weather event, document and label that approach; the two estimands answer different questions.

#### Outcome-level alternate

Use connected baseline-policy dots at each return period. Avoid drawing independent baseline and policy ribbons.

#### Heading and subtitle

Heading: **Policy effect in adverse weather years**

Subtitle:

> Differences compare policy and baseline outcomes at the same return-period probability under each climate scenario.

#### Required note

> A change at the 1-in-10 threshold describes the simulated outcome distribution under the policy. It is not evidence that the policy changes the probability of the underlying weather event.

### Figure S3-5. Advanced exceedance-probability comparison

Retain the full curve only as an advanced view. The current mirrored chart becomes cluttered because each scenario adds baseline and policy curves, inter-model ribbons, and coefficient bounds.

Use one of these two display modes:

**Preferred: policy-effect curve**

- X-axis: paired policy effect at each exceedance probability.
- Y-axis: annual exceedance probability or return period.
- Zero reference line.
- One scenario-period per facet.
- Ribbon: inter-model spread of the paired effect.

**Alternate: outcome-level curves**

- Baseline: thin, muted, dashed or dotted curve.
- Policy: solid scenario-colored curve.
- Inter-model ribbon: show for one selected series at a time or use thin quantile boundaries; do not default to two overlapping ribbons.
- Coefficient uncertainty: off by default.
- Limit the visible selection to one SSP and one projection window per panel, or automatically facet the combinations.
- Historical: show once as a fixed neutral reference, not repeated within every baseline-policy pair.

Heading: **Advanced annual risk curves: baseline and policy**

Add controls: **Show baseline**, **Show inter-model spread**, **Show coefficient uncertainty**, **Adverse tail only**, and **Expand rare-event tails**.

Tooltips should show probability, return period, baseline outcome, policy outcome, paired difference, scenario, period, model-summary convention, and interval definition.

## Section heading: Who benefits?

### Figure S3-6. Policy effect by baseline welfare decile

#### Purpose

Show the distributional incidence of the policy without requiring users to subtract two household profiles visually.

#### Construction

- X-axis: baseline welfare decile, 1 poorest to 10 richest.
- Y-axis: mean policy-minus-baseline welfare effect.
- Mark: bars or dots with a zero line.
- Group households using observed baseline welfare and keep group membership fixed.
- Use one focus scenario-period or small multiples.
- Optional second panel: coverage rate or mean transfer by decile for social-protection policies.
- Optional total-effect marker with decomposition channels shown only when the user expands the technical view.

Heading: **Policy benefit by baseline welfare decile**

Subtitle:

> Households are grouped by observed baseline welfare; the chart shows policy minus paired baseline outcomes.

For RIF results, disclose the rank-stability assumption. For OLS, explain when a flat profile follows mechanically from a homogeneous specification.

### Figure S3-7. Household welfare distribution — optional

If household-level distributions are shown, use one scenario-period per panel and one clearly defined weather summary, such as expected climate conditions or a selected adverse return period.

Preferred encoding:

- Baseline distribution: neutral outline or light fill.
- Policy distribution: policy outline or limited transparent fill.
- Poverty line: vertical reference when relevant.
- Add direct annotations for the change in poverty rate or lower-tail mass.

Do not use a mirrored tornado histogram unless audiences understand the format and both sides share a clearly labeled scale. A difference-in-density curve may be offered as an advanced diagnostic, but it is less intuitive than aligned baseline-policy distributions.

Heading: **Household welfare distribution before and after policy**

Required note:

> The chart uses the same fixed baseline population. It does not represent demographic or economic change over time.

## Section heading: Detailed results

### Table S3-1. Policy effects at return-period thresholds

The default table should foreground paired differences:

| Scenario and period | Expected baseline | Expected policy | Policy effect | Effect at adverse 1-in-10 | Effect at adverse 1-in-20 |
|---|---:|---:|---:|---:|---:|

Use signed effects in the selected metric’s unit and optionally add an **Improvement** column if the metric direction is configured. Freeze or visually distinguish the scenario-period columns rather than relying on color.

The expandable technical table may include:

- Baseline and policy values at both tails.
- Paired differences at every threshold.
- Coefficient uncertainty for the paired effect.
- Inter-model quantiles and extrema.
- Pooled uncertainty only when its assumptions are clearly stated.
- Number of climate models and weather-year draws.

Replace probability ratios with labels such as **Adverse 1-in-10 year**. Do not repeat historical baseline rows for every policy scenario. Provide CSV download with baseline, policy, and paired effect in tidy columns.

## Step 3 Results tooltips and notes

Every main tooltip should include:

- Scenario and projection window.
- Metric and unit.
- Baseline value.
- Policy value.
- Signed paired effect.
- Favorable/adverse interpretation when configured.
- Relative or percentage-point effect where valid.
- Climate-model and weather-year counts.
- Interval type and coverage.

Place this note near the first results figure:

> Step 3 applies policy deltas to the Step 2 simulation for the same households and climate-weather realizations. Baseline-policy comparisons are therefore paired. Policy results are scenario-based model estimates, not causal evaluations or operational cost-benefit estimates.

If the current approximation for policy coefficient bands remains in use, show:

> Policy coefficient-uncertainty bands reuse baseline factor loadings. Central policy effects are calculated from the policy-adjusted model, but these bands are approximate for large covariate changes.

## Section heading: Is the policy robust across climate futures?

### Figure S3-8. Policy-effect robustness

This may reuse Figure S3-2A with an alternate aggregation or appear as a dedicated technical view.

- Y-axis: scenario × projection window.
- X-axis: paired policy effect.
- Dot: mean paired effect.
- Interval: inter-model distribution of model-level paired effects.
- Optional background distribution: weather-year variation in paired effects.
- Zero line: no policy effect.

Heading: **Robustness of the policy effect across climate futures**

Required note:

> Variation across climate futures does not capture implementation uncertainty, behavioral responses, prices, labor demand, or other general-equilibrium effects.

## Section heading: How does the policy work?

### Figure S3-9. Level and resilience decomposition

#### Default construction

Use paired or stacked bars for two top-level channels:

- **Level effect** = cash-transfer effect + covariate-shift effect.
- **Resilience effect** = repositioning effect + interaction effect.
- **Total effect** = level effect + resilience effect.

Show a total marker or adjacent total bar. Allow users to expand the two main channels into the four technical components. Ensure the total reconciles numerically with the paired effect shown in the Results section for the same metric, scenario, period, and aggregation convention.

Use a consistent channel palette across all decomposition charts. Do not use colors that conflict with SSP colors; scenario colors and mechanism colors should serve different roles.

#### Labels and notes

Heading: **Why the policy changes welfare**

Definitions:

- **Level effect:** direct change in welfare from transfers or changed household characteristics.
- **Resilience effect:** change in the sensitivity of welfare to weather.

For linear models, hide or mark the repositioning channel as not applicable rather than showing a misleading zero. Show a warning when the specification contains no weather × policy interactions.

### Figure S3-10. Resilience response plot — advanced

Where interpretable, show predicted welfare against a clearly defined weather hazard for baseline and policy:

- X-axis: named weather hazard in real units or a clearly defined standardized index.
- Y-axis: predicted welfare outcome.
- Baseline and policy lines.
- Vertical separation: level effect.
- Slope difference: resilience effect.

Use one weather variable per panel. Do not create a composite hazard index without documented construction. Treat this as an explanatory figure, not the primary quantitative result.

## Step 3 Results validation checklist

- Every baseline-policy comparison is paired by household, climate model, and weather-year draw.
- The default estimand is policy minus baseline, not two visually independent series.
- Policy effects in cards, plots, tables, and decomposition reconcile for matching settings.
- Difference intervals are derived from paired effects rather than independent baseline and policy variances.
- Historical results appear once and are not duplicated across future scenario groups.
- Outcome-level charts use open/filled markers or direct labels in addition to color.
- Baseline and policy ribbons are not overlaid by default.
- Return-period comparisons use a documented probability-matching rule.
- Adverse-tail direction changes correctly with the selected metric.
- Annual-effect distributions are not mislabeled as household distributions.
- The approximation used for policy coefficient bands is disclosed.
- A no-op policy produces zero effect everywhere and identical outcome-level series.

# Step 2 Diagnostics tab

## Purpose and information architecture

The Diagnostics tab should help users answer three distinct questions:

1. **Is the welfare model being applied to weather conditions similar to those used to estimate it?**
2. **Which source accounts for the variation or uncertainty in the reported welfare outcome?**
3. **Are results robust across climate models and weather-year realizations?**

The current tab contains the right underlying diagnostics but needs a clearer hierarchy. It currently presents weather input distributions, a stacked standard-deviation decomposition, and per-model trajectories. The redesign should retain all three analytical functions while correcting the interpretation risks described below.

Use this page order:

1. Diagnostics status summary.
2. Weather support and extrapolation.
3. Sources of variation and uncertainty.
4. Climate-model robustness.
5. Technical definitions and downloadable data.

Place scenario filters in one compact row directly below the tab heading. Use the same selected scenarios, periods, metric, and display state as the Results tab unless the user deliberately changes them. Filters should update charts automatically or require an explicit **Apply filters** action; the interface must never leave charts visibly out of sync with selected controls.

## Section heading: Diagnostic summary

### Component D-0. Status cards and warnings

Show three compact status cards:

1. **Weather support:** percentage of future simulated weather observations outside or near the edge of the Step 1 regression support.
2. **Largest uncertainty source:** the source with the greatest variance contribution for the selected scenario-period.
3. **Climate-model agreement:** a concise measure of dispersion in model-level expected outcomes.

Use neutral labels such as **Within observed support**, **Some extrapolation**, and **Substantial extrapolation**. Thresholds must be configurable and documented rather than hard-coded without justification.

Do not label disagreement or extrapolation as model failure. Use warnings to guide interpretation:

> Some simulated weather conditions extend beyond those represented in the Step 1 estimation sample. Welfare responses in this range rely on model extrapolation.

## Section heading: Are simulated weather conditions within model support?

### Figure D-1. Weather support and scenario alignment

#### Purpose

Compare the weather used to estimate the Step 1 welfare relationship with the historical and future weather inputs used in Step 2. This is primarily an extrapolation diagnostic, not a general climate-description chart.

#### Current-interface issues to address

The present display uses relative-frequency bars for samples with very different numbers of observations. Side-by-side bars make overlap difficult to assess, and a final open-ended bin can conceal the shape of the extreme-weather tail. Future scenario lines may also be difficult to see or interpret when several scenarios, periods, and line types are combined.

#### Construction

Use one panel per selected weather variable. Provide two supported display modes:

**Default: normalized density or step histogram**

- Step 1 regression input: dark grey outline with light grey fill. This is the primary model-support reference.
- Full historical weather archive: thin black or medium-grey outline, hidden by default if it distracts from the support comparison.
- Future scenarios: colored outlines using the shared SSP palette.
- Projection windows: facet into columns or use clearly distinguishable line types when only two windows are selected.
- Normalize every distribution independently so its area sums to one. This permits shape comparisons despite unequal sample sizes.
- Use common bins or a common density bandwidth within each weather-variable panel.
- Avoid open-ended catch-all bins. If clipping is necessary, show an overflow count and allow users to inspect the tail.

**Optional: support-overlap view**

Show the regression-input range or central support interval as a shaded vertical region, with scenario distributions or quantile markers overlaid. This view may be preferable when many scenarios are selected.

The future distribution must be based on the actual weather inputs entering the welfare simulation after temporal aggregation. If the diagnostic instead uses monthly precursor values, state that explicitly and provide the selected aggregation window.

#### Summary statistics

Above or below each panel, show:

- Regression-input sample size.
- Historical-weather sample size.
- Future scenario sample size.
- Share of future values outside the observed regression minimum and maximum.
- Share outside a robust support interval, such as the 1st–99th regression percentiles.
- Optional distribution-overlap statistic, if methodologically agreed.

Raw minimum–maximum support is sensitive to outliers, so the robust support measure should be the main warning basis. The exact warning threshold should be configurable. A possible starting rule is to flag a scenario when more than 10–15% of simulated values fall outside the regression sample’s 1st–99th percentile interval, but this must be validated by the methodological team before release.

#### Heading and subtitle

Heading: **Weather inputs and Step 1 model support**

Subtitle:

> Compare the weather used to estimate the welfare relationship with the weather applied in each climate scenario.

#### Controls

- Weather variable selector.
- Scenario and projection-window filter.
- **Show full historical archive** toggle.
- **Show Step 1 regression input** toggle, on by default.
- **Density / histogram / support range** display selector.
- Optional weighting selector only if both weighted and unweighted views have a defensible interpretation.

#### Tooltips

Tooltips should report the variable name and unit, interval or bin, normalized density or share, source dataset, scenario, projection window, climate model or aggregation status, and observation count.

#### Required notes

> Distributions are normalized separately so samples of different sizes can be compared. Bar or density height represents relative frequency, not the number of observations.

> Conditions outside the Step 1 regression support require extrapolation of the estimated weather–welfare relationship. Overlap does not by itself establish model validity.

If monthly weather is shown while the model uses a transformed or multi-month measure, add:

> This panel shows monthly precursor weather. The welfare model uses [exact transformation and temporal window].

## Section heading: What drives variation and uncertainty?

### Figure D-2A. Magnitude by source

#### Purpose

Show the absolute magnitude of each uncertainty or variability component without implying that standard deviations add linearly.

#### Construction

Use grouped or aligned horizontal bars rather than stacked standard deviations.

- Rows: historical and each scenario × projection window.
- Within each row, one separate bar or point-range for:
  - coefficient uncertainty;
  - inter-annual weather variability;
  - inter-model climate spread.
- X-axis: standard deviation in the selected outcome’s unit.
- Historical inter-model spread: display as **Not applicable**, not as an unexplained zero.
- Sort scenario rows chronologically within SSP or use the same ordering as the Results tab.

Heading: **Magnitude of variation and uncertainty by source**

Subtitle:

> Separate standard deviations are shown on a common scale; they should not be added as bar lengths.

This should be the default decomposition because it preserves absolute magnitude. For example, variance shares can change even when total uncertainty changes substantially, whereas absolute SD bars make that visible.

### Figure D-2B. Variance shares — optional companion

#### Purpose

Show the relative importance of the sources for a selected scenario-period.

#### Construction

Square each valid standard-deviation component to obtain its variance component, then normalize the components to 100% if the independence/decomposition assumptions are appropriate:

$$
\text{Share}_k = \frac{\sigma_k^2}{\sum_j \sigma_j^2} \times 100.
$$

Use a 100% stacked bar or three labeled proportions. Do not call these shares of total uncertainty unless the components and assumptions support that interpretation. If covariance terms exist or the decomposition is approximate, show an **Unallocated/covariance** component or label the chart **Approximate variance shares**.

Heading: **Approximate share of variance by source**

Required note:

> Variance shares are based on squared standard-deviation components and the stated decomposition assumptions. Standard deviations themselves are not additive.

#### Definitions shown in an expandable note

- **Inter-annual weather variability:** variation in the aggregate across weather-year draws within a climate model.
- **Inter-model climate spread:** disagreement across climate models in their model-level expected aggregate.
- **Coefficient uncertainty:** uncertainty propagated from the estimated Step 1 regression coefficients.

#### Tooltips

Show the source, SD in outcome units, variance component, variance share where applicable, selected interval or estimation convention, scenario, period, and sample counts.

## Section heading: Are results consistent across climate models?

### Figure D-3A. Model-level expected outcomes

#### Purpose

Reveal climate-model disagreement without suggesting that WISE-APP produces a continuous year-by-year socioeconomic forecast.

#### Default construction

Use a model-level dot plot, boxplot, or beeswarm grouped by scenario and projection window.

- Each point: one climate model’s mean aggregate across the weather-year ensemble for that scenario-period.
- Group center: across-model median or mean, matching the Results-tab convention.
- Interval: selected across-model quantiles.
- Historical: show once as a neutral reference; do not manufacture multiple historical climate models.
- Facet by projection window or SSP when many combinations are selected.
- Allow points to be labeled with model names on hover and through a selection table.

Heading: **Expected outcome across climate models**

Subtitle:

> Each point is one climate model’s average across simulated weather years within a projection window.

This should replace the spaghetti chart as the default model-robustness diagnostic.

### Figure D-3B. Weather-year detail by climate model — advanced

Retain a detailed view for technical users, but do not connect separate projection windows into one continuous line.

Preferred options, in order:

1. **Small-multiple trajectories:** one facet per projection window and SSP, with simulation weather years on the X-axis. Individual model lines are thin and muted; the across-model median is emphasized.
2. **Model-by-year heatmap:** rows are climate models, columns are weather-year draws, and fill is the aggregate outcome or deviation from the model-period mean.
3. **Boxplots by climate model:** useful when chronological ordering of weather-year draws has no substantive interpretation.

If lines are retained:

- Label the X-axis **Historical weather-year draw**, if future scenarios perturb historical-year weather realizations rather than producing literal future annual forecasts.
- If displayed years are actual climate-model projection years, label them precisely and explain their role.
- Separate 2025–2035 and 2040–2060 with facets or visible panel breaks.
- Never draw a line across the gap between projection windows.
- Do not connect the historical baseline to future windows as one trajectory.
- Use SSP color consistently; identify individual climate models through muted lines, hover labels, or optional highlighting rather than dozens of saturated colors.

Heading: **Weather-year variation within each climate model**

Required note:

> Lines or columns represent simulation draws within a climate projection window. They are not a forecast of annual welfare or of future socioeconomic development.

#### Controls

- View: **Model averages / Weather-year detail**.
- Display: **Outcome level / Change from historical / Within-model deviation**.
- SSP and projection-window filter.
- Climate-model selector or highlight control.
- Inter-model band toggle.
- Optional **Order weather draws chronologically** control only if the year labels correspond to meaningful historical chronology.

#### Tooltips

Show climate model, SSP, projection window, weather-year draw, aggregate outcome, difference from historical, within-model difference, and number of households represented.

## Section heading: Technical definitions and downloads

Provide a collapsed definitions panel explaining the unit of observation in each diagnostic:

- Weather distribution observation.
- Annual welfare aggregate.
- Climate-model mean.
- Inter-annual SD.
- Inter-model SD.
- Coefficient SD.

Provide downloadable tidy data for every diagnostic. Filenames should include economy, survey year, metric, scenario selection, projection windows, and run date. Include a metadata sheet or companion file defining units, weights, sample counts, aggregation rules, and uncertainty conventions.

## Diagnostics layout and responsive behavior

Use a single-column reading order for primary diagnostics. Weather-variable facets may form a two-column grid on wide screens, but each chart must remain readable at 200% browser zoom. Avoid placing the uncertainty chart and model-robustness chart side by side if that forces small labels.

Within each section, place the title and interpretive subtitle first, controls second, chart third, and methodological note last. Warnings should appear immediately above the affected chart and should identify the specific variable, scenario, and period.

## Diagnostics validation checklist

- All compared weather distributions use common bins or bandwidths and are normalized consistently.
- Units and temporal transformations match the actual Step 1 regressors.
- Open-ended bins do not hide extreme-tail behavior.
- Sample sizes are visible and survey weighting is documented.
- Historical results show no inter-model component.
- Standard deviations are never stacked as though additive.
- Variance shares use squared components and disclose assumptions or covariance omissions.
- Model-level points reproduce the inter-model summaries used in Results.
- Weather-year detail reproduces the inter-annual component used in the decomposition.
- Projection windows are visually separated.
- Lines do not imply a continuous forecast between windows.
- Scenario filters and displayed data remain synchronized.
- Warnings identify extrapolation without claiming that overlap proves validity.

# Step 3 Diagnostics tab

## Purpose and relationship to Results

The Step 3 Diagnostics tab should validate that the requested policy was translated into the intended counterfactual population. It should answer **who was treated, what changed, how much the intervention costs, and whether the policy pushes covariates beyond the Step 1 estimation support**. It should not repeat climate-result figures or present policy effects as causal estimates.

Use this order:

1. Policy construction status.
2. Program scale and targeting.
3. Variables changed by the policy.
4. Before/after distributions and model-support checks.
5. Assignment reproducibility and technical downloads.

The current diagnostics already contain useful fiscal totals, a manipulated-variable summary, and before/after charts. The redesign should connect these outputs more clearly to the policy controls and expose internal inconsistencies before users interpret the Results or Decomposition tabs.

## Section heading: Was the policy constructed as intended?

### Component S3D-1. Policy construction summary

Show a compact summary banner containing:

- Active policy categories and levers.
- Transfer type, budget mode, entered transfer amount, payment frequency, targeting method, targeting cutoff, inclusion error, and exclusion error when applicable.
- Baseline survey population and analysis unit.
- Number and weighted share of units whose values changed.
- Random-assignment seed or run identifier.
- Run status and timestamp.

Clearly distinguish **user input**, **derived quantity**, and **realized simulation value**. For example:

- Entered transfer: `$20 per household per payment`.
- Frequency: `6 payments per year`.
- Derived annual transfer: `$120 per eligible household per year`.
- Daily per-capita welfare equivalent: `[derived amount]`.

This resolves the apparent mismatch between per-payment values in the sidebar and annual amounts in the current diagnostic.

Add a reconciliation status:

- **Passed:** all active levers changed the intended modeled variables.
- **Warning:** a lever produced no realized changes, a required variable was absent, or a requested universal target was already universal.
- **Error:** policy outputs do not reconcile with configured inputs.

## Section heading: What is the scale and targeting of the intervention?

### Component S3D-2. Fiscal and coverage cards

Show cards only when relevant to the active policy:

1. **Annual program budget:** weighted population-level annual amount in the configured currency basis.
2. **Eligible units:** weighted count and share before targeting errors.
3. **Actual recipients:** weighted count and share after inclusion and exclusion errors.
4. **Annual transfer per recipient:** distinguish household amount from per-capita equivalent.
5. **Administrative targeting results:** realized inclusion and exclusion rates.
6. **Coverage change:** for non-transfer access policies, baseline and policy coverage with percentage-point change.

Do not show excessive decimal precision. Use compact currency notation on cards and exact values in tooltips and downloads.

Required note:

> Program costs are simulated transfer amounts or coverage changes. They exclude administrative costs, financing effects, behavioral responses, and general-equilibrium effects.

### Figure S3D-3. Targeting and treatment assignment

For targeted transfers or randomly assigned binary levers, add a validation chart rather than a new policy-setting control.

Preferred construction for transfers:

- Rows: eligible poor, eligible non-poor where relevant, and non-eligible population.
- Segments: treated and untreated.
- Display weighted population shares or counts.
- Show intended and realized inclusion/exclusion rates.

Alternative construction: a 2×2 weighted matrix of **Eligible / Not eligible** by **Treated / Not treated**.

For binary access levers, show:

- Baseline covered.
- Newly covered.
- Remained uncovered.
- Lost coverage, if a negative lever was applied.

Heading: **Who was selected by the policy?**

Subtitle:

> Assignment reflects the selected eligibility rule and simulated inclusion or exclusion errors.

Do not add a Diagnostics-tab slider that changes targeting assumptions. Policy assumptions belong in the Step 3 sidebar; Diagnostics should report the realized assignment.

## Section heading: Which variables changed?

### Table S3D-1. Summary of policy adjustments

Use one row per manipulated variable and include:

| Variable | Lever | Baseline mean/share | Policy mean/share | Change | Baseline SD | Policy SD | Units changed | Weighted share changed |
|---|---|---:|---:|---:|---:|---:|---:|

Adapt columns by variable type. For binary variables, prioritize coverage shares and percentage-point changes; SD is secondary and may be omitted from the default view. For categorical variables, show category shares in an expandable table. For numeric variables, retain means, SDs, selected quantiles, and the share capped or rescaled.

Separate the modeled welfare outcome from covariates. A cash transfer added after prediction may not alter the baseline covariate called `welfare`; label the relevant quantity as **Policy-adjusted simulated welfare** rather than implying the raw survey variable was mutated. Add an automated check that the welfare change shown here reconciles with the transfer and Results calculations.

Use readable labels by default, with raw variable names available in tooltips or a technical-name column.

## Section heading: How did the policy change the baseline population?

### Figure S3D-4. Before/after distributions

Use a consistent small-multiple grid, one panel per manipulated variable. Select the chart by variable type.

#### Continuous variables

Use aligned density outlines, histograms with common bins, or empirical cumulative distribution functions:

- Baseline: neutral grey.
- Policy-adjusted: filled or outlined using the policy color.
- Same weights, bin edges, bandwidth, and axis limits for both series.
- Add markers for means and selected quantiles when useful.
- For welfare, show the poverty line when relevant and state whether the scale is level or logarithmic.

If the policy caps a variable such as travel time, an ECDF or histogram is usually preferable to a kernel density because it preserves the mass at the cap.

#### Binary variables

Use a 100% grouped or stacked bar with explicit percentages for 0 and 1, preferably labeled with meaningful states such as **No electricity / Electricity**. Show baseline and policy side by side, plus the percentage-point change.

#### Categorical variables

Use a grouped horizontal bar chart of category shares. Preserve a stable category order and display net percentage-point changes. For labor-sector reallocations, add a check that shares sum to 100% among the intended working population.

#### Required subtitle

> Charts compare the same baseline survey units before and after applying the policy levers.

#### Required notes

> Differences show constructed counterfactual inputs, not observed program impacts.

> Binary and selected numeric levers use random assignment within affected groups. Re-running with a different random seed may change which individual units are selected while leaving aggregate targets similar.

## Section heading: Does the policy remain within Step 1 model support?

### Figure S3D-5. Covariate-support diagnostic

For each manipulated model covariate, compare policy-adjusted values with the Step 1 estimation distribution.

- Continuous variables: training-support band plus baseline and policy distributions.
- Binary or categorical variables: baseline, policy, and Step 1 training shares.
- Show the share of policy-adjusted observations outside a robust training-support interval for numeric variables.
- Flag categories absent or extremely rare in the estimation sample.
- For universal access scenarios, explicitly show the distance from observed training prevalence.

Heading: **Policy-adjusted covariates and Step 1 model support**

Required note:

> Moving a covariate beyond the range or prevalence observed in the estimation sample increases reliance on model extrapolation. This diagnostic does not validate the realism or feasibility of the policy.

## Section heading: Reproducibility and downloads

Record and make downloadable:

- Random seed and assignment method.
- Baseline and policy values for manipulated variables.
- Eligibility and treatment flags.
- Survey weights and analysis unit.
- Entered, derived, and realized transfer values.
- Aggregate budget reconciliation.

For privacy and file-size reasons, household-level exports should follow existing access controls. Provide aggregate diagnostic data even when microdata export is unavailable.

## Step 3 Diagnostics validation checklist

- Entered per-payment, annual household, and daily per-capita transfer values reconcile.
- Weighted recipient count multiplied by the realized transfer reconciles with the reported budget, subject to documented rounding.
- Realized inclusion and exclusion errors match configured rates within expected random variation.
- Only variables active in the Step 1 model are mutated, except the direct welfare transfer.
- No-op levers produce no changes.
- Universal levers achieve the intended final coverage.
- Binary and categorical shares remain valid and sum correctly.
- Labor-market reallocations preserve the intended working population and sector-share constraints.
- Baseline values are not redrawn between runs.
- Before/after charts use identical scales, bins, bandwidths, and weights.
- Policy-adjusted welfare is labeled separately from raw baseline welfare where transfers are added after prediction.
- Support warnings use documented thresholds.

# Step 3 Decomposition tab

## Purpose and information architecture

The Decomposition tab should explain **why** the paired policy effect appears in Results. It should move from a simple two-part story to the technical channels:

1. Total policy effect.
2. Level effect versus resilience effect.
3. Detailed channels by welfare group.
4. Weather-sensitivity evidence for RIF models.
5. Variation of channels across climate scenarios and weather years.
6. Numerical reconciliation and technical assumptions.

The current tab contains these ingredients, but the relationship among main effect, repositioning, interaction, resilience, and total effect is difficult to infer. The revised tab should establish the hierarchy before showing all components.

## Section heading: What drives the total policy effect?

### Figure S3C-1. Headline decomposition

#### Purpose

Give users a simple, reconciled explanation of the total effect before exposing technical channels.

#### Construction

Use a waterfall chart or two-part stacked bar:

- Level effect.
- Resilience effect.
- Total effect.

If using a waterfall, begin at zero, add the level effect, add the resilience effect, and end at the total. If positive and negative channels offset, the waterfall is preferable to a standard stack.

Show both the selected outcome unit and, where meaningful, percent change. Do not mix log points and percentages on the same axis. Provide a unit toggle or separate table columns.

Heading: **How the policy changes welfare**

Subtitle:

> The total paired policy effect is the sum of a direct level effect and a change in weather sensitivity.

Definitions shown directly below:

- **Level effect:** direct change from transfers or policy-adjusted characteristics.
- **Resilience effect:** change in how welfare responds to weather.

For OLS, explain that resilience is available only through modeled weather × policy interactions. For RIF, resilience may include repositioning and interaction channels.

### Table S3C-1. Decomposition summary

Use a hierarchical table:

| Channel | Mean effect | Standard error | Median effect | Share of total |
|---|---:|---:|---:|---:|
| **Total effect** | | | | 100% |
| **Level effect** | | | | |
| ↳ Cash-transfer effect | | | | |
| ↳ Covariate-shift effect | | | | |
| **Resilience effect** | | | | |
| ↳ Repositioning — RIF only | | | | |
| ↳ Interaction | | | | |

Do not show a share of total when the total is near zero or when offsetting positive and negative channels make the ratio unstable. Use `Not meaningful` with an explanation.

Show uncertainty as estimate ± SE or a confidence interval, not both unless the user expands the technical view. The total uncertainty must preserve cross-channel covariance and must not be calculated as the sum of channel SEs.

Add an automated reconciliation line:

> Level effect + resilience effect = total effect: [Passed / Difference due to rounding / Failed].

Also reconcile the total with the paired baseline-policy result for the same scenario and aggregation convention. If the Results series uses period-mean hazards while a decomposition panel uses year-specific hazards, label the difference in estimand rather than forcing an invalid equality.

## Section heading: Who gains, and through which channel?

### Figure S3C-2. Decomposition by baseline welfare decile

#### Purpose

Show how policy benefits and resilience channels differ across the baseline welfare distribution.

#### Default construction

Use a two-layer display rather than relying only on a multicolor stacked bar:

- Bars: level and resilience effects by baseline welfare decile.
- Total marker: black or dark marker showing their sum.
- Zero line.
- Deciles 1–10, with decile 1 labeled poorest and decile 10 richest.

Allow an **Expand technical channels** control that replaces the two bars with:

- Cash-transfer effect.
- Covariate-shift effect.
- Repositioning effect for RIF.
- Interaction effect.

When channels have opposing signs, use a diverging stack around zero or grouped bars; do not stack negative values on top of positive values in a way that obscures cancellation.

The current chart appears to stop before decile 10 in the visible area; ensure all ten deciles are present or explain empty groups. Show weighted sample size per decile in tooltips.

#### Heading and subtitle

Heading: **Policy effect and resilience by baseline welfare decile**

Subtitle:

> Decile 1 is the poorest. Bars show channel contributions evaluated at the stated weather hazard; the marker shows the total effect.

#### Controls

- Effect unit: original unit, log points, or percent where mathematically valid.
- Weather reference: historical-mean hazard or selected scenario-period.
- Channels: level/resilience or detailed.
- Coefficient uncertainty toggle.
- Optional outcome subgroup filter.

#### Tooltips

Show decile, weighted population share, total effect, each channel, SE or interval, weather reference, and model engine.

#### Required note

> Deciles are defined using observed baseline welfare and remain fixed after the policy. Percent transformations may not add exactly after rounding; model-scale channels should reconcile exactly.

## Section heading: How does weather sensitivity vary across the welfare distribution?

### Figure S3C-3. RIF weather-sensitivity curves

#### Applicability

Show only for RIF models. For OLS, replace the panel with a concise explanation that weather coefficients are constant across the modeled welfare distribution, apart from specified interactions.

#### Construction

Use one facet per weather variable or weather term. Avoid cryptic formula labels and open-ended bin notation where plain-language labels are available.

- X-axis: baseline welfare percentile or estimated RIF quantile.
- Y-axis: weather coefficient in a fully specified unit, such as change in log welfare per 1°C increase.
- Main-effect curve: estimated weather sensitivity.
- Moderator comparison: separate curves for meaningful baseline and policy states only when an interaction is part of the model—for example, no electricity versus electricity.
- Zero reference line.
- Confidence ribbon: selected coefficient interval, with restrained opacity.
- Mark the estimated quantile grid points so users can distinguish estimates from interpolation.

If several weather bins or transformations are present, use descriptive facet titles such as **Monthly temperature: 26.6–28.4°C** and **Monthly temperature: above 31.9°C**. State the omitted/reference category.

Heading: **Weather sensitivity across the welfare distribution**

Subtitle:

> The curves show how the estimated weather coefficient varies by baseline welfare rank. Movement along the curve contributes to the RIF repositioning channel.

#### Tooltips

Show quantile, coefficient, unit, confidence interval, weather term, moderator state, estimation sample, and whether the displayed value is directly estimated or interpolated.

Do not default to p-values in tooltips; emphasize effect estimates and intervals. P-values may appear in a technical coefficient table.

#### Required notes

> These curves are estimated statistical associations, not causal weather-response functions.

> Repositioning relies on the assumption that baseline welfare ranks remain locally informative after the simulated policy change.

## Section heading: Does the decomposition change across climate scenarios?

### Figure S3C-4. Channel effects across climate scenarios

#### Purpose

Show whether the level and resilience contributions are stable across SSPs, projection windows, climate models, and weather-year realizations.

#### Construction

Use small multiples, one panel per top-level channel and total:

- Level effect.
- Resilience effect.
- Total effect.

Provide an advanced mode that splits level into cash and covariate effects and resilience into repositioning and interaction.

Within each panel:

- X-axis: scenario × projection window, grouped or faceted by period.
- Point: mean channel effect.
- Box or interval: within-period variation across weather-year effects.
- Optional outer interval: inter-model spread of model-level mean channel effects, using a distinct thin whisker rather than another filled box.
- Zero line.
- SSP color consistent with Results.

Because the level effect is constant across weather years under the documented formulation, show it as a point rather than a box. Label it **Constant across weather-year draws**. Weather-sensitive channels may use boxplots or quantile intervals.

Do not connect projection periods with lines. Each period is a separate climate regime, not a continuous welfare forecast.

Heading: **Policy channels across climate scenarios**

Subtitle:

> Points show average channel effects. Boxes show variation across weather-year realizations for weather-sensitive channels.

#### Required note

> Variation across scenarios reflects modeled climate conditions. It does not include future socioeconomic change, implementation uncertainty, prices, wages, labor-demand responses, or other general-equilibrium effects.

## Section heading: Reconciliation and technical details

### Component S3C-5. Reconciliation panel

Show automated checks for the current filters:

1. Detailed main channels sum to level effect.
2. Detailed resilience channels sum to resilience effect.
3. Level plus resilience equals total on the model scale.
4. Total reconciles with the Step 3 paired baseline-policy result under the same hazard and aggregation definition.
5. All channel SEs are zero when coefficient uncertainty is disabled.
6. Repositioning is absent for OLS.
7. Interaction is zero when no relevant weather × policy terms exist.

If a check fails beyond numerical tolerance, show the magnitude and likely source rather than a generic warning.

### Component S3C-6. Method and interpretation note

Provide a collapsed explanation of:

- The weather hazard used in each panel.
- Why historical-mean, period-mean, and year-specific decompositions may differ.
- How percent effects are transformed from model-scale effects.
- How coefficient uncertainty and cross-channel covariance are propagated.
- Why residual and survey-sampling uncertainty are not represented in the paired decomposition.
- Which channels apply to OLS and RIF.

## Step 3 Decomposition visual system

Use mechanism colors consistently:

- Level effect: one blue family.
- Cash and covariate subchannels: distinguishable shades or patterns within the level family.
- Resilience effect: one orange or purple family.
- Repositioning and interaction: distinguishable shades or patterns within the resilience family.
- Total effect: dark neutral marker.

Do not reuse SSP colors for mechanism channels. In the across-scenario figure, use SSP color for scenario identity and separate panels or shape/pattern for channels.

Keep legends close to the first relevant figure and use plain-language labels before technical names. All charts must provide downloadable underlying data and a textual table.

## Step 3 Decomposition validation checklist

- All channels use the same baseline households and policy assignment as Results.
- Deciles are based on observed baseline welfare and include all valid groups.
- Channel sums reconcile on the model scale before percentage transformation and rounding.
- Total-effect uncertainty retains cross-channel covariance.
- RIF interpolation is limited to the supported quantile grid and identified in tooltips.
- OLS views do not imply a repositioning channel.
- Interaction is clearly marked zero or unavailable when relevant terms are absent.
- Weather-beta units and reference categories are explicit.
- Scenario panels distinguish weather-year variation from inter-model spread.
- The constant main effect is not displayed as though it varied across weather years.
- No lines imply continuous forecasts between projection windows.
- Results-tab and Decomposition-tab differences in hazard conventions are disclosed.
- Cash-transfer amounts and covariate changes reconcile with Diagnostics.

# Visual system

## Color

- Historical: dark neutral grey.
- SSPs: use a colorblind-safe qualitative palette and preserve the same SSP color everywhere.
- Baseline versus policy: distinguish primarily through open/filled markers, shape, or line weight.
- Decomposition channels: use a separate, stable mechanism palette.
- Avoid red-green contrasts as the sole indicator of favorable versus adverse results.

## Typography and labels

- Use sentence-case chart titles.
- Include the selected metric and units in every axis title.
- Use “expected” rather than “forecast” or “predicted future level” for scenario summaries.
- Spell out uncommon abbreviations in visible labels.
- Use dynamic subtitles to identify the unit of observation and interval definition.

## Legends

Prefer direct labels when they remain readable. Otherwise, use separate legend groups for scenario, baseline-policy status, and interval type. Do not combine unrelated aesthetics into one dense legend.

## Tooltips

Each tooltip should include, where relevant:

- Scenario and projection window.
- Outcome and unit.
- Central estimate.
- Difference from historical or baseline.
- Interval type and coverage.
- Number of climate models.
- Number of weather-year draws.
- Whether the value is an annual aggregate, household statistic, or model-level summary.

## Accessibility

- Ensure sufficient contrast in light and dark display conditions used by the app.
- Do not rely on color alone.
- Provide keyboard-accessible controls and tooltips where the framework permits.
- Provide a downloadable or expandable data table for every figure.
- Preserve meaningful reading order for screen readers.
- Test narrow screens and browser zoom at 200%.

# Figures to avoid or constrain

Do not use continuous temporal trajectories from the historical period to 2100 unless the underlying simulation genuinely evaluates each displayed period and the chart clearly identifies discrete climate windows. Such paths can imply unsupported annual forecasting.

Do not show an evolving population-density surface unless population and welfare dynamics are actually simulated. The baseline survey population is fixed.

Do not use nested fan bands as the default expression of all uncertainty sources. They invite users to treat distinct concepts as one confidence envelope.

Do not combine the distribution of household welfare with the distribution of annual population aggregates. They require separate figures and explicit titles.

Avoid poverty–inequality “paths” through time. If a joint poverty–Gini comparison is desired, use scenario points or arrows from historical to scenario outcomes, with no interpolation between projection windows.

# Implementation roadmap

## Phase 1: Clarity and hierarchy

- Add the run context banner and stress-test label.
- Reorganize controls into primary and advanced groups.
- Add Step 2 and Step 3 headline cards.
- Replace generic labels with dynamic metric names and units.
- Simplify the default return-period table.
- Add chart subtitles that define the unit of observation.

This phase can reuse existing aggregates and should not require major simulation changes.

## Phase 2: Core chart redesign

- Implement S2-2 expected outcome by scenario.
- Implement S2-3 annual aggregate distribution.
- Implement S2-4 return-period dot plot.
- Retain the full exceedance curve as an advanced view.
- Implement S3-2 paired baseline-policy chart.
- Implement S3-3 policy robustness chart.

Validate all values against current charts and exported tables before replacing the existing defaults.

## Phase 3: Distributional and decomposition views

- Implement S2-5 and S3-4 decile incidence charts.
- Implement the top-level level/resilience decomposition.
- Add expandable technical channels.
- Add the optional household distribution figure with an explicit scenario-summary rule.
- Add engine-specific notes and conditional visibility for OLS versus RIF.

## Phase 4: Diagnostics and accessibility

- Replace stacked SDs with variance shares or aligned SD bars.
- Refine weather-support and model-trajectory diagnostics.
- Add accessible tables and full keyboard/contrast testing.
- Add image and data exports with informative filenames and embedded run metadata.

# Validation checklist

Before release, verify the following for every supported outcome and model engine:

- Historical values agree with existing validated outputs.
- Scenario means and return-period thresholds agree with the technical table.
- Adverse-tail direction changes correctly by metric.
- Percentage versus percentage-point changes are correct.
- Historical scenarios never display inter-model spread.
- No-op Step 3 policies produce identical baseline and policy results.
- Step 3 total effects reconcile with level plus resilience effects.
- Decomposition channels reconcile with the paired Results-tab difference.
- OLS and RIF notes, controls, and channels appear only when applicable.
- Charts clearly distinguish household distributions from annual aggregate distributions.
- Projection windows are not presented as continuous annual forecasts.
- All chart data can be downloaded with definitions and units.

# Coding handoff guidance

The design specification above describes the intended analytical behavior. Before coding individual charts, the implementation agent should establish the following shared contracts. This will reduce duplicated logic and prevent superficially consistent figures from calculating different quantities.

## 1. Create a metric metadata registry

Define one authoritative registry for every supported outcome and aggregation method. At minimum, each metric should provide:

- Stable metric ID and display name.
- Numerator, denominator, and population basis.
- Unit and preferred number format.
- Whether higher values are favorable or adverse.
- Whether zero is meaningful.
- Whether percent change, percentage-point change, and totals are valid.
- Which poverty line or threshold control applies.
- Supported model engines and uncertainty methods.
- Adverse-tail direction.
- Recommended decimal precision.
- Plain-language definition and methodological caveat.

All titles, axes, cards, return-period directions, tooltips, tables, and exports should read from this registry. Do not infer direction from variable names inside individual plotting functions.

## 2. Define canonical estimands and aggregation order

Create documented helper functions for the recurring estimands rather than recomputing them in each chart. The order of aggregation matters and must be explicit. Define at least:

- Household outcome for one simulation row.
- Weighted population aggregate for one climate model and weather-year draw.
- Model-level mean across weather-year draws.
- Across-model central estimate.
- Inter-annual distribution within a model.
- Inter-model distribution of model-level means.
- Historical reference mean and median.
- Return-period threshold and tail convention.
- Paired Step 3 policy effect at household, annual-aggregate, and model-mean levels.
- Decile effect using fixed, survey-weighted baseline deciles.
- Level, resilience, and detailed decomposition channels.

For every output object, retain identifiers for economy, survey round, scenario, projection window, climate model, weather-year draw, household or survey row, policy arm, model engine, outcome scale, and survey weight where applicable.

Do not pool model-year rows before deciding the estimand. Pooling gives models with more valid draws more influence and mixes within-model variability with between-model disagreement. If equal model weighting is intended, compute model-level summaries first and then aggregate across models.

## 3. Resolve tail-risk limits before implementation

The default historical window contains approximately 30 weather-year draws. An empirical 1-in-50 threshold cannot be estimated robustly from 30 annual observations within one climate model. Before retaining 1-in-50 outputs, the methodological owner must select and document one approach:

- Hide return periods longer than the available empirical record.
- Show them as boundary/order-statistic estimates with a prominent low-support warning.
- Fit a documented tail model with diagnostics and uncertainty.
- Use a pooled construction across climate models, while clearly acknowledging that this changes the estimand and treats the ensemble structure differently.

The interface should calculate an **effective tail sample size** and disable or warn on unsupported return periods. Do not imply that a nominal 1-in-50 value has empirical precision simply because it can be interpolated from an exceedance curve.

Also state that CMIP6 ensemble members are an ensemble of opportunity rather than independent probabilistic draws. Across-model quantiles describe ensemble spread; they should not be labeled as probabilities that the future lies within the interval.

## 4. Specify uncertainty objects separately

Use separate fields and rendering functions for:

- Inter-annual weather variability.
- Inter-model ensemble spread.
- Coefficient sampling uncertainty.
- Paired policy-effect uncertainty.
- Monte Carlo fallback uncertainty.
- Any pooled or approximate uncertainty measure.

Each uncertainty object should carry its method, coverage, lower and upper values, sample count, and applicability flag. Charts should not silently substitute one uncertainty type when another is unavailable. Use **Not available** or **Not applicable** with a reason.

For Step 3, preserve covariance created by using the same baseline and policy simulation rows. Add unit tests confirming that paired uncertainty collapses appropriately for a no-op policy.

## 5. Build reusable presentation components

Implement common modules rather than separate one-off charts for each tab:

- Run-context banner.
- Metric and display controls.
- Dot-and-interval plot.
- Paired difference/dumbbell plot.
- Distribution plot with an explicit observation-unit subtitle.
- Return-period plot and table.
- Status/warning callout.
- Accessible chart-data table.
- Download control and metadata manifest.

Step 2 and Step 3 should call the same component with different estimands and display modes. Keep calculation functions separate from plotting functions so numerical outputs can be tested without rendering the UI.

The Step 3 Results decomposition item should be a concise preview or link to the Decomposition tab, not a second full implementation of the same figures. Use one decomposition calculation source for both locations.

## 6. Define reactive state behavior

Document which controls:

- Require a full simulation rerun.
- Recompute summaries from cached simulation rows.
- Only change chart presentation.
- Are shared across tabs.
- Reset when the metric or model engine changes.

Use a visible **Results based on** timestamp or run ID. If simulation inputs change after a run, mark existing outputs as stale until rerun. Preserve shared metric, scenario, period, and display selections across tabs where sensible, but do not carry controls into contexts where they are invalid.

Provide explicit loading, empty, warning, and error states. Examples include no complete climate models, too few poor households, missing covariance matrices, unavailable RIF channels, no manipulated variables, all-zero policy effects, or an unsupported metric transformation.

## 7. Add performance requirements

The coding agent should profile the largest expected combination of households, weather years, climate models, SSPs, and policy arms. Recommended practices include:

- Cache simulation-level aggregates keyed by run ID and metric settings.
- Precompute common model-year, model-mean, return-period, and decile summaries after each run.
- Avoid sending household-level simulation rows to the browser unless needed.
- Downsample only visual marks, never analytical summaries, and disclose any visual downsampling.
- Cancel or supersede stale reactive computations when controls change quickly.
- Render an initial summary before expensive advanced diagnostics where possible.

Set measurable targets appropriate to the deployment environment—for example, near-instant display-only changes and bounded wait times for cached summary recomputation.

## 8. Establish formatting and export contracts

Use centralized functions for currency, percentages, percentage points, welfare units, counts, scientific notation, and missing values. Cards, charts, tables, and downloads must not round differently in ways that appear inconsistent.

Every export should include:

- Run ID and generation timestamp.
- App and package version or commit hash.
- Economy and survey rounds.
- Model engine and specification identifier.
- Historical weather window.
- SSP and projection windows.
- Climate models included and exclusions.
- Residual and coefficient-uncertainty settings.
- Metric definition, unit, poverty line, and adverse direction.
- Weighting and aggregation convention.
- Interval method and coverage.
- Policy configuration and random seed for Step 3.

Use tidy machine-readable columns with stable names. A chart image export should have an accompanying data and metadata export.

## 9. Add automated and visual testing

Use several layers of tests:

**Numerical unit tests**

- Aggregation order and survey weighting.
- Tail direction and return-period interpolation.
- Historical-reference calculations.
- Paired baseline-policy effects.
- Variance and SD calculations.
- Percent and percentage-point transformations.
- Decomposition identities and covariance handling.

**Invariant tests**

- A no-op policy gives zero effects and identical outcome levels.
- Historical results have no inter-model spread.
- Level plus resilience equals total on the model scale.
- Binary shares and sector shares remain valid.
- Changing display coverage does not change central estimates.
- Filtering only removes observations and does not alter unaffected summaries.

**Golden-data tests**

Create a small deterministic fixture with a few households, weather years, and climate models for which outputs can be calculated manually. Store expected values for every chart and table.

**Visual regression tests**

Capture representative states for OLS and RIF, raw levels and changes, poverty and welfare metrics, one and several SSPs, small screens, 200% zoom, missing uncertainty, and empty/error conditions.

**Accessibility tests**

Check keyboard navigation, focus order, accessible names, contrast, non-color encodings, and equivalence between chart and table content.

## 10. Use feature flags and preserve validated outputs during migration

Implement redesigned figures behind feature flags or an internal preview mode. During validation, allow users to compare the new figure with the current validated chart or table using the same run. Do not remove existing technical exports until the replacement reproduces their validated values or an intentional methodological change is approved.

Record intentional changes in estimand, weighting, uncertainty, or return-period calculation as methodological changes—not merely visual changes—and update the user guide accordingly.

## 11. Track decisions requiring methodological sign-off

The implementation agent should not silently choose among these unresolved options. Maintain a short decision log and obtain sign-off for:

- Mean versus median as the default across-model center.
- Equal climate-model weighting versus pooling model-year observations.
- Exact construction of inter-annual bands averaged across models.
- Definition of Step 3 return-period effects: matched probability quantiles versus the same baseline weather event.
- Treatment of 1-in-50 thresholds with a 30-year weather record.
- Warning thresholds for weather and covariate extrapolation.
- Whether survey weights apply to every household distribution, decile, and targeting diagnostic.
- Transformation of log-model effects into percent and level effects.
- Handling of RIF interpolation and quantiles outside the estimated grid.
- Whether and how approximate policy coefficient bands remain available.
- Whether variance shares can legitimately omit covariance terms.

## 12. Define completion criteria for each figure

A figure is complete only when:

- Its estimand and aggregation order are documented.
- It uses the metric registry for direction, units, and formatting.
- Its values reconcile with a downloadable table.
- Its loading, empty, unavailable, and error states are implemented.
- Its uncertainty type and coverage are visible.
- Its subtitle identifies the unit of observation.
- It passes numerical, visual, and accessibility tests.
- It behaves correctly for OLS and RIF where applicable.
- It remains legible with the maximum supported number of scenarios and periods.
- Its wording has been added to the user guide.

# Flexibility for the implementing agent

The implementing agent may choose the specific R or JavaScript visualization library, exact responsive breakpoints, and minor stylistic details. Violin plots may be replaced by boxplots or quantile dot plots if performance or accessibility is better. Dumbbells may be replaced by zero-centered difference plots when many scenarios make pairing unreadable. Small multiples may replace overlays whenever more than three series are selected.

Any deviation should preserve the analytical question, unit of observation, uncertainty definition, methodological constraints, and explanatory notes specified above. When visual simplicity conflicts with complete technical detail, keep the simple figure as the default and place the additional detail in an advanced view or downloadable table.

---
*This document was generated by mAI.*