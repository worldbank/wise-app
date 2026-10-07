# Code hygiene guidelines

Standing conventions for `R/` and the procedure for a hygiene pass. A hygiene pass improves readability and structural consistency with **zero behavioral change**. The first full pass is complete and archived in `review/archive/golem_code_hygiene_progress.md`; use this file to keep new code consistent and to run later passes.

Hard limits and style rules in `AGENTS.md` and the user's global instructions take precedence over this file.

## Scope

- **In scope for edits:** `R/` (`app_ui.R`, `app_server.R`, `mod_*.R`, `fct_*.R`, `utils_*.R`, `app_config.R`, `run_app.R`), roxygen blocks, and the `Imports:` field of `DESCRIPTION` (only with approval, see Escalation).
- **Out of scope for edits:** `batch/`, `dev/`, `inst/`, `review/`, and non-app scripts. `tests/` is not edited, but it must be run as part of verification.
- If a file's purpose or status is unclear, do not edit it. List it in the report.

## Conventions

These describe what the codebase already does. New and modified code should follow them.

**Golem structure**
- Modules use `mod_NAME_ui(id)` / `mod_NAME_server(id, ...)`, `NS(id)` and `moduleServer()`, consistently.
- No `library()` or `require()` calls anywhere in `R/`. Dependencies come from `DESCRIPTION` `Imports:`.
- Business logic with no Shiny dependency belongs in `fct_*.R` or `utils_*.R`, not in modules. A hygiene pass does not move code; it lists misplaced logic in the report, because moving code is a refactor.

**Pipes and assignment**
- Native pipe `|>` only. Do not introduce `%>%`, and convert any that appear in files you modify.
- `<-` for assignment; `=` only for function arguments.

**Namespacing**
- Use roxygen `@importFrom pkg fn` for heavily used core functions (Shiny tags, primary dplyr verbs), only for packages already in `Imports:`.
- Use `pkg::fn()` inline for infrequent or collision-prone calls (`stats`, `collapse`, `kit`, utility packages).
- After any roxygen edit, run `devtools::document()` with the roxygen2 version pinned in `DESCRIPTION` (`RoxygenNote`; 8.x rewrites the NAMESPACE layout) and confirm the `NAMESPACE` and `man/` diffs contain only intended changes.

**Section headers** (RStudio-outline compatible, `# Title ----`)
- `mod_*.R`: `# UI ----`, `# Server ----`, `# Reactives ----`, `# Handlers ----`, `# Helpers ----`, using only the sections the file needs.
- `fct_*.R` and `utils_*.R`: `# <Topic> ----`.
- In-function markers use the same `# Title ----` form rather than rule-line sandwiches.
- If a file's existing headers are internally consistent, keep them and report the deviation; do not make churn-only edits.

**Comments**
- Remove outdated comments. Add concise comments only for non-obvious logic.
- Preserve comments that reference `review/` plans, contract notes or issue IDs (for example `CR-CQ-07`, `R2-PERF-04`).
- Comments and roxygen must not introduce new failures in `tests/spelling.R`.
- ASCII quotes and hyphens only in code and comments.

**Style**
- Tidyverse style, 2-space indentation, lines up to 120 characters (`.lintr` sets `line_length_linter(120L)` and disables `object_name_linter`; `dev`, `batch`, `review` and test snapshots are excluded).
- Prefer `styler` and `lintr` for mechanical fixes. Run `styler::style_file()` on one file first and check the diff size; skip files where it reflows unrelated code.
- Preserve each file's existing line endings. Do not let a styler run rewrite CRLF or mixed endings across a whole file (`git diff --check` flags this).
- Rename to `snake_case` only for local variables inside one function. Never rename exported functions, registry fields, column names, input/output IDs, or anything under Protected areas.

**Dead code**
- Remove unused local variables, orphaned commented-out code, legacy debugging scripts and stray console printing, subject to the safety rules below. Do not comment code out as a substitute for deleting it.
- Unreferenced functions and unused arguments are flag-first. Remove them only after the search in Safety rule 5.
- `message()` diagnostics and `cat()` inside `renderPrint` are behavior-visible output. Keep them unless the user decides a logging policy.

## Protected areas

Whitespace and comment edits only; flag anything else.

- **Numerics:** `fct_run_simulation.R`, `fct_step2_compute.R`, and the decomposition code (`fct_policy_decompose.R`, `fct_policy_metric_decompose.R`, `fct_decomposition_summary.R`). Reference numerics and determinism tests depend on them.
- **Async code:** `fct_step2_async.R` and anything serialized to mirai workers. Functions, globals and arguments may be captured by name, so "unused" cannot be proven by static reading.
- **Contract surface:** exported functions, `ENGINE_REGISTRY` and metric-registry fields, `.wiseapp_*` columns, and any identifier used in `inst/` JS, `Shiny.setInputValue` or `tests/`. This includes the `year` type contract described in `AGENTS.md`.

## Safety protocol for a pass

1. **Clean tree.** Run `git status` first. Skip any target file with uncommitted changes, or ask the user to commit or stash. Work on a dedicated branch. Do not commit or push unless asked.
2. **Baseline.** Before editing, run `devtools::test()` (about 4 to 6 minutes serial) and record the pass/fail state per file. Failures at baseline, and tests that error for environment reasons (credentials, network), are recorded and excluded from regression checks. `git status` on `tests/` must show no changes afterwards; never accept or update snapshots.
3. **Plan.** Read the target files and write a short plan per file so conventions are applied consistently across files.
4. **Batches.** Order: `utils_*`, `fct_*`, `mod_1_*`, `mod_2_*`, `mod_3_*`, then `app_*` and `run_app.R`. Split any batch whose diff exceeds roughly 400 changed lines. After each batch, run `devtools::test()` and `tests/spelling.R`, then stop for user review. If a previously passing test fails, revert that change and flag it.
   - Revert mechanics: save a patch to the scratchpad (`git diff <file>`) after editing and before testing. Revert one file with `git restore <file>`, or part of a change with `git apply -R` on the patch. The user commits each batch.
   - For comment-only and whitespace-only batches, also check that every changed file parses to an expression identical to HEAD.
5. **Dead-code search.** Before removing anything, search beyond `R/`: `tests/`, `inst/app/` JS, `dev/`, `batch/`, `NAMESPACE`, and string references.

## Escalation

Flag to the user instead of applying when:

- Deleting a variable, argument or function cannot be confirmed safe by static reading (possible NSE or tidy eval, dynamic UI, `do.call`, `get()`, `match.fun`, registry lookups, values referenced only by string or id).
- A reactive, observer or event chain would need reordering, since order can change the dependency graph.
- `DESCRIPTION` `Imports:` would change. List the proposed diff and the reason first.
- The touched file or function has no test coverage. Say so in the report, so the user knows that section relied on manual review.

## Hard constraints

- Do not change app functionality, UI layout, input/output IDs or reactive logic.
- Apply edits directly in the source files; do not leave parallel copies.

## Report format

After each batch, and again at the end:

1. **Test status:** baseline against current pass/fail, with the exact command and output summary.
2. **Per-file changelog:** short bullets of the cleanups applied.
3. **Flagged items:** everything paused under Escalation, plus misplaced-logic candidates and skipped files, with reasons.
4. **Coverage note:** count and list of touched files with no dedicated test coverage.
5. **Files touched:** list of modified paths.
