# Pure helpers of the social protection panel, moved out of
# mod_3_01_sp_server() (CR-CQ-01).

.sp_unit_word <- function(plural = TRUE, capitalize = FALSE, au = NULL) {
  au <- if (is.null(au) || !nzchar(au)) "hh" else au
  word <- switch(au,
    ind  = if (plural) "individuals" else "individual",
    hh   = if (plural) "households" else "household",
    firm = if (plural) "firms" else "firm",
    if (plural) "households" else "household"
  )
  if (capitalize) {
    paste0(toupper(substr(word, 1, 1)), substr(word, 2, nchar(word)))
  } else {
    word
  }
}

# Currency label of the amount inputs from the outcome's units; LCU amounts are
# in 2021 prices, matching the "LCU (2021)" outcome option (see R2-BUG-04).
.sp_amount_currency_label <- function(currency) {
  if (is.na(currency) || !nzchar(currency)) currency <- "PPP"
  if (identical(.sp_currency(currency), "LCU")) "2021 LCU" else currency
}

.sp_targeting_summary <- function(targeting, error_concentration,
                                  inclusion_error_pct, exclusion_error_pct) {
  if (identical(targeting, "universal")) {
    return("")
  }
  conc <- suppressWarnings(as.numeric(error_concentration))
  paste0(
    if (identical(targeting, "pmt")) "Proxy rule; " else "",
    "errors ", inclusion_error_pct, "% / ", exclusion_error_pct, "%",
    if (is.finite(conc) && conc > 0) ", near cutoff" else ""
  )
}

# `n_payments` is NULL when the payment count is not part of the summary.
.sp_payment_summary <- function(admin_cost_pct, basis, n_payments, analysis_unit) {
  admin <- suppressWarnings(as.numeric(admin_cost_pct))
  parts <- c(
    if (!is.null(n_payments)) paste0(n_payments, " payments/year"),
    # Basis of the amount: per household (default) or per person; other
    # analysis units are paid per unit.
    if (identical(analysis_unit, "hh")) {
      if (identical(basis, "per_capita")) "per person" else "per household"
    } else {
      paste("per", .sp_unit_word(plural = FALSE, au = analysis_unit))
    },
    if (is.finite(admin) && admin > 0) paste0("admin ", admin, "%")
  )
  if (length(parts)) paste(parts, collapse = ", ") else ""
}

# Live reach / cost card of the social protection panel. `shock_state` is
# sp_shock_state() for a shock program (NULL otherwise) and `analysis_unit_now`
# the live analysis unit; both are passed in so the module reads its reactives
# only where it did before.
.sp_reach_card <- function(r, preview_spec, preview_unit, display_type,
                           shock_state, analysis_unit_now) {
  unit_pl <- .sp_unit_word(plural = TRUE, au = preview_unit)
  unit_sg <- .sp_unit_word(plural = FALSE, au = preview_unit)
  program_label <- if (identical(display_type, "shock")) {
    "Shock-responsive"
  } else {
    "Regular"
  }
  program_title <- tags$span(
    class = "sp-summary-program",
    tags$span(class = "selection-card-badge", program_label),
    tags$span(class = "sp-summary-program-suffix", "cash transfer")
  )

  if (is.null(r)) {
    return(selection_summary_card(
      title = program_title,
      rows = list(list(
        name = paste("Recipient", unit_pl),
        pills = "Not available"
      )),
      compact = TRUE
    ))
  }

  # Report household recipients separately from their represented people.
  count_hint <- if (isTRUE(r$weighted)) {
    paste0(
      "Survey-weighted; ", fmt_count(r$n_rows), " of ",
      fmt_count(r$n_total), " sampled ", unit_pl
    )
  } else {
    paste0(
      "Unweighted sample count; ", fmt_count(r$n_rows), " of ",
      fmt_count(r$n_total), " sampled ", unit_pl
    )
  }

  is_shock <- identical(preview_spec$sp_type, "shock")
  cost_label <- if (is_shock) "Annual cost in a year it pays" else "Estimated annual cost"
  shock_rows <- if (is_shock) {
    s <- shock_state
    cur <- .sp_currency_prefix(preview_spec$currency)
    if (is.null(s) || !is.null(s$problem)) {
      list(selection_card_row(
        name = "Trigger", pills = s$problem %||% "Not available"
      ))
    } else {
      list(
        selection_card_row(
          name = "Years with payments",
          pills = fmt_num(100 * s$activation_freq, suffix = "%")
        ),
        selection_card_row(
          name = "Expected annual cost",
          pills = fmt_compact(s$mean_cost, prefix = cur)
        ),
        selection_card_row(
          name = "95th percentile annual cost",
          pills = if (is.finite(s$cost_1_in_20)) {
            fmt_compact(s$cost_1_in_20, prefix = cur)
          } else {
            "Needs 20 years"
          }
        ),
        if (is.finite(suppressWarnings(as.numeric(preview_spec$annual_cap %||% NA)))) {
          selection_card_row(
            name = "Years the cap binds",
            pills = fmt_num(100 * s$cap_exhaustion_share, suffix = "%", na = "Not available")
          )
        },
        if (is.finite(s$breakeven_m %||% NA_real_)) {
          selection_card_row(
            name = "Payments before no event",
            pills = fmt_num(100 * s$false_alarm_cost_share, suffix = "%", na = "Not available")
          )
        },
        if (is.finite(s$breakeven_m %||% NA_real_)) {
          selection_card_row(
            name = "m needed to match ex post",
            pills = fmt_num(s$breakeven_m, digits = 2, na = "Not available")
          )
        },
        if (is.finite(s$breakeven_m_cost %||% NA_real_)) {
          selection_card_row(
            name = "m needed to match ex post, per dollar",
            pills = fmt_num(s$breakeven_m_cost, digits = 2, na = "Not available")
          )
        }
      )
    }
  }

  targeting <- preview_spec$targeting
  targeting_info <- switch(targeting,
    exante_poor = paste(
      "The bottom", preview_spec$targeting_threshold,
      "% is selected by sampled", unit_pl, "before inclusion and exclusion",
      "errors. The reached share is survey-weighted, so it can differ from",
      "the cutoff when sampled", unit_pl, "represent different population",
      "sizes. Household size affects transfer cost, not this percentage."
    ),
    pmt = paste(
      "Eligibility follows the selected Proxy variable and cutoff. The reached",
      "share is survey-weighted; inclusion and exclusion errors are applied",
      "after the Proxy rule."
    ),
    paste(
      "Universal targeting reaches all sampled units; survey weights determine",
      "the population count and share."
    )
  )

  selection_summary_card(
    title = program_title,
    rows = Filter(Negate(is.null), c(list(
      selection_card_row(
        name  = paste("Recipient", unit_pl),
        pills = fmt_compact(r$n_recipient_units)
      ),
      selection_card_row(
        name  = if (identical(analysis_unit_now, "hh")) {
          "People represented"
        } else {
          "Population represented"
        },
        pills = fmt_compact(r$n_pop)
      ),
      selection_card_row(
        name  = "Share of total population",
        pills = fmt_num(r$share_pct, suffix = "%")
      ),
      if (identical(r$amount_basis, "per_capita") &&
        identical(preview_unit, "hh")) {
        selection_card_row(
          name  = "Annual transfer per person",
          pills = fmt_compact(
            r$transfer_per_person,
            small_digits = 2, prefix = .sp_currency_prefix(preview_spec$currency)
          )
        )
      } else {
        selection_card_row(
          name  = paste("Annual transfer per", unit_sg),
          pills = fmt_compact(
            r$transfer_per_unit,
            small_digits = 2, prefix = .sp_currency_prefix(preview_spec$currency)
          )
        )
      },
      selection_card_row(
        name  = cost_label,
        pills = fmt_compact(
          r$transfer_total, prefix = .sp_currency_prefix(preview_spec$currency)
        )
      ),
      if (isTRUE(r$admin_cost > 0)) {
        selection_card_row(
          name  = "Of which administration",
          pills = fmt_compact(
            r$admin_cost, prefix = .sp_currency_prefix(preview_spec$currency)
          )
        )
      }
    ), shock_rows)),
    info = paste(
      count_hint,
      targeting_info,
      if (is_shock) {
        paste(
          "Recipients and cost are for a year in which the program pays.",
          "Years with payments, expected cost and the 95th percentile annual",
          "cost come from the historical weather years of Step 2, evaluated per",
          "survey location; they are not a forecast. Basis risk and the full",
          "set of measures are in the Policy profile tab. Large numbers are",
          "shortened (K thousand, M million, B billion)."
        )
      } else {
        ""
      },
      if (isTRUE(r$transfer_total <= 0) &&
        !identical(preview_spec$budget_rule, "loss_share")) {
        "No transfer is configured yet, so welfare would remain unchanged."
      } else {
        ""
      },
      if (!isTRUE(r$on_baseline)) {
        paste0(
          "Before Step 2 runs, this preview covers every survey round; ",
          "after the run it uses the baseline round used by the simulation."
        )
      } else {
        ""
      }
    ),
    compact = TRUE
  )
}
