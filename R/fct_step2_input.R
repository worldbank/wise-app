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

#' Households of a baseline survey a Step 2 run can predict for
#'
#' The model is fitted on complete cases, so a household with a missing weather
#' value (no weather row for its location, for example outside the land
#' coverage of the weather data) or a missing model covariate gets no
#' prediction. Left in the baseline it would silently drop out of the Step 2
#' metrics and make Step 3 refuse to run. This removes such households up
#' front, so Step 2, Step 3 and the model fit use the same population. The
#' survey-weather frame itself (and with it `weather_stats`) keeps counting them.
#'
#' Columns checked: every weather variable of the model in the form the model
#' uses (the column and its continuous companion `<var>_cont` when present),
#' and the other variables of the final model formula (fixed effects,
#' interaction moderators, controls) that the baseline carries. The outcome is
#' not a prediction input and is not checked. Weights of the remaining
#' households are not rescaled: shares are unchanged and the dropped share is
#' reported instead.
#'
#' @param svy Baseline survey-weather frame.
#' @param sw Selected weather (`name`).
#' @param mf Step 1 model fit (`weather_terms`, `formulas$formula3`, `y_var`),
#'   or `NULL` to check the selected weather only.
#' @param so Selected outcome (`name`), or `NULL`.
#' @return A list: `svy` (the households kept) and `dropped`, a list with
#'   `n_total`, `n_dropped`, `n_dropped_weather` (rows with a missing weather
#'   value), `weight_share_dropped` (`NA` without a weight column) and
#'   `variables` (the columns checked). Stops when no household is left.
#' @noRd
step2_baseline_complete <- function(svy, sw, mf = NULL, so = NULL) {
  weather <- unique(c(as.character(sw$name), as.character(mf$weather_terms)))
  weather <- weather[!is.na(weather) & nzchar(weather)]
  weather_cols <- intersect(c(weather, paste0(weather, "_cont")), names(svy))
  model_vars <- .step2_formula_vars(mf$formulas$formula3)
  other_cols <- setdiff(
    intersect(model_vars, names(svy)),
    c(weather_cols, so$name, mf$y_var)
  )
  n_total <- nrow(svy)
  missing_any <- function(cols) {
    out <- rep(FALSE, n_total)
    for (col in cols) out <- out | is.na(svy[[col]])
    out
  }
  no_weather <- missing_any(weather_cols)
  drop <- no_weather | missing_any(other_cols)
  weight_col <- survey_weight_column(names(svy))
  wt <- if (is.null(weight_col)) NULL else suppressWarnings(as.numeric(svy[[weight_col]]))
  share <- if (is.null(wt) || !any(is.finite(wt))) {
    NA_real_
  } else {
    sum(wt[drop], na.rm = TRUE) / sum(wt, na.rm = TRUE)
  }
  dropped <- list(
    n_total = n_total, n_dropped = sum(drop), n_dropped_weather = sum(no_weather),
    weight_share_dropped = share, variables = c(weather_cols, other_cols)
  )
  if (n_total > 0L && all(drop)) {
    stop(
      "No household of the baseline survey has complete weather and model data ",
      "(checked: ", paste(utils::head(dropped$variables, 8L), collapse = ", "),
      "). Check the weather data coverage of the survey locations.",
      call. = FALSE
    )
  }
  list(svy = if (any(drop)) svy[!drop, , drop = FALSE] else svy, dropped = dropped)
}

#' Baseline survey of a Step 2 run, complete cases only
#'
#' `step2_baseline_svy()` followed by `step2_baseline_complete()`: the one
#' call the Step 2 module and the batch runner share.
#' @inheritParams step2_baseline_svy
#' @inheritParams step2_baseline_complete
#' @return See `step2_baseline_complete()`.
#' @noRd
step2_baseline_run <- function(survey_weather, selection, sw, mf = NULL, so = NULL) {
  step2_baseline_complete(step2_baseline_svy(survey_weather, selection), sw, mf, so)
}

#' Note on the households left out of the baseline
#' @param dropped `dropped` element of `step2_baseline_complete()`.
#' @return A string, or `NULL` when nothing was left out.
#' @noRd
step2_dropped_note <- function(dropped) {
  if (is.null(dropped) || !isTRUE(dropped$n_dropped > 0)) {
    return(NULL)
  }
  share <- dropped$weight_share_dropped
  paste0(
    format(dropped$n_dropped, big.mark = ","), " of ",
    format(dropped$n_total, big.mark = ","), " baseline households left out",
    " (missing weather or model data)",
    if (is.finite(share)) sprintf(", %.1f%% of the survey weight", 100 * share)
  )
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
#' @param baseline_dropped Households left out of the baseline
#'   (`step2_baseline_complete()$dropped`), or `NULL`.
#' @return `result`, with the two fields set on `hist_sim_result`.
#' @noRd
wise_step2_annotate <- function(result, sw, hist_years, baseline_label,
                                baseline_dropped = NULL) {
  result$hist_sim_result$hist_label <- step2_hist_label(hist_years)
  result$hist_sim_result$sim_summary <- list(
    weather = sw,
    historical_years = unlist(hist_years, use.names = FALSE),
    baseline_survey = baseline_label,
    baseline_dropped = baseline_dropped,
    total_runs = result$total_runs
  )
  result
}
