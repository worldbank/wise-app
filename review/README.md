# review/

Standards, open work, plans and reviews. Read only what the task needs; the large files are for lookup by id, not for reading through. Finished work is in `archive/` (verbatim records, not guidance).

Status: **standard** (rules to follow) · **open** (work in progress, may change) · **reference** (design record that code and docs cite) · **lookup** (read by id only).

| File | Status | Read when |
|---|---|---|
| `code_hygiene.md` | standard | Writing or cleaning `R/` code; defines protected areas |
| `optimization_guidelines.md` | standard | Any performance, caching, async or UI-table/figure work (section 9: benchmark gate) |
| `REVIEW-tracking.md` | open | Choosing or closing a finding; "Where things stand" is the current status |
| `REVIEW-2026-10-06.md` | lookup | Reading the text of a finding by id (`grep -n "<ID>"`). Immutable; 120 KB |
| `agent_setup_review.md` | open | Changing `AGENTS.md`, `ARCHITECTURE.md`, skills or `dev/agents_check.R` |
| `methodology_review_2026-10-26.md` | open | Methods implementation review of 2026-10-26 |
| `sp_shock_responsive_plan.md` | reference | Shock-responsive social protection: design rules; Phase 3 design is still open. Cited by `R/fct_sp_shock.R` |
| `sp_shock_responsive_tasks.md` | reference | Remaining SP tasks and the decisions that still bind. Cited by `R/fct_sp_shock.R`, `R/fct_sp_effectiveness.R` |
| `step3_cost_effectiveness_plan.md` | reference | Why the cost-effectiveness tab works as it does (built as task P2-2). Cited by `R/fct_sp_effectiveness.R` |
| `batch_pipeline_plan.md` | reference | Batch pipeline design; Phases 1 to 4 are built, Phase 5 is planned. Cited by `batch/` docs and tests |
| `archive/` | archive | Evidence behind a closed finding, the Decision log and earlier plans (`uncertainty_residuals_review.md`: the evidence and tables behind the residual and uncertainty work, closed 2026-10-26). Open it for a specific item, not for orientation |

## Conventions

- New plans and reviews go here, with a status line at the top. When one is finished, move it to `archive/` and update this table.
- A file that code comments or tests cite stays in place until those references are updated; that is why the three finished or mostly finished plans above are still here.
- Do not edit `REVIEW-2026-10-06.md`. Record progress in the tracking file (skill `wise-close-finding`).
- Do not put generated output, screenshots or datasets here.
