# Social protection: remaining tasks (Phase 1 close-out, Phase 2, Phase 3)

Companion to `review/sp_shock_responsive_plan.md` (design rules, Phase 2 and 3 design). Updated 2026-10-08.

Phase 0 and Phase 1 are built, tested and committed on `dev` (495ae85, 2b3822e, cf900f0, dc84b1f, 766d37a); what each task did is in the git history. This file lists only what is left. Sizes: S under a week of focused work for one person, M one to three weeks, L more. They come from reading the code, not from prototyping.

Status key: `☐` todo · `◐` partly done · `✗` not doing.

## 0. Conventions

- Task ids: `P0-n` (Phase 0 leftovers), `P1-n` (Phase 1 close-out), `P2-n`, `P3-n`. A spike ends in a written answer and may change later tasks.
- Every task lists files, dependencies, "done when" and tests.
- Repository rules: `fct_` files stay free of Shiny; touch only files the task needs; run the narrowest meaningful check (`devtools::test(filter = "...")`); run `devtools::document()` when roxygen or exports change; no commits or pushes unless requested; code, comments and commit messages use ASCII quotes and hyphens.
- Reproducibility (plan rule 10): same inputs and seed give identical outputs regardless of row order, chunk size and thread count; preview equals run; every new spec field enters the run signature and the export; every task that changes numbers or draws carries a determinism test.
- Any change in the Step 3 hot path (the annual correction loop) needs the benchmark in `review/optimization_guidelines.md`.
- Tests are named after the file or concept they cover (`test-fct_sp_shock.R`, `test-sp-shock-correction.R`, `test-sp-reach.R`).
- New tasks read `sp$currency` and use `outcome_level_scale()` / `.policy_sp_transfer()`, never the raw transfer column.

## Decisions (8 October 2026)

| # | Decision |
|---|---|
| 1 | Finish the Phase 1 close-out (section 1) before Phase 2 feature work. |
| 2 | "People lifted" is the net change in the number of poor, labelled as such. Gross movements are not built (the annual aggregates keep no household-level before/after status). |
| 3 | The cost-effectiveness section leads with cost per person lifted when the metric is a poverty rate, and welfare gain per $1 otherwise. Near-zero or wrong-signed effects print "not applicable", never an extreme ratio. |
| 4 | Cost-effectiveness gets a dedicated Step 3 tab (not a Results section). |
| 5 | Scope: cost-effectiveness applies to cash transfers only, and only to the modelled benefits and costs listed in the tab (transfer, administration, modelled welfare and poverty effect). Other levers (`mod_3_02` to `mod_3_05`) are out of scope: no unit costs exist. The tab must state this. |
| 6 | The decomposition channel split (P2-3) comes right after P2-1 and P2-2, before impact triggers and budgets. |
| 7 | P2-6 builds share-of-loss budgets with a ceiling and the cap with pro-rata scale-down. AAL sizing, poverty-linked budgets and the envelope per activation stay in the plan, moved to Phase 3 (P3-5). |
| 8 | P0-8 (weighted error counts) is done next, before the close-out, because it is a correctness issue (done 8 October 2026, uncommitted). P0-9 (admin presets, error defaults) is deferred. |
| 9 | Cost-effectiveness uses one seeded targeting draw (no repeated-draw range) and the Results poverty line input. |

## 1. Phase 1 close-out (decision 1: finish before Phase 2 features; P0-8 is done)

Phase 1 has no missing feature. These items turn "built and unit tested" into "verified in the real app".

| Task | Status | Work | Size |
|---|---|---|---|
| P1-13 real-app run | ☑ (8 October 2026, by the user) | Marked off on the user's report that the real app works interactively. I could not run it: no browser or data source in my session. The user's run also exposed the stale historical policy arm (fixed, see side fixes below). Detailed checklist results (export bundle, absent-transfer column) were not reported to me. Original: Run Step 0 to 3 in the real app (use the `run` skill) with a shock program: trigger flyout, sidebar card, run, Results, Decomposition, Diagnostics (shock table and cost chart), export bundle. Check that nothing assumes `.wiseapp_sp_transfer` exists when it does not. | S |
| P1-14 a11y walk | ☑ (8 October 2026, by the user) | Marked off by the user's instruction; I did not run it and have no findings. Original: Keyboard-only and screen reader pass over both SP flyouts ("Payment settings", "Targeting details") and the "Trigger settings" flyout: focus order, Escape, `aria-expanded`, validation message announced. | S |
| P1-15 Step 3 benchmark harness | ☑ (8 October 2026; harness built and smoke-tested by me; production run ticked off by the user, results not recorded here) | `dev/bench_step3_helpers.R` has a `shock_sp` fixture (1-in-5 return-period trigger on the first continuous exposure variable, filled in at run time by `.bench_step3_fill_shock_trigger()`). For shock it builds the plan with `sp_shock_plan()` before `.prepare_policy_annual_channels(shock =)`, checks `SP_ELIGIBLE_COL` instead of the transfer, passes `sp`/`analysis_unit` to `apply_policy_delta_to_baseline()`, and skips the slow-reference parity (regular-only, P1-17). Use `WISEAPP_STEP3_POLICIES=targeted_sp,shock_sp WISEAPP_STEP2_INCLUDE_STEP3=1 Rscript dev/bench_step2.R` for the regular vs shock comparison. New smoke test in `test-bench-step3.R` (status ok, identical fingerprint on repeat); file passes (64 expectations, 0 fail). NOT run: the production-data benchmark (no `WISEAPP_DATA_PATH` or snapshot in this session), so no new timing figures; the known BFA figure (7.0 s shock vs 3.6 s regular) is unchanged and unrecorded in the tracker. Owed: the user runs it on BFA and IRN and records results in the tracker. Original: `dev/bench_step2.R` with `WISEAPP_STEP2_INCLUDE_STEP3=1` prepares `annual_channels` before the run, so it needs a shock fixture that builds the plan first. Record results in the tracker. The BFA correction-loop figure is already known: 7.0 s shock vs 3.6 s regular. | S |
| P1-16 trigger unit label | ☑ (8 October 2026; uncommitted) | New pure helper `.sp_trigger_unit()` (`fct_sp_shock.R`): physical unit, "deviation from mean, <unit>" or "standardized anomaly (z-score)" from the Step 2 `selected_weather`. `mod_3_01_sp_server()` gets a `selected_weather` argument (wired in `mod_3_scenario.R`) and shows "Thresholds are in: ..." under the variable dropdown. Two tests added to `test-fct_sp_shock.R`; file passes (213 expectations, 0 fail). Not checked in a browser (P1-13). Original: The flyout shows only the catalogue label, not the unit of a transformed variable (physical, deviation, z-score), because the Step 2 transformation is not passed to `mod_3_01_sp`. Pass it and show the unit beside the threshold. | S |
| P1-17 slow reference path | ☑ (8 October 2026; comment only) | Took the second option: comment above `.policy_annual_channels_reference()` states it is regular-only (static `context$sp_transfer`, no shock argument). No test passes it a shock run; shock parity is covered by `test-sp-shock-correction.R` (always-on trigger equals the regular correction; adapter and attribution agree). No code change, so no test re-run. Original: `.policy_annual_channels_reference()` (`fct_policy_metric_decompose.R:447`) does not model shock. Either teach it the dynamic transfer so the parity tests can cover shock, or state in its comment that it is regular-only and make the tests skip shock. | S |
| P1-18 column lists | ☑ dropped, no change needed (8 October 2026) | Checked on a synthetic frame: `.compute_policy_deltas()` skips the logical `SP_ELIGIBLE_COL` (numeric-only test, and it is not in `.policy_candidate_cols()`); `detect_modified_cols()` / `attach_active_mask()` only compare columns shared with the baseline or training frame, and neither carries the eligibility column. Neither list changed. Not run: a real shock run through the app (covered by P1-13). Original: `fct_policy_decompose.R:58` and `fct_results.R:474` exclude `SP_TRANSFER_COL` from covariate-change detection but not `SP_ELIGIBLE_COL`. The eligibility column exists only in the policy frame, so the shared-column checks probably ignore it; verify with a shock run and add it to both lists if it is ever seen as a changed covariate. | S |
| P1-19 manifest | ◐ (8 October 2026) | `test-deploy-contract.R` passes now (11 expectations, 0 fail): the manifest regenerated in 6de87e9 already lists `R/fct_sp_effectiveness.R` and `R/fct_sp_shock.R`. File checksums are stale for everything changed since (P0-8, P1-16, P1-17). `dev/00_make_manifest.R` builds from `git archive HEAD`, so regenerate only after the user commits this work, then re-run the test. Owed. Original: `test-deploy-contract.R:76` failed because `manifest.json` did not list `R/fct_sp_effectiveness.R` (and now `R/fct_sp_shock.R`). Regenerate with `dev/00_make_manifest.R` after the commit and re-run the test. | S |
| P1-20 BFA LCU re-run | ☑ (8 October 2026, by the user) | Marked off by the user's instruction; the figures for the Decision log are not in this file. Original: Owed by the user for the Decision log (R2-BUG-04 / CR-BUG-02), tracked in `review/REVIEW-2026-10-06-tracking.md`. Repeat it with a shock program to cover the dynamic transfer's currency path. | S |

Side fixes (8 October 2026, uncommitted): (1) stale Step 3 historical policy arm, `make_agg_hist()` in `fct_policy_sim_compare.R` keyed the shared aggregation cache on Step 2's signature only, so a second Step 3 run on the same Step 2 run was served the first run's historical policy aggregate; the key now includes the policy run signature; regression test in `test-policy-sim-compare-agg-cache.R` (fails without the fix). (2) SP sidebar order is now Trigger (own section, shock only), Amount with Payment settings beneath it, Targeting. Not checked in a browser. (3) The "per household / per person" basis now shows only beside Payment settings (`payment_summary`), always, in place of the hint beside the amount field; test added in `test-sp-design-options.R`.

Done when: P1-13 to P1-15 have recorded results (what was checked, what was not); P1-16 to P1-19 are closed or consciously dropped with a note.

## 2. Phase 0 leftovers

| Task | Status | Work |
|---|---|---|
| P0-5 poverty effect per cost | ◐ | Cost per person lifted out of poverty and similar. Decided (decisions 2 to 5): net people lifted, lead metric by outcome type, dedicated tab, cash transfers only. Moved to P2-2. |
| P0-8 weighted error counts | ☑ (8 October 2026; uncommitted) | Done in `.determine_sp_eligibility()` with the helper `.sp_error_weights()`: rows are drawn in a random order (uniform or distance-weighted) and flipped until the cumulative weight is closest to the slider share of the non-eligible (inclusion) or eligible (exclusion) weight; the realised weighted rate is within half the largest flipped row's weight of the target. No usable weights, or constant weights, keep the old row-count draw (same `sample.int()` call, bit-identical; tested against the legacy algorithm). Popover text updated. Synthetic check (4,000 rows, lognormal weights, 15% / 10% sliders): realised weighted inclusion 15.8% and exclusion 12.2% before, 15.0% and 10.0% after. Tests in `test-sp-design-options.R`: weighted rates, determinism and row-order invariance, preview equals run, zero and missing weights; 2135 expectations pass in the `sp`, `shock`, `policy`, `effective`, `reach` filters. Still owed: BFA before and after headline numbers for the Decision log (needs a manual Step 3 run; BFA survey weights are what make this visible). Original spec follows. Correctness fix (decision 8). Make inclusion and exclusion errors hit the weighted share the sliders describe, not the row count, reusing the P0-4 distance-weighted selection: flip units until the weighted share of non-eligible units included, or of eligible units excluded, reaches the target (person weights for household surveys, the convention of `.sp_transfer_totals()`). Changes the static program's numbers for weighted surveys, so it gets its own Decision log entry in `review/REVIEW-2026-10-06-tracking.md` with before and after headline numbers (BFA). Shock mode uses the same eligibility function, so it inherits the fix. Files: `R/fct_policy_sim.R` (`.determine_sp_eligibility`), `R/mod_3_01_sp.R` (help text and the row-count note in the popover and code comment). Done when: realised weighted inclusion and exclusion rates equal the sliders within one unit's weight on weighted synthetic surveys; unweighted surveys and concentration 0 on unit weights are bit-identical to today; counts and determinism hold under reordered rows; preview equals run. Tests: extend `test-sp-design-options.R` with a widely varying weighted survey; check the `sp_effectiveness()` realised-error figures agree with the sliders. Size S to M. |
| P0-9 admin presets and error defaults | deferred | Literature pass on cost-transfer ratios and PMT error rates, then a preset dropdown. Not scheduled (decision 8); the 10% / 10% defaults and a zero admin share stay, and the cost-effectiveness tab prints the admin share beside every figure. Owner: the project owner. |

## 3. Phase 2: recommended order and tasks

**What to do next, in order.**

0. Close out Phase 1 (section 1); P0-8 is done.
1. P2-1 response check and P2-2 outputs and cost-effectiveness tab. Highest value for least risk: the response check fixes the BFA problem (users picking a trigger variable that does not drive loss) and the outputs finish the finance-ministry story. Neither touches the hot path.
2. P2-3 decomposition channel split, while the numbers are stable and before more terms are added to Main.
3. P2-4 binned triggers, after a short benchmark spike (it touches the weather path).
4. P2-5 impact-based triggers, then P2-6 budgets linked to need (they share the loss machinery).
5. P2-7 and P2-8 (layered targeting, anticipatory) last: they add the most assumptions and should reuse the settled trigger and budget code.

### P2-0: Spikes (S each, before the tasks they gate)

- **P2-0a binned-variable cost (gates P2-4).** Measure the extra memory and worker payload of a companion `<var>_cont` column per binned variable per member on BFA and IRN, and confirm the prepared-weather and weather-disk caches store pre-binning values. Output: go or no-go for option 1.
- **P2-0b aggregate loss metrics (gates P2-5).** Prototype location and national modelled loss, poverty rate and number of poor per (member, year) from the central predictions; check behaviour of the historical thresholds and the record-length rule on real BFA exposure. Output: which metric is defined where, and the trigger input units.
- **P2-0c forecast skill (gates P2-7).** Decide POD/FAR input versus noisy hazard copy, the seeded key (location, year, member), and how a false alarm is costed. Output: written choice.

### P2-1: Response check for the trigger variable (S to M)

Mean modelled loss by decile of the chosen variable from the Step 2 historical predictions; show where losses concentrate, suggest high, low or either end, and show the loss-event share's basis risk beside it. Pure function in `fct_sp_shock.R`, shown in the Trigger settings flyout.

- Files: `R/fct_sp_shock.R`, `R/mod_3_01_sp.R`.
- Done when: on BFA the hint says "wet years, high `spei6`" (not `t`); an unusable variable shows a message, not an error; deterministic.
- Tests: hand-calculated deciles on a small panel; direction suggestion on a one-sided and a two-sided response; module render.

### P2-2: Shock outputs and the cost-effectiveness tab (L)

Climate-adjusted cost; coverage of the shock-affected poor; adequacy; poverty effect per cost in average and 1-in-20 years (closes P0-5); and a dedicated cost-effectiveness tab that works for regular and shock cash transfers. Most inputs already exist in `out$shock$rows` and `$cells` and in `sp_effectiveness()`.

- Decided (decisions 2 to 5, 9): net change in the number of poor, labelled as such; lead with cost per person lifted for poverty-rate metrics and welfare gain per $1 otherwise; "not applicable" for near-zero or wrong-signed effects; a dedicated tab; one seeded targeting draw; the Results poverty line input.
- Scope statement shown in the tab: cash transfers only; only the modelled transfer, administration, welfare and poverty effects count; delivery of other levers, targeting surveys and financing are excluded; other levers have no cost-effectiveness figure. Admin share shown beside every figure.
- Files: new tab module (`R/mod_3_10_cost_effectiveness.R` or the next free number, wired in `R/mod_3_scenario.R`), `R/fct_sp_shock.R`, `R/fct_sp_effectiveness.R`, `R/mod_3_08_diagnostics.R` (move or link the existing effectiveness table), export registration in `R/fct_export.R`. Design and arithmetic: `review/step3_cost_effectiveness_plan.md`; update it to option "dedicated tab" first.
- Done when: metrics match hand calculations on a small panel; the "not reported for a shock program" notice is gone; exports carry the new tables; poverty-line absent shows "Not available"; the tab is empty-state safe when the SP lever is off.
- Tests: extend `test-fct_sp_shock.R` and `test-fct_sp_effectiveness.R`; export test; a module render test; `app_server` wiring test.

### P2-3: Separate decomposition channel (L)

Split `delta_sp_shock` out of Main into its own channel in the compact stats, level channels, summaries and exports. Numbers must not change, only grouping.

- Files: `R/fct_policy_metric_decompose.R`, `R/fct_decomposition_summary.R`, `R/fct_policy_metric_decompose.R` consumers, `R/mod_3_09_decomposition.R` (`.compact_decomp_channels`, `:109`), `R/fct_export.R`.
- Done when: totals, Main plus the new channel, equal the old Main for every method and metric; the channel identity checks pass; labels and exports updated; regular runs show no new channel.
- Tests: identity before and after on a shock fixture; snapshot updates for exports; the three consumers agree. Hot-path benchmark.
- Risk: the largest uncertainty in Phase 2 (touches snapshots and exports).

### P2-4: Binned weather triggers (M, after P2-0a)

Option 1 from plan section 3.2 if P2-0a passes: companion continuous column kept before `.apply_binning()` in the historical slice and every member, added to `weather_columns`, offered through `.sp_trigger_variables()` with its unit.

- Files: `R/fct_get_weather.R` (three call sites), `R/fct_simulations.R` (`weather_columns`), `R/fct_sp_shock.R`.
- Done when: existing model matrices and outputs are bit-identical (equivalence gate); a binned variable can be used for weather-level and return-period triggers; the companion is never a model term.
- Tests: companion excluded from model matrices; bit-identical outputs for existing runs; trigger thresholds on a binned variable equal those on its continuous source. Benchmark per the optimization guidelines.
- Fallback: option 2 ("bin at or beyond k") if P2-0a is no-go.

### P2-5: Impact-based triggers (M to L, after P2-0b)

Trigger on modelled loss, poverty rate or number of poor at location and national level. New `trigger_type` values, thresholds on the historical distribution of the metric (same record rule), applied unchanged to SSP members. Household-level modelled quantities only as a labelled oracle.

- Files: `R/fct_sp_shock.R` (thresholds, state), `R/mod_3_01_sp.R` (flyout), `R/fct_policy_sim.R` (`has_sp_change`, spec validation).
- Depends on: P2-0b; the poverty line from Step 2 (`hs$pov_line`).
- Done when: never-fires and always-fires invariants hold for each metric; preview equals run; basis risk scored against the same loss events; spec fields in signature and export.
- Tests: hand-calculated metric thresholds; scope truth table with the new trigger types; determinism.

### P2-6: Budgets linked to need (M, after P2-5)

Decision 7 scope: budget as a share of modelled loss with a ceiling, and the cap with pro-rata scale-down. AAL sizing, poverty-linked budgets and the envelope per activation are P3-5. Report coefficient of variation of annual cost, share of loss offset and share of affected poor not covered beside each rule.

- Files: `R/fct_sp_shock.R`, `R/fct_policy_sim.R`, `R/mod_3_01_sp.R`, `R/mod_3_08_diagnostics.R`.
- Done when: budget identity holds (total = net transfers + admin); an envelope is never exceeded; the ceiling binds as set; budget exhaustion share reported.
- Tests: identities, ceiling, monotonicity in the share, determinism; preview parity.

### P2-7: Anticipatory design (M to L, after P2-0c and P2-6)

Forecast skill (POD, FAR) with seeded draws keyed by (location, year, member); effectiveness multiplier on welfare, not on cost; delivery-delay multiplier reviving `timeliness_weeks`; breakeven `m` display; in-app statement of the static-model limitation.

- Files: `R/fct_sp_shock.R`, `R/mod_3_01_sp.R`, `R/mod_3_08_diagnostics.R`.
- Done when: POD = 1, FAR = 0, `m` = 1 reproduces the ex-post design exactly; false-alarm cost shows in cost outputs; the breakeven `m` is reproducible; draws independent of row order and chunk size.
- Tests: the identity above; monotonic in skill; determinism; breakeven hand example.

### P2-8: Layered geographic and predicted-welfare targeting (M)

`static rule AND dynamic rule` with geography (triggered locations, or worst-affected share) and optionally predicted welfare at trigger (oracle, labelled, larger default errors). Replaces the single dropdown in shock mode.

- Files: `R/fct_sp_shock.R`, `R/fct_policy_sim.R`, `R/mod_3_01_sp.R`.
- Done when: with the dynamic rule off, results equal Phase 1 exactly; the oracle option carries its label; the reach card reflects the layers.
- Tests: truth table for the layers; regression to Phase 1; preview parity.

### P2-9: Tests, benchmark and docs for Phase 2 (S to M)

Extend the invariants list in the plan; hot-path benchmark of the correction loop before and after Phase 2; update `AGENTS.md` (file entry, pipeline description) and roxygen; update the plan's decisions.

## 4. Phase 3: design-space tools (not scheduled)

| Task | Work | Size |
|---|---|---|
| P3-1 presets | Named presets (protective, preventive, promotive, custom) as data; combined "cash plus" scenarios use the existing levers. | S |
| P3-2 design sweep | Grid of shock designs reusing baseline pipelines and prepared channels; cost vs poverty-reduction frontier; bounded grid size, progress reporting, resource limits. Shock arm only at first. | M |
| P3-3 reserve dynamics | Carry-over and depletion need an ordered-year rule; years are draws today, so decide the rule first. | M |
| P3-4 amount rules | Gap-filling and tiered amounts; loss-proportional only as an oracle or not at all. | S to M |
| P3-5 further budget rules | Moved from P2-6 (decision 7): annual expected loss (AAL) sizing and premium-equivalent cost; budget proportional to the rise in the number of poor or the poverty gap; envelope per activation. Reuse the P2-6 ceiling and cap code. | M |

## 5. Dependencies

```
P0-8 --> Phase 1 close-out (P1-13..P1-20)
   |
   +--> P2-1 --\
   +--> P2-2 ---+--> P2-9
   +--> P2-3 --/
   +--> P2-0a --> P2-4
   +--> P2-0b --> P2-5 --> P2-6 --> P2-7 (also needs P2-0c)
   +--> P2-8 (independent, after P2-5 for shared trigger code)
Phase 3 follows Phase 2 outputs (P2-2, P2-6).
```

## 6. Risks

| Risk | Where | Mitigation |
|---|---|---|
| Decomposition split changes snapshots and exports | P2-3 | Numbers unchanged by construction; identity test before and after; update exports once |
| Weather-path change alters existing results or memory | P2-4 | Spike P2-0a first; bit-identical gate; fallback option 2 |
| Hot-loop slowdown (already +95 % in the loop) | P2-3, P2-5 to P2-7 | Benchmark each; cheaper key index and one `rowsum` for annual cost are ready options |
| Anticipatory multiplier read as a calibrated number | P2-7 | Default 1, breakeven display, explicit in-app limitation text |
| Impact-based triggers unobservable in practice | P2-5 | Location or national level by default; household level only as a labelled oracle |
| Cost-effectiveness read as covering all policy levers | P2-2 | Decision 5: cash transfers only, with the scope statement shown in the tab |
| P0-8 changes static program numbers | P0-8 | Own Decision log entry with BFA before and after; unit-weight and unweighted cases bit-identical |
| Unverified phase 1 UI/a11y | P1-13, P1-14 | Do the close-out before Phase 2 UI work |

## 7. Open questions

None blocking. Still to settle when reached: the unit-cost question for non-cash levers (out of scope until the policy team supplies unit costs) and the P0-9 literature pass (deferred).
