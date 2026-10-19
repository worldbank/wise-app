# Phase 2 tables - column reference

Status: implemented (2026-10-19). Part of `review/batch_pipeline_plan.md`.
These are the three Step 1 model tables: `model_terms`, `model_fit` and
`model_vcov`. The catalogue of all planned tables is `batch/docs/tables.md`;
the builders are in `R/fct_step1_model_tables.R`, and the fit they describe is
made by `wise_fit()` (`R/fct_step1_model.R`), the function the Results tab
calls.

Every table is a parquet dataset in `results/tables/<table>/`, partitioned by
`code`. Values are raw (never rounded). Each row carries `fit_id`; join to
`runs.parquet` for the labels and settings of the runs that use the fit.

**App-identical** columns hold the value the app shows, computed by the app's
own function: the coefficient table (`make_regtable_df()` / the fitted
objects), the Model fit tab (`calc_fit_stats()`, from the same raw values
`fit_stats_raw()`), the At a glance cards (`step1_headline_cards()`), the
focused table (`make_regtable_focused_df()`) and the importance plot
(`importance_shares()`). **Batch-only** columns exist only in the batch tables.

## Common columns

| Column | Meaning |
|---|---|
| `fit_id` | Stage id (12 hex characters): hash of `data_id`, the whole weather section (binning included), the model section and the seed. One fit per `fit_id`, however many runs share it. |
| `code` | Country code of the sample; for two economies the sorted codes joined by `+` (for example `BFA+MWI`), one pooled fit. The partition column. |

## What a fit is

The app's "Run model" for the sample, outcome and weather of the run. Three
nested specifications are fitted on the same observations (those complete on
every variable of the fullest model):

| `model` | Specification |
|---|---|
| 1 | weather terms only |
| 2 | + fixed effects |
| 3 | + fixed effects and covariates (the one Steps 2 and 3 use) |

The engine follows the model type: `Linear regression` and
`Logistic regression` use fixest (`feols`, `feglm`); `Unconditional quantile
regression (RIF)` fits the nine quantiles `tau` = 0.1, ..., 0.9. Standard
errors are clustered at the location panel (`loc_id_panel`, from the H3 files)
when the data stage could join it; otherwise fixest's default variance applies
and `model_fit` says so (`vcov`, `location_panel`). Models are fitted without
survey weights. The random seed is the run's `seed`.

Interactions and policy-relevant variables are not part of the Phase 2 spec
(the policy phase adds them); the tables already carry interaction terms in
the same columns when they exist.

## model_terms

One row per specification x term (x quantile for RIF).

| Column | Meaning | Source |
|---|---|---|
| `model` | 1, 2 or 3 (see above). | app |
| `term` | Coefficient name as fixest reports it: `tx`, `I(I(tx^2))`, `tx(24, 27.4]` (bin), `tx:urban`, covariates, `(Intercept)`. Fixed effects are absorbed and not listed. | app |
| `tau` | Quantile (RIF); missing otherwise. | app |
| `is_weather` | The term involves a weather variable of the model (main, bin, polynomial or interaction). | batch-only |
| `estimate`, `std_error` | Coefficient and standard error on the model scale. | app (`Estimate`, `Std. error`) |
| `statistic`, `p_value` | t or z statistic and its p-value. | app (`p value`) |
| `conf_low`, `conf_high` | 95 % interval. fixest: estimate +/- 1.96 x SE, the rule of the app's figures and tables. RIF: the interval of `broom::tidy()` in the app's coefficient grid. | app |
| `n_obs` | Observations of the specification (for RIF, of the quantile's fit). | app (`Observations`) |
| `importance_share` | Share (%) of the sum of squared standardised coefficients, `(abs(beta) x sd(x))^2` (fixed effects excluded, collinearity ignored). Specification 3 only; for RIF the median quantile only. Sums to 100 over its rows. | app (importance plot) |
| `lasso_freq` | Lasso selection frequency of the covariate (share of imputations or folds that selected it). Specification 3, Lasso covariates only; forced-in covariates the Lasso did not select are missing. | app (`run_lasso_selection()`) |
| `translation` | The At a glance translation of the weather term (for example `+2.9%` per +1 SD of the weather variable, or a bin contrast). Specification 3, weather terms with a translation; RIF at `tau` 0.5. | app (focused table `Translation`) |

## model_fit

Long format; `section` says what a row describes.

| Column | Meaning |
|---|---|
| `section` | `fit`, `sample`, `spec`, `effect_inputs` or `headline` (below). |
| `variable` | Weather variable (`effect_inputs`, `headline`); missing otherwise. |
| `model`, `tau` | Specification and quantile where they apply. |
| `statistic` | The quantity (below). |
| `value` | Numeric value; missing for text rows. |
| `text`, `detail` | Text value and note of text rows. |

| `section` | `statistic` | Meaning |
|---|---|---|
| `fit` | `nobs`, `r2`, `ar2`, `wr2` (linear, RIF per `tau`: `nobs`, `r2`, `wr2`); `nobs`, `pr2`, `aic` (binary outcome) | Goodness of fit per specification: observations, R-squared, adjusted and within R-squared; McFadden R-squared and AIC. `wr2` is missing for models without fixed effects. The Model fit tab shows specification 3, formatted (`calc_fit_stats()`). App-identical (raw). |
| `sample` | `n_estimation` | Rows of the estimation sample (after dropping incomplete cases). |
| `spec` | `engine`, `model_family`, `requested_type`, `vcov`, `fixed_effects`, `covariate_selection`, `location_panel` (`text`) | What was fitted. `model_family` is `linear` or `logistic` as fitted, `requested_type` the model type asked for, `vcov` `clustered: loc_id_panel` or `default (IID)`, `location_panel` `joined` or `unavailable: <reason>`. |
| `spec` | `fallback_model_family`, `fallback_vcv` (`text` = `requested -> used`, `detail` = reason) | A specification fallback the fitter applied (a logistic model fitted as linear; clustered errors fitted without clusters). Present only when it happened. |
| `effect_inputs` | `x_min`, `x_max`, `x_mean`, `x_sd` (per continuous weather variable); `profile_eta` (binary outcomes) | What the effect charts need besides the coefficients and `model_vcov`: the model sample's range and mean of the weather variable (the continuous marginal-effect curve is drawn over it), its standard deviation (the per-+1-SD translation), and the median-risk linear predictor that converts a logistic effect to percentage points. Binned variables have none of the `x_` rows. |
| `headline` | The card label (for example `Effect of Max temperature`, `Spec robustness`) | The At a glance cards: `text` the value (`+2.9%`), `detail` the note. App-identical. |

Rebuilding the app's effect charts needs `model_terms` (coefficients and
intervals), `model_vcov` (covariances for the marginal-effect band) and the
`effect_inputs` rows. The observed-weather rug is observation-level and is not
stored.

## model_vcov

The variance-covariance matrix of specification 3, restricted to the weather
terms (main, bins, polynomials, interactions) and stored as a long full matrix
(both triangles), one block per quantile for RIF.

| Column | Meaning |
|---|---|
| `tau` | Quantile (RIF); missing otherwise. |
| `term_1`, `term_2` | Coefficient names, as in `model_terms$term`. |
| `covariance` | Covariance of the two estimates, under the fit's variance estimator (the one behind `std_error`: clustered at the location panel when available). The diagonal is `std_error^2`. |

## Notes

- The batch fits equal the app's: a test compares them with the Results and
  Model modules on a fixture, and `dev/batch_parity_bfa_models.R` compares
  them with the module servers on real BFA data (linear fixest with a user
  covariate list, and with Lasso covariates).
- The batch sorts a user covariate list and the fixed effects (equal sets are
  one fit). The app keeps the order of the selection; the term order of a
  model changes the estimates only at floating-point level (about 1e-16).
- The default fixed effects follow the app's rule at fit time: `year` and
  `gaul1_code` where the data offers them as valid fixed-effect variables.
  Explicit fixed effects must be valid; the app only offers valid ones.
- Covariates must be available at the unit of analysis (or the area level) and
  complete in at least 90 % of the records of every wave, as in the app's
  Model tab; a request outside that fails the fit with a message listing them.
