# Agent setup review: instructions, skills and self-maintenance

Started 2026-10-26 on `dev` (HEAD `2af403d`). How coding agents (Claude Code, Kilo and others used by the World Bank team) find instructions and workflows in this repo, and how to keep those instructions current. Constraints from the user: several agent tools are in use, so the setup must be interoperable; other team members use agents too, so Windows clones are likely.

Status: `✓` done · `☐` todo.

## Status

| # | Item | Status | Notes |
|---|---|---|---|
| R1 | Slim `AGENTS.md` into a router | ✓ 2026-10-26 | 216 to 89 lines. Rules, commands, map, "after you change X" table, skills table, write-back rule. Reference detail moved verbatim to the new `ARCHITECTURE.md`. |
| R2 | Fix stale facts | ✓ 2026-10-26 | See section 1. |
| R3a | Skills findable by every agent | ✓ 2026-10-26 | Skills table in `AGENTS.md`; agents without native skill support read the `SKILL.md` on demand. |
| R5 | Write-back rule | ✓ 2026-10-26 | "Keeping these instructions current" section in `AGENTS.md`. |
| R4 | `dev/agents_check.R` in CI | ✓ 2026-10-26 | Job `agents-check` in `R-CMD-check.yaml`. Required inputs, heuristic path checks, root-guide function checks, skill metadata and bidirectional listing, size budgets and existing version match. Negative tests in `tests/testthat/test-agents_check.R`. README setup is outside checker scope. |
| R6 | Missing skills | ✓ 2026-10-26 | `wise-verify`, `wise-numeric-change`, `wise-close-finding`, `add-policy-lever`, `add-metric`, `wise-release`. Listed in `AGENTS.md`. |
| R7 | `review/README.md` index; archive finished plans | ✓ 2026-10-26 | Index records the current locations. Finished SP, cost-effectiveness and batch plans are archived, with incoming references updated. |
| R3b | One shared skills folder, pointed to from the README; no copies in the repo | ✓ 2026-10-26 | Skills moved with `git mv` to `.agents/skills/`. `.claude/skills` is a git-ignored local link (`ln -s ../.agents/skills .claude/skills`); setup in README "Agent skills" and the Skills section of `AGENTS.md`. |
| R9 | Trim `ARCHITECTURE.md` | ✓ 2026-10-26 | 23 KB to 9 KB. Deployment settings moved intact to `DEPLOYMENT.md`; per-file prose and the lever, uncertainty and decomposition detail now point to `docs/` pages and R file headers. Budgets in `dev/agents_check.R` lowered to match. |
| R10 | Scope-aware write-back | ✓ 2026-10-26 | Correct instructions only within authorized scope; otherwise report and await approval. Prefer corrections, not extra rules. |
| R11 | Standing user decisions | ✓ 2026-10-26 | Benchmark defaults, ceiling and harness notes consolidated in `review/optimization_guidelines.md` section 9; tracker and skill point there. Historical decisions remain in their records. |
| R12 | Shared Claude allowlist | ✓ 2026-10-26 | `.claude/settings.json` allows `ui_drive.R` app automation and the agent/docs check and docs-index scripts; no blanket R or Git permission. |

## 1. Done on 2026-10-26

- `AGENTS.md` rewritten (89 lines, was 216). Pointers changed from `AGENTS.md` to `ARCHITECTURE.md` in `review/code_hygiene.md`, `review/optimization_guidelines.md`, `.claude/skills/add-model-engine/SKILL.md` and a comment in `tests/testthat/setup-env.R`. `ARCHITECTURE.md` added to `.Rbuildignore`.
- Stale facts removed or fixed: module, `fct_` and test file counts (dropped, they rot); `testthat::test_dir("tests")` (runs nothing; replaced by `devtools::test()`); the install one-liner (replaced by `pak::local_install_deps()`); residual options (UI offers `original` and `resample`; `normal` and `none` are internal, per `residual_choices()`); `ranger` and `xgboost` now shown as registered but not offered in the UI; Step 3 harness path in the tracking file is `dev/bench/bench_step2.R`.
- Correction to the first draft of this review: protected areas are defined in `review/code_hygiene.md` (the first check was truncated). No change needed.
- Check: every path and function named in backticks in `AGENTS.md` and `ARCHITECTURE.md` exists (scripted; the remaining hits were relative paths inside `review/` and base R functions).
- `manifest.json` needs no regeneration for these changes: it covers only `app.R`, `R/`, `src/`, `inst/`, `DESCRIPTION` and `NAMESPACE`.

## 2. Skills

Six written 2026-10-26 (see R6). Candidates not written: none known. Add a skill when a task recurs and an agent got it wrong or slow; keep each under 300 lines (`dev/agents_check.R`).

## 3. Self-improvement

Three levels, each building on the one before.

1. **Write-back rule plus a staleness check (in place).** R4/R5/R10 cover authorized, minimal corrections and CI checks. Path checks inspect selected backtick references, not all links or commands; function checks cover only `AGENTS.md`, `ARCHITECTURE.md` and `DEPLOYMENT.md`. Skill copies are not managed or compared. Standing decisions consolidated in R11.
2. **End-of-session hook (Claude Code only).** A `Stop` hook in a shared `.claude/settings.json` asks "did any instruction mislead you?". Consistent, but only one tool has it, and it can produce churn edits. Consider after a month of level 1.
3. **Scheduled audit agent.** A periodic cloud agent runs the checks, compares recent commits with the instructions and opens PRs. Catches untouched drift, but is billed per run, needs a reviewer and care with credentials. Only if the team grows.

## 4. Skills location (R3b)

Discovery resolved from official documentation, 2026-10-26 (not a runtime compatibility test):

| Tool | Shared-source discovery | Refresh / confirmation |
|---|---|---|
| [Kilo CLI and current VS Code platform](https://kilo.ai/docs/customize/skills) | `.agents/skills/` loaded by default; `.kilo/skills/` and `skills.paths` also supported | `/reload` or new session; confirm the skill appears and is loaded through the skill tool |
| [Codex CLI and IDE](https://developers.openai.com/codex/build-skills) | `.agents/skills/` from the current directory up to the repository root | `/skills` or `$` mention; restart if updates do not appear |
| Claude Code | Local link or copy at `.claude/skills/` | New session; confirm skill availability |

Kilo and Codex need no link or copy on Windows either. Other tools can read `SKILL.md` directly. Portable content and `name`/`description` do not imply portable tool names, invocation settings or permissions; do not rely on Claude-specific fields to enforce permissions elsewhere. Runtime discovery on the team's installed versions remains a setup smoke check.

Decision (user, 2026-10-26): one shared skills folder in the repo, described in the README; each person points their tool at it or copies it into the tool folder. No copies or sync script in the repo. `dev/agents_check.R` checks `.agents/skills/`.

`README.md` is now the editable source; the redundant `README.Rmd` (no executable chunks or build references) was removed.

## 5. Other recommendations

- Large files (`fct_policy_sim_compare.R` 3,436 lines, `fct_results.R` 3,368, `fct_sim_compare.R` 2,756) are read in chunks by agents. Splitting is a refactor, not proposed; keep section headers current.
- Implemented (R12): a tracked `.claude/settings.json` allowlist for common checks and app automation. `ui_drive.R` is deliberately included to run and drive the app; it is not read-only. Permission behavior still needs confirmation in Claude Code after workspace trust.
- Deferred: further version-equality CI enforcement (user decision, 2026-10-26); the existing equality check remains unchanged. Optional guards for `RoxygenNote` and no `%>%` in executable `R/` code are also not implemented.
