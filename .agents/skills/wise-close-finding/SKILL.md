---
name: wise-close-finding
description: >
  Close an item of the review remediation tracker (review/REVIEW-tracking.md):
  the evidence a finding needs, the commit convention, and how to move the row
  to the archive, update the counts and add the Log line. Also covers closing as
  won't fix or deferred.
when_to_use: >
  When the user asks to fix, close, defer or drop a review finding by id (for
  example CR-CQ-01, R2-PERF-01), or to update the tracker after finishing one.
user-invocable: true
allowed-tools: Read Grep Glob Edit Bash
argument-hint: "[finding id, e.g. R2-PERF-01]"
---

# Closing a review finding

Open work is in `review/REVIEW-tracking.md`. The findings text is
`review/archive/REVIEW-2026-10-06.md` (immutable: read it by id, never edit it). The
record of finished work is `review/archive/REVIEW-2026-10-06-tracking-full.md`.
The tracker's "Working rules" are the authority; this skill is the procedure.

Status marks: `☐` todo, `◐` in progress (the open remainder is listed), `✗`
won't fix or deferred (the reason is given).

## 1. Before the work

- Read the row and the finding text (`grep -n "<ID>" review/archive/REVIEW-2026-10-06.md`).
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

## 4. Finish

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
