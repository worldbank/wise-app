# Survey and outcome statistics

Status: proposal, 2026-11-09. Issues: [#78](https://github.com/worldbank/wise-app/issues/78) (prettier survey stats), [#76](https://github.com/worldbank/wise-app/issues/76) (outcome stats). Both are Step 1 data-exploration features with no model change.

## Where things stand

The Survey Stats panel already reports weighted summaries, coverage and missingness, timing and related diagnostics before the outcome is chosen. After the outcome is chosen, the app shows outcome distribution plots, maps, summary statistics, missingness information and a CSV export. The remaining asks, from the issue comments, are:

- A compact per-variable distribution view like the summary panel of the Positron Data Explorer (#78): percent missing, a mini histogram or bar chart per variable.
- Profiling of the outcome by household or individual characteristic, plus a subnational map and distributions (#76).

## Proposed app changes

1. **Variable summary table.** One `reactable` row per variable: type, percent missing (weighted and unweighted), number of distinct values, mean or modal category, and an inline distribution cell. Numeric variables get a weighted histogram sparkline, categorical ones a stacked share bar. Rows sort by percent missing so the user sees unusable candidates first.
2. **Limits.** Build sparklines lazily, for visible rows only, and cap at the variables already offered in the model selector. Compute histograms in DuckDB (binned, weighted) on the loaded survey rather than in R on the full frame.
3. **Outcome profile.** After the outcome is chosen, a "Profile by" selector (any categorical covariate already in the variable list, for example urban, sex of head, education) that shows the weighted outcome mean and the poverty rate by group. Reuse the existing outcome chart builders (`echart_*`) and the weighted aggregation kernel; do not add a new statistics path.
4. **Subnational map.** The outcome map exists. Check that it offers the same profile filter, and that it uses the MapLibre bridge in `fct_hexmap.R` only.
5. **Export.** Add the new table to the existing CSV export bundle (`fct_export.R`).

## Upstream data

None. The `psu`, `strata` and weight variables are already in the microdata when the survey has them; variable labels and types come from the variable list in the data directory. If a variable has no label there, the new table shows the raw name.

## Decisions

- Sparklines in the table for the first version (decided 2026-11-09). A detail panel that expands on click is the fallback if the table is too slow with 100+ variables.

## Open questions

- Weighted or unweighted missingness as the default? Recommendation: weighted, with the unweighted count in a tooltip.

## Checks

Narrow tests for the summary builder (weights, all-missing and constant variables), then a browser check on a real country (skill `wise-ui-check`) for the layout with many variables.
