# Social protection cost and targeting effectiveness ----
#
# Pure functions (no Shiny) behind the Step 3 diagnostics "Cost and targeting"
# table (plan: review/step3_cost_effectiveness_plan.md, sections 4.1 and 4.2;
# task P0-5 in review/sp_shock_responsive_tasks.md). They need only the baseline
# and policy survey frames, so every figure is exact for the run's single seeded
# targeting draw. Effect-per-cost metrics (cost per person lifted out of
# poverty) are not here: they need a Step 3 effect and open decisions in
# section 10 of that plan.

#' Cost and targeting effectiveness of a social-protection transfer
#'
#' Conventions follow `.sp_transfer_totals()`: survey weights represent people;
#' in household analysis the transfer column is per capita, so a household's
#' spending is `transfer * weight` (or `transfer * hhsize` without weights).
#' "Poor" means baseline welfare below `poverty_line`. The line is entered in
#' the outcome's currency and converted to the stored 2021 PPP scale per row
#' (`currency = "LCU"`), the same way the Results poverty line is.
#'
#' @param baseline_svy,policy_svy Survey frames before and after
#'   `apply_policy_to_svy()`; same rows. `policy_svy` carries `SP_TRANSFER_COL`.
#' @param poverty_line Poverty line in the outcome's currency, or NULL/NA when
#'   unavailable (the targeting metrics are then reported as not available).
#' @param analysis_unit `"hh"`, `"ind"` or `"firm"`.
#' @param currency `"PPP"` or `"LCU"`; see `sp$currency`.
#' @param admin_share Administration as a share of total cost, see
#'   `.sp_admin_share()`.
#' @param eligibility Optional logical vector, the ideal eligibility before
#'   targeting errors (as kept by the diagnostics snapshot). Enables the
#'   realised inclusion and exclusion error rates.
#' @param weight_col Name of the survey weight column.
#'
#' @return A list: `status` (`"ok"` or `"no_transfer"`), `has_line` (logical)
#'   and `metrics`, a data frame with `metric`, `value` (numeric, NA when not
#'   available), `kind` (`"money"`, `"percent"` or `"text"`) and `note`.
#' @keywords internal
sp_effectiveness <- function(baseline_svy, policy_svy, poverty_line = NULL,
                             analysis_unit = "hh", currency = "PPP",
                             admin_share = 0, eligibility = NULL,
                             weight_col = "weight") {
  empty <- list(
    status = "no_transfer", has_line = FALSE,
    metrics = data.frame(
      metric = character(), value = numeric(), kind = character(),
      note = character(), stringsAsFactors = FALSE
    )
  )
  if (!is.data.frame(baseline_svy) || !is.data.frame(policy_svy) ||
    nrow(baseline_svy) != nrow(policy_svy) || nrow(baseline_svy) == 0L ||
    !SP_TRANSFER_COL %in% names(policy_svy) ||
    !"welfare" %in% names(baseline_svy)) {
    return(empty)
  }

  n <- nrow(baseline_svy)
  v <- suppressWarnings(as.numeric(policy_svy[[SP_TRANSFER_COL]]))
  has_w <- weight_col %in% names(baseline_svy)
  w <- if (has_w) suppressWarnings(as.numeric(baseline_svy[[weight_col]])) else rep(1, n)
  w[!is.finite(w) | w < 0] <- 0
  hh <- if (identical(analysis_unit, "hh") && "hhsize" %in% names(baseline_svy)) {
    h <- suppressWarnings(as.numeric(baseline_svy$hhsize))
    h[!is.finite(h) | h <= 0] <- 1
    h
  } else {
    rep(1, n)
  }
  # Persons (or units) each row stands for, and spending per row per day.
  persons <- if (identical(analysis_unit, "hh") && !has_w) hh else w
  spend <- ifelse(is.finite(v), v, 0) * persons
  recip <- is.finite(v) & v > 0

  totals <- .sp_transfer_totals(policy_svy, analysis_unit, currency, admin_share)
  if (!any(recip) || !is.finite(totals$total_cost) || totals$total_cost <= 0) {
    return(empty)
  }

  pop <- sum(persons)
  rows <- list()
  add <- function(metric, value, kind, note = "") {
    rows[[length(rows) + 1L]] <<- data.frame(
      metric = metric, value = as.numeric(value), kind = kind, note = note,
      stringsAsFactors = FALSE
    )
  }

  add("Annual cost per person in the population",
    if (pop > 0) totals$total_cost / pop else NA_real_, "money",
    "Total annual cost (including administration) over all represented people.")
  add("Administration share of cost", admin_share, "percent",
    "Set in Payment settings; 0 means no administration cost is counted.")

  # Targeting accuracy against the ideal rule (before inclusion/exclusion errors)
  if (!is.null(eligibility) && length(eligibility) == n) {
    elig <- as.logical(eligibility)
    elig[is.na(elig)] <- FALSE
    add("Inclusion error (realised)",
      if (sum(persons[recip]) > 0) sum(persons[recip & !elig]) / sum(persons[recip]) else NA_real_,
      "percent", "Recipients who are not eligible under the rule, as a share of recipients.")
    add("Exclusion error (realised)",
      if (sum(persons[elig]) > 0) sum(persons[elig & !recip]) / sum(persons[elig]) else NA_real_,
      "percent", "Eligible units without a transfer, as a share of eligible units.")
  }

  # Poverty-line metrics
  pl <- suppressWarnings(as.numeric(poverty_line)[1L])
  has_line <- is.finite(pl) && pl > 0
  line_note <- "Needs a positive poverty line."
  if (has_line) {
    line <- .povline_to_ppp(rep(pl, n), baseline_svy, identical(.sp_currency(currency), "LCU"))
    welfare <- suppressWarnings(as.numeric(baseline_svy$welfare))
    poor <- is.finite(welfare) & is.finite(line) & welfare < line
    poor_pop <- sum(persons[poor])
    add("Coverage of the poor",
      if (poor_pop > 0) sum(persons[poor & recip]) / poor_pop else NA_real_,
      "percent", "Poor people (baseline welfare below the line) who receive a transfer.")
    add("Leakage to the non-poor",
      sum(spend[recip & !poor]) / sum(spend[recip]),
      "percent", "Share of transfer spending that reaches people above the line.")
    pr <- recip & poor
    gap_total <- sum(persons[pr] * (line[pr] - welfare[pr]))
    add("Adequacy for poor recipients",
      if (gap_total > 0) sum(spend[pr]) / gap_total else NA_real_,
      "percent",
      "Transfers to poor recipients as a share of their poverty gap (100% closes it).")
  } else {
    for (m in c("Coverage of the poor", "Leakage to the non-poor",
                "Adequacy for poor recipients")) {
      add(m, NA_real_, "percent", line_note)
    }
  }

  list(
    status = "ok", has_line = has_line,
    metrics = do.call(rbind, rows)
  )
}

# Display table for `sp_effectiveness()`: strings, one rule for every figure.
# Money uses the entry-currency prefix; percentages one decimal place.
.sp_effectiveness_display <- function(res, currency = "PPP") {
  m <- res$metrics
  if (is.null(m) || nrow(m) == 0L) {
    return(data.frame(Metric = character(), Value = character(), Note = character()))
  }
  value <- vapply(seq_len(nrow(m)), function(i) {
    if (identical(m$kind[[i]], "money")) {
      fmt_num(m$value[[i]], digits = 2, prefix = .sp_currency_prefix(currency))
    } else {
      fmt_num(100 * m$value[[i]], digits = 1, suffix = "%", na = "Not available")
    }
  }, character(1))
  data.frame(Metric = m$metric, Value = value, Note = m$note, stringsAsFactors = FALSE)
}
