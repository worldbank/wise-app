# Social protection: Phase 0 and Phase 1 task breakdown

Companion to `review/sp_shock_responsive_plan.md` (design, decisions 1 to 14). This file turns Phase 0 and Phase 1 into work items.

Status: proposal only. No shock-responsive code has been written. Reviewed 2026-10-07: scope and order are unchanged; code references were refreshed and the prerequisite fixes (R2-BUG-04, CR-BUG-02, R2-BUG-06/07/12, CR-BUG-04) have landed on `dev`. Sizes are rough (S under a week of focused work for one person, M one to three weeks, L more) and come from reading the code, not from prototyping.

## Progress

Status key: `☐` todo · `◐` partly done (remainder listed) · `☑` done and tested · `✗` not doing. Updated 2026-10-08. Phase 0 is committed (495ae85, 2b3822e); P1-1 and P1-2 are in the working tree until committed.

| Task | Status | What was done, what is left |
|---|---|---|
| P0-0 flyout spike | ☑ | See "Spike results" below. One CSS fix made. |
| P0-1 SP panel flyouts | ☑ | `mod_3_01_sp.R`: "Targeting details" flyout (proxy variable and cutoff, inclusion and exclusion errors, where errors fall) and "Payment settings" flyout (transfers per year, amount basis, administration cost), each with a one-line summary beside the button. Sidebar keeps the summary card, Program toggle, Amount, and the Targeting dropdown with the bottom-x% slider. Input ids and defaults are unchanged; the new flyout toggles are `targeting_toggle` and `payment_toggle` (the `_toggle` suffix keeps them out of the exported config). The "Targeting" and "Transfers per year" hidden labels remain. Checked in a real browser (chromote) against the actual module: layout, summaries, reach card. Not checked: keyboard-only walk-through and screen reader. |
| P0-2 admin cost | ☑ | `admin_cost_pct` (default 0, clamped to 0-90% in the engine, 0-50% in the UI), a share of total cost. Welfare uses the net transfer; the preview, diagnostics and component table report total cost including administration, with the transfer/admin split. Tests: default reproduces earlier numbers exactly, identity total = transfers + admin, budget never exceeded, preview equals run (`test-sp-design-options.R`). Not done: numeric presets (P0-9). |
| P0-3 per person amount | ☑ | `amount_basis` (`per_household` default, `per_capita`), household analysis only; the UI shows a note for other units. A total budget is shared over recipient people. Reach card shows "Annual transfer per person". Tests cover transfer arithmetic, cost, budget mode, other analysis units and the default. |
| P0-4 error placement | ☑ | `error_concentration` (0 random, 5 near the cutoff, 20 mostly near), distance is the percentile-rank difference from the cutoff; binary proxies, universal and unusable cutoffs stay uniform. At 0 the draw is the same `sample.int()` call as before; a test replays the old algorithm and checks `identical()`. Tests also cover exact error counts, determinism per seed and the direction of the effect. Not done: a Decision log entry is not needed because defaults are unchanged; revisit the 10% / 10% defaults with P0-9. Row-count (not weighted) error counting is documented in the code and the popover. |
| P0-5 cost-effectiveness metrics | ◐ | New `R/fct_sp_effectiveness.R` (`sp_effectiveness()`): annual cost per person, administration share, realised inclusion and exclusion error, coverage of the poor, leakage, adequacy. Shown as a "Cost and targeting effectiveness" table in the Diagnostics tab and registered for export (`policy_sp_effectiveness`). Poverty line: the Results line, falling back to the baseline run's line; unavailable lines show "Not available". Hand-calculation tests included. Left: poverty effect per cost (cost per person lifted out of poverty and similar) needs the Step 3 effect and the open decisions 1 to 3 in `review/step3_cost_effectiveness_plan.md` (gross or net people lifted, leading metric, tab or section); the diagnostics module does not have the effect today. |
| P0-6 plumbing | ☑ | The run signature hashes the whole SP list, so every new field marks results stale (tested). The export bundle records all inputs; the three new inputs travel and the two flyout toggles are dropped (tested). Provenance records source type and origin only, so it needed no change. |
| P0-7 currency | ☑ | R2-BUG-04 and CR-BUG-02 are committed. New code reads `sp$currency`. |
| P0-8 weighted error counts | ☐ | Optional, not started. Needs its own Decision log entry. |
| P0-9 admin presets | ☐ | Needs the literature pass; not a gate. |
| P1-0a spike weather variables | ☑ | See "Spike results". |
| P1-0b spike historical reference | ☑ | See "Spike results". |
| P1-0c spike consumers | ☑ | See "Spike results". |
| P1-0d spike loss reference | ☑ | Synthetic prototype and a real BFA check (8 October 2026), see "Spike results". |
| P1-1 spec and validation | ◐ | Spec fields added to `sp_scenario_spec()` (`trigger_type`, `trigger_variable`, `trigger_direction`, `trigger_value`, `trigger_return_period_years`, `payout_scope`, `national_k_pct`, `payments_per_activation`) with inert defaults; they enter the run signature automatically (tested). `.sp_shock_problem()` validates them; `has_sp_change()` has a shock branch (amount, payments per activation, valid trigger; budget mode ignored). The coercion of `sp_type == "shock"` to regular and the display-only alert were kept until the run applied the dynamic transfer; both are removed with P1-8. Tests: `test-fct_sp_shock.R`. |
| P1-3 trigger state | ☑ | `sp_trigger_state()` in `R/fct_sp_shock.R`: per prediction row `exceeds` and `in_scope`, survey-weighted exposed `share` and national `gate` by simulation year. Gate fires when the share is above 0 and at least `national_k_pct`, so `k = 0` makes `national_triggered` identical to `local`; `national_all` needs `k > 0` (validated: "any location fires, pay everyone" is not offered, decision 10). Rows with no finite value or no supported threshold never exceed. Threshold match is a keyed `left_join`; benchmark at P1-6 (4.9 million rows). Tests: scope truth table, weighted share hand example, `k = 0`, direction, return-period one-in-N per cell, row-order invariance. |
| P1-4 static eligibility | ☑ | `apply_policy_to_svy()` in shock mode writes `SP_ELIGIBLE_COL` (`.wiseapp_sp_eligible`, same `.determine_sp_eligibility()` and `wise_seed(seed, "policy", "sp")` stream) and no `SP_TRANSFER_COL`; an invalid shock spec writes neither. `.scenario_has_effect()` counts an eligible shock program. Tests: eligibility equals the regular program's `transfer > 0` for the same seed, determinism, regular mode unchanged. Left for P1-6/P1-9: the column lists in `fct_policy_decompose.R:58` and `fct_results.R:474` and the diagnostics definition of "treated" still look only at the transfer column. |
| P1-5 dynamic transfer | ☑ | `sp_dynamic_transfer()` reuses `.sp_transfer_values()` (household size, amount basis, currency) with `payments_per_activation`, then multiplies by `state$in_scope`; stored welfare scale like `SP_TRANSFER_COL`, convert with `outcome_level_scale()` at use. `sp_dynamic_effect()` is the `log(exp(y_t) + T) - y_t` formula (identity outcomes add directly); P1-6 should call it from the block in place of the inline copy, with a bit-identical check for the regular program. Tests: never-on is 0; always-on equals the regular program's transfer for per household, per capita, LCU, four payments and individual units; scope and NA handling; misaligned inputs refused; formula values. |
| P1-6 hook into the correction | ◐ | Done and tested at function level. `sp_shock_plan()` (thresholds from the historical exposure plus the per-survey-row transfer; plain data) is built once in `apply_policy_delta_to_baseline()` (new args `sp`, `analysis_unit`, passed by `mod_3_06_policy_sim.R`) and stored on the locked `prepared` object (`prepare_policy_annual_channels(..., shock =)`). `.policy_sp_dynamic()` computes the per-pipeline vector once, before any chunk or year loop, in all three consumers (`.policy_annual_channels()`, `.apply_policy_annual_pipeline()`, the attribution path); `.policy_annual_channel_block()` takes it as an optional 5th argument `sp_dynamic = NULL` and adds `sp_dynamic_effect()` into `delta_sp`, `delta_main` and `delta_total`, returning it as its own `delta_sp_shock` (absent for regular runs, which are unchanged). Trigger evaluation runs on the pipeline's small exposure table and is indexed by prediction row. Rows without a finite prediction use the observed baseline level, like the static transfer. Tests in `test-sp-shock-correction.R` (38 expectations): always-on equals the regular program for identity and log outcomes, never-on equals no program, paid rows are exactly exceeding and eligible rows, monotonic in threshold, national gate by year, Results, adapter and attribution agree (the attribution reconstruction check passes), chunk-size independence. Benchmark: a synthetic pipeline of 1.65 million prediction rows (180,000 exposure rows, 6,000 cells) takes 0.25 to 0.5 s per pipeline (about 13 MB for the vector), so about 1 s at 4.9 million rows; regular runs pay only a `NULL` check. The full Step 3 harness (`dev/bench_step2.R` with `WISEAPP_STEP2_INCLUDE_STEP3=1`) has not been run. Left: the slow reference `.policy_annual_channels_reference()` does not model shock; the column lists in `fct_policy_decompose.R:58` and `fct_results.R:474` and the diagnostics definition of "treated" (P1-9). Touches a protected file (`fct_policy_metric_decompose.R`) beyond whitespace, as the task requires. |
| P1-8 shock-mode UI | ◐ | Done and checked in a real browser (chromote, standalone module app with a synthetic 30-year exposure): the display-only alert and the shock-to-regular coercion are gone, so a shock selection now runs. A "Trigger settings" flyout (shock mode only) holds trigger type (weather level or return period), weather variable (continuous variables of the historical exposure only, read from the baseline survey), direction, threshold value or 1-in-x with the historical record length and annual probability, payout scope (three choices), the national gate share, and payments per activation, with a one-line summary or the validation message beside the button. In shock mode the "Total budget" pill and the "Transfers per year" slider are hidden, the budget mode is forced to per transfer, and `transfer_n_payments` carries payments per activation so the reach card and the cost arithmetic read one number. The summary card adds, from the historical years: years with payments, expected annual cost, 1-in-20 year cost (needs 20 years) and the average population in triggered locations; an unfinished trigger shows the missing item instead of numbers. New pure functions in `fct_sp_shock.R`: `sp_shock_preview()`, `sp_shock_annual()` (also the base for the P1-7 cost distribution), `sp_shock_pipeline_state()`; user-fixable trigger errors are a classed condition (`sp_trigger_problem`) so other errors still go through `wise_user_error()`. Tests (`test-fct_sp_shock.R`, 153 expectations): hand-calculated preview, scope and direction, administration, always-on equals the regular program's cost, 1-in-20 as the 95th percentile, flyout contents and the module card. Left: keyboard-only and screen reader walk-through (not checked); the flyout does not show the unit of a transformed variable (only the catalogue label) because Step 2's weather transformation is not passed to this module; the preview and the run use one function for thresholds, but a literal preview-equals-run test needs the P1-7 run summary. |
| P1-7 shock-mode outputs | ☑ | `sp_shock_pipeline_rows()` (per pipeline and year: activation, exposed share, transfer, administration and total cost, and population weights for true and false positives and negatives and for spending) is computed inside `.apply_policy_annual_pipeline()` from the baseline central predictions and returned with the pipeline; `apply_policy_delta_to_baseline()` binds them as `out$shock$rows` and `sp_shock_summary()` pools them by scenario: share of member-years with payments, mean, median and 1-in-20 (95th percentile, needs 20 member-years) annual cost with transfers and administration split, false-positive and false-negative rates (population-weighted, location level) and the share of spending in locations without a loss event. A loss event follows decision 6: the location's mean modelled loss, against each household's own historical mean level (`sp_shock_reference()`, levels not logs), is at or below minus `loss_event_pct` (new spec field, default 10, in the Trigger settings flyout). Published as `shock_summary` (atomic publish in `mod_3_06`), shown in the Diagnostics tab as a table (measures by scenario) and a cost chart, and registered for export (`policy_shock_summary`, `policy_shock_annual`, `policy_shock_cost`). Tests: hand-calculated cost, activation and basis-risk columns on the correction fixture, summary pooling, reference averaging, table and chart contracts, module render. |
| P1-9 run plumbing, diagnostics, export | ☑ | The whole SP list (all trigger fields and `loss_event_pct`) is already in the policy signature (tested). In the diagnostics snapshot a shock program counts a household as treated when it was paid in at least one historical year (`paid_historical`, from the historical arm), at the amount of one activation; the cost fields and the component table report the expected annual cost (historical mean) and the treatment explanation says so. The published `policy_svy` carries that transfer so the reach card and the Results headline keep one definition. The "Cost and targeting effectiveness" table is not reported for a shock program (its annual-cost basis needs a transfer paid every year) and says so. New inputs travel in the export config and `trigger_toggle` does not (tested); provenance records source type and origin only and needed no change. Not done: a run through the real app (Step 0 to 3) with a shock program, and a keyboard or screen reader check of the flyout. |
| P1-10 tests, benchmark, docs | ◐ | Invariants from plan section 9 are tests (`test-sp-shock-correction.R`, `test-fct_sp_shock.R`): never fires equals no program; always fires equals the regular program (identity and log); monotonic in threshold and amount; preview equals run for the historical arm; determinism under reordered prediction rows and chunk sizes; budget identity with administration; direction handling; warmer member fires a fixed historical trigger at least as often. `AGENTS.md` updated (file entry and the pipeline description). Benchmark on BFA (OLS, one SSP and period: 17 pipelines of 213,840 prediction rows, 3.6 million rows; model `t` and `spei6`; this laptop, two repetitions each): `apply_policy_delta_to_baseline()` takes 3.5 to 3.8 s for the regular static program and 7.0 to 7.2 s for a shock program (1-in-10 `t` trigger, local scope), so the shock layer adds about 3.4 s (+95 %) to the correction loop; process RSS after the shock run was 16 to 33 MB higher than after the regular run (sampled after the call, not a peak). Profile of the shock run: trigger state 1.3 s (of which the keyed join 0.9 s), annual cost and basis-risk rows 1.8 s. This is the correction loop only; the first visit of each Step 3 method (about 52 s on BFA 3x3) dominates the user-visible time. Possible cheaper alternatives if it matters: replace the keyed `left_join` with a one-time key index, and compute annual cost by one `rowsum` over year and survey row. Not run: `dev/bench_step2.R` Step 3 harness (it prepares `annual_channels` before the run, so it needs a shock fixture that builds the plan first). |
| P1-11 either-end trigger | ☑ | Added after the BFA basis-risk finding (8 October 2026). Direction `"either"` for variables that hurt at both ends (very dry and very wet). Weather level: a low and a high threshold (`trigger_value_low`, new spec field; the existing `trigger_value` is the high one; validated: both finite, low not above high). Return period: the 1-in-N chance is shared over two tails (the `1/(2N)` and `1 - 1/(2N)` quantiles per cell, so the total activation probability stays 1 in N), and since each tail is a 1-in-2N level the Step 2 record rule asks for 2N historical years; the flyout says up to `years / 2` is supported. Pill label "Either end". Tests: validation, weather-level OR, hand-computed tails on a 40-year cell (4 of 40 fire), the 2N rule, module spec and summary text. Deferred to Phase 2 by decision: the response check (modelled loss by decile of each variable, suggesting high, low or either) and any adverse-direction hint in the flyout; recorded in the plan. |
| P1-12 loss-event scoring | ☑ | Follows the 8 October review of where the loss-event share belongs. One input stays in the Trigger flyout, labelled scoring only. The sidebar card now shows the historical-arm basis risk ("Paid, no loss event", "Loss event, not paid") from the same `sp_shock_pipeline_rows()` the run uses. The run keeps compact per-cell loss data (`out$shock$cells`: scenario, member, year, population, mean relative loss, fired, spending) and `sp_shock_rescore()` recomputes the scoring columns and the summary for another share, so Diagnostics re-scores the finished run with the live input (`loss_event_pct` passed from the SP module to `mod_3_08`) and exports the re-scored tables. The share is excluded from the policy run signature (`.policy_sig_from_live()`), so changing it does not mark Step 3 stale. Costs and activation never depend on it. Tests: rescoring with the same share reproduces the run; a stricter share has fewer events; rescored rows equal a run made with that share; invalid shares and runs without cells pass through; a share-only change leaves results fresh while an amount change marks them stale. |
| P1-2 trigger thresholds | ☑ | New `R/fct_sp_shock.R`: `sp_trigger_thresholds()` (weather: common value; return period: per survey round, location and interview month, `1 - 1/N` quantile for `above`, `1/N` for `below`, type 7 as in Step 2), `.sp_trigger_variables()` (numeric exposure columns only, so binned variables are excluded). A 1-in-N trigger needs N finite historical years per cell; shorter cells get `NA` (never fire), and the call stops when no cell supports N. Hand-computed quantile, mirror, record-limit and row-order tests in `test-fct_sp_shock.R`. |

Verification: `test-sp-design-options.R` (20 tests, 99 expectations, including regression guards that the defaults reproduce the earlier numbers) and the related suites (`sp`, `policy`, `step3`, `diagnostic`, `a11y`, `export`, `deploy`, `determinism`, `mod_3` filters: 2803 passed). One failure: `test-deploy-contract.R:76` because `manifest.json` does not list the new `R/fct_sp_effectiveness.R`; regenerate the manifest after committing (`dev/00_make_manifest.R` builds from committed content). `devtools::document()` was not needed (no exports or roxygen blocks changed) and was not run.

### Spike results

**P0-0 (flyout in accordion, 7 October 2026).** Built a minimal app with the real theme, `custom.css`/`custom.js`, a sidebar accordion and two `config_flyout_block()`s, and drove it with chromote. At 1400 px the panel opens beside its toggle (`position: fixed`), is not clipped by the accordion or sidebar, and is the topmost element at its own position; one flyout is open at a time (opening the second closes the first), Escape closes it and returns focus to its toggle, `aria-expanded` follows. Below 992 px the panel falls back to inline flow but was only 168 px wide when sharing a row with the inline summary label; fixed with `flex: 0 0 100%` for `.config-flyout-inline .config-flyout` in `custom.css`. Two flyouts with identical "Configure" labels are ambiguous, so each now has its own `toggle_label`.

**P1-0a (weather variables as the model sees them).** Per variable the pipeline applies a temporal aggregation (mean or sum), then one transformation: `None` (physical units), `Deviation from mean` (against the 1991-2020 monthly mean per location) or `Standardized anomaly` (zero reference SD gives NA, R2-BUG-29); `spi6` and `spei6` are never transformed and dimensionless variables default to the anomaly. A variable can then be binned (breaks from the historical reference; exposure values become bin labels) and polynomial terms live in the model formula, not in the exposure. Consequence: a numeric trigger can use any continuous variable, in the unit its transformation implies (physical, deviation or z-score), and the UI must label that unit. Binned variables carry only a category in the exposure, so v1 should exclude them from trigger choices (or offer "bin at or beyond k", which is a larger change). Return-period triggers work for any continuous variable.

**P1-0b (historical reference).** Each pipeline's exposure table is keyed by `code`, `year` (survey round), `survname`, `loc_id`, `int_month`, `sim_year`, `timestamp` (`.policy_exposure_key_cols`, `fct_simulations.R:797`). The historical arm therefore gives, per (survey round, `loc_id`, `int_month`), one value per historical `sim_year`; the number of finite years there is the record length behind a 1-in-N threshold. Future member pipelines carry the same key columns, so thresholds computed from the historical arm join by (`code`, `year`, `survname`, `loc_id`, `int_month`). Sketch: `ref <- hist_exposure[, c(keys, var)]` grouped by the five keys, `threshold = quantile(value, 1 - 1/N)` for an adverse high tail (`1/N` for a low tail), `n_years = sum(is.finite(value))`; use the same tail and quantile rule as `step2_adverse_return_period()` (`fct_sim_compare.R:537`) so Step 2 and the trigger agree. `step2_exposure_resolve()` rebuilds the table for a pipeline from its compact recipe and owner scenario.

**P1-0c (consumers of the correction).** `.policy_annual_channel_block(pipeline, prepared, exposure, rows)` has three callers, all with `pipeline`, `prepared` and the validated `exposure` in scope: `.policy_annual_channels()` (`fct_policy_metric_decompose.R:183`), `.apply_policy_annual_pipeline()` (`:268`) and the attribution path (`:619`). `prepared` is locked and weather-invariant, so the dynamic vector cannot live there. Recommendation: compute one per-pipeline vector `sp_dynamic` (aligned with the pipeline rows) next to `.validate_policy_annual_exposure()` and pass it as an optional fifth argument `sp_dynamic = NULL` to the block; with `NULL` the block behaves exactly as today. The block already recomputes `delta_sp` per row from `transfer[ids]` and `y_t` (R2-BUG-07); the dynamic transfer replaces `transfer[ids]` there.

**P1-0d (loss reference), synthetic.** With `loss = level(yhat) - own historical mean of level(yhat)` on central predictions: zero mean in the historical arm by construction; a warmer member gives negative mean loss (about -6% of the household's reference level in the prototype); averaging levels before comparing, not logs, matters (-6.2% vs -6.4% on the log scale), so the back-transform must come before the mean; location-level loss has a much smaller spread than household-level loss (sd 0.025 vs 0.077 with 10 households per location), so a loss-event threshold set as a share of welfare will fire far less often at location level than household level, which the basis-risk output must make visible. 

**P1-0d (loss reference), real BFA (8 October 2026).** BFA 2021 baseline (7,128 households), OLS with `t` and `spei6`, log outcome, historical 1991-2020 plus SSP2-4.5 2025-2035 (16 members; the other 7 are excluded for partial coverage). Same formula: level-scale `exp(yhat)` minus the household's own historical mean level, central predictions. Results: (1) the historical arm has weighted mean loss 0 (2e-17), as designed. (2) Member means of loss relative to the reference level range from -8.0% to +5.3%; 13 of 16 are negative, a few percent on average, and two members are positive, so the sign follows each member's weather, not an artefact. (3) The back-transform order matters as in the prototype: using the mean of logs as the reference shifts every member by +0.45 points (for example -6.1% vs -5.6%), so the level mean must be used. (4) No non-finite losses. (5) Household and location spread are equal here (sd about 0.09 both), unlike the prototype: with a weather-only model every household in a location has the same relative loss, so location-level and household-level basis risk coincide until the model has weather-covariate interactions. The prototype's warning (location loss events fire less often than household events) holds only for models where households respond differently. (6) A loss event at "5% below the reference" occurs in 31% of historical household-years, because the weather-driven spread is about 9% of welfare; the user-set loss share therefore needs a sensible default and help text. Also exercised P1-2 on the real exposure: 733 location-month cells, 30 historical years each, all supported; a 1-in-10 `t` trigger fires in 10.2% of historical cell-years (3 of 30 per cell; ties add 0.15 points) and in 21% to 85% of member cell-years under SSP2-4.5, which is the expected warming direction. The capture script is not committed (scratchpad only).

## 0. Conventions

- Task ids: `P0-n` (Phase 0), `P1-n` (Phase 1). "Spike" means a short investigation that ends in a written answer and may change later tasks.
- Every task lists: files touched, dependencies, "done when", and tests.
- Repository rules that apply to all tasks (`AGENTS.md`, user instructions): `fct_` files stay free of Shiny; touch only files the task needs; run the narrowest meaningful check (`devtools::test(filter = "...")`); run `devtools::document()` when roxygen or exports change; no commits or pushes unless requested; code, comments and commit messages use ASCII quotes and hyphens.
- Reproducibility is a requirement for every task (plan section 4.7): same inputs and seed give identical outputs, independent of row order, chunk size and thread count; the preview equals the run; every new spec field enters the run signature and the export. Each task that changes numbers or draws carries a determinism test.
- Any change in the Step 3 hot path (the annual correction loop) needs the benchmarking described in `review/optimization_guidelines.md` before it is accepted.
- Tests are named after the file or concept they cover (`test-fct_sp_shock.R`, extensions of `test-sp-reach.R`).

## 1. Facts from the code that shape the tasks

These were checked while preparing this breakdown.

1. **Exposure unit.** The weather exposure table is keyed by (`code`, `year`, `survname`, `loc_id`, `int_month`, `sim_year`, `timestamp`) (`.policy_exposure_key_cols`, `fct_simulations.R:797`). A prediction row is a household in one `sim_year`, using weather at its location for its interview month. So the natural evaluation unit for a "location trigger" is (location, interview month, `sim_year`). Households in the same location but interviewed in different months can differ in activation in the same year.
2. **One hook, three consumers.** `.policy_annual_channel_block()` (`fct_policy_metric_decompose.R:188`) is called from `.policy_annual_channels()` (line 183), `.apply_policy_annual_pipeline()` (line 268) and the metric attribution path (line 619). The dynamic transfer must be applied inside or immediately beside that function, or the Results and Decomposition tabs would disagree.
3. **The SP channel already exists in the compact stats.** The correction loop already accumulates `delta_total`, `delta_main`, `delta_sp`, `delta_main_covar`, and the two resilience channels. "Fold into Main" (decision 1) therefore means adding the dynamic effect to `delta_sp`, `delta_main` and `delta_total` together. No new column is needed in Phase 1.
4. **Convention for the dynamic effect.** For log outcomes the annual block now computes the SP effect against the predicted year-t level, `log(exp(y_t) + T) - y_t` with `y_t = pipeline$y_point` (R2-BUG-07; rows without a finite prediction keep the observed-baseline value, and a zero transfer stays exactly 0). The dynamic effect must use this same formula with a per-row `T`, so channel identities and the level-scale channels (`.policy_level_channels`) stay consistent. The static `.compute_rif_channels()` path still uses the observed baseline. The transfer is converted to the model scale with `.policy_sp_transfer()` / `outcome_level_scale()` (CR-BUG-02); the stored column stays on the 2021 PPP scale.
5. **Static column must stay empty in shock mode.** `apply_policy_to_svy()` writes `.wiseapp_sp_transfer` (`fct_policy_sim.R:996`). In shock mode it must write an eligibility column instead and no transfer, or the transfer would be counted twice (static plus dynamic). Diagnostics currently define "treated" as transfer greater than zero (`fct_policy_diagnostics.R`), so they need a shock-mode definition.
6. **Flyout pattern.** `config_flyout_block()` (`utils_ui.R:655`) builds an anchored, one-open-at-a-time panel with `aria-expanded`, focus management and Escape to close (`custom.js`, `.config-flyout` in `custom.css`). It accepts a `display_label` for an inline summary beside the button. Inputs in a flyout are registered eagerly only if `uiOutput` content is added to the `suspendWhenHidden = FALSE` list, as the SP module already does (UI-43). Static inputs in a `conditionalPanel` register by default.
7. **Existing test hooks on the SP UI.** `test-a11y-contract.R:198-199` asserts the source contains the hidden labels `"Targeting"` and `"Transfers per year"`. Keep those labels when controls move into flyouts.
8. **Working tree.** At the 2026-10-07 review, `git status` showed no uncommitted changes under `R/`, `inst/` or `tests/` (only docs and version files), so the Q1 condition (headline-cards work committed) is met. Re-check `git status` before starting.
9. **Existing SP behaviour that tasks must preserve.** Ex-ante poor targeting uses a survey-weighted quantile (`.sp_welfare_quantile()`, CR-BUG-04); the SP draw stream is `wise_seed(seed, "policy", "sp")` (R2-BUG-12); NA outcome or transfer rows are treated as untreated and counted (R2-BUG-13); the spec carries `currency`; Step 3 is blocked when the Step 2 model signature is stale (R2-BUG-14).

## 2. Phase 0: independent improvements

Target: about 1 to 2 weeks in total. All tasks improve the regular program and none depend on the shock engine, except P0-1, which provides the UI home for P0-2 and P0-3.

### P0-1: SP panel restructure into flyouts (M)

Move the detail controls out of the sidebar so the SP accordion panel stays short. Layout (decided, Q3):

| Location | Controls |
|---|---|
| Sidebar (always visible) | Reach and cost summary card; Program pill toggle; Amount (per household or total budget); Targeting dropdown and its main cutoff (bottom x% slider) |
| Flyout "Targeting details" (inline label summarising the setting) | Proxy variable and cutoff; inclusion and exclusion errors |
| Flyout "Payment settings" | Transfers per year; amount basis (P0-3); admin cost (P0-2) |
| Flyout "Trigger settings" (P1-8, shock mode only) | Trigger, payout scope, payments per activation |

- Files: `R/mod_3_01_sp.R`; `R/utils_ui.R` only if the shared block needs a small extension; `inst/app/www/custom.css` only if the flyout needs SP-specific tweaks.
- Depends on: P0-0 spike.
- Done when: all existing SP inputs keep their ids and defaults; the scenario spec is unchanged for an untouched panel (UI-43 contract); flyouts open, close, take focus and close on Escape; the preview card still shows the same numbers for the same inputs.
- Tests: extend `test-a11y-contract.R` (labels retained, flyout toggles have `aria-controls`); add a source-level or rendered-HTML check that the SP module builds its flyout toggles; keep `test-sp-reach.R` green.

#### P0-0: flyout-in-accordion spike (S)

The SP module lives inside a `bslib::accordion_panel` inside a sidebar (`mod_3_scenario.R:18-26`). Existing flyouts are in plain sidebars. Confirm that a `position: fixed` flyout opens beside its toggle, is not clipped by the accordion or sidebar overflow, and is not hidden behind other layers (`z-index: 1046`). Check also narrow screens (the CSS falls back to inline flow below 992 px). Output: a short note, plus any CSS fix needed. Use the `run` skill to look at it in the real app.

### P0-2: Admin cost markup (S to M)

- New spec field `admin_cost_pct` (default 0), defined as a share of total cost, so the net transfer is `(1 - a)` of spend (plan section 5.1).
- Welfare effect uses the net transfer only. Admin is a cost, not a welfare gain.
- Budget-first: net transfer per recipient is `budget * (1 - a) / recipients`. Transfer-first: total cost is `net transfer cost / (1 - a)`.
- Cost reporting: separate transfer cost, admin cost and total cost in `.sp_transfer_totals()` and `.sp_scenario_reach()`; show total in the summary card and the split in the diagnostics tab.
- Files: `R/mod_3_01_sp.R` (input in the Payment settings flyout), `R/fct_policy_sim.R` (`.sp_transfer_values`, `.sp_transfer_totals_values`, `.sp_scenario_reach`), `R/fct_policy_diagnostics.R` and `R/mod_3_08_diagnostics.R` (cost wording and columns).
- Depends on: P0-1 for the control location (can be built first with the control temporarily in the sidebar).
- Done when: with `admin_cost_pct = 0` all numbers are identical to today (regression); with `a > 0` the budget identity holds (total cost = net transfers + admin); preview equals run.
- Tests: extend `test-sp-reach.R` (parity and identity with admin); `test-step3-wave2-e.R` if it covers diagnostics cost.
- No numeric presets in v1 (see Q5).

### P0-3: Per capita vs per household amount (S to M)

- New spec field `amount_basis` in `"per_household"` (today's behaviour, default) and `"per_capita"`. Applies only to household analysis units.
- Per capita: each recipient person receives the amount, so the household's per-capita welfare gain is not divided by `hhsize`. Cost scales with household size. Budget-first divides by recipient persons, not households.
- Reach card wording: "Annual transfer per household" vs "per person".
- Files: `R/fct_policy_sim.R` (`.sp_transfer_values`, totals, reach), `R/mod_3_01_sp.R`, `R/mod_3_08_diagnostics.R` labels.
- Done when: default reproduces today's numbers exactly; per-capita changes who gains in the expected direction (larger households gain more per household); preview equals run.
- Tests: `test-sp-reach.R` additions; a numerical check on a small synthetic survey.

### P0-4: Distance-weighted targeting errors (M)

Plan section 5.4 proposed a noisy-score model. On inspection a simpler mechanism fits better: keep the exact inclusion and exclusion counts (so the sliders mean what they say today), but choose which units to flip with probability decreasing in distance from the cutoff, instead of uniformly. One concentration parameter; large values reproduce uniform flips. Reasons: the sliders and the preview stay interpretable, the stream stays seeded, and there is no calibration step (a noisy score cannot, in general, hit two target error rates with one noise parameter).

- Files: `R/fct_policy_sim.R` (`.determine_sp_eligibility`), `R/mod_3_01_sp.R` (concentration control inside Targeting details), `R/fct_policy_diagnostics.R` only if labels change.
- Distance is the welfare percentile distance for ex-ante poor targeting and the rank distance of the proxy variable for continuous proxies. Binary proxy variables have no distance, so they keep uniform flips.
- Depends on: P0-1 (control location). Output changes numbers, so it needs a Decision log entry in the review tracker with before and after headline numbers.
- Done when: with the concentration at its "uniform" setting, results equal today's exactly; with concentration on, flipped units are measurably closer to the cutoff; counts and determinism hold.
- Tests: new tests for count preservation, distance effect, determinism under reordered rows, preview parity.
- Known limitation, not fixed here (Q6): flips are counted by sample rows, not survey weights, so weighted rates differ slightly from the sliders. Document it in the Targeting details help and in the code comment; P0-8 covers the fix.

### P0-5: Cost-effectiveness metrics for the regular program (M)

Build the "compare designs" outputs for the static program first, since they carry over to the shock engine.

| Metric | Source | Notes |
|---|---|---|
| Coverage of the poor | Baseline and policy survey frames | Share of poor households (baseline welfare below the poverty line) that receive a transfer |
| Leakage | Same | Share of spending reaching households above the poverty line |
| Adequacy | Same | Average transfer as a share of the average poverty gap of recipients below the line |
| Poverty effect per cost | Step 3 results (average year and 1-in-20 year) and cost | People lifted out of poverty, or change in the headline poverty metric, per unit cost |

- New pure functions in a new file `R/fct_sp_effectiveness.R` (no Shiny). Display in the diagnostics tab (`mod_3_08_diagnostics.R`) as a table, not in the headline cards, because the cards are under separate review (`review/archive/headline_cards_review.md`). The fuller results design that builds on this task is `review/step3_cost_effectiveness_plan.md`; keep the two consistent (it names the same file, `R/fct_sp_effectiveness.R`).
- Spike inside the task: find where the Step 3 poverty headline numbers are stored so "per cost" reuses them rather than recomputing.
- Depends on: P0-2 (cost with admin).
- Done when: metrics reproduce hand calculations on a small synthetic survey; weights and household size are handled as in `.sp_transfer_totals`; missing poverty line shows "not available" rather than an error.
- Tests: new `test-fct_sp_effectiveness.R`.

### P0-6: Spec, signature and export plumbing for new fields (S)

New fields (`admin_cost_pct`, `amount_basis`, concentration) must appear in `sp_scenario_spec()`, flow into the run signature (a plain list goes through `.sig_plain` automatically, but check the stale logic), and into export and provenance. `fct_export.R` and `fct_provenance.R` have no direct `sp` reference, so first confirm how the bundle records the scenario.

- Done when: changing any new field marks results stale; the export bundle records them.
- Tests: extend `test-export-bundle.R` and the stale-signature tests.

### P0-8: Weighted-share targeting errors (S to M, optional, after P0-4)

Make inclusion and exclusion errors hit the weighted share the sliders describe, instead of the row count. Flip units (using the same distance-weighted selection from P0-4) until the weighted share of non-eligible units included, or of eligible units excluded, reaches the target, in person weights for household surveys under the household convention used by `.sp_transfer_totals()`.

- Why separate: it changes the static program's numbers for weighted surveys. Keeping it apart from P0-4 means P0-4 can promise "default reproduces today's numbers exactly" and each change gets its own Decision log entry with before and after headline numbers (the tracker requires this for output changes).
- Files: `R/fct_policy_sim.R` (`.determine_sp_eligibility`), `R/mod_3_01_sp.R` help text.
- Depends on: P0-4. Not a gate for Phase 1.
- Done when: realised weighted incl and excl rates equal the sliders within one unit's weight on weighted synthetic surveys; unweighted surveys unchanged; preview equals run; determinism holds.
- Tests: extend the P0-4 tests with a weighted survey whose weights vary widely.

### P0-9: Admin cost presets (follow-up, not a gate)

Evidence-backed presets for the admin cost percentage by delivery method, after a literature pass (cost-transfer ratio sources are listed in section 9 of the plan). Until then the control is a plain percentage with a short help text and no suggested values. Owner: the project owner unless someone else is named. Output: a short sourced table with ranges and caveats; then a preset dropdown (S). Same pass should check whether the 10% / 10% default for targeting errors is defensible against proxy-means-test error evidence.

### P0-7: Currency dependency (tracked elsewhere)

R2-BUG-04 (SP transfer applied as PPP dollars when the outcome is in LCU) belonged to batch B4 of the review tracker (now in `review/archive/REVIEW-2026-10-06-tracking-full.md`) (Q2). Decision: it is fixed first, and it is a gate for P0-2, P0-3 and P1-5.

Status (updated 7 October 2026): done and committed (134170e; touched `R/fct_policy_sim.R`, `R/fct_policy_diagnostics.R`, `R/mod_3_01_sp.R`, `R/mod_3_08_diagnostics.R`, `tests/testthat/test-sp-reach.R`). The SP spec now carries `currency` (outcome units). The transfer column stays on the stored-welfare scale (2021 PPP), so an LCU amount is divided by per-row `ppp2021`; totals, the reach card and diagnostics report cost back in the entry currency. New tasks read `sp$currency` for admin cost, cost distributions and the reach card. The gate is met for R2-BUG-04.

CR-BUG-02 (RIF model scale for LCU outcomes) is fixed as well (0228c1c, 7 October 2026): `outcome_level_scale()` / `outcome_to_model_scale()` in `R/fct_results.R` are the single definition of the model scale, and `SP_TRANSFER_COL` is converted at use (`.policy_sp_transfer()`), so it stays on the stored 2021 PPP scale. New tasks that read the outcome or the transfer (P1-5, P1-6, P1-7) must use these helpers rather than `svy[[outcome]]` or the transfer column directly. Still owed (by the user, tracked under "Waiting on the user" in `review/REVIEW-2026-10-06-tracking.md`): a BFA run with an LCU outcome for the Decision log. The two display leftovers (policy summary label in `utils_ui.R`, Amount pill and popover in `mod_3_01_sp.R`) are also fixed: LCU amounts are labelled "2021 LCU" / "LCU", never "$". The amount is read as 2021-price LCU, the same convention as the "LCU (2021)" outcome option and LCU poverty lines (stored welfare = nominal LCU / cpi / ppp2021, so 2021 LCU = stored x ppp2021).

## 3. Phase 1: shock-responsive MVP

Target: about 3 to 5 weeks. Scope fixed by decisions 1 to 12 of the plan. Ex-post only; weather threshold and return-period triggers; payout scope control; transfer per household per activation; admin cost; outputs for activation frequency, annual cost distribution and basis risk.

### P1-0: Spikes before building (S, one to two days each)

- **P1-0a: weather variables as the model sees them.** Which weather columns does the exposure table hold (physical units, anomalies, binned categories)? The trigger needs a numeric value in physical units. If a variable enters the model as bins or a transformation, decide how a trigger relates to it. Output: list of trigger-eligible variable types and how to read their numeric value.
- **P1-0b: historical reference.** How to obtain the historical distribution of each weather variable per (location, interview month) from `hist_sim$weather_raw` and the resolved exposure (`step2_exposure_resolve()`), the number of historical years behind it, and how SSP member pipelines map to it. Output: a function sketch and `n_years`.
- **P1-0c: all consumers of the correction.** Confirm the three callers of `.policy_annual_channel_block` (fact 2) and decide how the per-pipeline dynamic vector reaches them (extra argument or attached to the validated exposure object).
- **P1-0d: loss reference.** Prototype the modelled weather loss of plan section 4.4 (central prediction, own historical mean) on one dataset and check it behaves (sign, scale, log back-transformation).

### P1-1: Spec and validation (S)

- Remove the coercion of `sp_type == "shock"` to regular (`sp_scenario_spec()`, `mod_3_01_sp.R:514-523`) and the display-only alert (`:150-160`).
- New spec fields: `trigger_type` (`"weather"` or `"return_period"`), `trigger_variable`, `trigger_direction` (`"above"` or `"below"`), `trigger_value`, `trigger_return_period_years`, `payout_scope` (`"local"`, `"national_triggered"`, `"national_all"`), `national_k_pct`, `payments_per_activation`.
- `has_sp_change()`: shock mode needs a positive amount and payments, and a valid trigger.
- Shock mode supports "$ per household per activation" only (decision 12); budget-first is hidden in shock mode.
- Files: `R/mod_3_01_sp.R`, `R/fct_policy_sim.R` (`has_sp_change`).
- Tests: `test-policy-lever-activity.R` additions; spec defaults when the panel is untouched.

### P1-2: Trigger thresholds (M)

New file `R/fct_sp_shock.R` (pure, no Shiny).

- `sp_trigger_thresholds(hist_exposure, spec)`: weather type returns one common threshold; return-period type returns a threshold per (location, interview month) at the 1-in-N level of the historical record in the adverse direction.
- Apply the Step 2 rule: a 1-in-N trigger is available only when the historical record has at least N finite years (decision 8, `filter_historically_supported_return_periods()` logic); return the years behind each threshold.
- Depends on: P1-0a, P1-0b.
- Done when: thresholds reproduce a hand-computed quantile on a small panel; unsupported N is refused with a clear message; direction `below` mirrors `above`.
- Tests: new `test-fct_sp_shock.R`.

### P1-3: Trigger state (M)

- `sp_trigger_state(exposure, thresholds, weights, spec)` returns, per prediction row, `exceeds` (logical), and per (`sim_year`) the survey-weighted exposed population share, plus the national gate result for `national_k_pct`.
- Payout scope: local (row exceeds), national gate then local (gate fired and row exceeds), national gate then all (gate fired).
- One pre-pass per pipeline before the chunk loop; memory is one logical vector per pipeline (about 20 MB at 4.9 million rows).
- Depends on: P1-2.
- Tests: scope truth table (three scopes by gate fired or not by row exceeds or not); weighted exposed share on a hand example; `k = 0` equals local behaviour.

### P1-4: Static eligibility in shock mode (S)

- `apply_policy_to_svy()` in shock mode writes an eligibility column (new constant alongside `SP_TRANSFER_COL`) using the same `.determine_sp_eligibility()` and the same seeded stream, and writes no transfer (fact 5).
- Ex-ante poor stays defined on the whole survey frame (decision 11).
- Files: `R/fct_policy_sim.R`.
- Tests: shock mode leaves `SP_TRANSFER_COL` absent; eligibility equals the regular program's for the same seed; `.scenario_has_effect()` handles shock mode.

### P1-5: Dynamic transfer (M)

- `sp_dynamic_transfer(state, eligibility, spec, svy, analysis_unit)` returns the daily-equivalent transfer per prediction row: `amount * payments_per_activation / 365`, divided by household size under the household convention, zero unless eligible and in scope.
- Effect on welfare as `log(exp(y_t) + sp_row) - y_t` against the predicted year-t level (fact 4, R2-BUG-07); identity outcomes add directly.
- Depends on: P1-3, P1-4. Also depends on P0-3 for the amount basis.
- Tests: zero when never triggered; equals the regular program's per-row transfer when always triggered with the same payments (OLS exact).

### P1-6: Hook into the correction (L)

- Apply the dynamic vector inside `.policy_annual_channel_block()` (or by one extra argument threaded through all three callers) so it adds to `delta_sp`, `delta_main` and `delta_total` (decision 1, fact 3).
- Compute the trigger state once per pipeline before the chunk loop in `.apply_policy_annual_pipeline()` and pass it down.
- Keep the dynamic effect as its own vector inside the block so the Phase 2 channel split is presentational.
- Since R2-BUG-07 the block already recomputes `delta_sp` per row for log outcomes (`transfer[ids]` against `y_t`), so the dynamic transfer substitutes for that per-row `transfer` input. This likely makes the hook smaller than first estimated, but the size stays L until the three-consumer consistency work is scoped.
- Depends on: P1-0c, P1-5.
- Verification: same results on the Results tab, the Decomposition tab and the attribution path for the same run; benchmark the loop before and after (optimization guidelines).
- Tests: extend `test-fct-policy-metric-decompose.R` and `test-policy-central-kernel.R` with a shock case; consistency between the three consumers; zero-trigger run equals baseline; determinism.
- Risk: this is the largest task and the one most likely to surface surprises (RIF repositioning is not updated for the dynamic transfer, by design: plan section 4.3; state this in the code comment and the UI help).

### P1-7: Shock-mode outputs (M)

New pure function `sp_shock_summary()` (in `fct_sp_shock.R`):

| Output | Definition |
|---|---|
| Activation frequency | Weighted share of (member, year) pairs in which the program activates (any recipient paid), by scenario and period |
| Annual cost distribution | Mean, median and 1-in-20 annual cost across years and members, with transfer and admin shown separately |
| Basis risk | False-positive and false-negative rates of the trigger against location-level loss events (decision 6), computed from the modelled loss of plan section 4.4 |
| Leakage by scope | Share of spending in locations without a loss event |

- Stored with the run (atomic publish, INT-09) in `mod_3_06_policy_sim.R` alongside `diagnostic_summary_rv`; displayed in `mod_3_08_diagnostics.R` as a table and a cost distribution plot; included in the export bundle.
- Depends on: P1-0d, P1-6.
- Tests: hand-checkable synthetic panel for each output; a plot-contract test in the style of `test-visualization-contracts.R`.

### P1-8: Shock-mode UI (M)

- Trigger settings flyout: trigger type (weather or return period), variable, direction, threshold value or 1-in-x (with the annual probability shown beside it), the supported range and the number of historical years, payout scope (three choices), `k` when a national gate is chosen, payments per activation.
- Sidebar: Program toggle now live; the summary card in shock mode shows expected activation frequency, expected annual cost and 1-in-20 cost from the historical pipeline (debounced, as the current preview is); label the unit as "survey location".
- Default text explains the RIF approximation and the ex-post-only scope.
- Depends on: P1-1, P1-3, P1-5; P0-1 for the flyout skeleton.
- Tests: rendered-HTML checks for the flyout and its accessible names; a preview parity test (preview equals run) in the style of `test-sp-reach.R`.

### P1-9: Run plumbing, diagnostics and export (M)

- `mod_3_06_policy_sim.R`: new fields flow into the signature and the stale logic; the new summary is published atomically.
- `fct_policy_diagnostics.R`, `mod_3_08_diagnostics.R`: shock-mode definition of "treated" (paid in at least one activation) and the treatment explanation text (`.policy_treatment_explanation`).
- Export and provenance record the shock fields.
- Tests: extend `test-export-bundle.R`, `test-policy-diagnostic-snapshot.R`.

### P1-10: Tests, benchmark and documentation (S to M)

- Invariants from plan section 9: never triggers equals baseline; always triggers matches the static program (OLS); monotonic in threshold; preview parity; determinism under reordered rows and different chunk sizes; budget identity; direction handling.
- Benchmark the correction loop (rows per second and peak memory) on a real run; compare with the current baseline.
- Update `AGENTS.md` (the `fct_sp_shock.R` entry and the shock-responsive pipeline description) and the roxygen docs; update `review/sp_shock_responsive_plan.md` decisions as they change.

## 4. Dependencies and order

```
P0-0 -> P0-1 -> P0-2 -> P0-5
          |  \-> P0-3
          \----> P0-4
P0-4 -> P0-8 (optional)
P0-6 follows P0-2, P0-3, P0-4
P0-9 (literature pass) is independent and not a gate

P1-0a/b/c/d (spikes, can start any time) 
P1-1 -> P1-4
P1-0a,b -> P1-2 -> P1-3 -> P1-5 -> P1-6 -> P1-7 -> P1-9 -> P1-10
P0-1, P1-1, P1-3, P1-5 -> P1-8
```

Phase 1 spikes and P1-1 can run in parallel with Phase 0. P1-5 needs P0-3 only for the amount basis. P1-6 is the critical path.

## 5. Risks

| Risk | Where | Mitigation |
|---|---|---|
| Binned or transformed weather variables do not give a usable numeric trigger value | P1-2 | Spike P1-0a first; restrict triggers to supported variable types and say so in the UI |
| Per-month, per-location evaluation surprises users (same location, different activation by interview month) | P1-3, P1-8 | Decided to accept (Q4); explain in the flyout help |
| Hot-loop slowdown | P1-6 | Pre-pass once per pipeline; benchmark before merging |
| Results, Decomposition and attribution paths disagree | P1-6 | One hook in the shared block; three-consumer consistency test |
| Static program numbers change under P0-4 | P0-4 | Default setting reproduces today's numbers; Decision log entry with before and after |
| Merge conflicts with uncommitted headline-card work | All | Resolved at the 2026-10-07 review (tree clean under `R/`); re-check `git status` before starting (Q1) |
| Currency bug (R2-BUG-04) makes dollar amounts wrong in LCU surveys | P0-2, P0-3, P1-5 | Fixed (134170e); new code must read `sp$currency` and use the CR-BUG-02 helpers. A BFA LCU re-run is still owed for the Decision log |

## 6. Decisions and open questions

Decided (7 October 2026):

| # | Question | Decision |
|---|---|---|
| Q1 | Sequencing vs uncommitted headline-card changes | Wait until the headline-cards work is committed, then start SP implementation from a clean `dev` (condition met at the 2026-10-07 review). Spikes (P0-0, P1-0a to P1-0d) and documentation can proceed in the meantime because they do not edit shared files. |
| Q2 | R2-BUG-04 (currency) | Fix first, as a prerequisite. The CR-BUG-02 / R2-BUG-04 work (done, 0228c1c and 134170e) lands before shock mode ships. P0-7 becomes a gate: P0-2, P0-3 and P1-5 should not merge before it. P0-1, P0-4, P0-5 and the P1 spikes are not blocked by it. |
| Q3 | Sidebar vs flyouts | Sidebar: summary card, Program toggle, Amount, Targeting dropdown with its main cutoff slider. Flyouts: Targeting details (proxy variable and cutoff, errors, concentration), Payment settings (transfers per year, amount basis, admin cost), Trigger settings (shock mode only). |
| Q4 | Trigger evaluation unit | (location, interview month, `sim_year`), matching the model's own exposure. Explain it in the Trigger settings help and label the unit "survey location". P1-0a still confirms against real exposure tables. |
| Q5 | Admin cost | v1 ships with a user-entered percentage of total cost, default 0, no presets. Presets are P0-9, a non-blocking follow-up owned by the project owner unless someone else is named. |
| Q6 | Row-count vs weighted-count errors | Document in P0-4; fix as the separate optional task P0-8 after P0-4, with its own Decision log entry. Rationale: P0-4 can then guarantee that its default reproduces today's numbers exactly, and each numerical change stays attributable. |

No open questions remain for Phase 0 and Phase 1. Items to watch: the outcome of spikes P1-0a to P1-0d (they can still change P1-2, P1-3 and P1-6), (the currency fix, Q2, is done).
