# Policy scenarios and macro links

Status: proposal, 2026-11-09. Issues: [#35](https://github.com/worldbank/wise-app/issues/35) (custom policy scenarios with user effect size), [#37](https://github.com/worldbank/wise-app/issues/37) (link with MFMod and Unbreakable). Methods: `docs/40_policy_framework.md`, `docs/41_policy_levers.md`, `docs/43_shock_responsive_sp.md`.

## #35 Custom scenarios with user effect size

Today a lever changes a survey variable, and the welfare effect is the fitted coefficient (an association, not a causal effect). The issue asks for effects taken from impact evaluations or reviews instead.

Proposal:

1. **New control type.** "Custom effect": the user names a scenario, picks the outcome and affected group (a filter on survey variables), enters an effect size in outcome units or percent, and optionally a bound for uncertainty (standard error or confidence interval).
2. **Method.** Add the effect to predicted welfare of the affected rows, as the cash transfer does (`docs/40_policy_framework.md`, Eq. 2.3 correction). Draw the effect from a normal with the entered standard error, independent of the model draws, and state that assumption in the card.
3. **Weather dependence.** First version: constant effect. Later: a user-entered effect that scales with weather change.
4. **Provenance.** Store the source citation in the run export so a result is traceable to the study.
5. **Skill.** `add-policy-lever` covers the registry and UI wiring; the decomposition needs a "user-specified" channel in `docs/44_decomposition.md`.

## #37 MFMod and Unbreakable

Exploratory (label: question). Two directions: WISE outputs as inputs to a macro model (household welfare change, shares in poverty by shock year), and macro outputs (prices, wages, employment) as inputs to WISE through lever values.

Proposal for now: do not build modules. Write a short interface note:

- Export a tidy table of per-year results by region and quintile in a documented schema, from the existing batch run.
- Import macro price or income changes as a percent-change lever on the consumption or labour income variable, using the existing percent-change lever.
- List what indirect channels are lost without the link, in `docs/50_assumptions_limitations.md`.

## Upstream data

- #35: a catalogue of effect sizes (programme, outcome, effect, standard error, source) would let users pick a published value; keep it outside the app first, as a CSV in the data directory.
- #37: schema agreement with the macro teams.
