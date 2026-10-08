# CR-PERF-04 plan: Step 3 off the main thread

Status: Phases 0 to 2 implemented (2026-10-08); Phase 3 open; browser check and `manifest.json` regeneration (it is built from `git archive HEAD`, so it needs a commit first) pending. Owner: tracker row CR-PERF-04 (`review/REVIEW-2026-10-06-tracking.md`).

## Results so far (BFA, OLS, 2x2, uncertainty off, local laptop)

Phase 0 (probe sourced from `dev/bench_step3_helpers.R` via `WISEAPP_STEP3_PROBE_SCRIPT`):

| Measurement | Value |
|---|---:|
| Step 2 artifact on disk / write / read + unshare | 178 MB / 1.3 s / 0.52 s |
| Policy run artifact on disk / write / read | 216 MB / 1.6 s / 0.84 s |
| Metric decomposition (mean) in process | 15.0 s |
| Same, on the qs2 round-tripped run | 15.6 s, `summary` and `annual` identical |

Findings that changed the design:
- qs2 keeps environment locks and shared references, so the annual-channel and context environments arrive locked and still point at each other. It does **not** keep the identity of `.decomposition_context_owner` (an environment used as a token), so every deserialised run failed `.validate_run_decomposition_context()` ("unavailable"). Fix: the marker is now compared by an `id` field (`.is_decomposition_context_owner()`), not by identity. No rehydration step is needed; `step3_validate_worker_run()` only checks what arrives.
- mirai daemons use `L'Ecuyer-CMRG`. The seeded targeting draws differed from the in-process run until the worker applied the submitter's `RNGkind()`. (`step2_compute()` already pins its RNG kind; the Step 3 worker now does the same.)

Phase 1 (real daemon, `step3_async_submit()`; probe `probe_phase1.R`): the policy-arm histories, scenarios, decomposition scenarios, diagnostic summary and policy survey are `identical()` to the in-process `step3_compute()`. Wall time 23.9 s through the worker against 13.3 s in process (daemon cold start, artifact read, result write and read-back); the main thread is free during the run and blocked only for the read-back (about 1 s at 2x2). Peak worker RSS was not captured (the `pgrep` sampling matched the wrong process); measure it in a real session before the Connect memory limit is chosen.

Stage timings (BFA 2x2, laptop, `probe_phase1b.R`): in-process run 13.3 s; through the shared daemon 21.7 s cold and 16.6-17.7 s warm. Worker read 0.6-1.2 s, compute 12.8-13.8 s, write 1.5-1.7 s, main-thread read-back 0.9-1.1 s; the cold run adds about 4 s (daemon start and `pkgload::load_all()` in dev mode; a session that already ran Step 2 has a warm daemon, and the deployed app uses `loadNamespace()`, not measured). Decision (user, 2026-10-08): accept the roughly 3 s of artifact I/O as the price of a free main thread.

Phase 2 (implemented 2026-10-08): the Step 3 result file is retained (`computed$artifact`, owned by `mod_3_06_policy_sim.R`, removed on replacement and at session end) and `step3_metric_worker()` reads it together with the retained Step 2 artifact. The `metric_decomposition` reactive in `.wire_results_pane()` (`R/fct_policy_sim_compare.R`) submits a job per cache key (`method`, poverty line, residuals, focus, unit, series) and returns an "unavailable" result with the reason "Computing the decomposition in the background..." until the job stores its result and `metric_job_tick` fires. It falls back to the in-process computation when either artifact is missing or `WISEAPP_ASYNC_STEP3=0`. Measured (BFA 2x2): metric job 16.5-17.5 s wall against 15.9 s in process, `summary` and `annual` identical. The worker starts with empty validation caches, so the warm-cache saving of the second metric in the in-process path (3x3: 35.2 s then 22.4 s) is lost; not measured at 3x3. Not seen in a browser: how the Results pane renders the computing state.

Deviations from the plan below: the existing disabled "Run" button (`sim_running`) is kept instead of `input_task_button()`; progress uses `shiny::Progress` fed from the worker's progress file.

## Goal and scope

Remove the long main-thread freezes in Step 3. Decided scope (2026-10-08): Step 3 only (the policy run and the metric decomposition). Step 2 stays as it is. Design option (b): a separate Step 3 runner on the shared mirai pool, with `input_task_button()`. Shared lifecycle helpers are extracted from the Step 2 coordinator only after Step 3 shows which parts it shares. No general framework first.

Local BFA 3x3 baseline (tracker, "Local measurements"):

| Blocking step | Where | Time |
|---|---|---:|
| Policy run (`apply_policy_delta_to_baseline()` and `.build_decomposition_context()`) | `run()` in `R/mod_3_06_policy_sim.R` | 33.8 s |
| First metric decomposition (mean) | `metric_decomposition` reactive, `R/fct_policy_sim_compare.R:2632` | 35.2 s |
| Second metric (headcount ratio), warm context caches | same | 22.4 s |

## What the code does today

- `run()` executes in the Shiny process inside `withProgress()`. It reads `hs` (the Step 2 `hist_sim`) and `ss` (the saved scenarios), builds the policy survey, the decomposition context and the annual channels, then publishes about 20 reactive values in one block (INT-09 atomic publish).
- The policy arm (`pol_out$hist_sim`, `pol_out$saved_scenarios`) has the same shape and size as the Step 2 result. The `annual_channels` value is an environment (`prepared`) that carries `context`, `run_identity` and run-owned caches.
- `metric_decomposition` is a reactive in the Results module code. It calls `.policy_metric_decomposition(baseline_hist, policy_hist, baseline_scenarios, policy_scenarios, prepared, method, ...)`. It memoises up to six results per run in `metric_cache()`. Only small tables escape (`annual`, `summary`, `return_period`, `mechanisms`, `scenarios`).
- The Step 2 coordinator (`R/fct_step2_async.R`, 1,178 lines) is process-wide: a FIFO queue, one daemon, an artifact directory per job (qs2), a progress file, a retire marker, a publication lock and session detach. After a Step 2 result is adopted, `.wise_step2_async_cleanup_job()` deletes the artifact directory, so the Step 2 result exists only in the Shiny process.
- Metadata loads (`R/fct_overview_metadata.R:91`) show the lightweight pattern on the same pool: `mirai::try_mirai()` with `.compute = "default"`, `promises::then()`, a retry with `later::later()` when the dispatcher memory cap returns NULL, and a timeout from `.wise_step2_async_timeout_ms()`.

## Core design problem: getting the Step 2 result to the worker

The worker needs `hist_sim` and `saved_scenarios` (up to 1.16 GB in memory at 3x3, 428 MB on disk). Passing them as `try_mirai()` arguments serialises about 1-2 GB through a dispatcher whose queue cap is `WISEAPP_ASYNC_QUEUE_MEMORY_MB` (512 MB), and it holds a second copy in the main process while it does so. So:

- **Decision 1: the worker reads the result from disk.** Keep the Step 2 `result.qs2` artifact for the life of the adopted result (same session-lifetime cleanup as the weather store lease) and pass the path. Step 3 jobs then send only small inputs: the policy configs, the survey frames, `model_fit` (slimmed), `so`, seed, run id and the artifact path. The artifact is already checksummed and signature-checked by `.wise_step2_async_read_manifest()`; the Step 3 worker repeats the check against the Step 2 signature.
- Cost: up to 428 MB of temp disk per session at 3x3 until the next Step 2 run or session end. Needs a statement in the deployment notes (the artifact root already honours `WISEAPP_ASYNC_ARTIFACT_ROOT`).
- Cost: `hist_sim` objects are modified in the main process after adoption in places (labels, `sim_summary`, `.sig`; `mod_2_01_weathersim.R:1145-1152`). Those edits are small; the worker artifact is the pre-edit object, so the Step 3 worker must re-apply only what the run reads (`so`, `residuals`, `.sig`, `hist_label`). Verify by the parity gate below, not by assumption.

## Phase 0 - measure before building (half a day)

1. Peak RSS of the Shiny process and the daemon together for a BFA 3x3 Step 2 run followed by a Step 3 run, with the Step 3 run in the main process (today) and with a stub worker that only reads `result.qs2`. This answers the open question in the tracker ("memory split between the worker and the Shiny process in a real session").
2. Time `qs_read` of the artifact inside the worker (expected 1.2 s plus unshare) and the return trip of the policy artifact (`pol_out`, about the same size as Step 2 at 3x3).
3. Go/no-go: if worker plus Shiny RSS at 3x3 exceeds what the Connect host allows (8 cores, 31 GiB, 4 processes), pick the lazy variant (the worker returns only the summaries and the policy arm stays on disk; the main process reads policy pipelines per scenario on demand). That decision changes Phase 2, not Phase 1.

## Phase 1 - the policy run in a worker (the 33.8 s step)

Files: new `R/fct_step3_async.R`; edits in `R/mod_3_06_policy_sim.R`, `R/mod_3_scenario.R`, `R/fct_step2_async.R` (artifact retention only).

1. **Pure compute function** `step3_compute(input, hist_sim, saved_scenarios, ...)` in `R/fct_step3_async.R` holding the body of `run()` between "apply_policy_to_svy" and `.policy_diagnostics_snapshot()`. It returns plain data: `svy_mod`, `decomp_context`, `pol_out`, `diagnostic_summary`, `policy_sig`, `n_na_untreated`. No Shiny, no reactives. `run()` calls it synchronously first (step 1a, no behaviour change), so the sync path stays the reference.
2. **Step 3 worker** `step3_async_worker(snapshot, step2_artifact, ...)`: loads the namespace as in `.wise_step2_async_dispatch()`, reads the Step 2 artifact, calls `step3_compute()`, writes `result.qs2` plus a manifest (same atomic-rename and signature pattern as `step2_async_worker()`), returns the manifest.
3. **Submit and adopt.** A small coordinator in `R/fct_step3_async.R` using `mirai::try_mirai()` on `.compute = "default"`, `promises::then()`, the existing timeout helper (new kind `"step3"`, env `WISEAPP_ASYNC_STEP3_TIMEOUT_MIN`, default 90), retry on NULL (dispatcher cap), and `.wise_step2_async_describe_error()`. Jobs share the one daemon, so a Step 2 run and a Step 3 run queue behind each other (the dispatcher serialises them); the UI shows "queued" for Step 3 when Step 2 is active.
4. **Adoption** reads the artifact on the main thread (`qs_read` plus `step2_unshare_constants()`), then performs the existing atomic publish block unchanged (INT-09). A generation check (`run_generation()`) discards a result whose generation or `policy_signature` no longer matches (INT-08), the same way Step 2 does.
5. **UI.** `input_task_button()` replaces the plain action button in `mod_3_scenario`; `sim_running` stays the single guard (REACT-02). A failed or cancelled job leaves the previous published results intact (INT-09 already guarantees this because publish happens only on adoption). Cancel on session end and on input change reuses the retire-marker pattern (see Phase 3 for what is shared).
6. **Progress.** Worker writes a progress file (phases: prepare, context, correction, diagnostics); a poll with `later::later()` updates `withProgress`-free status text. Keep it to four phases; no partials.

Gate (guidelines section 9): worker result bit-identical to the synchronous path on the `targeted_sp` and `covariate` fixtures (the `dev/bench_step2.R` harness already checks the optimised annual path against the reference with max abs difference 0). Before/after: Step 3 run main-thread blocked time (target under 1 s: snapshot build plus adoption read), total wall time, peak RSS of both processes.

Tests (`tests/testthat/test-fct_step3_async.R`): compute parity sync vs worker (using `WISEAPP_ASYNC_SYNC=1` and a real daemon in separate tests), stale-generation result discarded, failed job keeps previous results, cancel on session end, artifact retention and cleanup, credentials never in the snapshot.

## Phase 2 - the metric decomposition (the 35 s and 22 s steps)

The decomposition re-runs member x year work from the prepared annual channels (`prepared`, an environment with run-owned caches) and the policy pipelines. Its inputs are the Phase 1 outputs, so the worker can compute it only if it holds them.

- **Option A (recommended): compute the default metric inside the Phase 1 job, and run other metrics as small follow-up jobs on the same worker artifacts.** The worker keeps the Phase 1 results on disk (policy arm artifact). Each metric job reads the policy artifact plus the Step 2 artifact and `prepared` (serialised once at the end of Phase 1; verify that the environment and its closures round-trip through qs2), calls `.policy_metric_decomposition()`, and returns the small tables. The main-thread `metric_decomposition` reactive becomes a cache lookup keyed as today (`method`, `pov_line`, residuals, focus, unit, series) plus a "computing" state that the Results pane renders as a spinner.
- **Option B: keep a persistent worker state** (the daemon holds the loaded results in a global between jobs). Faster per metric (no re-read) but ties a session to one daemon, which breaks with one shared daemon and several sessions. Not recommended.
- The six-entry per-run cache stays on the main thread (results are small). The `validated` environment is per-worker-job, so repeated metric jobs lose the 35 s to 22 s warm-context saving unless the job also persists it; measure in Phase 0 whether that matters (Option A job time on a warm filesystem cache).

Open risk: `prepared` may hold references that do not serialise (external pointers, environments with `lockBinding`). Phase 0 includes a round-trip test of `prepared` through `qs2`.

Gate: metric tables bit-identical to the in-process result for `mean` and `headcount_ratio` on the fixtures; Results tab stays usable (no input lag) while a metric computes.

## Phase 3 - extract shared lifecycle helpers

Closed 2026-10-08 without a refactor: the Step 3 runner calls the Step 2 helpers directly (`.wise_step2_async_init()`, `_ensure_daemon()`, `_timeout_ms()`, `_describe_error()`, `_artifact_root()`, `_write_control()`), so nothing is duplicated. What differs (retire marker, publication lock, partials, FIFO queue) is Step 2-specific and Step 3 does not need it, because the button guard (`sim_running`) allows one run at a time and the daemon queues jobs. Renaming the `.wise_step2_async_*` helpers to a neutral prefix would be churn with no behaviour change; do it only if a third consumer appears. Original note kept below.

Only after Phases 1 and 2 run. Candidates seen in `R/fct_step2_async.R`: the module-level state and queue, `.wise_step2_async_ensure_daemon()`, timeout and error description, artifact root, the retire-marker and publication-lock protocol, session detach. Move a helper to a shared name only if both coordinators call it with the same arguments. Do not rename the Step 2 functions in the same commit as any behaviour change.

## Folded in or affected

- CR-SEC-07 (per-run size limits, queue cap by bytes): the Step 3 job adds a size check on the artifact path and the input snapshot; the by-bytes queue cap stays the dispatcher memory cap.
- R2-PERF-01 (shrink the Step 2 result): the lazy per-member `weather_raw` read becomes possible once the Step 3 worker owns the read. Separate follow-up; not part of this plan.
- `hist_sim_result$svy` fallback (R2-PERF-01 note): the worker reads `svy` from the artifact, so the main-thread `hs$svy` read in `run()` disappears; the other consumers (`mod_2_02_results.R:688`, `mod_3_01_sp.R:165,1053`, `fct_sim_compare.R`) are unchanged.

## Order of work and commits

One branch off `dev`, one commit per step, finding ID in the subject:

1. Phase 0 measurements (scratch scripts; numbers go in the tracker).
2. `step3_compute()` extracted, `run()` calls it synchronously (CR-PERF-04 step 1a). Existing tests must pass unchanged.
3. Artifact retention for the adopted Step 2 result.
4. Step 3 worker, coordinator and tests behind `WISEAPP_ASYNC_STEP3` (default on; `0` restores the synchronous path).
5. UI wiring (`input_task_button()`, queued and failure states).
6. Phase 2 decomposition jobs.
7. Phase 3 helper extraction.
8. Tracker update, `devtools::document()`, full suite once, `manifest.json` regeneration.

## Not in scope

Step 1 weather and fits, exports, XGBoost, general job framework, changing numerics. A Step 3 result that differs from the synchronous result by any amount is a bug, not a decision-log entry.
