# AGENTS.md

Guidance for coding agents (Claude Code, Kilo, Codex and others) working in this repository. This file holds the rules and a map; the detail lives in the files it points to. Read those only when the task needs them.

## What this is

**WISE-APP** (Weather Impact Simulation and Evaluation for Adaptation Policy and Planning) is an R Shiny app built by the World Bank. It estimates how weather affects household welfare (Step 1), simulates welfare under historical and future climate (Step 2) and evaluates policies (Step 3). R package `wiseapp`, built with [Golem](https://thinkr-open.github.io/golem/), deployed on Posit Connect, MIT licence. `DESCRIPTION` requires R >= 4.4.0; development uses R 4.5.3.

## Rules

- **Git:** work on `dev` or a branch off it (`origin` is `worldbank/wise-app`). Do not push, deploy or upload without an explicit go-ahead.
- **Secrets and data:** never open or print `.Renviron` or credentials. Real data is at `WISEAPP_DATA_PATH`; read it from R (`Sys.getenv("WISEAPP_DATA_PATH")`), because the shell does not load `.Renviron`. The sibling repo `wise-app-data` is data-prep code only, with no produced datasets.
- **Pinned tools:** `devtools::document()` only with roxygen2 7.3.3 (`RoxygenNote`; 8.x rewrites `NAMESPACE`). `duckdb` must be exactly the version pinned in `DESCRIPTION`; the bundled extensions are built for it.
- **Version:** `DESCRIPTION` and `inst/golem-config.yml` must match; regenerate `manifest.json` after.
- **Protected areas** (numerics, async code, contract surface; list in `review/code_hygiene.md`): change only deliberately, with tests that cover the change.
- **`year` type contract:** do not unify the type of `year` across stages without parity runs on every engine (CR-CQ-07, see `ARCHITECTURE.md`).
- **Errors in the UI** go through `wise_user_error()`; never show `conditionMessage()` in modules.
- **UI stack:** tables `reactable`, charts `echarts4r` (`echart_*` builders), maps only the MapLibre bridge (`fct_hexmap.R`).
- **Style:** native pipe `|>`, `<-`, no `library()` in `R/`, ASCII quotes and hyphens in code and comments, 120-character lines. Full conventions: `review/code_hygiene.md`.
- **Numbers that move:** a change to model or simulation outputs needs a Decision log entry with before/after BFA headline numbers (`review/REVIEW-2026-10-06-tracking.md`, Working rules).
- **Speed claims** need before/after timing and peak memory per `review/optimization_guidelines.md` section 9 (skill `wise-benchmark`).

## Commands

```r
devtools::load_all()     # load the package from source
wiseapp::run_app()       # run the app (dev/run_dev.R also documents and reloads)
devtools::document()     # regenerate man/ and NAMESPACE (roxygen2 7.3.3)
devtools::test()         # full suite from the source tree, 4 to 6 minutes
devtools::test(filter = "fct_hexmap")   # one file: tests/testthat/test-fct_hexmap.R
devtools::check()        # R CMD check (runs with --no-tests in CI)
```

Install dependencies with `pak::local_install_deps()` or from `DESCRIPTION` `Imports`, then install the pinned `duckdb` version.

## Where things live

| Path | What |
|---|---|
| `ARCHITECTURE.md` | Map of `R/` by pipeline step, contracts that span files (engines, `year`, levers, transfers, UI), testing details |
| `DEPLOYMENT.md` | Posit Connect deployment, bundled DuckDB extensions, resource limits and all environment variables |
| `R/` | `mod_*` Shiny modules, `fct_*` Shiny-free logic, `utils_*` shared helpers, `app_*` wiring |
| `src/welfare_stats.cpp` | Rcpp kernel for aggregation statistics |
| `docs/` | Methods pages (equations, assumptions); index `docs/README.md`. Each ends with an Implementation map and records `verified_against` |
| `batch/` | Batch runs (`targets`): `batch/README.md`, table reference `batch/docs/tables.md` |
| `review/` | Standards (`code_hygiene.md`, `optimization_guidelines.md`), open items (`REVIEW-2026-10-06-tracking.md`, its "Where things stand" block is the current status), plans; finished work in `review/archive/` |
| `dev/` | `run_dev.R`, `00_make_manifest.R` (Connect manifest), `ui_drive.R` (headless-Chrome driver), `docs_check.R` / `docs_index.R`, `agents_check.R` (paths, functions and sizes named in these instructions; run in CI), parity scripts `batch_parity_bfa*.R`, benchmarks in `dev/bench/` |
| `tests/testthat/` | Unit tests; `tests/e2e/smoke.R` browser smoke with axe-core |
| `.agents/skills/` | Skills, the one shared copy (see Skills) |

## Pipeline

Step 0 Overview, Step 1 Modelling, Step 2 Simulation, Step 3 Policy scenarios; data flows forward. Map of the code by step: `ARCHITECTURE.md`. Methods: `docs/README.md`.

## After you change X, also do Y

| Change | Also |
|---|---|
| Any `R/` file | Run the matching test file (`test-<file>.R`; some use hyphens, so also try `filter = "<topic>"`) |
| Roxygen block or exports | `devtools::document()`; check the `NAMESPACE` and `man/` diff |
| A method (estimator, simulation, metric, policy mechanics) | Update the methods page in `docs/`, its `verified_against`; run `Rscript dev/docs_check.R` |
| Model or simulation outputs | Determinism tests; Decision log with BFA before/after |
| A batch table builder | `batch/docs/tables.md`; batch tests (`ARCHITECTURE.md`, Testing details) |
| UI (modules, CSS, charts, maps) | Check in the running app (skill `wise-ui-check`); `tests/e2e/smoke.R` for larger changes |
| Performance | Skill `wise-benchmark` |
| `R/`, `inst/` or dependencies, before a deploy | `Rscript dev/00_make_manifest.R`; settings in `DEPLOYMENT.md` |
| DuckDB version | Rebuild `inst/duckdb_extensions/`, update the pin, the version constant and the SHA-256 values in `R/fct_load_data.R` together (`DEPLOYMENT.md`) |
| A review finding | Close it per the Working rules in `review/REVIEW-2026-10-06-tracking.md` |

## Skills

Task guides in `.agents/skills/<name>/SKILL.md`, the only copy in the repo. If your tool does not load skills from there, read the `SKILL.md` before doing that kind of task. To make a tool load them, link or copy the folder into the tool's own skills folder (not tracked by git); Claude Code, from the repo root: `ln -s ../.agents/skills .claude/skills` (`.claude/skills` is git-ignored). Edit skills only in `.agents/skills/`. Setup for other tools: README, "Agent skills".

| Skill | Use when |
|---|---|
| `wise-ui-check` | A change touches the UI, or the user asks to run, screenshot or inspect the app |
| `wise-benchmark` | Benchmarking or claiming a speed or memory improvement |
| `wise-hygiene-pass` | Cleanup, style, lint or dead-code pass over `R/` with no behaviour change |
| `add-model-engine` | Adding or extending a model engine |

## Testing essentials

- Run from the source tree, as CI does. The environment is pinned by `tests/testthat/setup-env.R` (caches in a temp dir; `WISEAPP_DATA_*` and cloud credentials unset) and `setup-locale.R`; do not rely on the developer's `.Renviron`.
- New tests go in `test-<R file>.R`. A fixture builder moves into a `helper-*.R` file only when two or more test files use it.
- Not covered by R tests: MapLibre rendering, `conditionalPanel` visibility, `update*Input()` on config import and the real Step 0 to 3 flow. Check them with `dev/ui_drive.R` (skill `wise-ui-check`).
- Coverage, browser smoke and batch test details: `ARCHITECTURE.md`, Testing details.

## Keeping these instructions current

If an instruction in this file, `ARCHITECTURE.md`, a skill or a `review/` standard was wrong, missing or misleading during your task, fix it in the same change and say so in your report. Record a trap you hit in the skill's Traps or notes section. Do not add counts or line numbers; they go stale. Keep this file short: detail goes to `ARCHITECTURE.md`, `docs/` or a skill. After editing any instruction file, run `Rscript dev/agents_check.R`.
