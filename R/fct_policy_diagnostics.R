# Step 3 policy diagnostics ----
# Construction, treatment assignment, and covariate support diagnostics.

policy_treatment_matrix <- function(baseline_svy, policy_svy,
                                    eligibility = NULL, weight_col = "weight",
                                    analysis_unit = "hh") {
  if (is.null(baseline_svy) || is.null(policy_svy) ||
    nrow(baseline_svy) != nrow(policy_svy)) {
    return(data.frame())
  }
  p <- if (SP_TRANSFER_COL %in% names(policy_svy)) {
    policy_svy[[SP_TRANSFER_COL]] > 0
  } else {
    if ("sp_eligible" %in% names(policy_svy)) as.logical(policy_svy$sp_eligible) else rep(FALSE, nrow(policy_svy))
  }
  p[is.na(p)] <- FALSE
  # A zero-transfer run has no social-protection assignment, even if an
  # inactive scenario still supplies an ideal eligibility vector.
  has_transfer_col <- SP_TRANSFER_COL %in% names(policy_svy)
  b <- if (has_transfer_col && !any(p)) {
    rep(FALSE, nrow(baseline_svy))
  } else if (!is.null(eligibility)) {
    as.logical(eligibility)
  } else {
    if ("sp_eligible" %in% names(baseline_svy)) as.logical(baseline_svy$sp_eligible) else rep(FALSE, nrow(baseline_svy))
  }
  b[is.na(b)] <- FALSE
  p[is.na(p)] <- FALSE
  w <- if (weight_col %in% names(baseline_svy)) as.numeric(baseline_svy[[weight_col]]) else rep(1, nrow(baseline_svy))
  w[!is.finite(w) | w < 0] <- 0
  hhsize <- if (identical(analysis_unit, "hh") && "hhsize" %in% names(baseline_svy)) {
    hs <- suppressWarnings(as.numeric(baseline_svy$hhsize))
    hs[!is.finite(hs) | hs <= 0] <- 1
    hs
  } else {
    rep(1, nrow(baseline_svy))
  }
  household_w <- if (identical(analysis_unit, "hh") && weight_col %in% names(baseline_svy)) {
    w / hhsize
  } else {
    w
  }
  status <- interaction(b, p, drop = TRUE, sep = "_")
  labels <- c(
    `FALSE_FALSE` = "Not eligible, not treated",
    `FALSE_TRUE` = "Inclusion error: not eligible, treated",
    `TRUE_FALSE` = "Exclusion error: eligible, not treated",
    `TRUE_TRUE` = "Eligible and treated"
  )
  dplyr::bind_rows(lapply(names(labels), function(k) {
    ok <- as.character(status) == k
    data.frame(
      status = labels[[k]],
      eligible_baseline = startsWith(k, "TRUE"),
      treated_policy = endsWith(k, "TRUE"),
      n = sum(ok), weighted_n = sum(w[ok]),
      weighted_households = sum(household_w[ok]),
      weighted_share = if (sum(w) > 0) sum(w[ok]) / sum(w) else NA_real_,
      stringsAsFactors = FALSE
    )
  }))
}

# Unit-level masks shared by the diagnostics coverage table and the Step 3
# Results headline card, so reach cannot drift between the two surfaces.

.policy_sp_mask <- function(policy_svy) {
  if (SP_TRANSFER_COL %in% names(policy_svy)) {
    is.finite(as.numeric(policy_svy[[SP_TRANSFER_COL]])) & as.numeric(policy_svy[[SP_TRANSFER_COL]]) > 0
  } else {
    rep(FALSE, nrow(policy_svy))
  }
}

.policy_other_mask <- function(baseline_svy, policy_svy, weight_col = "weight",
                               candidates = NULL) {
  changed <- detect_manipulated_vars(baseline_svy, policy_svy, candidates = candidates)
  non_sp_vars <- setdiff(changed, c("welfare", SP_TRANSFER_COL, weight_col, "sim_year", "year"))
  if (!length(non_sp_vars)) {
    return(rep(FALSE, nrow(policy_svy)))
  }
  changed_mask <- function(v) {
    b <- baseline_svy[[v]]
    p <- policy_svy[[v]]
    (!is.na(b) & !is.na(p) & b != p) | (is.na(b) != is.na(p))
  }
  Reduce("|", lapply(non_sp_vars, changed_mask))
}

#' Units touched by any implemented policy
#'
#' Logical mask over \code{policy_svy} rows: TRUE where the unit receives a
#' positive social-protection transfer or has any covariate changed by another
#' policy lever. The same union the Diagnostics tab's coverage table reports.
#'
#' @param baseline_svy Data frame before \code{apply_policy_to_svy()}.
#' @param policy_svy   Data frame after \code{apply_policy_to_svy()}.
#' @param weight_col   Weight column excluded from the covariate comparison.
#' @param candidates   Optional columns the policy can modify (see
#'   \code{detect_manipulated_vars()}); NULL compares every shared column.
#' @return Logical vector of length \code{nrow(policy_svy)}.
#' @keywords internal
policy_reach_mask <- function(baseline_svy, policy_svy, weight_col = "weight",
                              candidates = NULL) {
  .policy_sp_mask(policy_svy) |
    .policy_other_mask(baseline_svy, policy_svy, weight_col, candidates)
}

# Share and count of the represented population touched by any policy lever,
# stored on the diagnostics snapshot so the reach cards and the component table
# use one definition of "reached". `households` is NA outside household mode.
policy_reach_summary <- function(baseline_svy, policy_svy, weight_col = "weight",
                                 analysis_unit = "hh", candidates = NULL) {
  if (is.null(baseline_svy) || is.null(policy_svy) ||
    nrow(baseline_svy) != nrow(policy_svy)) {
    return(NULL)
  }
  w <- if (weight_col %in% names(baseline_svy)) as.numeric(baseline_svy[[weight_col]]) else rep(1, nrow(baseline_svy))
  w[!is.finite(w) | w < 0] <- 0
  hh_mode <- identical(analysis_unit, "hh") && "hhsize" %in% names(baseline_svy) &&
    weight_col %in% names(baseline_svy)
  hs <- if (hh_mode) {
    h <- suppressWarnings(as.numeric(baseline_svy$hhsize))
    h[!is.finite(h) | h <= 0] <- 1
    h
  } else {
    rep(1, nrow(baseline_svy))
  }
  mask <- policy_reach_mask(baseline_svy, policy_svy, weight_col, candidates)
  mask[is.na(mask)] <- FALSE
  list(
    share = if (sum(w) > 0) sum(w[mask]) / sum(w) else NA_real_,
    people = sum(w[mask]),
    households = if (hh_mode) sum((w / hs)[mask]) else NA_real_
  )
}

policy_component_matrix <- function(baseline_svy, policy_svy,
                                    weight_col = "weight", analysis_unit = "hh",
                                    candidates = NULL, currency = "PPP",
                                    admin_share = 0, sp_cost = NULL) {
  if (is.null(baseline_svy) || is.null(policy_svy) ||
    nrow(baseline_svy) != nrow(policy_svy)) {
    return(data.frame())
  }
  w <- if (weight_col %in% names(baseline_svy)) as.numeric(baseline_svy[[weight_col]]) else rep(1, nrow(baseline_svy))
  w[!is.finite(w) | w < 0] <- 0
  hhsize <- if (identical(analysis_unit, "hh") && "hhsize" %in% names(baseline_svy)) {
    hs <- suppressWarnings(as.numeric(baseline_svy$hhsize))
    hs[!is.finite(hs) | hs <= 0] <- 1
    hs
  } else {
    rep(1, nrow(baseline_svy))
  }
  household_w <- if (identical(analysis_unit, "hh") && weight_col %in% names(baseline_svy)) {
    w / hhsize
  } else {
    w
  }
  total_w <- sum(w)
  changed <- detect_manipulated_vars(
    baseline_svy, policy_svy,
    candidates = candidates
  )
  non_sp_vars <- setdiff(changed, c("welfare", SP_TRANSFER_COL, weight_col, "sim_year", "year"))
  changed_mask <- function(v) {
    b <- baseline_svy[[v]]
    p <- policy_svy[[v]]
    (!is.na(b) & !is.na(p) & b != p) | (is.na(b) != is.na(p))
  }
  sp_mask <- .policy_sp_mask(policy_svy)
  other_mask <- if (length(non_sp_vars)) {
    Reduce("|", lapply(non_sp_vars, changed_mask))
  } else {
    rep(FALSE, nrow(policy_svy))
  }
  rows <- list()
  add_row <- function(component, mask, cost = NA_real_) {
    rows[[length(rows) + 1L]] <<- data.frame(
      component = component, n_affected = sum(mask, na.rm = TRUE),
      weighted_affected = sum(w[mask], na.rm = TRUE),
      weighted_households = sum(household_w[mask], na.rm = TRUE),
      population_share = if (total_w > 0) sum(w[mask], na.rm = TRUE) / total_w else NA_real_,
      realized_cost = cost, stringsAsFactors = FALSE
    )
  }
  add_row(
    "Social protection", sp_mask,
    # A shock-responsive program reports its expected annual cost (`sp_cost`)
    sp_cost %||% if (SP_TRANSFER_COL %in% names(policy_svy)) {
      .sp_transfer_totals(policy_svy, analysis_unit, currency, admin_share)$total_cost
    } else {
      NA_real_
    }
  )
  for (v in non_sp_vars) add_row(.policy_display_name(v), changed_mask(v))
  if (length(non_sp_vars) > 1L) add_row("Other policy levers (combined)", other_mask)
  if (any(sp_mask & other_mask)) add_row(.policy_overlap_label, sp_mask & other_mask)
  dplyr::bind_rows(rows)
}


# Share of the represented population moved by more than one decile of the
# estimation-sample outcome distribution by the direct effect (DOC-03). The
# quantile model prices weather at the household's position, so a large share
# means the repositioning effect leans on an extrapolation. Only the quantile
# model has a position; other engines return NULL.
.DECILE_MOVE_WARN <- 0.10

policy_decile_movement <- function(context) {
  if (is.null(context) || !identical(context$engine, "rif") ||
    !is.function(context$F_hat) || is.null(context$delta_main)) {
    return(NULL)
  }
  decile <- function(y) pmin(pmax(ceiling(context$F_hat(y) * 10), 1L), 10L)
  d0 <- decile(context$y_baseline)
  d1 <- decile(context$y_baseline + context$delta_main)
  svy <- context$svy_baseline
  wcol <- survey_weight_column(names(svy))
  w <- if (!is.null(wcol)) as.numeric(svy[[wcol]]) else rep(1, length(d0))
  w[!is.finite(w) | w < 0] <- 0
  ok <- is.finite(d0) & is.finite(d1)
  if (!any(ok) || sum(w[ok]) <= 0) return(NULL)
  list(
    share = sum(w[ok & abs(d1 - d0) > 1L]) / sum(w[ok]),
    share_any = sum(w[ok & d1 != d0]) / sum(w[ok]),
    warn_at = .DECILE_MOVE_WARN
  )
}

.policy_display_name <- function(x) {
  x <- gsub("[_\\.]+", " ", x)
  x <- gsub("([a-z])([A-Z])", "\\1 \\2", x)
  tools::toTitleCase(x)
}

.policy_diagnostic_label <- function(var_name, variable_list = NULL,
                                     selected_outcome = NULL) {
  if (identical(var_name, SP_TRANSFER_COL)) {
    return("Social protection transfer ($ per day)")
  }
  if (!is.null(selected_outcome) && is.data.frame(selected_outcome) &&
    nrow(selected_outcome) && all(c("name", "label") %in% names(selected_outcome)) &&
    identical(var_name, as.character(selected_outcome$name[[1L]])) &&
    !is.na(selected_outcome$label[[1L]]) &&
    nzchar(as.character(selected_outcome$label[[1L]]))) {
    return(as.character(selected_outcome$label[[1L]]))
  }
  .label_lookup(variable_list)(var_name)
}

.policy_input_table_raw <- function(df) {
  if (is.null(df) || !nrow(df)) {
    return(df)
  }
  if (ncol(df) == 6L) {
    names(df) <- c(
      "Variable", "Baseline mean", "Policy mean",
      "Change in mean", "Baseline spread", "Policy spread"
    )
  } else if (ncol(df) == 7L) {
    names(df) <- c(
      "Variable", names(df)[2], "Baseline mean", "Policy mean",
      "Change in mean", "Baseline spread", "Policy spread"
    )
  } else {
    stop("Policy input summary must have six or seven columns.")
  }
  df$Variable <- .policy_display_name(df$Variable)
  df
}

.format_policy_input_table <- function(df) {
  df <- .policy_input_table_raw(df)
  if (is.null(df) || !nrow(df)) {
    return(df)
  }
  num_cols <- setdiff(names(df), "Variable")
  df[num_cols] <- lapply(df[num_cols], function(x) fmt_num(x, digits = 2))
  df
}

.policy_changed_counts <- function(baseline_svy, policy_svy, vars) {
  setNames(vapply(vars, function(v) {
    b <- baseline_svy[[v]]
    p <- policy_svy[[v]]
    sum((!is.na(b) & !is.na(p) & b != p) | (is.na(b) != is.na(p)), na.rm = TRUE)
  }, numeric(1L)), vars)
}

.policy_treatment_table_raw <- function(df, analysis_unit = "hh") {
  if (is.null(df) || !nrow(df)) {
    return(df)
  }
  out <- data.frame(
    `Coverage status` = df$status,
    `Sample units` = suppressWarnings(as.numeric(df$n)),
    `Population represented` = suppressWarnings(as.numeric(df$weighted_n)),
    `Population share` = 100 * suppressWarnings(as.numeric(df$weighted_share)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if (identical(analysis_unit, "hh") && "weighted_households" %in% names(df)) {
    out$`Households represented` <- suppressWarnings(as.numeric(df$weighted_households))
  }
  out
}

.format_policy_treatment_table <- function(df, analysis_unit = "hh") {
  raw <- .policy_treatment_table_raw(df, analysis_unit)
  if (is.null(raw) || !nrow(raw)) {
    return(raw)
  }
  out <- data.frame(
    `Coverage status` = raw$`Coverage status`,
    `Sample units` = fmt_num(raw$`Sample units`, digits = 0),
    `Population represented` = fmt_num(raw$`Population represented`, digits = 0),
    `Population share` = fmt_num(raw$`Population share`, digits = 1, suffix = "%"),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  if ("Households represented" %in% names(raw)) {
    out$`Households represented` <- fmt_num(raw$`Households represented`, digits = 0)
  }
  out
}

# Rows of the social-protection transfer summary, shared by the on-screen table
# and the export so they cannot drift. Raw values; callers format them. With no
# administration cost the rows are the original two (cost and per-recipient
# amount); with administration the cost is split into transfers, administration
# and total.
.policy_transfer_summary_rows <- function(d) {
  unit_label <- if (identical(d$analysis_unit, "hh")) "household" else "unit"
  basis <- if (length(d$transfer_households) && is.finite(d$transfer_households)) {
    "recipient households"
  } else {
    "recipient population"
  }
  per_recipient <- paste0("Annual transfer per recipient ", unit_label)
  if (isTRUE(d$admin_share > 0)) {
    data.frame(
      Type = c(
        paste0("Estimated annual transfer cost (", basis, ")"),
        "Estimated annual administration cost",
        "Estimated total annual cost",
        per_recipient
      ),
      Value = c(d$transfer_sum, d$admin_sum, d$total_cost_sum, d$transfer_pp),
      stringsAsFactors = FALSE
    )
  } else {
    data.frame(
      Type = c(paste0("Estimated annual cost (", basis, ")"), per_recipient),
      Value = c(d$transfer_sum, d$transfer_pp),
      stringsAsFactors = FALSE
    )
  }
}

.diag_subheading_style <- "margin: 14px 0 6px; font-weight: 600; color: #173042;"

# Headline cards of the cost section. `per_person` is the first row of
# `sp_effectiveness()$metrics` (cost per person in the population) or NULL.
# A shock program reports annual means over the historical years.
.sp_cost_cards <- function(d, shock = FALSE, per_person = NULL) {
  if (is.null(d) || is.null(d$transfer_sum)) {
    return(NULL)
  }
  prefix <- .sp_currency_prefix(d$transfer_currency)
  money <- function(x, digits = 0) fmt_compact(x, prefix = prefix, small_digits = digits)
  admin <- isTRUE(d$admin_share > 0)
  total <- if (is.finite(d$total_cost_sum %||% NA_real_)) d$total_cost_sum else d$transfer_sum
  unit <- if (identical(d$analysis_unit, "hh")) "household" else "unit"
  cards <- list(list(
    label = if (shock) "Mean annual cost" else "Annual cost",
    value = money(total),
    note = if (admin) {
      paste0(
        "Transfers ", money(d$transfer_sum), "; administration ", money(d$admin_sum),
        " (", fmt_num(100 * d$admin_share, digits = 0), "% of total cost)"
      )
    } else {
      "No administration cost counted"
    }
  ))
  if (is.finite(d$transfer_pp %||% NA_real_)) {
    cards[[length(cards) + 1L]] <- list(
      label = paste0("Transfer per recipient ", unit),
      value = money(d$transfer_pp, 1),
      note = if (shock) "In a year in which the household is paid" else "Per year"
    )
  }
  if (!is.null(per_person) && is.finite(per_person$value)) {
    cards[[length(cards) + 1L]] <- list(
      label = "Cost per person in the population",
      value = money(per_person$value, 2),
      note = if (shock) "In a year in which every eligible household is paid" else "Per year, all represented people"
    )
  }
  if (length(d$transfer_households) && is.finite(d$transfer_households)) {
    cards[[length(cards) + 1L]] <- list(
      label = if (shock) "Households paid at least once" else "Recipient households",
      value = fmt_compact(d$transfer_households),
      note = "Represented by the survey weights"
    )
  }
  cards
}

# Reach cards: share of the baseline population touched by any policy lever.
.policy_decile_move_cards <- function(movement) {
  if (is.null(movement) || !is.finite(movement$share %||% NA_real_)) {
    return(NULL)
  }
  large <- movement$share >= movement$warn_at
  list(list(
    label = "Households moving more than one decile",
    value = fmt_num(100 * movement$share, digits = 1, suffix = "%"),
    note = paste0(
      "Position before and after the direct effect. ",
      if (large) {
        "Large movement: the repositioning effect is an extrapolation."
      } else {
        "Repositioning stays close to the observed positions."
      }
    )
  ))
}

.policy_reach_cards <- function(reach, analysis_unit = "hh") {
  if (is.null(reach) || !is.finite(reach$share %||% NA_real_)) {
    return(NULL)
  }
  cards <- list(list(
    label = "Population reached by any policy",
    value = fmt_num(100 * reach$share, digits = 1, suffix = "%"),
    note = paste(fmt_compact(reach$people), "people represented")
  ))
  if (is.finite(reach$households %||% NA_real_)) {
    cards[[2L]] <- list(
      label = "Households reached",
      value = fmt_compact(reach$households),
      note = "Represented by the survey weights"
    )
  }
  cards
}

.policy_treatment_explanation <- function(sp) {
  base <- .policy_treatment_explanation_base(sp)
  if (is.list(sp) && identical(sp$sp_type, "shock")) {
    return(paste(
      "Shock-responsive program: treated means paid in at least one historical",
      "weather year, so eligible households that no trigger ever reached count as",
      "untreated here, besides targeting errors.", base
    ))
  }
  base
}

.policy_treatment_explanation_base <- function(sp) {
  if (is.null(sp) || !is.list(sp)) {
    return(paste(
      "Eligibility follows the selected targeting rule; treatment is a positive transfer after assignment.",
      "This table shows counterfactual assignment, not observed cash receipt."
    ))
  }

  targeting <- sp$targeting %||% "exante_poor"
  targeting_text <- switch(targeting,
    exante_poor = paste0(
      "Eligibility is the bottom ", sp$targeting_threshold %||% 20,
      "% by baseline welfare."
    ),
    pmt = paste0(
      "Eligibility follows the selected proxy variable and cutoff."
    ),
    universal = "Universal targeting makes every baseline unit eligible and applies no targeting errors.",
    "Eligibility follows the selected targeting rule before targeting errors."
  )

  if (identical(targeting, "universal")) {
    return(paste(
      targeting_text,
      "Treatment is a positive transfer after assignment; this table shows counterfactual assignment."
    ))
  }

  incl <- sp$inclusion_error_pct %||% 0
  excl <- sp$exclusion_error_pct %||% 0
  placement <- if (.sp_error_concentration(sp) > 0) {
    " Errors fall preferentially on units near the cutoff."
  } else {
    ""
  }
  paste(
    targeting_text,
    paste0(
      "The run then applies the selected targeting errors: ", incl,
      "% inclusion error can treat ineligible units, and ", excl,
      "% exclusion error can miss eligible units.", placement
    ),
    "Treatment is a positive transfer after that draw; this is counterfactual assignment."
  )
}

.policy_component_table_raw <- function(df, analysis_unit = "hh") {
  if (is.null(df) || !nrow(df)) {
    return(df)
  }
  unit_label <- if (identical(analysis_unit, "hh")) {
    "Sample households affected / covered"
  } else {
    "Sample observations affected / covered"
  }
  out <- data.frame(
    `Policy component` = df$component,
    setNames(list(suppressWarnings(as.numeric(df$n_affected))), unit_label),
    `Population represented` = suppressWarnings(as.numeric(df$weighted_affected)),
    `Population share` = 100 * suppressWarnings(as.numeric(df$population_share)),
    `Realized cost` = suppressWarnings(as.numeric(df$realized_cost)),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  if (identical(analysis_unit, "hh") && "weighted_households" %in% names(df)) {
    out$`Households represented` <- suppressWarnings(as.numeric(df$weighted_households))
  }
  out
}

.format_policy_component_table <- function(df, analysis_unit = "hh",
                                           currency = "PPP") {
  raw <- .policy_component_table_raw(df, analysis_unit)
  if (is.null(raw) || !nrow(raw)) {
    return(raw)
  }
  out <- data.frame(
    `Policy component` = raw$`Policy component`,
    raw[setdiff(names(raw), c(
      "Policy component", "Population represented", "Population share", "Realized cost"
    ))],
    `Population represented` = fmt_num(raw$`Population represented`, digits = 0),
    `Population share` = fmt_num(raw$`Population share`, digits = 1, suffix = "%"),
    `Realized cost` = fmt_num(
      raw$`Realized cost`,
      digits = 0, prefix = .sp_currency_prefix(currency)
    ),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  if ("Households represented" %in% names(raw)) {
    out$`Households represented` <- fmt_num(raw$`Households represented`, digits = 0)
  }
  out
}

# Shared reactable styling for the diagnostics tables (guidelines section 6): raw
# values in the data, display rounding via colFormat; `formats` maps column
# names to colFormat argument lists. Fallback states pass a single-column
# Note frame (mod_1_02 pattern).
#' @noRd
.wise_diag_reactable <- function(df, formats = list()) {
  cols <- lapply(names(df), function(nm) {
    x <- df[[nm]]
    if (is.numeric(x)) {
      fmt <- formats[[nm]] %||% list(digits = 2, separators = TRUE)
      reactable::colDef(
        format = do.call(reactable::colFormat, fmt),
        class = "wise-dt-wrap",
        minWidth = 90
      )
    } else if (is.character(x) || is.factor(x)) {
      reactable::colDef(class = "wise-dt-wrap", minWidth = 170)
    } else {
      reactable::colDef(class = "wise-dt-wrap", minWidth = 70)
    }
  })
  names(cols) <- names(df)
  reactable::reactable(
    df,
    columns = cols,
    compact = TRUE,
    searchable = FALSE,
    defaultPageSize = 10,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 25, 50, 100),
    highlight = TRUE
  )
}
