# docs/ revision - plan

Status: draft for approval (2026-10-23). Implementer: Sonnet 5.5, in batches with
a review round after each batch (section 8).

## 1. Goal

Replace the out-of-date `docs/` with a methods reference for WISE-APP: the
estimators, simulation design, metrics, uncertainty and policy mechanics, written
as they would appear in the methods appendix of an economics paper. The audience
is economists and policy analysts using the app and outside reviewers of its
methods. Every page must also be easy for an AI agent to read: stable ids, YAML
front matter, numbered equations, and a code map for the people and agents who
maintain the code (a future in-app AI chat could cite these pages).

The docs are plain Markdown read on GitHub or by an AI. They are not a Quarto site.

## 2. Relationship to other documentation

| Location | Role | Owner of |
|---|---|---|
| `docs/` (this plan) | Methods reference | Equations, estimands, assumptions, limitations, code map |
| `~/Github/wise-app-docs` (Quarto book, `worldbank/wise-app-docs`) | User guide | How to use each screen, how to read results, tips and caveats |
| `wise-app-data` repo | Data preparation | Input schema (`survey_list.csv`, `variable_list.csv`, `cpi_ppp.csv`, parquet files) |
| `batch/README.md`, `batch/docs/` | Batch runs | Spec, tables, runner |
| `review/` | Plans, reviews, open items | Improvement ideas, known issues |

Rules:

- **No duplicated content between docs/ and the user guide.** `docs/` owns the
  methods. The guide's "Methodology detail" sections are trimmed to a summary and
  a link to the matching `docs/` page later. That is a separate task and is not
  part of this plan.
- **Borrow from the guide.** Its method text (for example `step2.qmd`, "The Delta
  Method") is a good starting point. Check every borrowed equation against the
  code before using it.
- **Match the guide's notation** where it already defines a symbol (for example
  $\ell$ location, $m$ CMIP6 member, $\mu$ calendar month, $W$ weather vector).
  `00_notation.md` is the one authority. Report any conflict with the guide in
  the batch report; do not edit the guide.
- **Every page links to the user guide** through a `guide:` front-matter field
  and an "In the app" section. The guide will link back later.
- **Link to the data schema, do not copy it.** `10_data.md` describes the
  concepts and links to the wise-app-data repo
  (`https://github.com/worldbank/wise-app-data`), so the two never need syncing.
- **Citations use the guide's BibTeX keys** (`firpo2009`, `auffhammer2013`,
  `eyring2016`, `munozsabater2021`, `cameronmiller2015`, `abadie2023`, ...) as
  `[@key]`. Add new references to `docs/references.md` as BibTeX entries, so the
  later Quarto task can copy them into `references.bib`.

## 3. Writing rules

1. **Describe the app as it is now.** Check each equation against the code at the
   commit you record. If the code and an older document disagree, the code wins.
   Write the mismatch in the batch report; do not decide yourself which one is
   right.
2. **Use LaTeX:** `$...$` inline and `$$...$$` display. Number the key equations
   with `\tag{2.3}` (section.number) and refer to them as "Eq. (2.3) in
   [30_simulation](30_simulation.md#...)". Use only maths that GitHub MathJax
   renders: no macros, no `\begin{align}` with `&` alignment inside a list.
3. **The body has no code names.** Function, file, column and argument names
   appear only in the last section, "Implementation map", and in `index.yml`.
   UI labels (such as "Step 3 > Social protection > Trigger") are allowed in
   "In the app".
4. **Name what is not modelled** in a short list in each page. Do not add
   "suggestions for improvement" or "[IMPLEMENTED]" notes. Put improvement ideas
   in the batch report so they can go to `review/REVIEW-2026-10-06-tracking.md`.
5. **Plain English.** Define each term at first use and keep one term for one
   thing. Use the code name of a concept (for example "direct effect" for `main`)
   only in the Implementation map.
6. **Use ASCII quotes and hyphens in code spans and front matter.** Prose may use
   normal typography.
7. **Keep pages short:** one method per page, about 80 to 250 lines.

## 4. Page template

```markdown
---
id: rif-model                       # stable kebab-case id, unique
title: Unconditional quantile regression (RIF)
app_step: 1                         # 0, 1, 2, 3 or cross
depends_on: [notation, model-specification]
symbols: [y, tau, q_tau, f_Y, beta_tau, W, X]
guide: https://github.com/worldbank/wise-app-docs/blob/main/step1.qmd#unconditional-quantile-regression-rif
code: [R/fct_fit_model.R, R/fct_rif_sim.R]
verified_against: <git commit hash>
---

# Unconditional quantile regression (RIF)

> One-paragraph summary: what is estimated, when the app uses it, the key result.

## Setup
## Method            (numbered equations)
## Interpretation
## Assumptions       (numbered A1, A2, ... and referenced from 50_assumptions_limitations.md)
## Limitations and what is not modelled
## In the app        (UI path, user guide link)
## References
## Implementation map
| Concept | Equation | Code |
|---|---|---|
| RIF transform | (1.2) | `R/fct_rif_sim.R` `rif_transform()` |
```

## 5. Directory

| File | id | Contents | Main sources (read before writing) |
|---|---|---|---|
| `README.md` | `index` | Purpose, audience, reading order, map from app step to pages, how docs/ relates to the guide, data repo and batch, conventions | AGENTS.md, this plan |
| `index.yml` | - | Machine-readable list: for each page `id`, `file`, `title`, `app_step`, `methods` (list), `equations` (tag plus one-line meaning), `symbols`, `ui`, `guide`, `code` | all pages (built last) |
| `00_notation.md` | `notation` | Indices ($i$ household, $\ell$ location, $t$ survey year, $\mu$ month, $r$ simulation year, $s$ scenario, $m$ CMIP6 member, $\tau$ quantile), weights, outcome scale (log vs level), $W$, $X$, $D$ policy variables, fixed effects, units (2021 PPP, LCU) | guide `step1-3.qmd`, `fct_results.R`, `fct_aggregation_delta.R` |
| `01_framework.md` | `framework` | Research question; the estimand of each step; the counterfactual design (fixed population, weather varies); identification from local weather variation net of fixed effects; why policy coefficients are associational; pipeline diagram (Mermaid) | guide `index.qmd`, `step1.qmd` "Identification Asymmetry", `review/archive/` reviewer response content |
| `10_data.md` | `data` | Harmonised surveys, welfare in 2021 PPP, CPI/PPP deflation, geocoding to H3, population weighting, ERA5-Land, CMIP6 sources, variable list roles (outcome, weather, covariate, policy code); link to the data repo for the schema | guide `data.qmd`, `fct_load_data.R`, `fct_surveystats.R`, `fct_sample.R`, `fct_step1_data.R` |
| `11_outcomes.md` | `outcomes` | Outcome definitions; log transform; LCU back-conversion; poverty indicator; PPP vs LCU poverty line; default LCU line (20th percentile); which outcomes count as monetary | `fct_outcome.R`, `fct_results.R` (outcome prep), `fct_spec_defaults.R` |
| `12_weather_measures.md` | `weather-measures` | Monthly weather to the location; rolling window over months before the interview; temporal aggregation (mean, sum, days); transformations (level, anomaly, standardised, ...); continuous with polynomials vs bins (equal-width, quantile, custom); combining two variables; location panels from H3 overlap; weather statistics shown in Step 1 | `fct_get_weather.R`, `fct_weather_select.R`, `fct_weather_pipeline.R`, `fct_weatherstats.R`, `fct_loc_panel.R`, `mod_1_04`, `mod_1_05` |
| `20_model_specification.md` | `model-specification` | Progressive models 1-3; fixed effects choices; weather-by-covariate interactions (pairwise vs saturated); Lasso selection (penalty, what is forced in); clustering and the variance-covariance fallback order; estimation sample and weights | `fct_model_select.R`, `fct_step1_model.R`, `fct_fit_model.R`, `mod_1_06_model.R`, `fct_model_card.R` |
| `21_model_linear.md` | `linear-model` | OLS with absorbed fixed effects, logit; interpretation; back-transform of log predictions (no smearing); dropped unseen fixed-effect levels; how simulation and policy predictions use it | `docs/method_lin.md` sections 1, 3, 4; guide `step1.qmd`; `fct_fit_model.R`, `fct_predict_outcomes.R` |
| `22_model_rif.md` | `rif-model` | RIF transform and density estimation; quantile grid; interpolation across $\tau$; how the simulation assigns each household a quantile; section "Validity and interpretation of the RIF simulation" (from the reviewer response: realised consumption, repeated cross-section, reading results as a distributional gradient) | `docs/method_rif.md`, `docs/reviewer_response.md`, `fct_rif_sim.R`, `fct_fit_model.R` |
| `23_model_ml.md` | `ml-models` | Random forest and gradient boosting: target, tuning defaults, how predictions are formed, which uncertainty sources and Step 3 features are or are not available | `fct_fit_model.R` (ranger, xgboost entries), `fct_metric_registry.R` (engine support), Step 2/3 engine checks |
| `24_model_results.md` | `model-results` | Translated effects (log points to percent; per SD or per unit), headline cards and their contrasts, weather-effect curves with delta-method bands, binned effects with a reference bin, fit statistics and diagnostics | `fct_step1_headline.R`, `fct_step1_model_tables.R`, `fct_results.R`, `fct_results_table2.R`, `mod_1_07`, `mod_1_08` |
| `30_simulation.md` | `simulation` | Counterfactual: baseline survey fixed, weather from each historical year (interview-month alignment); prediction; residual rules (`original`, `normal`, `resample`, `none`) as equations; back-transform; household and annual series; weather-support diagnostics | `fct_step2_input.R`, `fct_step2_compute.R`, `fct_run_simulation.R`, `fct_simulations.R`, `fct_sim_diag.R`, guide `step2.qmd` |
| `31_climate_scenarios.md` | `climate-scenarios` | Delta method per member, location and month; additive vs multiplicative; SSPs and horizons; reference period; ensemble; not modelled (variance scaling, QDM) | `docs/method_climate.md`, guide `step2.qmd`, `fct_get_weather.R` |
| `32_metrics.md` | `metrics` | Each aggregate as a weighted equation: mean, median, total, poverty rate, gap, severity (FGT2), Gini, prosperity gap, average poverty; changes (absolute, percent); exceedance curves and return periods; threshold table; variance breakdown; incidence by fixed baseline decile | `fct_metric_registry.R`, `fct_aggregation.R`, `fct_sim_compare.R`, `fct_step2_tables.R`, `fct_incidence.R` |
| `33_uncertainty.md` | `uncertainty` | Sources (coefficients, residuals, weather years, climate models); factor loading; delta method; gradient for each metric; smoothed poverty indicator and its bandwidth; additive-decomposition scope (active coefficients); band transforms (logit, log, identity); paired contrasts; pooling across members by the law of total variance; the two band types | `docs/method_uncertainty.md`, `fct_aggregation_delta.R`, `fct_aggregation_kernel.R`, `fct_uncertainty_helpers.R` |
| `40_policy_framework.md` | `policy-framework` | Policy as a change in $X$ (and a cash transfer) on the fixed population; prediction under policy; how each engine passes on the change; levers found from the variable list; random assignment of partial coverage; policy needs its variable in the Step 1 model | `docs/method_policy.md`, `docs/policy_effects.md`, `fct_policy_sim.R`, `fct_policy_registry.R`, `fct_step3_input.R`, guide `step3.qmd` |
| `41_policy_levers.md` | `policy-levers` | Binary access (universal or a percentage of non-users), numeric percent change, health travel time, coupled labour levers, education, other groups; derived variables | `fct_policy_registry.R`, `mod_3_levers.R`, `fct_policy_sim.R`, `fct_model_select.R` (derived columns) |
| `42_social_protection.md` | `social-protection` | Regular cash transfers: targeting rules and eligibility, budget-first vs amount-first, amount from a welfare percentile, payments per year; coverage, leakage, adequacy, inclusion and exclusion errors | `fct_policy_sim.R`, `fct_step3_input.R`, `fct_sp_effectiveness.R`, `mod_3_01_sp.R` |
| `43_shock_responsive_sp.md` | `shock-sp` | Triggers (weather level, 1-in-N return period, N-year record rule; impact triggers on loss, poverty rate or number of poor; geographic level); thresholds fixed at historical values; scope and dynamic targeting; fixed amount vs loss share; annual cap; anticipatory timing (POD, FAR, multiplier, delay); activation, cost distribution, basis risk, breakeven | `fct_sp_shock.R`, `review/sp_shock_responsive_plan.md`, `review/sp_shock_responsive_tasks.md` |
| `44_decomposition.md` | `decomposition` | Total = direct effect + resilience (repositioning + interaction); RIF vs linear vs ML; decomposition for each metric and its channels; how it reconciles with the simulated total and where it does not | `docs/policy_effects.md`, `fct_policy_decompose.R`, `fct_policy_metric_decompose.R`, `fct_decomposition_summary.R`, `review/archive/step3_metric_aware_decomposition_plan.md` |
| `45_cost_effectiveness.md` | `cost-effectiveness` | Cost per person lifted out of poverty, gain per $1, average year and 1-in-20 year, regular vs shock programme costs | `fct_sp_effectiveness.R` (`sp_cost_effectiveness`), `fct_step3_tables.R`, `mod_3_10`, `review/step3_cost_effectiveness_plan.md` |
| `50_assumptions_limitations.md` | `assumptions` | Combined list of assumptions, each linked to the A-numbers on its page; grouped by identification, functional form, extrapolation, policy, uncertainty | all pages |
| `51_reproducibility.md` | `reproducibility` | Seeds and determinism, run provenance record, what an export contains (method level only; link to guide `export.qmd`) | `fct_provenance.R`, `fct_export.R` |
| `52_batch_runs.md` | `batch` | One page: batch runs give the app's numbers for the same spec and seed, publish only aggregates, and are documented in `batch/README.md` and `batch/docs/tables.md` | `batch/README.md` |
| `references.md` | `references` | References keyed to the guide's BibTeX keys; BibTeX for new entries | `wise-app-docs/references.bib` |

## 6. Files removed or moved

| Current | Action |
|---|---|
| `docs/method_lin.md` | Content moves to `21`, `20`, `30`, `33`. Delete. |
| `docs/method_rif.md` | Content moves to `22`, `44`. Delete. |
| `docs/method_climate.md` | Content moves to `31`, `12`. Delete. |
| `docs/method_uncertainty.md` | Content moves to `33`. Delete. |
| `docs/method_policy.md` | Content moves to `40`, `41`, `42`. Delete. |
| `docs/policy_effects.md` | Content moves to `40`, `44`. Delete. |
| `docs/batch_pipeline.md` | Replaced by `52`. Delete (legacy, already covered in `batch/`). |
| `docs/reviewer_response.md` | `git mv` to `review/archive/reviewer_response.md`. Its arguments go into `22` and `01`. |

Delete with `git rm` in the batch that replaces the content, so git history keeps it.
Before deleting, check that no other file links to it
(`grep -rn "docs/<file>" --exclude-dir=docs`) and update any links found.

## 7. Checks for each batch

1. Front matter parses as YAML, every `id` is unique, and every `depends_on` id exists.
2. All relative links and anchors resolve.
3. No code names in the body: `grep -nE '(fct_|mod_|utils_|\.wiseapp_|[a-z_]+\(\))'` finds
   matches only in the "Implementation map" section and the front matter.
4. Each "Implementation map" entry names a file and a function that exist (grep each one).
5. Maths renders in GitHub preview (spot-check display equations and `\tag`).
6. `verified_against` is the commit the check was done at.

## 8. Batches

1. `README.md` (draft), `00_notation.md`, `01_framework.md`. **Review stop:**
   notation is fixed before anything else is written.
2. Data and Step 1: `10`, `11`, `12`, `20`, `21`, `22`, `23`, `24`; move
   `reviewer_response.md`; delete `method_lin.md` and `method_rif.md`.
3. Step 2: `30`, `31`, `32`, `33`; delete `method_climate.md` and
   `method_uncertainty.md`.
4. Step 3: `40`, `41`, `42`, `43`, `44`, `45`; delete `method_policy.md` and
   `policy_effects.md`.
5. Cross-cutting: `50`, `51`, `52`, `references.md`, `index.yml`, final
   `README.md`; delete `batch_pipeline.md`; update the `docs/` mention in
   AGENTS.md if one is needed.

Each batch report lists: pages written, code-vs-doc mismatches found, notation
conflicts with the guide, improvement ideas for the tracker, and the check results.

## 9. Out of scope

- Editing `~/Github/wise-app-docs` (separate later task: trim its methodology
  sections and link to `docs/`).
- Any change to R code, tests or the data repo.
- Rendering `docs/` as a site.

## 10. Decisions

- Data repo: `https://github.com/worldbank/wise-app-data`.
- User guide links use the `main` branch of `worldbank/wise-app-docs`.
- `51_reproducibility.md` and `52_batch_runs.md` are in scope.
- One implementer session works through the batches in order, with a user
  review after each batch (section 8).
