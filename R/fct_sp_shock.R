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
  scope <- sp$payout_scope %||% "local"
  if (!identical(scope, "local")) {
    k <- num(sp$national_k_pct %||% 0)
    if (!is.finite(k) || k < 0 || k > 100) {
      return("The national gate share must be between 0 and 100 percent.")
    }
    # "Any location fires, pay everyone" is not offered (decision 10)
    if (identical(scope, "national_all") && k <= 0) {
      return("Paying all targeted households needs a national gate share above 0.")
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

#' Trigger state of one pipeline
#'
#' One pre-pass per pipeline (a climate member or the historical arm), before
#' any chunk loop: which prediction rows exceed the trigger, the survey-weighted
#' share of the population exposed in each simulation year, whether the
#' national gate fires, and which rows fall inside the payout scope. Rows are
#' evaluated at their own (survey round, location, interview month), so two
#' households of one location interviewed in different months can differ in a
#' year (decision Q4). Rows with no finite value or no supported threshold do
#' not exceed.
#'
#' Scopes: `local` pays rows that exceed; `national_triggered` pays rows that
#' exceed in a year where the gate fired; `national_all` pays every row in a
#' year where the gate fired. The gate fires in a year when the exposed
#' population share is above 0 and at least `national_k_pct` percent, so
#' `k = 0` makes `national_triggered` identical to `local`.
#'
#' @param exposure Data frame with one row per prediction row: `sim_year`, the
#'   trigger variable and, for return-period triggers, the key columns of
#'   `thresholds$table`.
#' @param thresholds Result of `sp_trigger_thresholds()`.
#' @param weights Numeric weights per row (people), or NULL for equal weights.
#'   Missing or negative weights count as 0.
#' @param spec Scenario list with `payout_scope` and `national_k_pct`.
#' @return A list: `exceeds` and `in_scope` (logical per row), `share`
#'   (exposed population share by simulation year, named by year) and `gate`
#'   (logical by simulation year; always FALSE for `local`).
#' @keywords internal
sp_trigger_state <- function(exposure, thresholds, weights = NULL, spec) {
  scope <- spec$payout_scope %||% "local"
  if (!scope %in% SP_PAYOUT_SCOPES) {
    stop("Unknown payout scope '", scope, "'.", call. = FALSE)
  }
  n <- nrow(exposure)
  if (!"sim_year" %in% names(exposure) || !thresholds$variable %in% names(exposure)) {
    stop("The exposure needs `sim_year` and the trigger variable.", call. = FALSE)
  }
  value <- as.numeric(exposure[[thresholds$variable]])
  limit <- if (identical(thresholds$type, "weather")) {
    rep(thresholds$value, n)
  } else {
    keys <- intersect(.sp_trigger_key_cols, names(thresholds$table))
    if (!all(keys %in% names(exposure))) {
      stop("The exposure lacks the threshold key columns.", call. = FALSE)
    }
    chr <- function(df) {
      df <- as.data.frame(df)[keys]
      df[] <- lapply(df, as.character)
      df
    }
    th <- chr(thresholds$table)
    th$threshold <- thresholds$table$threshold
    dplyr::left_join(chr(exposure), th, by = keys)$threshold
  }
  exceeds <- if (identical(thresholds$direction, "above")) value >= limit else value <= limit
  exceeds[is.na(exceeds)] <- FALSE

  w <- if (is.null(weights)) rep(1, n) else as.numeric(weights)
  w[!is.finite(w) | w < 0] <- 0
  year <- exposure$sim_year
  total <- rowsum(w, year, reorder = TRUE)[, 1L]
  hit <- rowsum(w * exceeds, year, reorder = TRUE)[, 1L]
  share <- ifelse(total > 0, hit / total, 0)

  k <- as.numeric(spec$national_k_pct %||% 0) / 100
  gate <- if (identical(scope, "local")) {
    stats::setNames(rep(FALSE, length(share)), names(share))
  } else {
    share > 0 & share >= k
  }
  gate_row <- unname(gate[as.character(year)])
  in_scope <- switch(scope,
    local = exceeds,
    national_triggered = gate_row & exceeds,
    national_all = gate_row
  )
  list(exceeds = exceeds, in_scope = in_scope, share = share, gate = gate)
}

#' Dynamic transfer per prediction row
#'
#' The daily-equivalent transfer a prediction row receives: the static
#' program's per-household amount (`transfer_amount_usd` times
#' `payments_per_activation`, over 365) for statically eligible households,
#' multiplied by the trigger's payout scope. The per-household arithmetic is
#' `.sp_transfer_values()` itself (household size, amount basis, currency), so a
#' trigger that always fires reproduces the regular program's transfer exactly.
#' Administration cost is not part of the transfer; it is a cost only.
#'
#' The result is on the stored welfare scale (2021 PPP), like `SP_TRANSFER_COL`.
#' Convert it to the outcome's scale with `outcome_level_scale()` before adding
#' it to a prediction.
#'
#' @param state Result of `sp_trigger_state()` for the pipeline.
#' @param eligibility Logical per survey row (`SP_ELIGIBLE_COL`).
#' @param spec Scenario list.
#' @param svy Survey frame the eligibility refers to (`welfare`, `hhsize`,
#'   `ppp2021` as the regular program needs them).
#' @param analysis_unit `"hh"`, `"ind"` or `"firm"`.
#' @param svy_row_id Integer survey row of each prediction row, aligned with
#'   `state$in_scope`.
#' @return Numeric vector, one value per prediction row.
#' @keywords internal
sp_dynamic_transfer <- function(state, eligibility, spec, svy, analysis_unit = "hh",
                                svy_row_id) {
  if (length(eligibility) != nrow(svy)) {
    stop("Eligibility must have one value per survey row.", call. = FALSE)
  }
  ids <- as.integer(svy_row_id)
  if (length(ids) != length(state$in_scope) || anyNA(ids) ||
    any(ids < 1L | ids > nrow(svy))) {
    stop("Prediction rows must map to survey rows.", call. = FALSE)
  }
  eligible <- !is.na(eligibility) & eligibility
  per_household <- .sp_transfer_values(
    svy,
    utils::modifyList(spec, list(
      budget_mode = "transfer_first",
      transfer_n_payments = spec$payments_per_activation %||% 1L
    )),
    analysis_unit, eligible
  )
  if (is.null(per_household)) {
    stop("The survey cannot support a transfer (no welfare column).", call. = FALSE)
  }
  per_household[ids] * state$in_scope
}

#' Welfare effect of a transfer against the predicted level
#'
#' For a log outcome the transfer is a level amount, so its log effect is taken
#' against the predicted year-t level, `log(exp(y_t) + T) - y_t` (the formula of
#' `.policy_annual_channel_block()`, R2-BUG-07); a zero transfer is exactly 0.
#' Identity outcomes add the transfer directly. Rows with a transfer but no
#' finite prediction return `NA` for the caller to handle.
#'
#' @param y_t Predicted outcome on the model scale.
#' @param transfer Transfer on the model scale (`outcome_level_scale()`).
#' @param is_log Whether the outcome is log-transformed.
#' @return Numeric vector, same length as `transfer`.
#' @keywords internal
sp_dynamic_effect <- function(y_t, transfer, is_log) {
  if (!is_log) {
    return(as.numeric(transfer))
  }
  y_t <- as.numeric(y_t)
  transfer <- as.numeric(transfer)
  out <- rep(NA_real_, length(transfer))
  out[!is.na(transfer) & transfer == 0] <- 0
  ok <- is.finite(y_t) & is.finite(transfer) & transfer != 0
  out[ok] <- log(pmax(exp(y_t[ok]) + transfer[ok], 1e-10)) - y_t[ok]
  out
}
