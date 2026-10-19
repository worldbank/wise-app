# Phase 1 tables - column reference

Status: implemented (2026-10-19). Part of `review/batch_pipeline_plan.md`.
These are the three tables of the survey and weather data side:
`variable_stats`, `interview_dates` and `weather_stats`. The catalogue of all
planned tables is `batch/docs/tables.md`; the builders are in
`R/fct_step1_tables.R`.

Every table is a parquet dataset in `results/tables/<table>/`, partitioned by
`code`. Values are raw (never rounded). Each row set carries the id of the
stage it depends on (`data_id` or `wxvar_id`); join to `runs.parquet` for the
labels and settings of the runs that use it.

**App-identical** columns hold the value the app shows, computed by the
app's own builder: `weighted_summary_long()` and `survey_missingness_long()`
for the survey summary tables, `outcome_summary_wide()` for the outcome
summary, `summarise_interview_dates()` for the interview chart and
`build_weather_stats_table()` for the weather summary. **Batch-only** columns
and rows exist only in the batch tables.

## Common columns

| Column | Meaning |
|---|---|
| `data_id` / `wxvar_id` | Stage id (12 hex characters). `data_id` hashes the source, sample, outcome and statistics options. `wxvar_id` hashes the data id, one weather variable's reference period, temporal aggregation and transformation, and the historical years (not the binning, which the statistics do not use). A run with two weather variables has two `wxvar_id`s (`runs.wxvar_ids`). |
| `code` | Country code. For the pooled scope of a two-country sample, the sorted codes joined by `+` (for example `BFA+MWI`). The partition column. |
| `wave` | The survey year of the wave, as text (waves of one country and year are merged, as the app does). `All` is the scope that pools every wave of the country (or, with `code` `A+B`, of both countries). |
| `year` | The wave's year; missing for `All`. |
| `survname` | The survey name(s) of the scope; several are joined by `+`. |

## variable_stats

One row per scope (wave, `All`, pool) x variable group x variable x sample.

| Column | Meaning | Source |
|---|---|---|
| `var_group` | `outcome` (flagged outcomes and the selected outcome), `policy` (the variables the Step 3 levers act on), `ind`, `hh`, `firm`, `area` (variable-list flags) or `indicator`. A variable in two groups has a row for each, with equal values. | app tables / batch |
| `variable` | Variable name (not the label). | |
| `sample` | `all`; `with_loc` (records with a `loc_id` and, if the data has it, `area_h3_7`); `without_loc` (the rest); `within_loc` (values minus the location mean over all the location's waves, `with_loc` records only; `n`, `mean` and `sd` only). | `all`: app. Others: batch-only |
| `n` | Records with a finite value and a finite positive weight. | app (`N`) |
| `n_rows` | Records in the scope and sample. | batch-only |
| `n_missing` | Records where the variable is missing. | batch-only |
| `pct_missing` | `100 * n_missing / n_rows`. | app (`% Missing`) |
| `n_unique` | Distinct non-missing values. | batch-only |
| `mean` | Weighted mean. For a 0/1 variable this is the share of ones. | app |
| `unweighted_mean` | Mean without weights. | app |
| `sd` | Weighted standard deviation (denominator: sum of weights minus 1). | app |
| `min`, `max` | Smallest and largest valid value. | app |
| `p10` ... `p90`, `p25`, `p75` | Weighted quantiles (`collapse::fquantile`, type 7), rows with a missing value or an invalid weight dropped. For the outcome rows the deciles equal the app's outcome summary. | batch-only for every variable |
| `share_one` | For a variable whose non-missing values are all 0 or 1: the weighted share of ones (equal to `mean`); otherwise missing. | batch-only |

**Indicators** (`var_group = indicator`) are 0/1 variables defined in the
spec (`stats.indicators`: variable, operator `<` or `>`, threshold). The
default set is `poor300`, `poor420`, `poor830` (`welfare` below 3.00, 4.20,
8.30) and `ttime_health_gt15`, `_gt30`, `_gt45`, `_gt60` (`ttime_health` above
the number of minutes). Their `mean` is the weighted share. An indicator
whose variable is not in the data is skipped.

`stats.location_samples: false` leaves only `sample = all`.

## interview_dates

One row per wave x interview month, plus one total row per wave
(`month` missing).

| Column | Meaning | Source |
|---|---|---|
| `month` | Interview month, 1 to 12; missing on the total row. | app |
| `n` | Records interviewed in the month (the chart's bar height). On the total row: records with an interview date. | app / batch-only |
| `n_dates` | Distinct interview dates (total row only). | batch-only |
| `first_date`, `last_date` | Earliest and latest interview date (total row only). | batch-only |
| `avg_dates_per_loc` | Mean number of distinct interview dates per location, over records with a location (total row only). | batch-only |

## weather_stats

One row per wave (and `All`) x weather variable x source x sample. Weather
values are the continuous ones, after temporal aggregation and the
transformation but before any binning, so a binned variable is described by
the values the bins were cut from.

| Column | Meaning | Source |
|---|---|---|
| `variable` | Weather variable name. | |
| `source` | `survey`: the weather the sample was exposed to (survey records merged with the weather of their location and interview month). `historical`: the same locations and calendar months over the historical comparison years (`weather.hist_years`), one value per location-month, weighted by the number of households in that location-month, as in the weather distribution plots. | survey: app. historical: batch-only |
| `sample` | `all`, or `within_loc` (values minus the location mean over the location's waves; `n`, `mean`, `sd` only). | `within_loc`: batch-only |
| `n` | Survey: records with a finite value and a positive weight. Historical: valid location-month cells. | app (`N`) |
| `pct_missing` | Survey: share of the original survey records without a value after the weather merge. Missing for the historical source. | app (`% Missing`) |
| `n_unique` | Distinct values. | batch-only |
| `n_unique_per_loc` | Mean number of distinct values per location, over records (cells) with a location. | batch-only |
| `unweighted_mean`, `mean`, `sd`, `min`, `max` | As in `variable_stats` (historical: weights are household counts). | survey: app. historical: batch-only |
| `p10` ... `p90`, `p25`, `p75` | Weighted quantiles as in `variable_stats`. | batch-only |

## Notes

- Statistics are computed on the records the pipeline loads, after the
  steps of the Survey stats tab: time columns, LCU to 2021 PPP conversion,
  the welfare floor of 0.28, the derived policy variables. Records without a
  weather match drop out of `weather_stats` (see `pct_missing`).
- A location is a country and `loc_id`: the same `loc_id` in two waves is the
  same place.
- Records with an invalid weight (missing, zero or negative) contribute to
  counts and `pct_missing` but not to weighted statistics, the app's rule.
- Rows with `n = 0` (a variable that is entirely missing in a wave) are kept
  here; the app hides them in its tables.
