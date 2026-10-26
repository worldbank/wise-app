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
| R4 | `dev/agents_check.R` in CI | ✓ 2026-10-26 | Job `agents-check` in `R-CMD-check.yaml`. Checks paths and functions named in `AGENTS.md`, `ARCHITECTURE.md`, skills and the two standards; skill front matter and listing in `AGENTS.md`; size budgets; version match. Budget for `ARCHITECTURE.md` is a ratchet just above today's size; lower it when trimmed. |
| R6 | Missing skills | ✓ 2026-10-26 | `wise-verify`, `wise-numeric-change`, `wise-close-finding`, `add-policy-lever`, `add-metric`, `wise-release`. Listed in `AGENTS.md`. |
| R7 | `review/README.md` index; archive finished plans | ✓ 2026-10-26 | Index with status written. No plan moved: `R/fct_sp_shock.R`, `R/fct_sp_effectiveness.R`, `batch/` docs and tests cite the plans by path. Move them when those comments are next edited. |
| R3b | One shared skills folder, pointed to from the README; no copies in the repo | ✓ 2026-10-26 | Skills moved with `git mv` to `.agents/skills/`. `.claude/skills` is a git-ignored local link (`ln -s ../.agents/skills .claude/skills`); setup in README "Agent skills" and the Skills section of `AGENTS.md`. |
| R9 | Trim `ARCHITECTURE.md` | ✓ 2026-10-26 | 23 KB to 9 KB. Deployment settings moved intact to `DEPLOYMENT.md`; per-file prose and the lever, uncertainty and decomposition detail now point to `docs/` pages and R file headers. Budgets in `dev/agents_check.R` lowered to match. |

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

1. **Write-back rule plus a staleness check (recommended).** The rule is in place (R5). Done (R4): `dev/agents_check.R`, modelled on `dev/docs_check.R`, run in CI. It checks that paths and `R/` functions named in `AGENTS.md`, `ARCHITECTURE.md`, skills and active `review/` standards exist; skill front matter (`name` matches folder, `description` present); generated skill copies match the source (R3b); size budgets (`AGENTS.md` lines, longest line). The scratch check used on 2026-10-26 is a starting point. Also move standing user decisions ("user instruction 2026-10-07" and similar in the tracking file) into one shared place; per-user agent memory is not shared with the team.
2. **End-of-session hook (Claude Code only).** A `Stop` hook in a shared `.claude/settings.json` asks "did any instruction mislead you?". Consistent, but only one tool has it, and it can produce churn edits. Consider after a month of level 1.
3. **Scheduled audit agent.** A periodic cloud agent runs the checks, compares recent commits with the instructions and opens PRs. Catches untouched drift, but is billed per run, needs a reviewer and care with credentials. Only if the team grows.

## 4. Skills location (R3b)

Checked 2026-10-26, recheck before acting: Claude Code documents `.claude/skills/`; Kilo Code documents `.kilocode/skills/` (Kilo CLI uses `.kilo/`, skills path unconfirmed); Codex sources disagree (`.agents/skills/` or `.codex/skills/`). The `SKILL.md` format is portable; the Claude-only front matter fields are ignored elsewhere.

Decision (user, 2026-10-26): one shared skills folder in the repo, described in the README; each person points their tool at it or copies it into the tool folder. No copies or sync script in the repo. `dev/agents_check.R` checks `.agents/skills/`.

## 5. Other recommendations

- Large files (`fct_policy_sim_compare.R` 3,436 lines, `fct_results.R` 3,368, `fct_sim_compare.R` 2,756) are read in chunks by agents. Splitting is a refactor, not proposed; keep section headers current.
- A tracked `.claude/settings.json` with an allowlist for common read-only commands (`Rscript dev/ui_drive.R`, `Rscript dev/docs_check.R`) would cut permission prompts for the team.
- CI guards for rules agents often break: `DESCRIPTION` and `inst/golem-config.yml` versions match, `RoxygenNote` unchanged, no `%>%` in `R/`.
