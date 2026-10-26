# review/

Standards, open work, plans and reviews. Read only what the task needs; the large files are for lookup by id, not for reading through. Finished work is in `archive/` (verbatim records, not guidance).

Status: **standard** (rules to follow) · **open** (work in progress, may change) · **reference** (design record that code and docs cite) · **lookup** (read by id only).

| File | Status | Read when |
|---|---|---|
| `code_hygiene.md` | standard | Writing or cleaning `R/` code; defines protected areas |
| `optimization_guidelines.md` | standard | Any performance, caching, async or UI-table/figure work (section 9: benchmark gate) |
| `TRACKING.md` | open | Actionable app/repo maintenance by category; Working rules define adding, updating, closing and reopening items |
| `archive/agent_setup_review.md` | reference | Completed agent-setup design and verification limits; current setup is in `AGENTS.md` and README "Agent skills" |
| `archive/batch_pipeline_plan.md` | reference | Built batch pipeline design, cited by `batch/` docs and tests. No open work in `TRACKING.md`; figures and selection belong in downstream reproducibility packages |
| `archive/` | archive | Closed/deferred decisions, numerical Decision log and earlier plans; look up by ID, not for orientation. `REVIEW-2026-10-06.md` is immutable; `REVIEW-2026-10-06-tracking-full.md` holds closure evidence and reopen triggers. The SP plans remain design records cited by code. |

## Conventions

- New plans and reviews go here, with a status line at the top. When one is finished, move it to `archive/` and update this table.
- When archiving a cited plan, update its references in code, tests and documentation in the same change.
- Do not edit `archive/REVIEW-2026-10-06.md`. Record progress in `TRACKING.md` (skill `wise-close-finding`). It is the one place for open items: when a review or plan is finished, add its remaining items to `TRACKING.md` and move the document to `archive/`.
- Do not put generated output, screenshots or datasets here.
