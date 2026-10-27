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

# UI builders of the social protection panels, moved out of mod_3_01_sp_server()
# (CR-CQ-01). Each returns the tags its renderUI built; the module passes `ns` and
# the reactives or closures the tags read, which are called where they were before.

.sp_trigger_tags <- function(ns, trigger_candidates) {
  cands <- trigger_candidates()
  conditionalPanel(
    condition = paste0("input['", ns("sp_type"), "'] == 'shock'"),
    tags$label(
      class = "control-label",
      tags$i(class = "fa fa-bolt me-1"),
      "Trigger",
      info_popover(
        title = "How payments are triggered",
        tags$p(
          "A household is paid in a year when its survey location and interview",
          "month pass the trigger, so households of one location interviewed in",
          "different months can differ."
        ),
        tags$p(
          "Payments follow the shock (ex post) unless \"On a forecast\" is",
          "chosen under Payments are made; then a forecast with the set",
          "detection and false-alarm rates decides. Quantile-based welfare",
          "effects (RIF) do not respond to the payment."
        )
      )
    ),
    config_flyout_block(
      ns("trigger_toggle"),
      "Trigger settings",
      toggle_label = "Trigger settings",
      display_label = textOutput(ns("trigger_summary"), inline = TRUE),
      if (length(cands) == 0) {
        no_data_warning(
          "No continuous weather variable is available. Run Step 2 first",
          "(a binned variable is used through its continuous value)."
        )
      } else {
        tagList(
          selectInput(
            ns("trigger_metric"),
            label = tags$span(
              tags$i(class = "fa fa-ruler me-1"),
              "Trigger measures",
              info_popover(
                title = "What the trigger measures",
                tags$p(
                  tags$b("Weather variable:"), "a hazard index, as in the",
                  "response check below."
                ),
                tags$p(
                  tags$b("Impact:"), "modelled welfare loss, poverty rate or number",
                  "of poor, read from the central predictions of the year, nationally",
                  "or per survey location (interview months pooled). The threshold",
                  "comes from the historical years and is applied unchanged to climate",
                  "members. A real program would need an impact estimate this timely,",
                  "so read it as a benchmark. Loss is the percent of the households'",
                  "own typical welfare. Poverty uses the poverty line set below, and per",
                  "location at least", SP_IMPACT_MIN_HH, "sampled households per",
                  "location. For a return period the poverty rate and the number of",
                  "poor give the same years."
                )
              )
            ),
            choices = c(
              "Weather variable" = "weather",
              "Modelled welfare loss (%)" = "loss",
              "Poverty rate (%)" = "poverty_rate",
              "Number of poor (people)" = "poor_count"
            ),
            selected = "weather"
          ),
          conditionalPanel(
            condition = paste0("input['", ns("trigger_metric"), "'] != 'weather'"),
            selectInput(
              ns("trigger_level"),
              label = tags$span(
                "Read at",
                info_popover(
                  title = "Impact level",
                  tags$p(
                    "National uses one series. Administrative levels use the GAUL",
                    "codes in the survey data; only the levels the data supports",
                    "are listed. A survey location is a sampling cluster, too",
                    "small for a reliable poverty rate."
                  )
                )
              ),
              choices = c(
                "National" = "national", "Administrative level 1" = "admin1",
                "Administrative level 2" = "admin2", "Survey location" = "location"
              ),
              selected = "national"
            ),
            conditionalPanel(
              condition = paste0(
                "input['", ns("trigger_metric"), "'] == 'poverty_rate' || input['",
                ns("trigger_metric"), "'] == 'poor_count'"
              ),
              numericInput(
                ns("trigger_pov_line"),
                label = tags$span(
                  "Poverty line for the trigger (per day)",
                  info_popover(
                    title = "Trigger poverty line",
                    tags$p(
                      "In the outcome's currency per day. Fixed for the run, so it",
                      "does not follow the poverty line chosen later in Results.",
                      "Prefilled from the outcome's poverty line."
                    )
                  )
                ),
                value = 3, min = 0, step = 0.05
              )
            ),
            tags$p(
              class = "text-muted small",
              "Pays when the metric is at or above the threshold (more loss or",
              "more poor is adverse)."
            ),
            textOutput(ns("impact_info"), container = function(...) {
              tags$p(class = "text-muted small", ...)
            })
          ),
          pill_toggle(
            inputId = ns("trigger_type"),
            label = "Trigger on",
            aria_label = "Trigger type",
            choices = c("Fixed level" = "weather", "Return period" = "return_period"),
            # A return period needs no threshold typed in, so the program
            # runs with the defaults
            selected = "return_period"
          ),
          conditionalPanel(
            condition = paste0("input['", ns("trigger_metric"), "'] == 'weather'"),
            selectInput(
              ns("trigger_variable"),
              label = tags$span(
                tags$i(class = "fa fa-cloud-sun-rain me-1"),
                "Weather variable",
                info_popover(
                  title = "Weather variable",
                  tags$p(
                    "Only continuous weather variables can trigger payments.",
                    "The value is read in the unit the model uses for the",
                    "variable: physical units, deviation from the reference",
                    "mean, or a standardized anomaly."
                  )
                )
              ),
              choices = cands, selected = cands[[1]]
            ),
            textOutput(ns("trigger_unit"), container = function(...) {
              tags$p(class = "text-muted small", ...)
            }),
            uiOutput(ns("trigger_response")),
            pill_toggle(
              inputId = ns("trigger_direction"),
              label = "Pay when the value is",
              aria_label = "Trigger direction",
              choices = c(
                "At or above" = "above", "At or below" = "below",
                "Either end" = "either"
              ),
              selected = "above"
            )
          ),
          conditionalPanel(
            condition = paste0("input['", ns("trigger_type"), "'] != 'return_period'"),
            conditionalPanel(
              condition = paste0(
                "input['", ns("trigger_direction"), "'] == 'either' && input['",
                ns("trigger_metric"), "'] == 'weather'"
              ),
              numericInput(
                ns("trigger_value_low"),
                label = tags$span(
                  tags$i(class = "fa fa-gauge me-1"),
                  "Low threshold",
                  info_popover(
                    title = "Either extreme",
                    tags$p(
                      "Pays when the value is at or below the low threshold or at",
                      "or above the high threshold, for variables that hurt at",
                      "both ends (very dry and very wet)."
                    )
                  )
                ),
                value = NA
              )
            ),
            numericInput(
              ns("trigger_value"),
              label = tags$span(
                tags$i(class = "fa fa-gauge-high me-1"),
                "Threshold value",
                tags$span(
                  class = "text-muted small ms-1",
                  textOutput(ns("trigger_value_hint"), inline = TRUE)
                ),
                info_popover(
                  title = "Threshold value",
                  tags$p(
                    "One value for every location. It fires more often where the",
                    "variable is typically more extreme, so cost concentrates",
                    "there. Use a return period for the same activation chance",
                    "everywhere."
                  ),
                  tags$p(
                    "For an impact metric the value is in the metric's unit (shown",
                    "below the settings), together with its range over the",
                    "historical years."
                  )
                )
              ),
              value = NA
            )
          ),
          conditionalPanel(
            condition = paste0("input['", ns("trigger_type"), "'] == 'return_period'"),
            numericInput(
              ns("trigger_return_period_years"),
              label = tags$span(
                tags$i(class = "fa fa-hourglass-half me-1"),
                "Return period (1 in x years)",
                info_popover(
                  title = "Return period",
                  tags$p(
                    "Each location uses its own 1-in-x level, taken from its",
                    "historical years and applied unchanged to every climate",
                    "member. A 1-in-x trigger needs at least x historical years.",
                    "At either extreme the chance is shared between both ends",
                    "(1 in 2x each), which needs 2x years."
                  )
                )
              ),
              value = 10, min = 1, step = 1
            ),
            textOutput(ns("trigger_support"), container = function(...) {
              tags$p(class = "text-muted small", ...)
            })
          ),
          selectInput(
            ns("payout_scope"),
            label = tags$span(
              tags$i(class = "fa fa-map-location-dot me-1"),
              "Who is paid",
              info_popover(
                title = "Payout scope",
                tags$p(
                  tags$b("Triggered locations only:"),
                  "each location decides for itself."
                ),
                tags$p(
                  tags$b("National gate, triggered locations:"),
                  "payments start only in a year when enough of the population",
                  "lives in locations that pass the trigger; then only those",
                  "locations are paid."
                ),
                tags$p(
                  tags$b("National gate, all targeted households:"),
                  "once the gate opens, every targeted household is paid,",
                  "wherever it lives. Bills are rarer and larger."
                )
              )
            ),
            choices = c(
              "Triggered locations only" = "local",
              "National gate, triggered locations" = "national_triggered",
              "National gate, all targeted households" = "national_all"
            ),
            selected = "local"
          ),
          conditionalPanel(
            condition = paste0("input['", ns("payout_scope"), "'] != 'local'"),
            sliderInput(
              ns("national_k_pct"),
              label = "Population in triggered locations needed (%)",
              min = 5, max = 100, value = 20, step = 5, post = "%"
            )
          ),
          selectInput(
            ns("dyn_geo"),
            label = tags$span(
              tags$i(class = "fa fa-location-crosshairs me-1"),
              "Within triggered locations",
              info_popover(
                title = "Worst-affected locations",
                tags$p(
                  "Added on top of the targeting rule and the payout scope.",
                  "\"Worst-affected share\" pays only the most severe triggered",
                  "locations of each year, ranked by how far the weather passes the",
                  "trigger in units of the location's own historical standard",
                  "deviation, until the chosen share of the triggered population",
                  "is covered. Not available when all targeted households are paid."
                )
              )
            ),
            choices = c(
              "All triggered locations" = "all",
              "Worst-affected share" = "worst_share"
            ),
            selected = "all"
          ),
          conditionalPanel(
            condition = paste0("input['", ns("dyn_geo"), "'] == 'worst_share'"),
            sliderInput(
              ns("dyn_geo_pct"),
              label = "Triggered population paid (%)",
              min = 5, max = 100, value = 50, step = 5, post = "%"
            )
          ),
          # The popover sits beside the checkbox, not inside its label (PR-11)
          tags$div(
            class = "d-flex align-items-start gap-1",
            checkboxInput(
              ns("dyn_welfare"),
              label = "Also select on predicted welfare at the trigger",
              value = FALSE
            ),
            info_popover(
              title = "Predicted welfare (oracle)",
              tags$p(
                "A household is selected when the model's prediction of its own",
                "welfare in that year is at or below the chosen share of the",
                "households' historical mean welfare distribution (fixed for the",
                "run). This knows each household's modelled welfare in the shock",
                "year, which a real registry would not: read the result as an",
                "upper bound and use larger error rates. Errors are drawn per",
                "household and year with the run seed, the same in every scenario."
              )
            )
          ),
          conditionalPanel(
            condition = paste0("input['", ns("dyn_welfare"), "']"),
            sliderInput(
              ns("dyn_welfare_pct"),
              label = "Poorest at the trigger (bottom x%)",
              min = 5, max = 60, value = 20, step = 5, post = "%"
            ),
            sliderInput(
              ns("dyn_incl_error_pct"),
              label = "Inclusion error at the trigger (%)",
              min = 0, max = 50, value = 20, step = 5, post = "%"
            ),
            sliderInput(
              ns("dyn_excl_error_pct"),
              label = "Exclusion error at the trigger (%)",
              min = 0, max = 50, value = 20, step = 5, post = "%"
            )
          ),
          pill_toggle(
            inputId = ns("transfer_timing"),
            label = "Payments are made",
            aria_label = "Payment timing",
            choices = c("After the shock (ex post)" = "expost", "On a forecast (anticipatory)" = "anticipatory"),
            selected = "expost"
          ),
          conditionalPanel(
            condition = paste0("input['", ns("transfer_timing"), "'] == 'anticipatory'"),
            sliderInput(
              ns("forecast_pod_pct"),
              label = tags$span(
                "Forecast detection (POD, %)",
                info_popover(
                  title = "Forecast skill",
                  tags$p(
                    "In a location-year where the weather really passes the trigger,",
                    "the forecast fires with this probability. A missed event pays",
                    "nobody. The draw is seeded by the unit the trigger is read at",
                    "(survey location and month, area, or the whole country for a",
                    "national gate or national impact) and the year."
                  ),
                  tags$p(
                    "100 % detection, 0 % false alarms and a multiplier of 1 give",
                    "exactly the ex-post design."
                  )
                )
              ),
              min = 0, max = 100, value = 100, step = 5, post = "%"
            ),
            sliderInput(
              ns("forecast_far_pct"),
              label = tags$span(
                "False-alarm rate (%)",
                info_popover(
                  title = "False alarms",
                  tags$p(
                    "Where the weather does not pass the trigger, the forecast still",
                    "fires with this probability. A false alarm pays the full cost",
                    "(transfers and administration) and the households receive the",
                    "cash, but the multiplier below does not apply."
                  )
                )
              ),
              min = 0, max = 100, value = 0, step = 5, post = "%"
            ),
            numericInput(
              ns("effect_multiplier"),
              label = tags$span(
                "Effectiveness multiplier m",
                info_popover(
                  title = "Effectiveness multiplier",
                  tags$p(
                    "Scales the welfare effect of a payment made before an event that",
                    "occurs (not its cost). It is an assumption: the model predicts",
                    "annual welfare and cannot show the mechanism (avoided asset",
                    "sales, scarring), so leave it at 1 unless you have evidence.",
                    "Policy profile shows the m at which the forecast design matches the",
                    "welfare effect of the ex-post design, in total and per dollar."
                  )
                )
              ),
              value = 1, min = 0.1, max = 10, step = 0.1
            )
          ),
          conditionalPanel(
            condition = paste0("input['", ns("transfer_timing"), "'] != 'anticipatory'"),
            numericInput(
              ns("timeliness_weeks"),
              label = tags$span(
                "Delivery delay (weeks)",
                info_popover(
                  title = "Delivery delay",
                  tags$p(
                    "Weeks between the shock and the payment. With a loss of",
                    "effectiveness per week below, the welfare effect is scaled by",
                    "1 - weeks x loss per week (never below 0). The cost does not",
                    "change. Both default to 0, which means no delay effect."
                  )
                )
              ),
              value = 0, min = 0, max = 52, step = 1
            ),
            numericInput(
              ns("delay_loss_pct_per_week"),
              label = "Effectiveness lost per week of delay (%)",
              value = 0, min = 0, max = 100, step = 1
            )
          ),
          sliderInput(
            ns("payments_per_activation"),
            label = tags$span(
              tags$i(class = "fa fa-hashtag me-1"),
              "Payments per activation",
              info_popover(
                title = "Payments per activation",
                tags$p(
                  "Each payment is the amount per transfer set above. Annual",
                  "support in an activated year = amount \u{00d7} payments."
                )
              )
            ),
            min = 1, max = 12, value = 1, step = 1
          ),
          numericInput(
            ns("loss_event_pct"),
            label = tags$span(
              tags$i(class = "fa fa-chart-line me-1"),
              "Loss event (% of welfare)",
              info_popover(
                title = "Loss event",
                tags$p(
                  "Scoring only: it changes no payment and no welfare result, so",
                  "changing it does not mark results stale and Policy profile",
                  "re-scores the finished run. A location has a",
                  "loss event in a year when its households' modelled weather",
                  "loss is at least this share of their own typical welfare.",
                  "Paying without a loss event is a false positive; a loss",
                  "event without payment is a false negative."
                )
              )
            ),
            value = 10, min = 1, max = 50, step = 1
          )
        )
      }
    ),
    tags$hr(style = "margin: 8px 0;")
  )
}

.sp_targeting_tags <- function(ns, unit_word) {
  tags$div(
    class = "sp-targeting",
    tags$div(
      class = "sp-targeting-label",
      tags$span(
        class = "sp-inline-label",
        tags$i(class = "fa fa-crosshairs me-1"),
        "Targeting"
      )
    ),
    tags$div(
      class = "sp-targeting-select",
      selectInput(
        inputId = ns("targeting"),
        label = tags$span(class = "visually-hidden", "Targeting"),
        choices = stats::setNames(
          c("universal", "exante_poor", "pmt"),
          c(
            "Universal",
            "Welfare below threshold (ex-ante poor)",
            paste(
              unit_word(plural = FALSE, capitalize = TRUE),
              "characteristics (Proxy)"
            )
          )
        ),
        selected = "universal"
      )
    ),

    # Threshold for ex-ante poor targeting
    conditionalPanel(
      condition = paste0("input['", ns("targeting"), "'] == 'exante_poor'"),
      sliderInput(
        inputId = ns("targeting_threshold_pct"),
        label = tags$span(
          tags$i(class = "fa fa-users me-1"),
          "Poorest (bottom x%)"
        ),
        min = 5, max = 60, value = 20, step = 5, post = "%"
      ) |>
        # 11 intervals -> majors at 5, 10, ..., 60
        with_grid_num(11)
    ),

    # Targeting details flyout (P0-1): proxy rule, errors and how errors
    # are placed. Universal targeting has no rule detail and no errors.
    conditionalPanel(
      condition = paste0("input['", ns("targeting"), "'] != 'universal'"),
      config_flyout_block(
        ns("targeting_toggle"),
        "Targeting details",
        toggle_label = "Targeting details",
        display_label = textOutput(ns("targeting_summary"), inline = TRUE),

        # Proxy variable and cutoff (only for Proxy targeting)
        conditionalPanel(
          condition = paste0("input['", ns("targeting"), "'] == 'pmt'"),
          uiOutput(ns("pmt_variable_ui")),
          uiOutput(ns("pmt_cutoff_ui"))
        ),

        # Inclusion/exclusion errors
        sliderInput(
          inputId = ns("inclusion_error_pct"),
          label = tags$div(
            tags$span(
              tags$i(class = "fa fa-user-plus me-1"),
              "Inclusion error (%)"
            ),
            tags$div(
              class = "text-muted",
              style = "font-size: 0.8em; font-weight: normal;",
              paste0("Non-eligible ", unit_word(plural = TRUE), " included")
            )
          ),
          min = 0, max = 30, value = 10, step = 5, post = "%"
        ),
        sliderInput(
          inputId = ns("exclusion_error_pct"),
          label = tags$div(
            tags$span(
              tags$i(class = "fa fa-user-minus me-1"),
              "Exclusion error (%)"
            ),
            tags$div(
              class = "text-muted",
              style = "font-size: 0.8em; font-weight: normal;",
              paste0("Eligible ", unit_word(plural = TRUE), " excluded")
            )
          ),
          min = 0, max = 30, value = 10, step = 5, post = "%"
        ),
        selectInput(
          inputId = ns("error_concentration"),
          label = tags$span(
            "Where errors fall",
            info_popover(
              title = "Where errors fall",
              tags$p(
                "The error rates above fix how many", unit_word(plural = TRUE),
                "are wrongly included or excluded. This setting chooses which",
                "ones. \"Random\" picks any unit with equal chance.",
                "The other settings make units close to the cutoff likelier to",
                "be misclassified, as in proxy-means tests. Closeness is the",
                "difference in welfare (or proxy) percentile rank, not weighted.",
                "Proxy variables with only two values always use random errors."
              ),
              tags$p(
                "Error rates are shares of the weighted population when the",
                "survey has weights, and of sampled rows otherwise. The",
                "realised rate matches the slider to within one row's weight."
              )
            )
          ),
          choices = c(
            "Random" = "0",
            "Near the cutoff" = "5",
            "Mostly near the cutoff" = "20"
          ),
          selected = "0"
        )
      )
    )
  )
}

.sp_budget_amount_tags <- function(ns, unit_word, amount_currency_label) {
  currency <- amount_currency_label()

  tagList(
    # Amount and budget mode ----
    tags$label(
      class = "control-label",
      tags$i(class = "fa fa-money-bill-transfer me-1"),
      "Amount",
      info_popover(
        title = "Amount and budget mode",
        tags$p(
          tags$b("Per transfer"),
          "sets the amount paid to each recipient", unit_word(plural = FALSE),
          "per payment (or per activation in shock-responsive mode). Whether a",
          "recipient is a household or a person is set in Payment settings.",
          "The annual cost then depends on the number of recipients and",
          "payments per year."
        ),
        tags$p(
          tags$b("Total budget"),
          "sets the total annual amount available. The transfer per recipient is",
          "derived from the configured budget and recipient population."
        )
      )
    ),
    # A shock-responsive program pays a fixed amount per activation, so the
    # total-budget mode is offered for regular programs only (decision 12).
    conditionalPanel(
      condition = paste0("input['", ns("sp_type"), "'] != 'shock'"),
      tags$div(
        class = "sp-budget-mode",
        pill_toggle(
          inputId = ns("budget_mode"),
          label = NULL,
          aria_label = "Amount or budget mode",
          choices = stats::setNames(
            c("transfer_first", "budget_first"),
            c("Per transfer", "Total budget")
          ),
          selected = "transfer_first"
        )
      )
    ),

    # Amount entry ----
    conditionalPanel(
      condition = paste0(
        "input['", ns("budget_mode"), "'] == 'budget_first' && input['",
        ns("sp_type"), "'] != 'shock'"
      ),
      tags$div(
        class = "sp-inline-control",
        tags$label(
          class = "sp-inline-label",
          `for` = ns("budget_fixed"),
          tags$i(class = "fa fa-dollar-sign me-1"),
          paste0("Total annual budget (", currency, ")")
        ),
        numericInput(
          inputId = ns("budget_fixed"),
          label = NULL,
          value = 0, min = 0, step = 100000
        )
      )
    ),
    # Budget rule (shock-responsive programs only, P2-6)
    conditionalPanel(
      condition = paste0("input['", ns("sp_type"), "'] == 'shock'"),
      tags$label(
        class = "control-label",
        tags$i(class = "fa fa-scale-balanced me-1"),
        "Budget rule",
        info_popover(
          title = "Budget rule",
          tags$p(
            tags$b("Fixed amount:"),
            "every paid", unit_word(plural = FALSE),
            "gets the amount below in each activated year."
          ),
          tags$p(
            tags$b("Share of modelled loss:"),
            "a triggered location-month in a year gets a budget equal to",
            "the chosen share of the modelled weather loss of its paid",
            "households. The amount below is not used. Shared equally over the",
            "paid households (or people, per Payment settings)."
          ),
          tags$p(
            tags$b("What counts as loss:"),
            "a household's loss in a year is how far its modelled welfare",
            "falls below its own average over the historical years, in",
            "welfare units, with no random residual. Years above the average",
            "count as zero loss. The loss of households that are targeted",
            "and in the payout scope is summed with survey weights, so",
            "targeting errors and the payout scope carry through. Under the",
            "national gate with all targeted households, each location is",
            "still budgeted from its own loss."
          )
        )
      ),
      pill_toggle(
        inputId = ns("budget_rule"),
        label = NULL,
        aria_label = "Budget rule",
        choices = stats::setNames(
          c("fixed", "loss_share"), c("Fixed amount", "Share of loss")
        ),
        selected = "fixed"
      ),
      conditionalPanel(
        condition = paste0("input['", ns("budget_rule"), "'] == 'loss_share'"),
        tags$div(
          class = "sp-inline-control",
          tags$label(
            class = "sp-inline-label",
            `for` = ns("loss_share_pct"),
            tags$i(class = "fa fa-percent me-1"),
            "Share of modelled loss paid (%)"
          ),
          numericInput(
            inputId = ns("loss_share_pct"),
            label = NULL,
            value = 50, min = 1, max = 100, step = 5
          )
        )
      )
    ),
    conditionalPanel(
      condition = paste0(
        "(input['", ns("budget_mode"), "'] == 'transfer_first' && input['",
        ns("sp_type"), "'] != 'shock') || (input['", ns("sp_type"),
        "'] == 'shock' && input['", ns("budget_rule"), "'] != 'loss_share')"
      ),
      # A regular program can set the amount from the baseline welfare
      # distribution; a shock program always states it.
      conditionalPanel(
        condition = paste0("input['", ns("sp_type"), "'] != 'shock'"),
        pill_toggle(
          inputId = ns("transfer_amount_mode"),
          label = NULL,
          aria_label = "Amount set as",
          choices = c("Fixed amount" = "fixed", "Welfare percentile" = "pctile"),
          selected = "fixed"
        )
      ),
      conditionalPanel(
        condition = paste0(
          "input['", ns("sp_type"), "'] == 'shock' || input['",
          ns("transfer_amount_mode"), "'] != 'pctile'"
        ),
        tags$div(
          class = "sp-inline-control",
          tags$label(
            class = "sp-inline-label",
            `for` = ns("transfer_amount_usd"),
            tags$i(class = "fa fa-dollar-sign me-1"),
            paste0("Amount per transfer (", currency, ")")
          ),
          numericInput(
            inputId = ns("transfer_amount_usd"),
            label = NULL,
            value = 0, min = 0, step = 10
          )
        )
      ),
      conditionalPanel(
        condition = paste0(
          "input['", ns("sp_type"), "'] != 'shock' && input['",
          ns("transfer_amount_mode"), "'] == 'pctile'"
        ),
        tags$div(
          class = "sp-inline-control",
          tags$label(
            class = "sp-inline-label",
            `for` = ns("transfer_pctile"),
            tags$i(class = "fa fa-percent me-1"),
            "Percentile of daily welfare",
            info_popover(
              title = "Amount from a welfare percentile",
              tags$p(
                "Each payment is the chosen percentile of baseline daily welfare",
                "\u00d7 365 \u00f7 transfers per year, in the outcome's currency.",
                "The percentile is read from the Step 2 baseline survey with survey",
                "weights, the same distribution that defines ex-ante poor targeting."
              ),
              tags$p(
                "The amount is paid per household or per person as set under",
                "Amount basis. Per household, a larger household shares it among",
                "more members."
              )
            )
          ),
          numericInput(
            inputId = ns("transfer_pctile"),
            label = NULL,
            value = 10, min = 1, max = 99, step = 1
          )
        ),
        tags$p(class = "text-muted small", textOutput(ns("transfer_amount_resolved")))
      )
    )
  )
}

.sp_timing_tags <- function(ns, amount_currency_label) {
  tagList(config_flyout_block(
    ns("payment_toggle"),
    "Payment settings",
    toggle_label = "Payment settings",
    display_label = textOutput(ns("payment_summary"), inline = TRUE),

    # Number of payments - only for a regular program whose amount is set per
    # payment (a shock program sets payments per activation in its trigger)
    conditionalPanel(
      condition = paste0(
        "input['", ns("budget_mode"), "'] == 'transfer_first' && input['",
        ns("sp_type"), "'] != 'shock'"
      ),
      tags$label(
        class = "control-label",
        tags$i(class = "fa fa-clock me-1"),
        "Frequency and timing",
        info_popover(
          title = "Transfers per year",
          tags$p(
            "The transfer amount above is per payment. Annual support =",
            "payment amount \u00d7 transfers per year, which the simulation",
            "converts to a daily equivalent added to daily welfare.",
            "More transfers per year means a larger annual transfer for the",
            "same per-payment amount."
          )
        )
      ),
      tags$div(
        class = "sp-inline-slider",
        tags$span(
          class = "sp-inline-label",
          tags$i(class = "fa fa-hashtag me-1"),
          "Transfers per year"
        ),
        with_grid_num(
          sliderInput(
            inputId = ns("transfer_n_payments"),
            label = tags$span(class = "visually-hidden", "Transfers per year"),
            min = 2, max = 24, value = 6, step = 1
          ),
          11
        )
      )
    ),

    uiOutput(ns("amount_basis_ui")),

    numericInput(
      inputId = ns("admin_cost_pct"),
      label = tags$span(
        tags$i(class = "fa fa-building-columns me-1"),
        "Administration cost (% of total cost)",
        info_popover(
          title = "Administration cost",
          tags$p(
            "Share of total program spending used for delivery and",
            "administration. Only the rest reaches recipients, so welfare",
            "effects use the net transfer, while the cost shown includes",
            "administration."
          ),
          tags$p(
            "With an amount per payment, total cost = transfers /",
            "(1 - share). With a total budget, the budget is total cost and",
            "recipients receive (1 - share) of it.",
            "The default of 0 means no administration cost."
          )
        )
      ),
      value = 0, min = 0, max = 50, step = 1
    ),

    # Shock-responsive programs only: a budget ceiling on a year's payments
    conditionalPanel(
      condition = paste0("input['", ns("sp_type"), "'] == 'shock'"),
      numericInput(
        inputId = ns("annual_cap"),
        label = tags$span(
          tags$i(class = "fa fa-lock me-1"),
          paste0("Annual cost cap (", amount_currency_label(), ")"),
          info_popover(
            title = "Annual cost cap",
            tags$p(
              "An upper limit on total cost (including administration) in any",
              "one year. When the payments of a year would exceed it, all",
              "payments of that year are scaled down by the same proportion.",
              "Leave blank for no cap."
            )
          )
        ),
        value = NA, min = 0, step = 100000
      )
    )
  ), tags$hr(style = "margin: 8px 0;"))
}
