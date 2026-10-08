# Shock-responsive social protection: spec checks and trigger thresholds ----
#
# Pure functions (no Shiny) for the shock-responsive transfer (plan:
# review/sp_shock_responsive_plan.md, decisions 2, 7, 8 and 9; tasks P1-1 and
# P1-2 in review/sp_shock_responsive_tasks.md). Thresholds are computed from the
# historical exposure table of the run and applied unchanged to every climate
# member, as Step 2 does for its return periods.

SP_TRIGGER_TYPES <- c("weather", "return_period")
SP_TRIGGER_DIRECTIONS <- c("above", "below")
SP_PAYOUT_SCOPES <- c("local", "national_triggered", "national_all")

# A trigger is evaluated per survey round, survey location and interview month.
.sp_trigger_key_cols <- c("code", "year", "survname", "loc_id", "int_month")

#' Why a shock-responsive spec cannot run, or NULL when it can
#'
#' Checks the trigger and payout fields of a scenario list from
#' `mod_3_01_sp_server()`. Shock mode pays a fixed amount per activation, so the
#' budget mode is not consulted (decision 12).
#'
#' @param sp Scenario list.
#' @return `NULL` when valid, otherwise one short message.
#' @keywords internal
.sp_shock_problem <- function(sp) {
  num <- function(x) suppressWarnings(as.numeric(x %||% NA_real_))[1L]
  type <- sp$trigger_type %||% "weather"
  if (!type %in% SP_TRIGGER_TYPES) {
    return("Choose a trigger type.")
  }
  var <- sp$trigger_variable %||% NA_character_
  if (length(var) != 1L || is.na(var) || !nzchar(var)) {
    return("Choose a weather variable for the trigger.")
  }
  if (!(sp$trigger_direction %||% "above") %in% SP_TRIGGER_DIRECTIONS) {
    return("Choose whether the trigger fires above or below its threshold.")
  }
  if (identical(type, "weather")) {
    if (!is.finite(num(sp$trigger_value))) {
      return("Enter a threshold value for the trigger.")
    }
  } else {
    n <- num(sp$trigger_return_period_years)
    if (!is.finite(n) || n < 1) {
      return("Enter a return period of at least 1 year.")
    }
  }
  if (!(sp$payout_scope %||% "local") %in% SP_PAYOUT_SCOPES) {
    return("Choose a payout scope.")
  }
  if (!identical(sp$payout_scope %||% "local", "local")) {
    k <- num(sp$national_k_pct %||% 0)
    if (!is.finite(k) || k < 0 || k > 100) {
      return("The national gate share must be between 0 and 100 percent.")
    }
  }
  NULL
}

#' Weather columns that can drive a trigger
#'
#' A trigger needs a continuous value. Binned variables reach the exposure table
#' as bin labels (character or factor), so only numeric columns qualify; the unit
#' is whatever the variable's transformation implies (physical units, deviation
#' or standardized anomaly).
#'
#' @param exposure Exposure table (`.policy_exposure_table()` layout).
#' @return Character vector of column names.
#' @keywords internal
.sp_trigger_variables <- function(exposure) {
  if (!is.data.frame(exposure)) {
    return(character())
  }
  cols <- setdiff(names(exposure), .policy_exposure_key_cols)
  cols[vapply(cols, function(v) is.numeric(exposure[[v]]), logical(1))]
}

#' Trigger thresholds from the historical exposure
#'
#' `"weather"` returns the common value the user entered. `"return_period"`
#' returns one threshold per (survey round, location, interview month) at the
#' 1-in-N level of that cell's historical record, on the adverse side given by
#' `trigger_direction`: `above` uses the `1 - 1/N` quantile and fires at or above
#' it, `below` uses the `1/N` quantile and fires at or below it (the rule of
#' `step2_adverse_return_period()`). Following Step 2, a 1-in-N trigger is
#' offered only when the historical record has at least N finite years; cells
#' with a shorter record get no threshold (`NA`, never fires) and the call stops
#' when no cell supports N.
#'
#' The exposure table holds one value per simulation year in each cell, so the
#' number of finite values is the record length behind the threshold.
#'
#' @param hist_exposure Exposure table of the historical pipeline.
#' @param spec Scenario list with the trigger fields.
#' @return A list with `type`, `variable`, `direction`, and either `value`
#'   (weather) or `table` (return period: key columns, `threshold`, `n_years`,
#'   `supported`) plus `return_period_years`.
#' @keywords internal
sp_trigger_thresholds <- function(hist_exposure, spec) {
  problem <- .sp_shock_problem(spec)
  if (!is.null(problem)) {
    stop(problem, call. = FALSE)
  }
  type <- spec$trigger_type %||% "weather"
  var <- spec$trigger_variable
  direction <- spec$trigger_direction %||% "above"
  if (!var %in% .sp_trigger_variables(hist_exposure)) {
    stop(
      "The trigger variable '", var, "' is not a continuous weather variable ",
      "in the exposure table (binned variables cannot drive a trigger).",
      call. = FALSE
    )
  }
  if (identical(type, "weather")) {
    return(list(
      type = type, variable = var, direction = direction,
      value = as.numeric(spec$trigger_value)
    ))
  }

  n_req <- as.numeric(spec$trigger_return_period_years)
  keys <- intersect(.sp_trigger_key_cols, names(hist_exposure))
  if (!all(c("loc_id", "int_month") %in% keys)) {
    stop("The exposure table has no location or interview month.", call. = FALSE)
  }
  prob <- if (identical(direction, "above")) 1 - 1 / n_req else 1 / n_req
  grp <- do.call(paste, c(unname(as.list(hist_exposure[keys])), sep = "\r"))
  first <- !duplicated(grp)
  vals <- split(as.numeric(hist_exposure[[var]]), factor(grp, levels = grp[first]))
  n_years <- vapply(vals, function(v) sum(is.finite(v)), integer(1))
  tbl <- hist_exposure[first, keys, drop = FALSE]
  rownames(tbl) <- NULL
  tbl$n_years <- unname(n_years)
  tbl$supported <- tbl$n_years >= ceiling(n_req)
  tbl$threshold <- NA_real_
  ok <- which(tbl$supported)
  tbl$threshold[ok] <- vapply(vals[ok], function(v) {
    unname(stats::quantile(v[is.finite(v)], probs = prob, names = FALSE))
  }, numeric(1))
  if (!any(tbl$supported)) {
    stop(
      "A 1-in-", format(n_req), " trigger needs at least ", ceiling(n_req),
      " historical years; the longest record has ", max(tbl$n_years, 0L), ".",
      call. = FALSE
    )
  }
  list(
    type = type, variable = var, direction = direction,
    return_period_years = n_req, table = tbl
  )
}
