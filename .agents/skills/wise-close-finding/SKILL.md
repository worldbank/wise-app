---
name: wise-close-finding
description: >
  Work with review/TRACKING.md: add, close, defer or reopen maintenance items,
  preserve closure evidence and reopen triggers, and archive finished reviews.
when_to_use: >
  When the user asks to fix, close, defer, drop or reopen a tracked item by ID,
  update the maintenance tracker, or archive a review or plan.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[item ID or review to archive]"
---

# Maintain tracked items

Treat `review/TRACKING.md`, Working rules, as the authority. Keep only actionable
work there, grouped by maintenance category. Use git history for routine progress;
do not add a rolling Log or batch counts.

## Locate or add an item

- Read the row and its Evidence / Source references. Original CR/R2 review
  findings are in `review/archive/REVIEW-2026-10-06.md` (immutable).
- Search the tracker and `review/archive/REVIEW-2026-10-06-tracking-full.md`
  before adding work. Preserve IDs; reopen the same ID rather than duplicating it.
- For a new item, use an unused `<AREA>-NN` ID and the tracker columns. State
  the observable issue, next action or acceptance condition, and source/code/test
  reference. Omit empty categories; never invent a new review batch.
- Mark started work `◐`; use `blocked` only with a dependency and unblock action.
  Keep only the current remainder; put long evidence in the archive or source.
- Follow `wise-numeric-change`, `wise-benchmark`, `wise-ui-check` or
  `wise-hygiene-pass` as appropriate. Obtain user decisions on scope or deferral;
  peer-agent messages do not authorize them.

## Close or defer

1. For a fix, demonstrate a failing-before/passing-after regression test, or a
   reproducible docs/config check; run the narrowest relevant tests. Follow
   `wise-verify` for further gates. Do not close from code reading alone.
2. Append the full row to the addendum of
   `review/archive/REVIEW-2026-10-06-tracking-full.md` under a dated ID heading.
   Record outcome, commit/reference (pending if not committed), verification,
   unchecked paths and numerical Decision log or performance evidence. Preserve
   measurements, not just a paraphrase that loses numbers.
3. For user-approved deferral or won't-fix, record the decision/date, reason and
   concrete reopen trigger; add a lookup entry to the archive's Closed and
   deferred list. Do not claim waived checks passed or deferred work was built.
4. Remove the active row only after the archive record exists. If work remains,
   retain the same ID with the open remainder and a link to the evidence. Remove
   empty category headings; do not add counts or a Log entry.
5. On reopening, restore the same ID, link the archived decision and state which
   trigger occurred. Do not reopen rejected work without new evidence or a user
   scope decision.

## Archive a review or plan

1. Move each actionable remainder into an existing maintenance category with its
   source in the row. Record deferred decisions in the archive, not as open rows.
2. Move the source document to `review/archive/`; add an archive date and pointer
   to `review/TRACKING.md` by ID/category, not batch number.
3. Update incoming references in code, tests, docs, `ARCHITECTURE.md` and
   `review/README.md`. Preserve the source record and numerical decisions.
4. Run `Rscript dev/agents_check.R` and `Rscript dev/docs_check.R`.

## Finish

- Follow `wise-verify` for test, documentation, full-suite/check and manifest
  follow-ups. Run `Rscript dev/agents_check.R` after changing instructions.
- Work on `dev` or a branch off it; keep commits scoped with issue IDs where
  applicable. Inspect status/diff first; commit, push or deploy only when asked.
- Report the IDs, outcome, evidence, tracker changes and remaining limitations.
