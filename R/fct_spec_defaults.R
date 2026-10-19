# Run-spec defaults ----
# The one place that holds the app's default settings for the Step 0/1 data
# side. The module servers read their initial control values from here, and
# the batch run spec (fct_batch_spec.R) fills omitted fields from here, so an
# untouched control and an omitted spec field mean the same thing.
# Pure and Shiny-free.

# Welfare floor ($/person/day, 2021 PPP) applied to every loaded survey.
WISEAPP_WELFARE_FLOOR <- 0.28

# Spec sections that exist in the current batch phase.
WISEAPP_SPEC_SECTIONS <- c("source", "sample", "outcome", "weather", "stats", "model")

# Model types of the Model tab and the engine each one runs on. Phase 2 covers
# the fixest and RIF engines.
WISEAPP_MODEL_TYPES <- c(
  "Linear regression" = "fixest",
  "Logistic regression" = "fixest",
  "Unconditional quantile regression (RIF)" = "rif"
)

#' Default binary indicator variables for the batch statistics tables
#'
#' Poverty-line indicators (`welfare` below the line) and the travel-time
#' thresholds used for the health-access policy variable.
#'
#' @return A named list; each element has `variable`, `operator` (`"<"` or
#'   `">"`) and `threshold`.
#' @noRd
wise_default_indicators <- function() {
  ind <- function(variable, operator, threshold) {
    list(variable = variable, operator = operator, threshold = threshold)
  }
  list(
    poor300 = ind("welfare", "<", 3.00),
    poor420 = ind("welfare", "<", 4.20),
    poor830 = ind("welfare", "<", 8.30),
    ttime_health_gt15 = ind("ttime_health", ">", 15),
    ttime_health_gt30 = ind("ttime_health", ">", 30),
    ttime_health_gt45 = ind("ttime_health", ">", 45),
    ttime_health_gt60 = ind("ttime_health", ">", 60)
  )
}

#' Default run spec
#'
#' Fields set to `NULL` follow a data-dependent rule (see the
#' `wise_default_*()` helpers): the default economy, all available survey
#' years, the first available outcome, the first weather variable.
#'
#' @return A named list, one element per spec section plus `seed`.
#' @noRd
wise_spec_defaults <- function() {
  list(
    schema_version = 1L,
    seed = WISEAPP_DEFAULT_SEED,
    source = list(type = "local"),
    sample = list(unit = "hh", countries = NULL, years = NULL),
    outcome = list(name = NULL, currency = "PPP", poverty_line = NULL),
    weather = list(hist_years = c(1991L, 2020L)),
    stats = list(
      indicators = wise_default_indicators(),
      location_samples = TRUE
    )
  )
}

#' Default economy: BFA when available, otherwise the first one
#' @param codes Character vector of available economy codes.
#' @noRd
wise_default_economy <- function(codes) {
  if ("BFA" %in% codes) "BFA" else codes[1]
}

#' Default survey years: every available year
#' @param years Available years for one economy.
#' @noRd
wise_default_years <- function(years) years

#' Default outcome: the first available outcome variable
#' @param outcome_names Character vector in the order of `filter_outcome_vars()`.
#' @noRd
wise_default_outcome <- function(outcome_names) outcome_names[1]

#' Default poverty line for the `poor` outcome
#'
#' $3.00 a day in 2021 PPP; for LCU the app default from
#' `default_lcu_poverty_line()` (needs the loaded survey).
#'
#' @param currency `"PPP"` or `"LCU"`.
#' @param df Survey data frame, used for LCU only.
#' @noRd
wise_default_poverty_line <- function(currency = "PPP", df = NULL) {
  if (is.null(currency) || identical(currency, "PPP")) {
    3.00
  } else {
    default_lcu_poverty_line(df)
  }
}

#' Default model section
#'
#' What `model: {}` stands for in a spec. A run spec without a `model` section
#' fits no model. `type` and `fixed_effects` follow rules on the data (see
#' `wise_default_model_type()` and `wise_default_fixed_effects()`), so they stay
#' absent until the spec is resolved or fitted.
#'
#' @return A named list: `covariates` (`method`, `vars`, `lasso`).
#' @noRd
wise_default_model <- function() {
  list(covariates = list(
    method = "user", vars = character(0),
    lasso = c(wise_default_lasso(), list(force_in = character(0), force_out = character(0)))
  ))
}

#' Default fixed effects: year and first-level region, where available
#' @param fe_names Names of the valid fixed-effect variables.
#' @noRd
wise_default_fixed_effects <- function(fe_names) intersect(c("year", "gaul1_code"), fe_names)

#' Default model type for an outcome type
#'
#' The first choice the Model tab offers (`model_type_choices()`).
#'
#' @param outcome_type `"logical"` for binary outcomes, otherwise numeric.
#' @noRd
wise_default_model_type <- function(outcome_type) model_type_choices(outcome_type)$choices[1]

#' Default Lasso settings (the Model tab's advanced controls)
#' @return A named list: `alpha`, `lambda`, `nfolds`, `standardize`, `use_mice`,
#'   `mi_m`, `mi_maxit`, `stability_threshold`.
#' @noRd
wise_default_lasso <- function() {
  list(
    alpha = 1, lambda = "lambda.1se", nfolds = 10L, standardize = TRUE,
    use_mice = FALSE, mi_m = 5L, mi_maxit = 5L, stability_threshold = 0.5
  )
}

#' Default settings of one weather variable in spec form
#'
#' Wraps `weather_spec_defaults()` (the unit-dependent defaults) in the spec's
#' field names.
#'
#' @param units Scalar character; the variable's units.
#' @return A named list: `ref_period`, `temporal_agg`, `transformation`,
#'   `form`, `n_bins`, `binning_method`, `custom_breaks`, `polynomial`.
#' @noRd
wise_weather_var_defaults <- function(units) {
  d <- weather_spec_defaults(units)
  list(
    ref_period = c(d$ref_start, d$ref_end),
    temporal_agg = d$temporal_agg,
    transformation = d$transformation,
    form = d$cont_binned,
    n_bins = d$num_bins,
    binning_method = d$binning_method,
    custom_breaks = d$custom_breaks,
    polynomial = d$polynomial
  )
}
