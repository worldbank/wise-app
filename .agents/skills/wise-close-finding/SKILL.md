---
name: wise-close-finding
description: >
  Work with the single open-work list (review/TRACKING.md): close an item
  (the evidence it needs, the commit convention, moving the row to the archive,
  the counts and the Log line), close it as won't fix or deferred, and fold the
  open items of a finished review or plan into the list.
when_to_use: >
  When the user asks to fix, close, defer or drop a tracked item by id (for
  example CR-CQ-01, R2-PERF-01, UR-01), to update TRACKING.md after finishing
  one, or to archive a finished review or plan and carry its open items over.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[item id, e.g. R2-PERF-01, or a review to fold in]"
---

# Closing a tracked item

All open work is in `review/TRACKING.md`, whatever review it came from. The
text of the first review's findings (batches B1 to B9) is
`review/archive/REVIEW-2026-10-06.md` (immutable: read it by id, never edit it);
the source of any other item is named in its section header. The record of
finished work is `review/archive/REVIEW-2026-10-06-tracking-full.md`. The
tracker's "Working rules" are the authority; this skill is the procedure.

Status marks: `☐` todo, `◐` in progress (the open remainder is listed), `✗`
won't fix or deferred (the reason is given).

## 1. Before the work

- Read the row and, for a B1 to B9 id, the finding text (`grep -n "<ID>" review/archive/REVIEW-2026-10-06.md`); for other ids read the source named in the section header.
- Work on a branch off `dev`, one commit per finding id, the id in the
  subject (`R2-PERF-01: share household-constant vectors`). Do not push.
- Check the work type and use the matching skill: numbers move
  (`wise-numeric-change`), speed or memory (`wise-benchmark`, gate in
  `review/optimization_guidelines.md` section 9), UI (`wise-ui-check`), a
  cleanup (`wise-hygiene-pass`).
- A decision that is the user's (scope, won't fix, which of two designs) is
  asked once with a recommendation; record "user, <date>".

## 2. Closing evidence

A finding closes only when all hold:

1. A regression test fails before and passes after, or a reproducible command
   shows a config or docs fix.
2. The narrowest relevant `devtools::test(filter = ...)` passes (skill
   `wise-verify`).
3. The Notes cell records the commit and what was verified, including what was
   not checked ("not driven in the browser").

Numerical changes also need the Decision log entry (`wise-numeric-change`).
Performance changes need before/after timing and peak RSS.

## 3. Update the tracker

1. Append the full row to the addendum of the archive file, under a heading
   `### <ID> closed: <what> (<date>)`, with the row as it stood, the commit,
   the verification and any Decision log text. Copy; do not paraphrase away
   numbers.
2. Delete the row from the tracker, or edit it to the open remainder and mark
   it `◐`.
3. Update the batch counts in "Where things stand" (the table of open rows per
   batch) and the "Waiting on the user" list if the item was there.
4. Add one Log line at the end of the tracker, dated, in the form of the
   existing entries: id, count change, what moved, where the record is.
5. If the item closes as won't fix or deferred: set `✗`, give the reason and
   a reopen trigger, and add it to "Closed and deferred list" in the archive.

## 4. Fold a finished review into the tracker

When a review or plan is done (built, or only deferred items left):

1. Add a section to `review/TRACKING.md` (next free batch letter and number)
   named for the area, with the source file in the header, one row per item
   that is still open, deferred or owed (`☐`, `◐`, `✗` with the reason), and a
   line for decisions that are closed and not to be reopened.
2. Add its row to the batch table in "Where things stand", and a Decision log
   entry for any change that moved numbers.
3. Move the document to `review/archive/`, put "Archived <date>; open items
   are in `review/TRACKING.md` (<batch>)" under its title, re-point the
   references in code comments, tests, `ARCHITECTURE.md` and `review/README.md`,
   and add one Log line.
4. `Rscript dev/agents_check.R` and `Rscript dev/docs_check.R`.

## 5. Finish

- Skill `wise-verify` for follow-ups; `Rscript dev/agents_check.R` if you
  edited an instruction file.
- Once per batch, with the tree quiet: `devtools::document()`,
  `devtools::check()`, the full suite, and `dev/00_make_manifest.R` if
  dependencies or `R/` changed (it reads `HEAD`, so commit first).
- Commit only when asked. Show `git status` and a diff summary first.

## Report

The id, what changed (commit), the evidence (test names and counts, command
output), the tracker edits, and what was not verified.

## Traps

- Do not mark a finding closed from reading the code alone.
- Counts in "Where things stand" drift: recount from the tables.
- Reopen triggers are part of a won't-fix; without one the item is lost.
