---
name: wise-numeric-change
description: >
  Procedure for a change that moves WISE-APP outputs on purpose (an estimator,
  simulation, aggregation, policy channel or default): tests, a real-data BFA
  before/after, the Decision log entry, and the documentation that must follow.
when_to_use: >
  When a fix or feature changes model, simulation, policy or metric numbers,
  when a test that asserts numbers must change, or when the user asks to
  quantify, document or decide a numerical change. Not for behaviour-preserving
  work (refactors, speed-ups): those must be bit-identical, see
  review/optimization_guidelines.md section 9.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[what moves, e.g. 'cash transfer added after the residual']"
---

# Changing WISE-APP numbers deliberately

Numbers that move need a decision, evidence and a record. A change that was
meant to leave numbers alone but moved them is a bug: stop and find out why.

Hard limits: no push or deploy; never print credentials or household-level
data; real data comes from `Sys.getenv("WISEAPP_DATA_PATH")` read in R, never
from the shell and never from `.Renviron` itself.

## 1. State the change

Write down, before editing: the formula before and after, why the old one was
wrong or the new one is wanted, which outputs move (which metrics, engines,
residual rules, Step 2 or Step 3, linear or RIF), and which stay fixed. Read
the matching `docs/` page and its Implementation map first; the equation there
is the specification, and the page must change with the code.

If the choice between designs is the user's (scope, which outputs move, a
default), ask once with the options and a recommendation, and record the
answer ("user, <date>") in the Decision log. Do not choose silently.

## 2. Find every place that applies

Several consumers often share one rule. For policy numbers, check all of:
the linear path, the RIF path (`predict_rif()`), the level channels, the
regular and shock-responsive transfer, the aggregation mean and its gradient,
the metric states, and the three callers of the shared annual-channel hook
(`ARCHITECTURE.md`, Contracts). `grep` the function and column names rather
than trusting memory. List what you changed and what you deliberately left.

Protected areas (`review/code_hygiene.md`) may be edited here, because this is
deliberate feature work: keep the edit minimal and covered by tests.

## 3. Tests

- Add a regression test that fails before the change and passes after (a
  small synthetic check with a known answer is best). Confirm the "fails
  before" half by running it against the old code path or by reasoning the
  expected value by hand, and say which.
- Run the tests that cover the area (skill `wise-verify`, table in section 2),
  always including `test-determinism.R` and the characterization tests
  (`test-w3-a-aggregation-characterization.R`,
  `test-w3-b-future-decomposition-characterization.R`) for Step 2 and
  decomposition changes.
- A test that asserts the old numbers is changed only to the new, justified
  numbers, and the Decision log says so. Do not loosen tolerances or update
  snapshot files to get green.
- Neutral setting: with every new option at its default, outputs must equal
  the old ones. Test that equality where an option is added.

## 4. Real-data before/after (BFA)

Use the batch pipeline (`wise_targets()`) on BFA. It needs `targets`, `arrow`,
`yaml`, the DuckDB `h3` extension and `WISEAPP_DATA_PATH` (check with
`nzchar(Sys.getenv("WISEAPP_DATA_PATH"))` in R; if unset, stop and tell the
user, do not substitute other data).

1. Pick the spec that exercises the change. Default: BFA household welfare
   (log outcome by default), linear fixest model with the app defaults,
   historical simulation only, no coefficient uncertainty, seed 123, residual
   rules `original` and `resample` (the batch offers these two). Add the
   lever or transfer the change touches (for example `transfer_amount_usd: 60`
   to the poorest 30%). Use RIF as a second spec when the RIF path changed.
2. `before` is the parent commit of the change, `after` the changed code. Do
   not reset or stash: add a worktree for the parent
   (`git worktree add <scratchpad>/before <commit>`), or ask the user to
   commit first. Install each build into its own library.
3. Run `targets::tar_make()` in the main process (remove `controller` in
   `_targets.R`) with `.libPaths()` set first. `crew` workers load the default
   installed `wiseapp`, not the one you meant, and then both runs print the
   same numbers: if before and after are identical when they should differ,
   discard the runs and suspect this.
4. Compare the headline numbers the change should move (mean, poverty rate,
   policy gain, by residual rule) and the ones it should not. Report absolute
   and relative change.
5. Where real data cannot show the effect, use the fixture
   (`.bench_small_step3_input()` in `dev/bench/bench_step3_helpers.R`) and say
   so. For a release, `dev/batch_parity_bfa*.R` compare the batch tables with
   the module servers.

Keep run outputs under `dev/outputs/` (git-ignored) or the scratchpad. Do not
commit household-level frames.

## 5. Record it

- **Decision log** (numerical change): the formula before and after, the
  design choice with the alternatives rejected, where it applies (functions),
  the before/after table with the spec, commits, seed and library setup, what
  was not changed, and what was not checked (for example "the Step 3 pane was
  not driven in the browser"). New entries go in the addendum of
  `review/archive/REVIEW-2026-10-06-tracking-full.md` or as a row in
  `review/REVIEW-2026-10-06-tracking.md`; the last two (DOC-11) are the model.
- **Log line** in the tracking file: date, finding id, one sentence on what
  moved and by how much.
- **Methods page**: update the equation or text in `docs/`, set
  `verified_against` to the commit, `Rscript dev/docs_index.R`, then
  `Rscript dev/docs_check.R`.
- **Other readers of the numbers**: `batch/docs/tables.md` if a table's
  meaning changes; in-app notes (for example on the Decomposition tab) if they
  describe the old behaviour; export and provenance fields if the spec changed
  shape.

## 6. Check the app

If a screen shows the moved numbers, drive it (skill `wise-ui-check`; Step 2
and Step 3 run on a worker, poll as that skill describes). If you did not,
write that in the Decision log.

## Report

The change in one paragraph; the before/after table; tests added and run (with
counts); docs and records updated; what was not checked. Commit only if the
user asks.

## Traps

- `year` is a factor, character or numeric depending on the stage; do not
  unify it as a side effect (CR-CQ-07).
- For a log outcome, the welfare is rebuilt after the residual:
  `exp(y - sp_log + e) + T`. A new level-scale term must follow the same
  carrying pattern (`sp_level`, `sp_log`) or it is scaled by `exp(e)`.
- RIF has its own path; fixing the linear model alone leaves RIF wrong.
- Shared helpers have several consumers (Step 2 aggregation, the Step 3
  results, the metric decomposition). Test each consumer, not only the one you
  were reading.
- A before run from a cache that was warm in one build and cold in the other
  is not a numeric difference; clear or pin the weather cache
  (`WISEAPP_WEATHER_CACHE_DISABLE=1`).
