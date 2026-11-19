# Optimization guidelines

Optimize measured bottlenecks without changing results or blocking other sessions. Prefer the smallest change that improves end-to-end time or process-tree peak memory; a faster isolated operation is not enough.

## 0. App-Specific Context

- Read `ARCHITECTURE.md` for pipeline and cross-file contracts, `review/code_hygiene.md` for protected areas, and `DEPLOYMENT.md` for resource limits. Do not duplicate those inventories here.
- Profile before choosing a target. Archived opportunity lists in `review/archive/` are evidence and traps, not an optimization backlog; reopen rejected experiments only with new evidence.
- Preserve the existing engine, `year`, residual, policy and artifact contracts. Deliberate numerical changes need skill `wise-numeric-change`; they are not performance-only changes.

## 1. Data Layer

- Push filtering, projection, joins and aggregation into DuckDB where appropriate; collect only the rows and columns the next stage needs. Avoid repeated conversions and materialization.
- Use the exact DuckDB pin in `DESCRIPTION`; bundled extensions must match (`DEPLOYMENT.md`). Do not change storage formats or dependencies as incidental optimizations.
- Compare SQL, existing R kernels and compiled code on the actual workload. Arrow and alternative engines are candidates, not mandatory faster paths; include conversion and transfer costs.

## 2. Simulation and RNG

- Optimize measured hot loops, not every loop. Keep compute kernels Shiny-free and usable both in-process and in workers.
- Preserve RNG kind, seeds, draw order and caller RNG state. Follow the existing `wise_seed()` and scoped-seed patterns; worker execution must reproduce the reference computation. Base RNG is not inherently unsafe in separate processes, but parallel streams need deliberate management.
- Changing RNG libraries, reduction order or threading can change numbers. Run determinism and relevant engine-parity tests; do not assume vectorized or compiled code is numerically equivalent.

## 3. Model Fitting

- Work through `ENGINE_REGISTRY`; supported engine paths and extension rules are in `ARCHITECTURE.md` and skill `add-model-engine`. Do not migrate existing fixest workflows to another estimator without an explicit decision.
- Preserve formulas, fixed effects, weights, sample selection, row alignment and prediction semantics. A faster least-squares solver is not automatically a substitute for the fitted model.
- Reuse prepared inputs where valid. Native DuckDB fetch beat the proposed Arrow conversion on the investigated workload; do not revive that conversion recipe without new evidence. Package upgrades require their own compatibility and benchmark checks.

## 4. Caching

- Reuse existing bounded caches before adding another. Keys must cover all result-affecting inputs, including data/model identity, display settings where relevant, and RNG configuration for stochastic results.
- Define invalidation, ownership, eviction and session isolation. Bound retained memory or disk; measure key construction, serialization and peak memory as well as cache-hit time.
- Cache stable plain inputs and outputs, not reactive expressions or live connections. Do not add memoization, hashing or shared-memory dependencies without a measured need.

## 5. Session State and Resources

- Minimize large-object duplication across reactives, snapshots, workers and result adoption. Reuse existing artifact and released-weather contracts rather than adding parallel storage paths.
- Keep main-thread work bounded, including artifact reads and result publication. Async computation does not make synchronous adoption free.
- Release session-owned connections, files and cache entries on replacement and session end. Respect shared-pool ownership and artifact leases; never destroy a process-wide resource when one session ends.

## 6. Tables

- Use `reactable` and the existing client-side CSV download helper. Export raw values; apply rounding through column formats.
- Reduce and prepare table data outside renderers where possible. Preserve sorting, filtering, downloads and accessibility when optimizing updates.

## 7. Figures and Maps

- Use `echarts4r` through the existing `echart_*` builders. Keep ggplot builders needed for static output, exports and tests; no blanket migration or deletion.
- Use proxies for compatible incremental updates when they avoid redundant work. Verify actual browser rendering and interactions, not just R construction time (skill `wise-ui-check`).
- Maps stay on the MapLibre bridge in `fct_hexmap.R`. Optimize data preparation or payload size without replacing the map stack.

## 8. Asynchronous Execution

- Reuse the lazy, process-wide mirai coordinator in `fct_step2_async.R`, shared by Steps 2 and 3 and Overview metadata. Preserve queue limits, cancellation, timeouts, stale-result rejection and shutdown cleanup; do not add a second pool or nested parallelism by default.
- Workers receive minimal plain snapshots, not reactive environments or live connections. Create and close task-local resources inside the worker. Environment-sourced credentials are resolved in workers; UI-supplied credentials may cross only to verified local daemons, never remote ones.
- Do not introduce `ExtendedTask`, `crew`, `future` or shared-memory machinery merely as a modernization. Justify coordinator changes against responsiveness, concurrent-session memory and end-to-end measurements.

## 9. Benchmarking

- Use real app data from `Sys.getenv("WISEAPP_DATA_PATH")` in R; never open or print `.Renviron`. Synthetic smoke fixtures are not production performance evidence.
- Reuse `dev/bench/` harnesses and skill `wise-benchmark`; write each run under a distinct `dev/outputs/` directory. Compare baseline and candidate on the same machine with equal seeds, threads, cache states and repetitions.
- **Default payload**: BFA surveys (all years), 1x1 OLS (`WISEAPP_STEP2_WORKLOADS=one_ssp_one_period`, `WISEAPP_STEP2_MODELS=ols`), unless the change needs a larger or different payload (user decision 2026-10-07).
- **Workload ceiling**: 2x2 (`WISEAPP_STEP2_WORKLOADS=two_ssps_two_periods`) for benchmarks and profiling; do not run 3x3 (user decision 2026-10-08). Use IRN or additional scenarios only when relevant, within this ceiling.
- **Step 3**: `dev/bench/bench_step2.R` with `WISEAPP_STEP2_INCLUDE_STEP3=1 WISEAPP_STEP3_POLICIES=targeted_sp`; the `covariate` fixture needs an electricity column in the fitted model.
- Report exact commands, baseline/candidate revisions, environment, repeated wall times and process-tree peak RSS, numerical parity and anything unmeasured. Stage-boundary memory samples are not peak RSS. Distinguish cold/warm caches and main-process/worker costs; archived timings are not a local baseline.
- Run the relevant regression and determinism tests. Require identical outputs for performance-only changes unless a numerical tolerance is explicitly justified and approved; report any difference, not just headline agreement.

## 10. Deployment and Runtime

Use `DEPLOYMENT.md` for configured resource controls; verify actual Connect settings before tuning. Budget main-process, daemon, DuckDB, thread and temporary-disk costs across concurrent sessions. Do not infer safe concurrency from one session or duplicate unverified server settings here. Deployment or upload still requires explicit approval.
