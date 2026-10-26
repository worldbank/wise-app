---
name: wise-verify
description: >
  End-of-task checklist for a change to WISE-APP: map the changed files to the
  narrowest tests that cover them, run the follow-up duties the change owes
  (documentation, methods pages, manifest, browser check) and report what was
  verified.
when_to_use: >
  When a code or documentation change is finished and needs checking before
  the user reviews or commits it, or when the user asks "is this done",
  "what should I run", "which tests cover this", or to verify a change.
user-invocable: true
allowed-tools: Read Grep Glob Bash
argument-hint: "[changed files or area, default: git diff]"
---

# Verifying a WISE-APP change

Run the narrowest check that proves the change, then the follow-ups it owes.
Do not run the full suite for a one-file change. Do not edit code here: if a
check fails, report it, or fix it as part of the task you were doing.

## 1. List what changed

`git status --short` and `git diff --stat`. The tree may hold unrelated
changes from other work: verify only your own files and say which you left
alone.

## 2. Run the matching tests

Tests are in `tests/testthat/`. A file `R/fct_<name>.R` is usually covered by
`test-fct_<name>.R`, but naming is mixed (`test-fct_*` and `test-fct-*`), so
`devtools::test(filter = "fct.x")` (the filter is a regex on the file name
without `test-`) catches both. Search for the function name in `tests/` too:
`grep -rl "function_name" tests/testthat`.

| Changed | Run (filter) |
|---|---|
| `fct_fit_model.R`, `fct_predict_outcomes.R`, `fct_rif_sim.R` | `fct.fit.model`, `fct.predict`, `fct.rif`, `determinism` |
| `fct_simulations.R`, `fct_run_simulation.R`, `fct_step2_*` | `fct.simulations`, `fct.run.simulation`, `step2`, `determinism`, `w3` |
| `fct_aggregation*.R` | `aggregation`, `w3` |
| `fct_policy_*`, `fct_sp_*`, `fct_step3_*` | `policy`, `^sp`, `fct.step3`, `fct.sp` |
| `fct_policy_decompose.R`, `fct_policy_metric_decompose.R`, `fct_decomposition_summary.R` | `policy.decomposition`, `policy.metric.decompose`, `decomposition`, `w3.b` |
| `fct_metric_registry.R`, uncertainty code | `uncertainty`, `policy.decomposition.uncertainty` |
| `fct_hexmap.R`, `inst/app/vendor/` | `hexmap` (rendering needs the browser, see below) |
| `fct_export.R`, `fct_provenance.R` | `export` |
| `fct_batch_*`, `fct_step*_input.R`, `fct_step*_tables.R` | `batch`, `step1`, `step2.input`, `step2.tables`, `step3` |
| `mod_*.R` | the `test-mod_*` file of the module, then the browser check below |
| `app_*.R`, `utils_*.R` | `app.server`, `utils` |

Tests that start real mirai workers or Chrome (`step2-async*`,
`fct-overview-metadata`, `export-bundle`, `mod-0-overview`) are slow: run them
only when the change touches async, metadata or export code.

Run the whole suite (`devtools::test()`, 4 to 6 minutes, use
`run_in_background`) once at the end of a multi-file change, with the tree
quiet.

Rules:
- Never update snapshots or the characterization files (`tests/testthat/_snaps/`)
  to make a test pass. A test that asserts old numbers after an intended
  change is a numeric change: use skill `wise-numeric-change`.
- A failure that also occurs without your change is reported, not fixed. To
  tell, read the failing test and the file it covers; do not stash or reset a
  tree that holds other people's changes.
- A bug fix needs a regression test that fails before and passes after.

## 3. Follow-up duties

Do the rows that apply.

| Change | Also |
|---|---|
| Roxygen block, `@export`, new or renamed function | `devtools::document()`; the `NAMESPACE` and `man/` diff must hold only intended changes (`man/` is not tracked, `NAMESPACE` is) |
| Comments or roxygen text | `Rscript tests/spelling.R` adds no new findings |
| Style-sensitive edit | `lintr::lint(<file>)` (config `.lintr`; CI lint is informational) |
| A method, equation, default or assumption | Update the page in `docs/`, set its `verified_against` to the commit checked, `Rscript dev/docs_index.R`, then `Rscript dev/docs_check.R` |
| Batch table columns or meaning | `batch/docs/tables.md`; batch tests |
| `AGENTS.md`, `ARCHITECTURE.md`, `DEPLOYMENT.md`, a skill | `Rscript dev/agents_check.R` |
| UI (module, CSS, chart, map, tab) | Skill `wise-ui-check`; larger UI changes also `Rscript tests/e2e/smoke.R` (about 5 minutes, needs Chrome) |
| A speed or memory claim | Skill `wise-benchmark` |
| Model or simulation numbers move | Skill `wise-numeric-change` |
| A review finding | Close it per Working rules in `review/REVIEW-2026-10-06-tracking.md` |
| Dependencies, `R/` or `inst/` before a deploy | `Rscript dev/00_make_manifest.R` after committing (it reads `HEAD`) |

`devtools::check()` is for releases and dependency changes, not every task.

## 4. Not covered by R tests

MapLibre rendering, `conditionalPanel` visibility, `update*Input()` on config
import and the real Step 0 to 3 flow need the running app. Say plainly if you
did not check them.

## Report

What changed, which tests ran with their result (counts, from the output),
which follow-ups were done, and what was not run and why. Do not write
"verified" for a check you did not run.

## Traps

- `devtools::test(filter = "x")` matching nothing passes silently with zero
  tests. Check the count in the output.
- `test-fct_step3_tables.R` needs the `dev/bench/` helpers, so it runs only
  from a source checkout (`devtools::test()`), not from an installed package.
- Tests pin their environment (`setup-env.R`): `WISEAPP_DATA_*` and cloud
  credentials are unset there. Do not rely on `.Renviron`.
- `tests/testthat/testthat-problems.rds` is a local artifact and is git-ignored.
