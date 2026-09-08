# Step 2 Scalable Optimization Plan

**Status:** Review plan only; no implementation changes are included.

**Scope:** Step 2 weather loading, simulation pipelines, result retention,
aggregation, diagnostics, and the Step 3 consumers of Step 2 results.

**Primary objectives:**

1. Keep small and large workloads correct and usable.
2. Reduce peak memory before considering concurrency.
3. Make long runs non-blocking without changing scientific behavior.
4. Improve throughput only where production-representative measurements justify
   the added complexity.

## 1. Governing Principles

These principles come from `review/profiling_optimization.md` and apply to
every phase below.

- **Separate responsiveness from throughput.** A run that does not block the
  Shiny session is a valid improvement even when the serial compute time is
  unchanged.
- **Preserve the serial reference.** Keep the current synchronous path as the
  correctness oracle until a replacement has passed characterization and
  equivalence tests.
- **Measure before restructuring.** Do not introduce process parallelism,
  chunking, SQL rewrites, or result-contract changes based on object-size
  estimates or isolated microbenchmarks.
- **Use shared core, thin adapters.** Computational functions must not read
  reactives, depend on Shiny session state, hold live database connections, or
  emit UI side effects.
- **Define stable contracts.** Required columns, types, ordering, scenario
  keys, failure-ledger shape, result signatures, and optional payloads must be
  explicit before extraction or storage changes.
- **Validate at boundaries.** Validate data keys, scenario-period compatibility,
  model/simulation signatures, row alignment, and finite values once at the
  public compute boundary.
- **Preserve failure semantics.** Historical failure remains fatal; a partially
  failed ensemble remains publishable only with its failure ledger and
  requested/succeeded counts.
- **Do not infer physical duplication from `object.size()`.** `train_aug` is
  precomputed once and referenced by multiple pipelines. Use process RSS,
  serialization size, and a deduplicating object-size tool when available.
- **Do not weaken exactness after observing differences.** Define exact or
  field-level tolerance rules before comparing implementations.

## 2. Current Evidence

The measured local LKA workload contained:

- 42,296 household observations.
- 40,142 complete model rows.
- 53,304 historical weather rows.
- Two weather variables.
- One SSP and one projection period.
- Eighteen successful future model keys plus historical.

Measured results:

| Measure | Result |
|---|---:|
| Total Step 2 elapsed time | 8.26 s |
| Weather loading | 3.70 s |
| Sum of per-key pipeline times | 1.14 s |
| Median per-key pipeline time | 0.055 s |
| Peak RSS | 1.42 GB |
| In-memory result object | 542 MB |
| Serialized result | 613 MB |

The result indicates:

- Weather loading is the largest measured timed stage on this workload.
- Per-key prediction and factor-loading work is not currently the dominant
  elapsed-time cost.
- Retained result payloads, especially per-model weather and household-level
  matrices/vectors, are the primary scalability concern.
- Display aggregation is currently inexpensive relative to weather loading and
  pipeline execution.
- PERF-02 is complete and should not be reopened unless a larger profile shows
  that climate-reference work remains material.
- PERF-15 remains deferred until a larger profile proves that design-matrix
  construction materially contributes to either CPU time or peak memory.

Local data provides useful workload candidates:

- LKA: approximately 42k household rows.
- Iran: approximately 306k household rows.
- India: approximately 676k household rows.

The exact largest supported production workload must be confirmed before final
latency and memory gates are set.

## 3. Phase 0: Establish Constraints

**Owner:** performance implementer with deployment owner input.

**Deliverable:** a short dated decision record before code restructuring.

### 3.1 Recover prior parallel-work evidence

Inspect the commits and available logs for the removed Step 2 parallel path.
Classify the failure as one or more of:

- process or cgroup OOM;
- aggregate RSS growth;
- swap or memory pressure;
- excessive input/output serialization;
- cache contention;
- worker lifecycle failure;
- negative speedup;
- deployment incompatibility.

Do not repeat the same topology before recording why it failed.

### 3.2 Confirm the deployment envelope

Record:

- R and locked package versions;
- Posit Connect R version and process limits;
- whether limits apply to the parent only or the complete process tree;
- CPU entitlement and effective core count;
- expected concurrent active sessions;
- timeout, reaping, restart, and deployment behavior;
- child-process support;
- whether `ExtendedTask`, `mirai`, and the deployed Shiny version support the
  intended workflow.

### 3.3 Confirm data and cache constraints

Verify:

- each worker can create and close its own DuckDB connection;
- live connections are never serialized;
- weather cache writes are atomic;
- concurrent cache misses for one key are safe and idempotent;
- credentials are acquired in the process that needs them and never logged or
  serialized;
- the session cleanup path removes process-wide resources after the final
  session.

### 3.4 Select representative workloads

At minimum, benchmark:

1. LKA or another typical country.
2. Iran or the largest supported country that can run locally.
3. India or the largest available stress workload, if feasible.

Each workload must record country identity, selected surveys, household count,
complete-case training count, selected weather variables, model engine, model
terms, historical date count, SSP count, period count, successful key count,
cache state, seed, package revision, and machine limits.

## 4. Phase 1: Build the Baseline Harness

**Do not edit production compute code before this harness exists.**

Create a development-only benchmark harness under `dev/` following the existing
benchmark conventions. It must call core functions directly outside Shiny and
must use explicit inputs, seeds, and cache-state controls.

### 4.1 Required workload matrix

For each representative country, run:

- historical only;
- one SSP × one projection period;
- three SSPs × three projection periods, where local data supports it;
- coefficient uncertainty disabled;
- coefficient uncertainty enabled;
- OLS path;
- RIF path when the selected model supports it;
- warm weather cache;
- cold weather cache when feasible.

### 4.2 Required measurements

Record:

- end-to-end Step 2 elapsed time;
- weather-load elapsed time;
- per-key elapsed time and distribution;
- survey-weather join time;
- prediction time;
- design-matrix and factor-loading time;
- result assembly time;
- display aggregation time per method;
- Step 3 policy/decomposition elapsed time;
- parent process peak RSS;
- complete process-tree peak RSS;
- serialized input and output sizes;
- result object size with and without deduplication;
- CPU utilization and effective core use;
- weather cache state and hit/miss counts;
- number and size of retained `weather_raw` objects;
- number and dimensions of retained `F_loading` matrices;
- number of model keys requested, succeeded, and failed.

Use `/usr/bin/time -l`, container/cgroup metrics, or the deployment-equivalent
measurement for process-tree RSS. R `gc()` deltas are diagnostic only and must
not be used as the production memory gate.

Use multiple repetitions and report medians and spread. A single run is not a
decision.

### 4.3 Required benchmark outputs

Produce a compact report containing:

- workload definition and environment metadata;
- stage-time breakdown;
- per-key size and latency distribution;
- memory timeline and peak RSS;
- serialization cost;
- cold/warm cache comparison;
- candidate bottlenecks ranked by measured contribution;
- an agreed wall-clock target;
- an agreed per-session and concurrent-session memory envelope.

## 5. Phase 2: Characterize the Existing Contracts

Add characterization tests before changing the result shape or orchestration.
The serial implementation remains the reference.

### 5.1 Step 2 result contract

Document and test the top-level fields:

- `hist_sim_result`;
- `new_scenarios`;
- `chol_obj`;
- `n_keys`, `n_keys_ok`, and `total_runs`;
- `t_elapsed` and `t_weather`;
- `failures`.

Document and test the historical and scenario fields, including:

- `pipeline` or `pipelines`;
- `weather_raw`;
- `train_data`;
- `so`;
- `chol_obj`;
- `year_range`;
- model requested/succeeded counts;
- residual mode;
- scenario and run signatures.

### 5.2 Per-pipeline contract

The per-pipeline fields currently include:

- `y_point`;
- `F_loading`;
- `sim_year`;
- `weight`;
- `id_vec`;
- `id_col`;
- `svy_row_id`;
- `n_pre_join`;
- `weather_raw`;
- `train_aug`.

Pin:

- vector lengths and matrix row alignment;
- row ordering;
- factor-loading column ordering against coefficient names;
- behavior for missing predictors and unknown fixed effects;
- residual modes;
- historical versus future key ordering;
- partial-key failure behavior;
- deterministic output under repeated runs.

### 5.3 Consumer inventory that must remain valid

Before removing or externalizing any payload, test these consumers:

- Step 2 Results aggregation and coefficient bands;
- Step 2 Diagnostics weather panels;
- Step 3 policy resimulation and policy decomposition;
- Step 3 model-specific inter-model spread;
- Step 3 scenario-year decomposition;
- exports and provenance metadata;
- stale-result and signature checks.

The most important constraint is that Step 3 currently uses each CMIP6
member's own `weather_raw`. Replacing all member weather with a representative
weather frame would silently change inter-model spread and is not acceptable.

## 6. Phase 3: Extract a Pure Serial Compute Entry Point

Extract an explicit Step 2 compute entry point before introducing asynchronous
execution or key-level workers.

The entry point must:

- accept an immutable ordinary-object input snapshot;
- accept no reactive reads or Shiny session objects;
- accept no live DuckDB connection;
- set RNG kind and seed explicitly;
- initialize process-local package, DuckDB, extension, cache, and credential
  state explicitly;
- return ordinary serializable objects or stable references;
- emit structured stage events rather than requiring `withProgress()`;
- preserve canonical key ordering and failure-ledger semantics;
- attach run/schema/signature metadata.

Keep the existing `fct_run_simulation()` path as the serial adapter initially.
The extracted entry point must reproduce:

- values;
- row ordering;
- warnings and errors;
- partial-failure behavior;
- requested/succeeded key counts;
- timestamps and scenario labels;
- deterministic output for the same seed and environment.

## 7. Phase 4: Reduce Serial Memory and Payloads

Run this phase before key-level parallelism. The goal is to reduce peak memory
and retained results without changing the science.

### 7.1 Separate shared metadata from per-key data

Move values that are logically shared from individual pipeline entries to a
shared historical/scenario context:

- `train_aug`;
- `id_col`;
- residual mode and residual lookup metadata;
- `chol_obj`;
- model and run metadata.

This improves the contract and may reduce serialization overhead. Do not claim a
large RSS reduction until measurements prove one; shared R references already
avoid much of the physical duplication.

Update aggregation to accept shared residual context explicitly while preserving
backward-compatible adapters during migration.

Parity requirements:

- residuals `none`, `original`, `normal`, and `resample`;
- weighted and unweighted aggregation;
- historical and scenario paths;
- Step 3 baseline/policy contrasts;
- deterministic residual matching by household ID.

### 7.2 Make diagnostics payloads explicit

Separate normal simulation data from optional diagnostic data.

Default simulation payload should retain only what Step 2 Results and Step 3
require. Diagnostic payload should be requested or retained explicitly.

Possible designs, to benchmark in this order:

1. Retain the representative scenario weather at the scenario level and keep
   per-model weather in a diagnostics-only field.
2. Retain compact per-model weather columns containing only the keys and
   variables required by Step 3.
3. Store per-model weather in a session/run-scoped DuckDB table or disk cache
   and retain a run/key reference instead of the full data frame.

The third design requires lifecycle cleanup, run-signature invalidation,
session ownership, worker restart behavior, and explicit fallback behavior. It
must not leave stale or cross-session weather data.

Parity gates:

- inter-model spread unchanged;
- Step 3 policy decomposition unchanged;
- scenario-year decomposition unchanged;
- diagnostics either unchanged or explicitly unavailable with a visible
  contract/status message;
- exports and stale-result behavior unchanged.

### 7.3 Reduce factor-loading retention only after consumer analysis

`F_loading` is needed for analytic coefficient uncertainty. It is not needed
when coefficient uncertainty is disabled and should remain `NULL` in that mode.

For enabled uncertainty, investigate a sufficient-statistics result contract:

- compute per-year aggregate gradients `F_agg` during or immediately after
  pipeline processing;
- retain coefficient variance and any required uncertainty summaries;
- retain the rowwise summary required by the headcount-ratio bandwidth logic;
- release full `N x K` matrices when no downstream consumer needs them.

Do not remove full `F_loading` until all consumers are covered, including:

- Step 2 Results coefficient bands;
- Step 3 comparison;
- policy decomposition;
- diagnostics variance breakdown;
- headcount bandwidth calculation;
- any export path.

Compare the compact and full contracts on exact values or pre-approved
field-level tolerances. The central estimates must remain exact.

### 7.4 Avoid unnecessary weather copies

Measure and reduce, where safe:

- weather result plus `weather_per_key` references;
- `weather_raw` retained in pipelines plus scenario representative weather;
- joined `survey_wd_sim` and prediction-frame copies;
- full weather columns passed into diagnostics when only selected variables are
  needed;
- repeated R-side materialization of period/model slices.

Do not remove a copy solely because it looks redundant. Confirm aliasing,
copy-on-write behavior, Step 3 use, and RSS impact.

## 8. Phase 5: Optimize Weather Loading

Only pursue candidates supported by the Phase 1 stage breakdown.

Profile and record separately:

- source weather reads;
- H3 harmonization;
- location aggregation;
- rolling windows;
- climate-reference construction;
- CMIP6 baseline overlap;
- perturbation/delta calculations;
- period rolling and transformations;
- collection and R-side assembly.

Potential candidates:

- push location/date filtering earlier when semantics permit;
- reduce future-model column sets to selected variables and required keys;
- materialize period-independent CMIP6 intermediates once per SSP;
- reuse location-level climate deltas across periods where date windows and
  transformation semantics are identical;
- stream model/period results into the serial pipeline instead of collecting all
  future outputs before simulation;
- avoid duplicate historical/base panels in diagnostics and simulation results.

PERF-02 remains the reference implementation for shared climate references.
Any new weather rewrite must preserve:

- `AVG` and `STDDEV_SAMP` behavior;
- left-join behavior for missing climate-normal groups;
- factor/bin assignments;
- historical/future parity;
- cache and cleanup ledger behavior;
- deterministic output.

## 9. Phase 6: Make Step 2 Non-Blocking

Ship this independently from throughput work. It is the minimum viable
responsiveness improvement for large countries.

Use the deployed-compatible `shiny::ExtendedTask`/task-button workflow only
after Phase 3's pure entry point exists.

Required behavior:

- snapshot inputs at button invocation;
- do not read reactives inside the task;
- set RNG state inside the task;
- establish DuckDB, extensions, cache, and credential state inside the task;
- preserve `.busy_guard()` across success, error, cancellation, and worker loss;
- compare result signature with the current live signature before publishing;
- mark stale results rather than overwriting newer state;
- make repeated invocation impossible for the same session;
- define navigation and input-edit behavior while running;
- replace `withProgress()` with task status and elapsed time;
- define cancellation honestly and avoid orphaned expensive jobs;
- log run ID, workload dimensions, elapsed stages, status, and worker failure
  without household-level values or credentials.

Acceptance tests:

- synchronous versus task output parity;
- heartbeat while Step 2 runs;
- repeated-click prevention;
- input change during run and stale-result rejection;
- task error and worker loss;
- session disconnect and deployment restart behavior;
- cold and warm worker behavior;
- existing staleness and failure-ledger tests.

## 10. Phase 7: Rebenchmark and Decide on PERF-15

Repeat the complete workload matrix after Phases 4-6.

PERF-15 is justified only if the large-country profile shows that OLS design
matrix construction is a material share of per-key CPU or peak memory.

If justified:

- start with RIF-first matrix reuse across tau subsets;
- keep `predict.fixest()` as the OLS prediction oracle;
- add row, column, and coefficient-order assertions;
- do not manually replace `predict.fixest()` with `X %*% beta + FE`;
- require exact or pre-approved field-level parity;
- close PERF-15 as measured/non-actionable if the full-pipeline gain is below
  the agreed threshold.

## 11. Phase 8: Conditional Bounded Parallelism

Do not begin this phase unless:

- production child workers are supported;
- the optimized serial path still misses the wall-clock target;
- per-key work is coarse enough to amortize startup and serialization;
- the reduced result payload is implemented;
- complete process-tree memory has enough safety reserve;
- concurrent-session limits are known.

Prototype only the simplest viable topology:

1. One outer non-blocking task running the optimized serial loop.
2. A bounded key-worker pool only if the outer task and deployment support it
   safely.

Do not nest worker systems without a deployment-specific measurement.

Implementation requirements:

- standalone key function with serializable inputs;
- bounded in-flight keys;
- dynamic scheduling only if key-size imbalance is measured;
- deterministic per-key RNG streams independent of worker count;
- canonical result ordering independent of completion order;
- explicit historical-key and partial-failure behavior;
- one DuckDB connection per process;
- cross-process-safe weather cache;
- validated worker-count setting, defaulting to serial;
- rollback flag and review/removal date.

Acceptance gate:

- compare workers 1, 2, and the proposed maximum;
- include worker startup, input/output serialization, cache behavior, result
  assembly, and UI publication;
- measure process-tree RSS under the agreed concurrent-session scenario;
- require material end-to-end benefit, provisionally 2x;
- reject parallelism if memory safety or benefit gates fail.

## 12. Definition of Done

The optimization program is complete when:

- LKA, Iran, and the largest feasible workload have reproducible benchmark
  records;
- the serial reference remains available and tested;
- the Step 2 compute entry point has a documented stable contract;
- result payload memory is reduced or the measured payload is shown to be
  necessary;
- Step 3 model-specific weather behavior remains exact;
- full process-tree RSS is within the production envelope with reserve;
- Step 2 is non-blocking and stale-safe;
- PERF-15 is either implemented behind parity tests or closed as measured;
- bounded parallelism is either rejected with evidence or shipped only behind
  a validated default-safe control;
- each phase has a dated decision record containing commit, workload,
  environment, measurements, correctness result, and rollback decision.

## 13. Recommended Execution Order

```text
Phase 0: deployment, prior-failure, and workload constraints
    ->
Phase 1: reproducible baseline harness and full RSS measurements
    ->
Phase 2: result and per-pipeline contract characterization
    ->
Phase 3: pure serial compute entry point
    ->
Phase 4: shared metadata, diagnostics payload, weather and F_loading retention
           reductions
    ->
Phase 5: measured weather-stage optimization
    ->
Phase 6: non-blocking serial Step 2
    ->
Rebenchmark complete pipeline
    ->
Phase 7: PERF-15 decision
    ->
Stop if latency and memory targets are met
    ->
Phase 8: bounded parallel experiment only if all gates pass
```

The immediate next implementation task is Phase 1: a reproducible benchmark
harness and decision record. Do not edit `R/mod_1_06_model.R`,
`inst/app/www/custom.css`, or any other unrelated worktree changes as part of
this plan.
