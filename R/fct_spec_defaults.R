# Run-spec defaults ----
# The one place that holds the app's default settings for the Step 0/1 data
# side. The module servers read their initial control values from here, and
# the batch run spec (fct_batch_spec.R) fills omitted fields from here, so an
# untouched control and an omitted spec field mean the same thing.
# Pure and Shiny-free.

# Welfare floor ($/person/day, 2021 PPP) applied to every loaded survey.
WISEAPP_WELFARE_FLOOR <- 0.28

# Spec sections that exist in the current batch phase.
WISEAPP_SPEC_SECTIONS <- c("source", "sample", "outcome", "weather", "stats", "model", "sim", "policy")

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

#' Climate scenarios of the Step 2 control, in the order the app runs them
#' @noRd
WISEAPP_SSP_CODES <- c("ssp2_4_5", "ssp3_7_0", "ssp5_8_5")

# Bounds of the Step 2 historical-period slider (the projection periods run
# from `.STEP2_SSP_START_YEAR` to `.STEP2_SSP_END_YEAR`, fct_step2_input.R).
WISEAPP_SIM_HIST_RANGE <- c(1950L, 2025L)

#' Default simulation section
#'
#' What `sim: {}` stands for: the initial state of the Step 2 sidebar. A run
#' spec without a `sim` section runs no simulation. `baseline_survey` follows a
#' rule on the survey waves (see `wise_default_baseline()`) and stays absent
#' until the spec is resolved.
#'
#' @return A named list: `hist_years`, `future_periods` (a list of
#'   start/end year pairs, at most three), `ssps`, `residuals`,
#'   `coef_uncertainty`, `propagate_all_covariate_uncertainty`.
#' @noRd
wise_default_sim <- function() {
  list(
    hist_years = c(1991L, 2020L),
    future_periods = list(c(2025L, 2035L)),
    ssps = "ssp3_7_0",
    residuals = "original",
    coef_uncertainty = TRUE,
    propagate_all_covariate_uncertainty = FALSE
  )
}

#' Default baseline survey: the latest year of each economy
#' @param values Survey waves as `"code|year"` strings.
#' @return The subset of `values` that is the latest wave of its economy, in
#'   the order given.
#' @noRd
wise_default_baseline <- function(values) {
  values <- as.character(values)
  if (!length(values)) {
    return(character(0))
  }
  code <- sub("^(.*?)\\|.*$", "\\1", values)
  year <- as.integer(sub("^.*\\|", "", values))
  latest <- tapply(year, code, max)
  values[year == latest[code]]
}

#' Default Step 3 lever settings
#'
#' The initial values of the Step 3 controls, by input id. A lever in the run
#' spec starts from these; a lever that is absent is not part of the run. Fields
#' that follow a rule on the data have no entry: the proxy variable and its
#' cutoff, the trigger variable, direction and thresholds, the annual cap, and
#' the trigger poverty line (the outcome's own line, else 3.00). The labour
#' sector targets default to the observed shares.
#'
#' @return A named list of levers (`sp`, `infra`, `digital`, `labor`,
#'   `education`), each a named list of control values.
#' @noRd
wise_default_policy <- function() {
  access <- function(stems) {
    out <- list()
    for (s in stems) {
      out[[paste0(s, "_universal")]] <- FALSE
      out[[paste0(s, "_pct")]] <- 0
    }
    out
  }
  list(
    sp = list(
      sp_type = "regular", budget_mode = "transfer_first", budget_fixed = 0,
      targeting = "universal", targeting_threshold_pct = 20, inclusion_error_pct = 10,
      exclusion_error_pct = 10, error_concentration = 0, transfer_amount_mode = "fixed",
      transfer_pctile = 10, transfer_amount_usd = 0,
      amount_basis = "per_household", admin_cost_pct = 0, transfer_n_payments = 6,
      trigger_type = "return_period", trigger_direction = "above",
      trigger_return_period_years = 10, trigger_metric = "weather", trigger_level = "national",
      payout_scope = "local", national_k_pct = 20, payments_per_activation = 1,
      dyn_geo = "all", dyn_geo_pct = 50, dyn_welfare = FALSE, dyn_welfare_pct = 20,
      dyn_incl_error_pct = 20, dyn_excl_error_pct = 20, budget_rule = "fixed",
      loss_share_pct = 50, loss_event_pct = 10, transfer_timing = "expost",
      timeliness_weeks = 0, forecast_pod_pct = 100, forecast_far_pct = 0,
      effect_multiplier = 1, delay_loss_pct_per_week = 0
    ),
    infra = c(
      access(c("electricity", "water", "sanitation", "piped", "piped_to_prem", "water_sanitation")),
      list(health_mode = "pct", health_travel_pct = 0, health_travel_max = 60)
    ),
    digital = access(c("internet", "mobile")),
    labor = list(labor_emp = 0),
    education = access(c("educ_primary", "educ_secondary", "educ_postsec")),
    other = list()
  )
}

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
#' @param name Optional scalar character; the variable name.
#' @return A named list: `ref_period`, `temporal_agg`, `transformation`,
#'   `form`, `n_bins`, `binning_method`, `custom_breaks`, `polynomial`.
#' @noRd
wise_weather_var_defaults <- function(units, name = NULL) {
  d <- weather_spec_defaults(units, name)
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
