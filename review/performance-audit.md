# Performance Audit — Remaining Work

**Audit revision:** `aa42136` | **Dev head:** Wave 3 W3-B (`7766333`, following W3-A) | **Date:** 2026-09-12

---

## Status

| Wave | Batch | Findings | Status |
|---|---|---|---|
| 0 | W0-A | S3-P12 | Integrated |
| 1 | W1-A | P3, P7, P8, P14, P16 | Integrated |
| 1 | W1-B | P2, P9 | Integrated |
| 1 | W1-C | P1, P5 | Integrated |
| 1 | W1-D | S2-P1, S2-P2, S2-P3, S2-P11, S2-P12 | Integrated |
| 1 | W1-E | S3-P2, S3-P3, S3-P5 | Integrated |
| 2 | W2-A | P6, P11 | Integrated |
| 2 | W2-B | S2-P4, S2-P5, S2-P8, S2-P14 | Integrated |
| 2 | W2-C | S2-P7, S2-P10 | Integrated; S2-P6 and S2-P9 dropped — see §2 |
| 2 | W2-D | S3-P4, S3-P7, S3-P10, S3-P13 | Integrated |
| 2 | W2-E | S3-P6, S3-P8, S3-P9, S3-P11, S3-C1 | Integrated |
| **3** | **W3-A** | **S2-P21, S2-P22** | **Integrated** |
| **3** | **W3-B** | **S3-P1** | **Integrated** |

Three authorized findings also require separate approval: **S2-P6**, **S2-P9**, **P15** — see §2.

---

## 1. Wave 3

Start all worktrees from the Wave 2 integrated revision.

### W3-A — Step 2 Aggregation Throughput

**Files:** `R/fct_aggregation.R`, `R/fct_aggregation_delta.R`, `R/mod_2_02_results.R`

**S2-P6 dependency:** S2-P6 must be resolved before or alongside W3-A. If approval (§2) is concurrent, integrate S2-P6 first. Otherwise W3-A must include a minimal scoped cache bound as a prerequisite.

#### S2-P21 — Lazy Weighting Arms

`R/mod_2_02_results.R`

Every method eagerly computes both weighted and unweighted results. `weight_key()` always selects the weighted branch for surveys with weights, so the unweighted arm is built and cached with no active consumer in normal use.

**Change:** Compute each arm lazily on first request. Retain the unweighted fallback when no weight is available and for verified export/compatibility consumers. Do not change the nested `weighted`/`unweighted` schema.

**Impact:** Up to ~50% of aggregation CPU and transient allocation for weighted workloads.

#### S2-P22 — Shared Per-Year Preparation

`R/fct_aggregation.R`, `R/fct_aggregation_delta.R`

Each method and arm independently repeats year grouping, row slicing, validity filtering, residual matching, back-transformation, and factor-loading slicing.

**Change:** Build a bounded preparation cache per pipeline containing year row indices, valid-row masks, normalized weights, and deterministic per-year residual vectors. Reuse across methods; do not cache `N x P` method-specific matrices. Pair with the S2-P6 bound so this cache cannot grow unbounded.

**Impact:** Moderate-to-high during multi-method Results sessions.

#### W3-A Gate

- Both weighting arms available on demand; values, gradients, residual pairing, and per-year RNG preserved exactly across all methods and residual modes for Steps 2 and 3. **Passed:** strict parity covered 72 method/arm/residual cases; the focused W3-A characterization suite passed 42 assertions.
- Preparation cache stays O(N) per pipeline and bounded. **Passed:** the shared preparation cache is bounded at 32 entries and the Results cache at 8 entries; cache-bound and lazy-arm tests are included in the characterization suite.
- Full package test suite passed: 2,589 assertions, 0 failures. Results tests passed 149 assertions, and aggregation-delta tests passed 37 assertions.
- Commit: `d7d8153` (`Optimize Step 2 aggregation caching`).

---

### W3-B — Step 3 Compact Future Decomposition

**Files:** `R/mod_3_06_policy_sim.R`, Step 3 payload/decomposition helpers and tests

**Dependency:** Start from the W3-A integrated revision.

#### S3-P1 — Compact Future Decomposition Retention

`R/mod_3_06_policy_sim.R`, `R/mod_3_09_decomposition.R`

The scenario/year loop row-binds a full 21-column household frame into `decomp_scenarios_rv`. At 231,087 rows this is 34.4 MB per year and ~426.7 MB for one 11-year scenario; multiple scenarios scale linearly. The UI consumes only: weighted channel summaries by scenario/year, channel-by-decile summaries, the per-household-weighted `delta_total` annual summary needed to rank and select adverse years (not a scalar — requires enough per-year information to reproduce the current weighted ranking for 1-in-10 and 1-in-20 selection), and scenario labels.

**Change:** Inside the loop, derive and immediately retain those four compact products, then release the full household frame before the next year. Keep the full historical household decomposition (used by Results incidence, decile display, and adverse recomputation). Any export of future household rows must be contracted explicitly before compaction proceeds.

**Impact:** Very high retained and transient memory reduction; also avoids a large final `bind_rows()`.

#### W3-B Gate

- Channel, scenario, year, model, and decile summaries and all exports identical to pre-compaction output. **Passed:** compact-vs-legacy characterization and export parity covered OLS and RIF; the W3-B suite passed 55 assertions.
- No downstream consumer requires discarded household rows (verified by the consumer audit and module/export contract tests). Historical `decomp_result` remains separate and unchanged.
- Substantial retained/serialized-size reduction demonstrated on an 11-year, one-scenario representative fixture: `object.size()` `203,358,848` to `28,080` bytes; serialized size `223,692,667` to `20,833` bytes. Controlled external max RSS was `1,223,786,496` bytes before and `725,811,200` bytes after.
- Fixed weighted baseline deciles, adverse-year selection, channel SE summaries, factor/bin behavior, scenario ordering, and empty-result behavior are unchanged under the contract tests.
- Full package suite passed 2,644 assertions with 0 failures. Commit: `7766333` (`Compact future decomposition retention`).
- Timing caveat: the isolated retention benchmark was slower (`0.009s` legacy vs `0.274s` compact median on 11 years x 50,000 rows); this is a memory-retention optimization, not a demonstrated elapsed-time optimization. Production end-to-end timing remains a follow-up.

---

### Wave 3 Integration Order

1. Resolve S2-P6 or implement the minimal scoped cache prerequisite.
2. Integrate and validate W3-A.
3. Integrate and validate W3-B against the W3-A revision.
4. Run the complete Step 1–3 suite and the production-sized benchmark matrix.

---

## 2. Authorized but Blocked

These were authorized in the delivery plan but excluded from Wave 2 for insufficient test coverage. W3-A and W3-B are now integrated; the items below remain the next approved work and should be addressed only after completing their listed lifecycle/browser evidence.

### Recommended Next Order

1. **S2-P6 — Bounded Results Aggregation Cache:** highest priority because it is the remaining Step 2 cache lifecycle gap and was the explicit dependency for W3-A. Complete the full eviction, stale-result, export, and reference-store lifecycle tests before changing cache ownership or eviction behavior.
2. **S2-P9 — Reference-Weather Store Ownership:** address next if Step 3 reruns, partial failures, or superseded weather references remain a memory/lifecycle risk. Establish the run-level ownership and historical-only cleanup contracts before implementation.
3. **P15 — Stable Weather Map Surfaces:** address after S2-P6/S2-P9 unless browser-level evidence is available sooner. This is UI-stability work with no demonstrated server-side performance gate yet; obtain the required browser instrumentation first.

No item in Section 3 is approved for implementation by this recommendation.

### S2-P6 — Bounded Results Aggregation Cache

`R/mod_2_02_results.R`, `R/fct_aggregation.R`

**Blocked because:** module-level cache and full Step 2/3 reference-store lifecycle tests were incomplete at W2-C.

**To unblock:** complete tests for method switching, poverty-line/bandwidth changes, export after eviction, stale-result display, and the full reference-store lifecycle (success, partial failure, total failure, rerun, clear, session end). Confirm eviction never alters active output and recomputed values match cached values.

**Change:** Bounded LRU or current-plus-default cache; evict older poverty-line/bandwidth variants; expose object-size instrumentation in the benchmark harness.

**Note:** W3-A depends on this. See §1.

### S2-P9 — Reference-Weather Store Ownership

`R/fct_run_simulation.R`, `R/mod_2_01_weathersim.R`, `R/mod_2_simulation.R`

**Blocked because:** lifecycle tests were incomplete at W2-C.

**To unblock:** full lifecycle suite (success, partial failure, total failure, rerun, clear, session end, historical-only and future runs). Confirm no weather referenced by Step 3 is ever removed.

**Change:** One run-level store owner with explicit references from every published result. Clean the superseded store on atomic replacement only when Step 3 holds no reference. Historical-only runs must avoid creating an orphaned store or retain it for cleanup.

### P15 — Stable Weather Map Surfaces

`R/mod_1_05_weatherstats.R`

**Blocked because:** browser-level camera/fullscreen/empty-state evidence was unavailable at W2-A.

**To unblock:** browser-level tests or instrumentation (R-only is insufficient) confirming that card headers, layout, full-screen behavior, and all IDs survive wave/month/view changes; camera position and full-screen state are preserved; no-data and historical-view messages are unchanged.

**Change:** Keep map surface and card structure stable after weather data loads; update only dynamic header text and payload/legend outputs.

---

## 3. Not Authorized

These require a separate authorization decision. No implementation without explicit approval.

### Step 1

| ID | Finding | Potential benefit | Blocked by |
|---|---|---|---|
| P4 | Compact retained fit-snapshot | 237.6 MB → ~63.7 MB illustrative projection; high session RSS saving when stale fit coexists with new weather data | Needs persisted schema decision |
| P10 | Grouped outcome map aggregation | Low-to-moderate CPU/allocation for large map inputs | Outside Sets A–D |
| P12 | Consolidated LASSO candidate matrix | Low-to-moderate setup gain; cross-validation dominates elapsed time | Outside Sets A–D |
| P13 | Direct RIF coeftable extraction | Moderate result-preparation speedup if VCV fallback probing is material | Unresolved numerical-parity risk |
| P17 | Deduplicated weather SQL denominators | Low-to-moderate; textual duplication may not imply duplicate execution — needs `EXPLAIN ANALYZE` first | Conditional on query-plan evidence |

### Step 2

| ID | Finding | Potential benefit | Blocked by |
|---|---|---|---|
| S2-P13 | Remove deep copy at async boundary | Potentially high startup peak-RSS reduction when async is enabled; no gain on current synchronous path | Async backend not yet selected |
| S2-P15 | Key-level parallelism | Wall-clock reduction when prediction dominates; may be net loss from serialization overhead and duplicated model/survey memory | Deferred until post-Sets 2A/2B RSS is known |
| S2-P16 | Bounded DuckDB thread scaling | Potentially substantial weather-query speedup (2–4 threads) on local/cached workloads; negligible for remote-I/O-bound runs; per-thread hash/sort/window memory is a key risk | Needs numerical, RSS, and CPU-entitlement gates |
| S2-P17 | Materialized location-month weather | Potentially high for 3-SSP/3-period runs (spatial aggregation paid once); memory impact ambiguous — depends on temporary-table lifetime | Needs query-plan comparison and RSS measurement |
| S2-P18 | Shared historical weight denominators | Moderate with many weather variables; low with one or two; DuckDB may already eliminate repeated expressions | Needs plan inspection and complete-case verification |
| S2-P19 | Fused future-model completeness filter | Moderate-to-high if the query plan executes the H3/delta relation twice | Needs query-plan confirmation |
| S2-P20 | Shared RIF design and FE indexing | Potentially high CPU reduction for fixed-effect RIF; point-prediction and loading-reuse variants need separate benchmarks due to peak-RSS trade-off | Needs production RIF benchmark |

### Step 3

| ID | Finding | Potential benefit | Blocked by |
|---|---|---|---|
| S3-P14 | Lazy paired policy pipelines | Potentially substantial retained-memory reduction for large baselines and many members; limited CPU benefit | Needs benchmark fixture and serialized-payload compatibility tests |
| S3-P15 | Per-year row index | ~1.2x–2x for long panels; avoids O(N × years) logical scans per method | Overlaps shared Step 2/3 aggregation path — implement once for both |
| S3-P16 | Direct model/year lookup | Near-free to implement; prevents quadratic growth with more years/models | Overlaps shared aggregation path — implement once for both |
| S3-P17 | Typed policy-diff pass | Moderate allocation reduction; removes duplicated comparison logic across policy construction, no-op detection, decomposition, and Diagnostics | Deferred; should replace S3-P2 caches, not coexist |
| S3-P18 | Direct residual ID lookup | ~1.05x–1.2x isolated; compounds across aggregation methods | Overlaps shared aggregation path — implement once for both |

---

## 4. Delivery Rules

1. Read the complete finding, equivalence requirements, and validation plan before editing.
2. Write characterization tests for current behavior before any compute or schema rewrite; cover edge cases from the audit, not only the happy path.
3. Make the smallest compatible change. No new runtime dependencies, no renamed public inputs/outputs, no broadened scope without coordinator approval.
4. Preserve: canonical ordering, factor levels, duplicate-key behavior, deterministic RNG, failure ledgers, stale-result preservation, member-specific weather.
5. Run focused tests and `git diff --check`. Report changed files, timings, allocations or RSS, and residual risk.
6. Stop and report rather than silently relaxing semantics when strict parity fails.
7. Do not modify this document from implementation worktrees.

The coordinator integrates only passing batches, reruns cross-step contracts after shared helper changes, and creates each wave from the newly integrated revision.

---

## 5. Acceptance Gate

Complete when:

- every authorized ID is implemented or recorded as gate-failed with evidence;
- `git diff --check` and the full test suite pass;
- cold/warm Step 2 and Step 3 benchmarks record elapsed time, allocation, retained/serialized size, and external process-tree RSS;
- coverage includes: small and large country, OLS and RIF, historical-only and future scenarios, compact and reference weather, uncertainty on and off;
- production data is read-only; no benchmark artifact enters the production source;
- Step 1 UI snapshots, Step 2 payload/replay, Step 3 Results/Diagnostics/Decomposition/stale state/exports all pass end-to-end;
- no unauthorized item, new runtime dependency, or unrelated refactor is included.
