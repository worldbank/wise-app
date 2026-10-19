# Step 2 input glue ----
# The code that turns the Step 2 sidebar settings (or the `sim` section of a
# batch spec) into the input of `step2_compute()`: the baseline survey subset,
# the historical and projection periods, the scenarios, the residual rule and
# the model snapshot. The simulation module (mod_2_01) and the batch runner
# call the same functions. Pure and Shiny-free.

# First and last year of the CMIP6 SSP projections. A future period that starts
# earlier would silently average only its SSP years (R2-BUG-23), so it is
# excluded.
.STEP2_SSP_START_YEAR <- 2015L
.STEP2_SSP_END_YEAR <- 2100L

# A future period slider value as an integer (start, end) pair, or NULL when
# it is incomplete, empty (end <= start) or starts before the SSP projections.
.step2_valid_future_period <- function(period) {
  if (length(period) >= 2 && all(is.finite(period)) && period[2] > period[1] &&
      period[1] >= .STEP2_SSP_START_YEAR) {
    as.integer(period[1:2])
  } else {
    NULL
  }
}

# Baseline survey ----

.step2_filter_baseline_surveys <- function(selected_surveys,
                                           baseline_selection) {
  if (is.null(selected_surveys) || length(baseline_selection) == 0L) {
    return(selected_surveys)
  }
  required <- c("code", "year")
  if (!all(required %in% names(selected_surveys))) {
    return(selected_surveys)
  }
  wave_key <- paste0(
    selected_surveys$code, "|",
    as.character(selected_surveys$year)
  )
  selected_surveys[wave_key %in% baseline_selection, , drop = FALSE]
}

#' Survey waves a Step 2 run can use as its baseline
#'
#' One choice per economy and year of the survey-weather frame, labelled with
#' the economy name from the selected surveys.
#'
#' Code (e.g. TGO, GNB) is unique per country; `survname` (e.g. EHCVM) is
#' shared across countries of one survey programme and must not be the join
#' key to the economy name (the bug that made Togo disappear).
#'
#' @param survey_weather Survey-weather frame (`code`, `survname`, `year`).
#' @param selected_surveys Selected surveys (`code`, `economy`), or `NULL`.
#' @return A named character vector: label -> `"code|year"`.
#' @noRd
step2_baseline_choices <- function(survey_weather, selected_surveys = NULL) {
  svy <- survey_weather
  if (!all(c("code", "survname", "year") %in% names(svy))) {
    return(character(0))
  }
  combos <- unique(svy[, c("code", "survname", "year")])
  combos <- combos[order(combos$code, combos$year), ]
  ss <- selected_surveys
  if (!is.null(ss) && all(c("code", "economy") %in% names(ss))) {
    lbl_map <- unique(ss[, c("code", "economy")])
    combos <- merge(combos, lbl_map, by = "code", all.x = TRUE)
    combos$economy[is.na(combos$economy)] <- combos$code[is.na(combos$economy)]
  } else {
    combos$economy <- combos$code
  }
  vals <- paste0(combos$code, "|", combos$year)
  lbls <- paste0(combos$economy, " ", combos$year)
  stats::setNames(vals, lbls)
}

#' Rows of the survey-weather frame in the selected baseline waves
#' @param survey_weather Survey-weather frame (`code`, `year`).
#' @param selection `"code|year"` values; empty keeps every row.
#' @noRd
step2_baseline_svy <- function(survey_weather, selection) {
  if (length(selection) == 0) {
    return(survey_weather)
  }
  svy <- survey_weather
  vals <- paste0(svy$code, "|", as.character(svy$year))
  svy[vals %in% selection, , drop = FALSE]
}

#' Label of the baseline survey recorded with a run
#' @param choices Named vector from `step2_baseline_choices()`.
#' @param selection `"code|year"` values.
#' @noRd
step2_baseline_label <- function(choices, selection) {
  labels <- names(choices)[choices %in% selection]
  if (length(labels)) paste(labels, collapse = ", ") else "Selected baseline survey"
}

#' Scenario label of the historical run
#' @param hist_years Two years.
#' @noRd
step2_hist_label <- function(hist_years) {
  paste0("Historical / ", hist_years[1], "-", hist_years[2])
}

# Input of step2_compute() ----

#' Input snapshot of a Step 2 run
#'
#' Builds the named list `step2_compute()` (and `fct_run_simulation()`) takes
#' from the run's settings: historical simulation dates, projection periods as
#' date strings, perturbation methods, the residual rule (forced to `"none"`
#' for RIF: the delta method needs no residual draw) and, for RIF, the
#' quantile fits.
#'
#' @param sw Selected weather. @param so Selected outcome.
#' @param svy Baseline survey-weather frame. @param ss Baseline selected
#'   surveys (weather retrieval).
#' @param mf Step 1 model fit.
#' @param cp Connection parameters.
#' @param hist_years Historical weather period (two years).
#' @param periods Projection periods, a list of start/end year pairs; pairs
#'   that are incomplete, empty or start before the SSP projections are left
#'   out.
#' @param ssps SSP codes; without a valid period there is no future run.
#' @param residuals Residual rule requested by the user.
#' @param coef_uncertainty Include coefficient uncertainty.
#' @param propagate_all Propagate uncertainty of all covariates.
#' @param stored_breaks Bin breaks stored at weather load.
#' @param slim Give the run the slim model copy (the worker snapshot). The
#'   live fit stays untouched either way.
#' @return A named list; see `.step2_compute_required`.
#' @noRd
wise_step2_input <- function(sw, so, svy, ss, mf, cp, hist_years, periods, ssps,
                             residuals = "original", coef_uncertainty = TRUE,
                             propagate_all = FALSE, stored_breaks = NULL,
                             slim = TRUE) {
  periods <- Filter(Negate(is.null), lapply(periods, .step2_valid_future_period))
  has_future <- length(ssps) > 0L && length(periods) > 0L
  is_rif <- identical(mf$engine %||% "fixest", "rif")
  mf_run <- if (isTRUE(slim)) step2_slim_model_fit(mf) else mf
  list(
    sw = sw, so = so, svy = svy, ss = ss, mf = mf_run, cp = cp,
    fp_list = if (has_future) {
      lapply(periods, function(yr) c(paste0(yr[1], "-01-01"), paste0(yr[2], "-12-31")))
    } else {
      list()
    },
    ssps = if (has_future) unique(as.character(ssps)) else character(0),
    residuals = if (is_rif) "none" else residuals,
    skip_coef_draws = !isTRUE(coef_uncertainty),
    sim_dates = build_hist_sim_dates(svy, unlist(hist_years)),
    perturbation_method = if (has_future) build_perturbation_method(sw) else NULL,
    stored_breaks = stored_breaks,
    propagate_all_covariate_uncertainty = isTRUE(propagate_all),
    fit_multi = if (is_rif) mf_run$fit3 else NULL,
    taus = if (is_rif) mf$taus else NULL,
    weather_cols = if (is_rif) mf$weather_terms else NULL
  )
}

#' Describe a finished Step 2 run on its historical result
#'
#' Binds the historical scenario label and the run summary the Results panes
#' and the headline cards read (`hist_label`, `sim_summary`).
#'
#' @param result A `fct_run_simulation()` / `step2_compute()$result` list.
#' @param sw Selected weather.
#' @param hist_years Historical weather period (two years).
#' @param baseline_label Label of the baseline survey (`step2_baseline_label()`).
#' @return `result`, with the two fields set on `hist_sim_result`.
#' @noRd
wise_step2_annotate <- function(result, sw, hist_years, baseline_label) {
  result$hist_sim_result$hist_label <- step2_hist_label(hist_years)
  result$hist_sim_result$sim_summary <- list(
    weather = sw,
    historical_years = unlist(hist_years, use.names = FALSE),
    baseline_survey = baseline_label,
    total_runs = result$total_runs
  )
  result
}
