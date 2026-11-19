---
name: add-policy-lever
description: >
  Add or change a Step 3 policy lever in WISE-APP. Most levers need no app code
  (they come from the variable list); this skill says how to tell, how to check
  a data-driven lever, and which files a new special behaviour or a new lever
  group touches.
when_to_use: >
  When the user wants a new policy lever, a new lever group or Step 3 panel, a
  new control type, or asks why a lever does not appear, or which parts of the
  app a lever change touches.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[lever code or variable, e.g. 'internet' or 'clean_cooking']"
---

# Adding a policy lever

Design: header of `R/fct_policy_registry.R`. Method: `docs/41_policy_levers.md`.
Contracts: `ARCHITECTURE.md`, Contracts, "Levers".

## 1. Decide the tier

A lever is a variable with a non-blank `policy` code in the variable list
(columns `policy` and `policy_group`, written by wise-app-data). The code is
the identity everywhere: scenario key, control ids `<code>_universal` and
`<code>_pct`, spec field stem. Variable names are data.

| Tier | When | Code change |
|---|---|---|
| A. Data-driven | A binary (`logical`) or numeric variable, in an existing group (`infrastructure`, `digital`, `education`, `labor`, or any other, which lands in the `other` slot) | None in this repo. The data repo adds the two columns; the variable must be in the Step 1 model and in the survey. |
| B. Special behaviour | The type does not decide the control (travel time with a cap, coupled labour shares) | Yes: `POLICY_SPECIAL_BEHAVIOURS`, a control, the simulation step, config and batch ids. |
| C. New group with its own panel | A new Step 3 tab | Yes: `POLICY_SLOTS`, a module, `mod_3_scenario.R` wiring. Ask the user first; it is a project. |

Say which tier it is before editing. Most requests are tier A: tell the user
what the data repo has to provide, and verify it (section 2) instead of
writing code. Do not extend `POLICY_FALLBACK` (the names of data directories
without policy metadata) or the alias tables (`POLICY_KEY_ALIASES`,
`POLICY_STEM_ALIASES`, they translate earlier specs only).

## 2. Check a data-driven lever

1. Build the registry from a variable list that has the lever
   (`policy_registry(variable_list)`; examples in
   `tests/testthat/test-fct_policy_registry.R`). Check code, slot, type and
   `behaviour` (`binary`, `pct`, or `none` for a type with no control). A code
   outside `^[a-z][a-z0-9_]*$` is dropped with a warning.
2. Add a registry test if the case is new (a group, a type, a level).
3. In the running app (skill `wise-ui-check`): the control appears in the
   slot's module only when the variable is in the Step 1 model and the survey;
   otherwise the module says why. Run a Step 3 simulation with the lever set
   and read the result.
4. Batch: a lever code is valid in `model.policy_vars` and in the `policy`
   section of a batch spec (`.policy_field_ok()` in `R/fct_batch_spec.R`);
   `wise_access_config()` builds the scenario list and records `lever_vars`, so
   the simulation needs no registry.

## 3. Tier B: a special behaviour

Touch, and read each before editing:

- `R/fct_policy_registry.R`: `POLICY_SPECIAL_BEHAVIOURS` and `policy_behaviour()`.
- `R/mod_3_levers.R`: the `switch()` on `behaviour` in `levers_ui` and the
  `slot_levers` filter, or a module of its own (`R/mod_3_04_labor.R` is the
  example for coupled levers).
- `R/fct_step3_input.R`: `wise_access_config()` and the config builders; the
  control ids (for labour, `STEP3_LABOR_IDS`).
- `R/fct_policy_sim.R`: where the lever changes the survey (search for the
  existing special codes; the local `lever_seed(<name>)` gives each stochastic step its own
  seed, so a new step needs its own name).
- `R/fct_batch_spec.R` (`.policy_ids()`, ranges) and `R/fct_spec_defaults.R`:
  the batch fields and the app defaults.
- `docs/41_policy_levers.md` (new section, Implementation map) and its
  `verified_against`.

A new lever must not move the numbers of existing levers: with the lever at
its neutral value the outputs equal the old ones (test it). If it does move
them, use skill `wise-numeric-change`.

## 4. Tier C: a new group and panel

Add the group to `POLICY_SLOTS`, a `mod_3_NN_*.R` that calls
`mod_3_levers_server()` (copy `R/mod_3_02_infra.R`), wire it in
`R/mod_3_scenario.R` and `step3_merge_access()` or its own config, then the
batch policy section. Confirm the module numbering and tab order with the
user.

## 5. Finish

Skill `wise-verify` (filters `policy.registry`, `policy.lever`, `fct.step3`,
`batch`), `Rscript dev/docs_check.R` after a docs change, and
`Rscript dev/agents_check.R` if `ARCHITECTURE.md` changed.

## Traps

- A lever whose variable is missing from the survey or the model is listed
  with a reason, not silently dropped; keep that behaviour.
- One control per lever code, however many levels (hh, ind, area) it has.
- Levers of groups without a module run inside the `infra` scenario
  (`step3_merge_access()`); a change to that merge affects all of them.
- Saved selections and batch specs use lever codes; renaming a code breaks
  them. Add an alias instead.
