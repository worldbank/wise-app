---
id: index
title: WISE-APP methods reference
app_step: cross
depends_on: [notation, framework]
symbols: []
guide: https://github.com/worldbank/wise-app-docs/blob/main/index.qmd
code: []
verified_against: 8592a9d
---

# WISE-APP methods reference

> This folder explains how WISE-APP computes its numbers: the estimators, the simulation design, the metrics, the uncertainty bands and the policy mechanics. It is written like the methods appendix of an economics paper. It does not explain how to use the screens; the user guide does that.

**Status: draft for review.** All pages are written and were checked against the code at the commit named in each page's `verified_against` field. The earlier method pages of this folder are replaced.

## Who this is for

- Economists and policy analysts who use the app and want to know what a number means.
- Outside reviewers of the methods.
- Maintainers of the code, and AI assistants that cite these pages. Every page has YAML front matter, stable ids, numbered equations and a closing "Implementation map" that links each concept to code.

## Reading order

1. [00_notation](00_notation.md): symbols, indices, units. Everything else relies on it.
2. [01_framework](01_framework.md): the question, the estimand of each step, and what the data identify.
3. Then the pages for the step you use, in the table below.
4. [50_assumptions_limitations](50_assumptions_limitations.md) for all assumptions in one place.

## Map from app step to pages

| App step | Pages |
|---|---|
| Overview | [10_data](10_data.md) |
| Step 1 Sample and Outcome | [10_data](10_data.md), [11_outcomes](11_outcomes.md) |
| Step 1 Weather | [12_weather_measures](12_weather_measures.md) |
| Step 1 Model and Results | [20_model_specification](20_model_specification.md), [21_model_linear](21_model_linear.md), [22_model_rif](22_model_rif.md), [23_model_ml](23_model_ml.md), [24_model_results](24_model_results.md) |
| Step 2 Simulation | [30_simulation](30_simulation.md), [31_climate_scenarios](31_climate_scenarios.md), [32_metrics](32_metrics.md), [33_uncertainty](33_uncertainty.md), [34_seasonal_forecast](34_seasonal_forecast.md) (design) |
| Step 3 Policy | [40_policy_framework](40_policy_framework.md), [41_policy_levers](41_policy_levers.md), [42_social_protection](42_social_protection.md), [43_shock_responsive_sp](43_shock_responsive_sp.md), [44_decomposition](44_decomposition.md), [45_cost_effectiveness](45_cost_effectiveness.md) |
| Across steps | [51_reproducibility](51_reproducibility.md), [52_batch_runs](52_batch_runs.md), [references](references.md) |

A machine-readable list of pages, equations and symbols is in [index.yml](index.yml).

## How this folder relates to other documentation

| Location | Role |
|---|---|
| This folder | Methods: equations, estimands, assumptions, limitations, code map. |
| [WISE-APP user guide](https://github.com/worldbank/wise-app-docs) (Quarto book) | How to use each screen, how to read results, tips. Each page here links to the matching guide section. |
| [wise-app-data](https://github.com/worldbank/wise-app-data) | Data preparation and the input schema (survey list, variable list, CPI and PPP table, parquet files). The data page links there and does not copy it. |
| [batch/README.md](../batch/README.md) and [batch/docs/](../batch/docs/) | Batch runs: specification, tables, runner. |
| [review/](../review/) | Plans, reviews and open items. |

Methods text lives here and not in the user guide, so the two do not drift apart.

## Conventions

- **Math.** `$...$` inline and `$$...$$` display, in LaTeX that GitHub renders. Key equations carry a tag `(n.m)`, where `n` is the numbered subsection under "Method" on that page. Across pages, write "Eq. (2.3) in [30_simulation](30_simulation.md)".
- **Assumptions** are numbered A1, A2, ... on each page and collected on the assumptions page.
- **No code names in the body.** Function, file, column and argument names appear only in the closing "Implementation map" and in the front matter. "In the app" names screens by their labels.
- **Plain terms.** A term is defined where it first appears, and one word is used for one thing.
- **Citations** use the user guide's BibTeX keys, written `[@key]`. Entries are listed in the references page.
- **Verification.** `verified_against` in the front matter is the git commit at which the page was checked against the code. Where an older document and the code disagree, the code is followed.
- **Page template.** Summary, Setup, Method, Interpretation, Assumptions, Limitations and what is not modelled, In the app, References, Implementation map.

## Not covered here

Instructions for the screens, data preparation scripts, the batch file format and open improvement items. See the table above for where they live.
