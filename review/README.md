# review/

Standards, open work, plans and reviews. Read only what the task needs; the large files are for lookup by id, not for reading through. Finished work is in `archive/` (verbatim records, not guidance).

Status: **standard** (rules to follow) · **open** (work in progress, may change) · **reference** (design record that code and docs cite) · **lookup** (read by id only).

| File | Status | Read when |
|---|---|---|
| `code_hygiene.md` | standard | Writing or cleaning `R/` code; defines protected areas |
| `optimization_guidelines.md` | standard | Any performance, caching, async or UI-table/figure work (section 9: benchmark gate) |
| `TRACKING.md` | open | The single list of open work from all reviews; "Where things stand" is the current status |
| `agent_setup_review.md` | open | Changing `AGENTS.md`, `ARCHITECTURE.md`, skills or `dev/agents_check.R` |
| `archive/batch_pipeline_plan.md` | reference | Built batch pipeline design, cited by `batch/` docs and tests. No open work in `TRACKING.md`; figures and selection belong in downstream reproducibility packages |
| `archive/` | archive | Evidence behind a closed finding, the Decision log and earlier plans (`uncertainty_residuals_review.md`: the evidence and tables behind the residual and uncertainty work, closed 2026-10-26; `methodology_review_2026-10-26.md`: the methods implementation review with findings 1 to 5 and its revision notes, closed 2026-10-26, open items in `TRACKING.md` B12). Open it for a specific item, not for orientation. `REVIEW-2026-10-06.md` holds the text of the findings (lookup by id, immutable); the shock-responsive SP plan and tasks and the cost-effectiveness plan are the design records cited by `R/fct_sp_shock.R` and `R/fct_sp_effectiveness.R`; their open items are in `TRACKING.md` (B11) |

## Conventions

- New plans and reviews go here, with a status line at the top. When one is finished, move it to `archive/` and update this table.
- When archiving a cited plan, update its references in code, tests and documentation in the same change.
- Do not edit `archive/REVIEW-2026-10-06.md`. Record progress in `TRACKING.md` (skill `wise-close-finding`). It is the one place for open items: when a review or plan is finished, add its remaining items to `TRACKING.md` and move the document to `archive/`.
- Do not put generated output, screenshots or datasets here.
