# Test Suite Plan (slimmed)

What is left to do from `review/test_suite_review.md`, kept deliberately small: a reliable CI run, a suite that stays fast, and targeted coverage where a broken number would reach users. The original eleven-phase plan was cut down (see "Decisions" in the review, section 4).

**Do not assume the repository is still in the state described here.** Each step starts by re-checking what it acts on, and ends with acceptance criteria that can be checked.

## Status at 2026-10-07

| Item | Status |
|---|---|
| DuckDB 1.5.6 upgrade (bundle, pin, checksums, manifest) | Done (`c733a10`, `d13a585`) |
| CI-safe suite: `duckdbfs` and redundant skips removed, `make_h3_con()` skips, `setup-env.R`, workflow with `--no-tests` then `test_local()` | Done (`598027f`) |
| CI roxygen2 pinned to `RoxygenNote` (8.x rewrites NAMESPACE layout) | Done (`4b42488`) |
| httpfs loaded in the credential-test seed helper; kernel random-draw tolerance 1e-10 | Done (`70cc61d`, `fe599ae`) |
| **First green GitHub run** | **Done: run 37618324871 on `fe599ae`; green again on `bfde4bc` (run 37621899857).** 0 failed, 1 skipped, 7627 expectations. Tests step about 6m20s to 6m35s, job about 11m47s to 12m44s. The R dependency cache was restored in both runs, so there is no separate warm figure. |
| Headless-Chrome PNG test (`test-export-bundle.R:201`) skipped on CI in runs 37618324871 and 37621899857 | **Accepted.** Run 37632880820 showed 0 skips, cause not investigated. Chrome is found but "debugging port not open after 10 seconds"; `--no-sandbox` did not help and was removed. The test passes locally and the skip message now carries the reason. Revisit only if a rendering regression slips through. |
| DuckDB extension cache step | Removed. On CI duckdb stores extensions in a per-session temp dir, not `~/.duckdb/extensions`, so the cache never saved or hit; extensions download in seconds each run. |
| Step 2 cleanups 1 to 3 | Done (`6d891d3`, `336a699`, `2a69600`). Item 4 (renames) deferred: history-named files cost 0.1 to 0.7 s each, so renaming is maintainability only. |
| Step 4 speed | Done as far as it pays off. `test-step2-partials.R` 26.5 s to 18.4 s (`82d0d65`); provisional seeding test folded (`26ce151`); delta Monte Carlo draws 2000 to 1000 (`fe37654`, file 9.7 s to 6.2 s). CI: Tests step 348 s on `82d0d65` (run 37632880820, 0 skipped, 7664 expectations), job 10m08s, down from 375 s and 12m44s. Check run 37635486269 (`fe37654`) for the effect of the last two commits. |
| Step 3 coverage | Done 2026-10-07 (`9f06a2f`, `e088c82`, `3ef8a4f`, `0dc46c7`). Re-measured with `load_package = "installed"`, excluding the five process-spawning files (`step2-async`, `step2-async-daemon`, `fct-overview-metadata`, `export-bundle`, `mod-0-overview`; with them in, covr aborts on unreadable trace files): overall 82.1%. `fct_predict_outcomes.R` 73% (rest is defensive error and fallback branches), `mod_3_02` to `mod_3_05` 96 to 100%, `mod_1_08_modelfit.R` 94%, `app_server.R` covered by a new stub-wiring test (not in that run). `fct_step1_headline.R` 77% and `fct_results.R` 87% were already above target and were left alone. Full suite: 0 failed, 0 skipped, 7920 expectations; the new files add about 3.6 s. `app_server` is tested with stubbed step modules, not a synthetic data directory: the real Step 0 to 3 flow stays a browser-test item. |
| Findings from Step 3 | `predict_outcome()`: `feglm` objects have class `"fixest"` only, so `is_fixest_logistic` is never TRUE and response residuals are used, not the deviance residuals the roxygen text describes. For parsnip logistic fits with a factor outcome, the fallback residual is `as.numeric(factor) - p`, which is shifted by 1 (factor codes are 1/2). Both pinned or left as-is; not changed. |
| `R CMD check` WARNING (undocumented `@param`, R2-CQ-01) and 3 NOTEs | Open. `error-on` stays `"error"` until the WARNING is fixed. |

## Ground rules

- One step per PR. Do not mix test moves with behaviour changes.
- The suite stays green at every step. Do not fix unrelated failures inside a refactor PR; record them.
- No change to `R/` behaviour unless a step says so.
- Move a fixture into a `helper-*.R` file only when two or more test files use it.
- Do not add a test tier, a skip-helper layer, or parallel test files unless a measured problem needs it (review, section 4).

---

## Step 1 - Get CI green

**Goal:** the workflow in `.github/workflows/R-CMD-check.yaml` passes on a push to `dev`.

1. Confirm the CI-safety changes are committed. Push `dev` (confirm with the user before pushing).
2. Watch the run: `gh run list --limit 3`, then `gh run view <id> --log-failed`.
3. Triage the first real failures. Likely causes, in order of probability:
   - **Dependency install:** `duckdb == 1.5.6` must resolve from Package Manager. If it does not, check that 1.5.6 is current; as a fallback, use a dated Package Manager snapshot.
   - **`R CMD check` warnings or errors** that never ran before (the workflow tolerates warnings; `error-on: "error"`). Roughly 25 functions lack `@param` entries (tracked as R2-CQ-01 in `review/REVIEW-2026-10-06-tracking.md`).
   - **`roxygenise()` changes `NAMESPACE`**, which fails the `git diff --exit-code NAMESPACE` step. Commit a regenerated `NAMESPACE`.
   - **`h3` extension** download or version mismatch on the runner.
   - **Headless Chrome:** the PNG export test skips itself if no Chrome is found. On CI it skips (accepted, see status).
   - **Real mirai worker tests:** outside a `load_all()` session the worker runs `library(wiseapp)` from default library paths. `test_local()` uses `load_all`, so this should work; verify the two worker tests (`test-step2-async.R`, `test-fct-overview-metadata.R`) actually ran.
   - **Locale or timezone** differences from macOS. `setup-locale.R` already forces a UTF-8 character locale.
4. Look for silent skips in the CI log: the number of skipped tests should be near zero. A drop in test count versus the local run means something skipped.
5. Record cold and warm run times.

**Acceptance:**
- The workflow is green, or red only on failures listed in the PR as pre-existing.
- CI log shows about 1067 tests and no unexpected skips.
- Test step ≤ 8 minutes; whole job ≤ 15 minutes cold and ≤ 10 minutes warm. If it is slower, do Step 4 for the slowest files only.
- Once warnings are fixed, tighten `error-on` to `"warning"`.

---

## Step 2 - Small cleanups (optional, low risk)

Each is one commit. Re-verify each candidate before acting.

1. **Remove the three Shiny-semantics tests** in `test-rerun-regressions.R` ("passing a reactive's value to observeEvent deafens it...", "passing the reactive itself keeps the dependency alive", "ignoreInit swallows the first click..."). Keep the explanation of the mechanism as a short comment beside the relevant helper in `R/` (comment-only `R/` edit is allowed). Before deleting, run the file with and without them and confirm no `R/` line loses coverage:
   `covr::file_coverage()` or `covr::package_coverage(type = "none", code = ...)` on the source `tests/` directory (not `type = "tests"`).
2. **Merge the two export-key scanners** (`test-export-wiring-contract.R`, `test-csv-export-wiring-contract.R`) into one source-contract file with one scanner covering every button helper. Keep an `expect_gt(length(files), 0)` guard so an empty scan fails.
3. **Move `make_regtable_df` tests** from `test-table-csv-export.R` to the `fct_results` tests.
4. **Rename history-named files** only as a pure `git mv` in its own PR, at a time with no open branches editing tests. Rule: a file that mainly covers one `R/` file is named `test-<stem>.R` (for example `test-fct-outcome.R` to `test-fct_outcome.R`). Skip this step if it causes rebase pain.

**Acceptance:** the pass count drops only by the removed tests; per-file coverage of `R/` does not drop.

---

## Step 3 - Close priority coverage gaps

Do one target file per PR, spread over time. Re-measure first:

```r
# Source-tree coverage; excludes real-worker test files (their traces corrupt covr).
covr::package_coverage(type = "none", code = 'testthat::test_dir("tests/testthat", stop_on_failure = FALSE, load_package = "none")')
```

Priority order (targets are guides, not gates; stop when what is left is presentation-only or defensive):

1. `R/fct_predict_outcomes.R` (38% at review time, 164 lines): unit tests per engine in `ENGINE_REGISTRY` and per outcome transform (identity, log back-transform, logistic probability). Target 80% or more.
2. `R/mod_3_02_infra.R`, `mod_3_03_digital.R`, `mod_3_04_labor.R`, `mod_3_05_education.R` (about 5% each): one `testServer()` per module asserting the returned scenario object for the default state and one non-default lever setting, and that a lever is inactive when its variable is missing from `variable_list`. Target 60% each.
3. `R/mod_1_08_modelfit.R` (0%): `testServer()` with a fixture model; diagnostics outputs render and a missing or failed fit is handled. Target 50%.
4. `R/fct_step1_headline.R`: re-measure (new tests were added since the review). Add hand-computed fixtures for log-outcome and binary-outcome paths if still below 70%.
5. `R/app_server.R` (0%): a `testServer(app_server, ...)` wiring test against a synthetic local data directory (`WISEAPP_DATA_SOURCE=local`). It asserts that Step 0 publishes a non-empty survey list and Step 1 receives it. If `testServer(app_server)` hits session-only code, mock the specific binding rather than changing app code, and record the limit.
6. `R/fct_results.R`: only branches that compute user-visible numbers (coefficient tables, translations).

Rules: tests go in `test-<R file>.R`; assert on values and returned objects, not rendered HTML; keep the full suite time from growing by more than a few seconds per PR.

---

## Step 4 - Speed (only if Step 1 shows a problem)

Trigger: the CI test step exceeds about 8 minutes, or a local run exceeds about 4 minutes.

1. Re-time per file to find the slow ones (the review-time list is stale):
   ```r
   r <- as.data.frame(testthat::test_dir("tests/testthat", reporter = "silent", stop_on_failure = FALSE))
   aggregate(real ~ file, r, sum) |> (\(d) d[order(-d$real), ])() |> head(10)
   ```
2. For the top few files, build expensive fixtures (fitted models, Step 2 or Step 3 pipelines, weather parquet directories) once per run in a helper with a visibly named `fixture_*()` function, memoised in a package-private environment. Fixtures are read-only by convention; tests that mutate copy first.
3. At review time the slowest files were `test-policy-sim-compare-agg-cache.R`, `test-fct_get_weather.R`, `test-step2-payload.R`, `test-fct-overview-metadata.R`, `test-export-bundle.R`. The last two are slow because they start a real worker or headless Chrome; do not "fix" those, they are meant to be real.
4. Only if still too slow after memoising: consider an explicit skip for the real-process tests locally, controlled by one environment variable, always on in CI.

**Acceptance:** same pass count; same per-file coverage; measurable time drop.

Wider speed options, if more is wanted after memoising (in this order; each needs the per-file timing from item 1 and the coverage check from Step 2):

- Consolidate near-duplicate tests (the duplicated fixture families in the review, M1) so a fixture is built once.
- Drop non-essential tests only where the coverage method shows no `R/` line loses coverage and no distinct behaviour is pinned.
- Speed up the slowest remaining tests by shrinking inputs (rows, draws, years) without changing what is asserted.

Findings from the 2026-10-07 speed pass (do not repeat this work):

- The suite is dominated by real computation (pipelines, Results-module drives, real mirai workers, headless Chrome). The 76 tests of 1 s or more hold about 218 of 336 s locally; no single test is over about 4 s standalone.
- Fixture builders in `test-policy-sim-compare-agg-cache.R` cost about 0.00 s each, and `.pv_run()` is built once in the provisional file, so memoised `fixture_*()` helpers would save nothing there.
- Local timings are noisy (load average 5 to 11 from other apps); `test-fct_get_weather.R` took 57 s in one full run but 19 to 20 s alone and after the 19 files before it. Use standalone before/after per file, and CI for suite totals.
- The gc test in `test-fct_get_weather.R` calls `gc()` only twice; it is not a gc cost.
- Parked, small: share one `get_weather()` result among the `cross_res_cmip6` tests (about 2 s); merge per-method delta Monte Carlo tests (saves about 0.1 s, not worth it).
- The history-named files from the review are 0.1 to 0.7 s each; removing them saves no time.
- The Monte Carlo in `test-fct_aggregation_delta.R` is a brute-force oracle (`mc_se()`) for the live delta-method path, not legacy app code.

CI reference: Tests step 348 s (about 6 min) on `82d0d65`. Step 3 additions should stay within a few seconds each.

---

## Backlog (do only if a concrete need appears)

| Item | When it is worth doing |
|---|---|
| Shared fixture helpers (`helper-fixtures-*.R`) for all duplicated builders | When fixture drift causes a real bug, or Step 4 needs it. |
| `shinytest2` end-to-end tests (boot smoke; golden path by config import; one `conditionalPanel` visibility check) | After CI is stable and a browser-only regression recurs. Keep to 2 or 3 tests. Needs `shinytest2` in `Suggests`, `shiny::exportTestValues()` hooks in `app_server`, and a synthetic data-directory helper. |
| App verbosity option (`wiseapp.verbose`) to silence progress messages in tests | When log noise hides real warnings. It is an `R/` change; keep it in its own PR. |
| Hygiene sweep (`library()` calls, `wiseapp:::` prefixes, `set.seed()` to `withr::local_seed()`, `expect_true(identical(...))`) | Only in files touched anyway. No repo-wide churn commit. |
| `tests/spelling.R` | Keep non-blocking or delete; add `inst/WORDLIST` if kept. |
| Coverage report job in CI | If wanted; make it non-blocking and upload as an artifact. |
| Coverage ratchet (fail if overall coverage drops more than 1 point) | After the Step 3 gaps are closed. |

---

## Documentation (at the end)

- Update the **Testing** section of `AGENTS.md`: test-file count; the env pinning in `setup-env.R`; "run the suite from the source tree" (`devtools::test()` or `testthat::test_local()`, as CI does); the rule that a fixture becomes a helper when two or more files use it.
- When this plan is finished, move `review/test_suite_review.md` and this plan to `review/archive/`, matching existing practice.

## Risks

| Risk | Mitigation |
|---|---|
| First CI run reveals many `R CMD check` warnings | `error-on: "error"` is already set; list the warnings in an issue and tighten later. |
| `h3` extension download fails on the runner | The fixture skips with a message. |
| Silent skips make CI look greener than it is | Compare the CI test and skip counts with a local run. |
| Memoised fixtures leak mutations between tests (Step 4) | Fixtures are read-only by convention; mutate copies. |
| Rename PRs conflict with feature branches | Pure `git mv`, at a quiet point. |
