#' Diagnostics tab content UI.
#' @noRd
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

.diagnostics_content_ui <- function(ns) {
  shiny::tagList(
    shiny::uiOutput(ns("stale_banner_ui")),
    shiny::uiOutput(ns("policy_summary_ui")),
    shiny::h4(
      "Which variables changed?",
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::tags$p(
        class = "diagnostic-note",
        "Before/after summaries use the same baseline units."
      ),
      shiny::div(
        class = "wise-reactable-controls",
        wise_reactable_csv_button(ns("diag_summary_table"), "policy_input_diagnostics")
      ),
      reactable::reactableOutput(ns("diag_summary_table"))
    ),
    shiny::h4(
      "How did the policy change the baseline population?",
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::tags$p(
        class = "diagnostic-note",
        "Charts show constructed before/after inputs, not observed impacts."
      ),
      shiny::uiOutput(ns("hist_plots_ui"))
    ),
    shiny::h4(
      "Who does the policy reach?",
      info_popover(
        title = "Policy reach",
        shiny::p(
          "A unit is reached when it receives a positive social protection",
          "transfer or has a covariate changed by another policy lever. Shares",
          "are of the baseline population, weighted. Reach is not a welfare effect."
        )
      ),
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::uiOutput(ns("reach_cards_ui")),
      wise_chart_output(
        ns("reach_plot"),
        "Share of the baseline population reached by each policy component",
        height = "300px"
      ),
      shiny::uiOutput(ns("reach_note_ui")),
      shiny::tags$details(
        class = "decomposition-data-details",
        shiny::tags$summary("View reach data"),
        shiny::div(
          class = "wise-reactable-controls",
          wise_reactable_csv_button(ns("policy_component_table"), "policy_component_summary")
        ),
        reactable::reactableOutput(ns("policy_component_table"))
      )
    ),
    shiny::uiOutput(ns("sp_sections_ui")),
    shiny::uiOutput(ns("shock_section_ui"))
  )
}

#' 3_08_diagnostics Server Functions
#'
#' Displays before/after summary tables and histograms for all variables
#' manipulated by the policy scenarios (mod_3_01 through mod_3_05). Only
#' variables still present in the Step 1 model are manipulated upstream by
#' \code{apply_policy_to_svy()}, so a variable dropped from Step 1 no longer
#' appears here. Inserts
#' a Diagnostics tab into the parent tabset on the first successful run
#' and selects it.
#'
#' @param id               Module id.
#' @param baseline_svy     Reactive survey-weather df before adjustment.
#' @param policy_svy       Reactive survey-weather df after adjustment.
#' @param diagnostic_summary Reactive immutable summary snapshot published by
#'   the policy runner after a successful run.
#' @param shock_summary Reactive list (`rows`, `cells`, `summary`) published by
#'   the policy runner for a shock-responsive program, or NULL.
#' @param loss_event_pct Reactive live loss-event share (percent). The stored
#'   shock run is re-scored with it, so changing it needs no new run.
#' @param selected_policies Reactive selected policy scenario keys.
#' @param poverty_line Reactive Results poverty line (outcome currency), used by
#'   the cost and targeting table. NULL or NA leaves line-based figures unavailable.
#' @param baseline_hist_sim Reactive Step 2-style baseline simulation result.
#' @param selected_weather Reactive selected weather specification.
#' @param policy_saved_scenarios Reactive named future scenario list.
#' @param sim_run_id       Reactive trigger for invalidation; the tab is
#'   appended on the first run for which this is > 0.
#' @param tabset_id        Character id of the parent tabset to append to.
#' @param tabset_session   Shiny session for the parent tabset. Defaults
#'   to the parent session.
#'
#' @noRd
mod_3_08_diagnostics_server <- function(id,
                                        baseline_svy,
                                        policy_svy,
                                        diagnostic_summary = reactive(NULL),
                                        shock_summary = reactive(NULL),
                                        sim_run_id = reactive(0L),
                                        tabset_id,
                                        tabset_session = NULL,
                                        analysis_unit = reactive("hh"),
                                        selected_policies = reactive(NULL),
                                        policy_scenarios = reactive(list()),
                                        baseline_hist_sim = reactive(NULL),
                                        selected_weather = reactive(NULL),
                                        selected_outcome = reactive(NULL),
                                        variable_list = reactive(NULL),
                                        sp_scenario = reactive(NULL),
                                        loss_event_pct = reactive(NULL),
                                        poverty_line = reactive(NULL),
                                        infra_scenario = reactive(NULL),
                                        digital_scenario = reactive(NULL),
                                        labor_scenario = reactive(NULL),
                                        education_scenario = reactive(NULL),
                                        policy_saved_scenarios = reactive(list()),
                                        stale = reactive(FALSE)) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    session$userData$wise_step3_stale <- stale

    output$stale_banner_ui <- shiny::renderUI({
      if (isTRUE(stale())) {
        .stale_banner(
          "Step 3 policy diagnostics",
          note = NULL
        )
      } else {
        NULL
      }
    })

    if (is.null(tabset_session)) {
      tabset_session <- session$parent %||% session
    }

    diag_tab_added <- reactiveVal(FALSE)

    variable_label <- function(var_name) {
      .policy_diagnostic_label(
        var_name,
        variable_list = tryCatch(variable_list(), error = function(e) NULL),
        selected_outcome = tryCatch(selected_outcome(), error = function(e) NULL)
      )
    }

    # Diagnostics data preparation ----

    # One successful run publishes one complete snapshot. Failed runs leave
    # this reactive value untouched, so renderers and exports keep the prior
    # internally consistent diagnostics instead of rebuilding from live state.
    diag_data <- reactive({
      sim_run_id()
      published <- diagnostic_summary()
      if (!is.null(published)) {
        return(published)
      }

      # Backward-compatible path for direct module callers that predate atomic
      # publication. Production supplies `diagnostic_summary`, so successful
      # runs never rescan the live survey frames here.
      .policy_diagnostics_snapshot(
        svy_baseline = baseline_svy(),
        svy_policy = policy_svy(),
        analysis_unit = analysis_unit(),
        sp = sp_scenario()
      )
    })

    # Transfer summary info box ----

    output$transfer_summary_ui <- reactable::renderReactable({
      d <- diag_data()
      if (is.null(d) || is.list(d) && !is.null(d$status)) {
        return(.wise_diag_reactable(
          data.frame(Note = "No transfer data available.")
        ))
      }
      # UI-32: displayed figures are rounded to one decimal, matching the
      # Step 3 sidebar's reach preview (fmt_num()) so the same quantity never
      # appears at two precisions. Raw values live in the data; rounding is
      # applied by colFormat.
      df <- .policy_transfer_summary_rows(d)
      .wise_diag_reactable(df, formats = list(
        Value = list(
          digits = 1, prefix = .sp_currency_prefix(d$transfer_currency),
          separators = TRUE
        )
      ))
    })

    outputOptions(output, "transfer_summary_ui", suspendWhenHidden = FALSE)

    # Cost and targeting effectiveness (P0-5) ----

    sp_effectiveness_res <- reactive({
      step3_sp_effectiveness(
        diag_data(), sp_scenario(), baseline_svy(), policy_svy(), shock_summary(),
        # The Results line is NULL when a non-poverty metric is selected, so
        # fall back to the line Step 1 stored with the baseline run.
        poverty_line = tryCatch(
          poverty_line() %||% baseline_hist_sim()$pov_line,
          error = function(e) NULL
        )
      )
    })

    sp_effectiveness_display <- reactive({
      res <- sp_effectiveness_res()
      if (is.null(res)) {
        return(NULL)
      }
      .sp_effectiveness_display(res, diag_data()$transfer_currency %||% "PPP")
    })

    output$sp_effectiveness_table <- reactable::renderReactable({
      df <- sp_effectiveness_display()
      if (is.null(df) || nrow(df) == 0L) {
        return(.wise_diag_reactable(data.frame(
          Note = "No social protection transfer to evaluate."
        )))
      }
      .wise_diag_reactable(df)
    })

    outputOptions(output, "sp_effectiveness_table", suspendWhenHidden = FALSE)

    wise_export_table(
      key = "policy_sp_effectiveness",
      label = "Social protection cost and targeting effectiveness",
      step = 3L,
      fun = function() {
        df <- sp_effectiveness_display()
        if (is.null(df) || nrow(df) == 0L) NULL else df
      },
      stale = stale,
      description = paste(
        "Cost per person, realised targeting errors, coverage of the poor,",
        "leakage and adequacy for the social protection transfer."
      )
    )

    # Shock-responsive program outputs (P1-7) ----
    #
    # Activation, annual cost distribution, basis risk and leakage by scenario,
    # from the run's published summary (the same rows the correction used).

    shock_currency <- reactive({
      sp <- tryCatch(sp_scenario(), error = function(e) NULL)
      sp$currency %||% "PPP"
    })

    # The published run, scored with the live loss-event share: it scores the
    # trigger only, so changing it re-scores the stored cells without a new run.
    shock_scored <- reactive({
      s <- shock_summary()
      if (is.null(s)) NULL else sp_shock_rescore(s, loss_event_pct())
    })

    shock_display <- reactive({
      s <- shock_scored()
      if (is.null(s)) NULL else .sp_shock_display(s$summary, shock_currency())
    })

    shock_cost_chart <- function() {
      s <- shock_scored()
      echart_shock_cost_distribution(
        s$summary,
        y_label = paste0(
          "Annual cost (", if (identical(.sp_currency(shock_currency()), "LCU")) "2021 LCU" else "$", ")"
        )
      )
    }

    output$shock_section_ui <- shiny::renderUI({
      if (is.null(shock_summary())) {
        return(NULL)
      }
      shiny::tagList(
        shiny::h4(
          "Shock-responsive program",
          info_popover(
            title = "Shock-responsive program",
            shiny::p(
              "Each bar pools the climate members and simulated years of the",
              "scenario. A year activates when any household is paid. A loss",
              "event is a survey location whose households lose at least the",
              "set share of their own typical welfare. Paying where there is no",
              "loss event is a false positive; a loss event without payment is a",
              "false negative. Costs include administration."
            ),
            shiny::p(
              "The share is set in Trigger settings. It only scores the trigger,",
              "so changing it re-scores this run without running Step 3 again."
            )
          ),
          class = "diagnostic-section-heading"
        ),
        shiny::div(
          class = "results-section-card diagnostic-section-card",
          shiny::tags$p(
            class = "diagnostic-note",
            style = "margin-top: 0;",
            shiny::textOutput(ns("shock_scoring_note"), inline = TRUE)
          ),
          shiny::div(
            style = "display: flex; flex-wrap: wrap; gap: 16px;",
            shiny::div(
              style = "flex: 1 1 320px; min-width: 0;",
              shiny::h6("How often are payments made?", style = .diag_subheading_style),
              wise_chart_output(
                ns("shock_activation_plot"),
                "Share of simulated years with payments, by scenario",
                height = "300px"
              )
            ),
            shiny::div(
              style = "flex: 1 1 320px; min-width: 0;",
              shiny::h6("Does the trigger pay the right places?", style = .diag_subheading_style),
              wise_chart_output(
                ns("shock_basis_plot"),
                "False positive and false negative rates of the trigger, by scenario",
                height = "300px"
              )
            )
          ),
          shiny::h6("What does it cost in a year?", style = .diag_subheading_style),
          wise_chart_output(
            ns("shock_cost_plot"),
            "Mean, median and 95th percentile annual cost, by scenario",
            height = "360px"
          ),
          shiny::tags$details(
            class = "decomposition-data-details",
            shiny::tags$summary("View all shock-responsive measures"),
            shiny::div(
              class = "wise-reactable-controls",
              wise_reactable_csv_button(ns("shock_summary_table"), "policy_shock_summary")
            ),
            reactable::reactableOutput(ns("shock_summary_table"))
          )
        )
      )
    })
    outputOptions(output, "shock_section_ui", suspendWhenHidden = FALSE)

    output$shock_scoring_note <- shiny::renderText({
      pct <- suppressWarnings(as.numeric(loss_event_pct()))[1L]
      if (is.null(shock_summary()) || !is.finite(pct) || pct <= 0) {
        return("")
      }
      paste0(
        "Loss event: a survey location whose households lose at least ", pct,
        "% of their typical welfare."
      )
    })
    outputOptions(output, "shock_scoring_note", suspendWhenHidden = FALSE)

    output$shock_summary_table <- reactable::renderReactable({
      .wise_diag_reactable(shock_display())
    })
    output$shock_cost_plot <- echarts4r::renderEcharts4r({
      req(!is.null(shock_summary()))
      shock_cost_chart()
    })
    output$shock_activation_plot <- echarts4r::renderEcharts4r({
      req(!is.null(shock_summary()))
      echart_shock_activation(shock_scored()$summary)
    })
    output$shock_basis_plot <- echarts4r::renderEcharts4r({
      req(!is.null(shock_summary()))
      echart_shock_basis_risk(shock_scored()$summary)
    })

    wise_export_table(
      key = "policy_shock_summary",
      label = "Shock-responsive program summary",
      step = 3L,
      fun = function() shock_scored()$summary,
      stale = stale,
      description = paste(
        "Activation frequency, annual cost distribution, basis risk and leakage",
        "of the shock-responsive transfer, by scenario."
      )
    )
    wise_export_table(
      key = "policy_shock_annual",
      label = "Shock-responsive program by member and year",
      step = 3L,
      fun = function() shock_scored()$rows,
      stale = stale,
      description = paste(
        "Per climate member and simulation year: activation, exposed population",
        "share, transfer and administration cost, and the population weights",
        "behind basis risk and leakage."
      )
    )
    wise_export_figure(
      key = "policy_shock_cost",
      label = "Shock-responsive annual cost",
      step = 3L,
      fun = function() if (is.null(shock_summary())) NULL else shock_cost_chart(),
      description = "Mean, median and 95th percentile annual cost by scenario.",
      width = 9, height = 5,
      stale = stale
    )
    wise_export_figure(
      key = "policy_shock_activation",
      label = "Shock-responsive payment frequency",
      step = 3L,
      fun = function() {
        if (is.null(shock_summary())) NULL else echart_shock_activation(shock_scored()$summary)
      },
      description = "Share of simulated years with payments, by scenario.",
      width = 8, height = 5,
      stale = stale
    )
    wise_export_figure(
      key = "policy_shock_basis_risk",
      label = "Shock-responsive trigger basis risk",
      step = 3L,
      fun = function() {
        if (is.null(shock_summary())) NULL else echart_shock_basis_risk(shock_scored()$summary)
      },
      description = "False positive and false negative rates of the trigger, by scenario.",
      width = 8, height = 5,
      stale = stale
    )

    # Reach and social protection sections ----

    valid_diag <- function() {
      d <- diag_data()
      if (is.null(d) || (is.list(d) && !is.null(d$status) && is.null(d$component_matrix))) NULL else d
    }

    output$reach_cards_ui <- shiny::renderUI({
      d <- valid_diag()
      headline_cards_ui(c(
        .policy_reach_cards(d$reach, d$analysis_unit),
        .policy_decile_move_cards(d$decile_movement)
      ))
    })
    outputOptions(output, "reach_cards_ui", suspendWhenHidden = FALSE)

    reach_chart <- function() {
      d <- valid_diag()
      if (is.null(d)) NULL else echart_policy_reach(d$component_matrix)
    }
    output$reach_plot <- echarts4r::renderEcharts4r({
      ch <- reach_chart()
      req(!is.null(ch))
      ch
    })

    output$reach_note_ui <- shiny::renderUI({
      shock <- identical(tryCatch(sp_scenario()$sp_type, error = function(e) NULL), "shock")
      shiny::tags$p(
        class = "diagnostic-note",
        "Charts show who is touched by the policy, not observed impacts.",
        "Population shares use the survey weights. Access and employment levers move",
        "the weighted share set by the slider; the sector lever draws workers by count.",
        if (shock) {
          paste(
            "For a shock-responsive program, social protection reach is households",
            "paid in at least one historical weather year."
          )
        }
      )
    })

    wise_export_figure(
      key = "policy_reach",
      label = "Population reached by each policy component",
      step = 3L,
      fun = reach_chart,
      description = "Share of the baseline population touched by each policy component.",
      width = 9, height = 5,
      stale = stale
    )

    # The social protection sections exist only when a program is in the run.
    has_sp <- reactive({
      if (!is.null(shock_summary())) {
        return(TRUE)
      }
      tm <- valid_diag()$treatment_matrix
      is.data.frame(tm) && nrow(tm) > 0L && any(tm$treated_policy & tm$n > 0)
    })

    output$sp_sections_ui <- shiny::renderUI({
      if (!isTRUE(has_sp())) {
        return(NULL)
      }
      shock <- identical(tryCatch(sp_scenario()$sp_type, error = function(e) NULL), "shock")
      shiny::tagList(
        shiny::h4(
          "Social protection: who is targeted, and how accurately?",
          info_popover(
            title = "Targeting",
            shiny::p(
              "The bar compares eligibility under the selected rule with treatment",
              "after targeting errors. Coverage, leakage and adequacy use the",
              "baseline welfare and the poverty line chosen in Results, for this",
              "run's single targeting draw. They say nothing about modelled",
              "welfare effects."
            ),
            if (shock) {
              shiny::p(
                "For a shock-responsive program the bars describe a year in which",
                "every eligible household is paid. Trigger scope, geography and",
                "forecast layers are not applied here; see the shock-responsive",
                "section for realised payments."
              )
            }
          ),
          class = "diagnostic-section-heading"
        ),
        shiny::div(
          class = "results-section-card diagnostic-section-card",
          shiny::uiOutput(ns("treatment_explanation_ui")),
          shiny::h6("Eligibility versus treatment", style = .diag_subheading_style),
          wise_chart_output(
            ns("sp_treatment_plot"),
            "Share of the population by eligibility and treatment status",
            height = "170px"
          ),
          shiny::h6(
            if (shock) "Who benefits, in a year with payments" else "Who benefits?",
            style = .diag_subheading_style
          ),
          wise_chart_output(
            ns("sp_metrics_plot"),
            "Coverage of the poor, leakage to the non-poor and adequacy for poor recipients",
            height = "260px"
          ),
          shiny::tags$details(
            class = "decomposition-data-details",
            shiny::tags$summary("View targeting data"),
            shiny::div(
              class = "wise-reactable-controls",
              wise_reactable_csv_button(ns("treatment_table"), "policy_treatment_assignment")
            ),
            reactable::reactableOutput(ns("treatment_table")),
            shiny::div(
              class = "wise-reactable-controls",
              wise_reactable_csv_button(ns("sp_effectiveness_table"), "policy_sp_effectiveness")
            ),
            reactable::reactableOutput(ns("sp_effectiveness_table"))
          )
        ),
        shiny::h4(
          "Social protection: what does it cost?",
          info_popover(
            title = "Program cost",
            shiny::p(
              "Costs are realised values in the policy-adjusted survey, annual,",
              "and include administration when a share is set in Payment settings."
            ),
            if (shock) {
              shiny::p(
                "For a shock-responsive program the cost is the mean over the",
                "historical years. The distribution over simulated years is in",
                "the shock-responsive section and the Cost-effectiveness tab."
              )
            }
          ),
          class = "diagnostic-section-heading"
        ),
        shiny::div(
          class = "results-section-card diagnostic-section-card",
          shiny::uiOutput(ns("cost_cards_ui")),
          shiny::tags$details(
            class = "decomposition-data-details",
            shiny::tags$summary("View cost data"),
            shiny::div(
              class = "wise-reactable-controls",
              wise_reactable_csv_button(ns("transfer_summary_ui"), "policy_transfer_summary")
            ),
            reactable::reactableOutput(ns("transfer_summary_ui"))
          )
        )
      )
    })
    outputOptions(output, "sp_sections_ui", suspendWhenHidden = FALSE)

    output$cost_cards_ui <- shiny::renderUI({
      shock <- identical(tryCatch(sp_scenario()$sp_type, error = function(e) NULL), "shock")
      m <- tryCatch(sp_effectiveness_res()$metrics, error = function(e) NULL)
      per_person <- if (is.data.frame(m) && nrow(m)) m[1L, , drop = FALSE] else NULL
      headline_cards_ui(.sp_cost_cards(valid_diag(), shock, per_person))
    })

    treatment_chart <- function() {
      d <- valid_diag()
      if (is.null(d)) {
        NULL
      } else {
        shock <- identical(tryCatch(sp_scenario()$sp_type, error = function(e) NULL), "shock")
        echart_sp_treatment(d$treatment_matrix, shock = shock)
      }
    }
    metrics_chart <- function() {
      m <- tryCatch(sp_effectiveness_res()$metrics, error = function(e) NULL)
      echart_sp_targeting_metrics(m)
    }
    output$sp_treatment_plot <- echarts4r::renderEcharts4r({
      ch <- treatment_chart()
      req(!is.null(ch))
      ch
    })
    output$sp_metrics_plot <- echarts4r::renderEcharts4r(metrics_chart())

    wise_export_figure(
      key = "policy_sp_treatment",
      label = "Social protection eligibility versus treatment",
      step = 3L,
      fun = function() if (isTRUE(has_sp())) treatment_chart() else NULL,
      description = "Share of the population by eligibility and treatment status.",
      width = 9, height = 3,
      stale = stale
    )
    wise_export_figure(
      key = "policy_sp_targeting_metrics",
      label = "Social protection coverage, leakage and adequacy",
      step = 3L,
      fun = function() if (isTRUE(has_sp())) metrics_chart() else NULL,
      description = "Coverage of the poor, leakage to the non-poor and adequacy for poor recipients.",
      width = 9, height = 4,
      stale = stale
    )

    # Summary statistics table ----

    output$diag_summary_table <- reactable::renderReactable({
      d <- diag_data()
      if (is.null(d)) {
        return(.wise_diag_reactable(
          data.frame(Note = paste(
            "Select policy options and run simulation to see ",
            "diagnostics."
          ))
        ))
      }
      if (is.list(d) && !is.null(d$status)) {
        msg <- if (identical(d$status, "no_change")) {
          "No variables were manipulated by the selected policy."
        } else {
          "Manipulated variables are non-numeric or absent."
        }
        return(.wise_diag_reactable(data.frame(Note = msg)))
      }

      vars <- d$manipulated_vars
      if (length(vars) == 0) {
        return(.wise_diag_reactable(
          data.frame(Note = "No numeric variables to summarize.")
        ))
      }

      df <- step3_input_summary_frame(d)
      if (is.null(df)) {
        return(.wise_diag_reactable(
          data.frame(Note = "No numeric variables to summarize.")
        ))
      }
      # Raw values in the data; display rounding lives in colFormat.
      .wise_diag_reactable(.policy_input_table_raw(df))
    })

    outputOptions(output, "diag_summary_table", suspendWhenHidden = FALSE)

    # UI-48: register Step 3's diagnostics for the export bundle.
    wise_export_table(
      key = "policy_transfer_summary",
      label = "Social protection transfer summary",
      step = 3L,
      fun = function() {
        d <- diag_data()
        if (is.null(d) || !is.null(d$status)) {
          return(NULL)
        }
        rows <- .policy_transfer_summary_rows(d)
        rows$Value <- fmt_num(
          rows$Value,
          prefix = .sp_currency_prefix(d$transfer_currency)
        )
        rows
      },
      stale = stale,
      description = paste(
        "Annual cost of social protection across represented recipients",
        "and annual transfer per recipient household or unit."
      )
    )

    wise_export_table(
      key = "policy_input_diagnostics",
      label = "Policy input diagnostics",
      step = 3L,
      fun = function() {
        df <- step3_input_summary_frame(diag_data())
        if (is.null(df)) NULL else .format_policy_input_table(df)
      },
      stale = stale,
      description = paste(
        "Before/after summary of every covariate the policy scenario changed,",
        "so the levers that actually moved can be checked."
      )
    )

    # Histogram plots container ----

    output$hist_plots_ui <- shiny::renderUI({
      d <- diag_data()
      if (is.null(d) || is.list(d) && !is.null(d$status)) {
        return(shiny::div(
          "No variables to display."
        ))
      }

      vars <- d$manipulated_vars
      if (length(vars) == 0) {
        return(shiny::div(
          "No variables to display."
        ))
      }

      tags <- lapply(vars, function(var) {
        label <- variable_label(var)
        shiny::div(
          style = "margin-bottom: 30px;",
          shiny::h6(
            label,
            style = "margin-bottom: 8px; font-weight: 600;"
          ),
          wise_chart_output(
            ns(paste0("hist_", var)),
            paste("Distribution of", label, "before and after the policy adjustment"),
            height = "300px"
          )
        )
      })

      do.call(shiny::tagList, tags)
    })

    # Per-variable histogram outputs ----

    observeEvent(diag_data(),
      {
        d <- diag_data()
        if (is.null(d) || is.list(d) && !is.null(d$status)) {
          return()
        }

        vars <- d$manipulated_vars
        wise_export_retain(
          "policy_before_after_",
          paste0("policy_before_after_", vars)
        )
        if (length(vars) == 0) {
          return()
        }

        for (var in vars) {
          local({
            var_name <- var
            display_label <- variable_label(var_name)
            baseline_vals <- d$baseline_values[[var_name]]
            policy_vals <- d$policy_values[[var_name]]
            # Zero-arg echarts closure shared by the on-screen render and the
            # export bundle (guidelines section 7 pattern).
            hist_chart <- function() {
              echart_before_after_hist(
                baseline_vals, policy_vals, display_label,
                height = "300px"
              )
            }

            output[[paste0("hist_", var_name)]] <- echarts4r::renderEcharts4r({
              ch <- hist_chart()
              req(!is.null(ch))
              ch
            })
            wise_export_figure(
              key = paste0("policy_before_after_", var_name),
              label = paste("Policy-adjusted before/after", display_label),
              step = 3L,
              fun = hist_chart,
              description = paste(
                "Baseline and policy-adjusted distributions for the manipulated",
                "variable", display_label, "."
              ),
              width = 9, height = 5,
              stale = stale
            )
          })
        }
      },
      ignoreInit = TRUE
    )

    # Append the policy profile tab (internal value "diag_tab") on first successful run ----

    observeEvent(sim_run_id(),
      {
        req(sim_run_id() > 0)

        if (!diag_tab_added()) {
          shiny::appendTab(
            inputId = tabset_id,
            shiny::tabPanel(
              title = "Policy profile",
              value = "diag_tab",
              shiny::div(id = ns("diagnostics_section"))
            ),
            select = FALSE,
            session = tabset_session
          )
          shiny::insertUI(
            selector = paste0("#", ns("diagnostics_section")),
            where = "afterBegin",
            ui = .diagnostics_content_ui(ns),
            session = session
          )
          diag_tab_added(TRUE)
        }
      },
      ignoreInit = TRUE
    )

    output$policy_summary_ui <- shiny::renderUI({
      policy_summary_card(
        selected_policies = selected_policies(),
        sp_scenario = sp_scenario(),
        infra_scenario = infra_scenario(),
        digital_scenario = digital_scenario(),
        labor_scenario = labor_scenario(),
        education_scenario = education_scenario()
      )
    })

    output$treatment_table <- reactable::renderReactable({
      d <- diag_data()
      req(d)
      .wise_diag_reactable(
        .policy_treatment_table_raw(d$treatment_matrix, d$analysis_unit),
        formats = list(
          `Sample units` = list(digits = 0, separators = TRUE),
          `Population represented` = list(digits = 0, separators = TRUE),
          `Population share` = list(digits = 1, suffix = "%"),
          `Households represented` = list(digits = 0, separators = TRUE)
        )
      )
    })
    output$treatment_explanation_ui <- shiny::renderUI({
      shiny::tags$p(
        class = "diagnostic-note",
        .policy_treatment_explanation(sp_scenario())
      )
    })
    output$policy_component_table <- reactable::renderReactable({
      d <- diag_data()
      req(d)
      .wise_diag_reactable(
        .policy_component_table_raw(d$component_matrix, d$analysis_unit),
        formats = list(
          `Sample households affected / covered` = list(digits = 0, separators = TRUE),
          `Sample observations affected / covered` = list(digits = 0, separators = TRUE),
          `Population represented` = list(digits = 0, separators = TRUE),
          `Population share` = list(digits = 1, suffix = "%"),
          `Households represented` = list(digits = 0, separators = TRUE),
          `Realized cost` = list(
            digits = 0, prefix = .sp_currency_prefix(d$transfer_currency),
            separators = TRUE
          )
        )
      )
    })
    wise_export_table(
      key = "policy_treatment_assignment",
      label = "Eligibility versus realized treatment assignment",
      step = 3L,
      fun = function() {
        d <- diag_data()
        if (is.null(d) || !is.data.frame(d$treatment_matrix)) {
          return(NULL)
        }
        .format_policy_treatment_table(d$treatment_matrix, d$analysis_unit)
      },
      stale = stale,
      description = paste(
        "Weighted eligibility versus realized positive-transfer treatment.",
        "Eligibility is measured before inclusion and exclusion errors;",
        "realized treatment includes the selected targeting-error draw."
      )
    )
    wise_export_table(
      key = "policy_component_summary",
      label = "Policy component coverage summary",
      step = 3L,
      fun = function() {
        d <- diag_data()
        if (is.null(d) || !is.data.frame(d$component_matrix)) {
          return(NULL)
        }
        .format_policy_component_table(
          d$component_matrix, d$analysis_unit, d$transfer_currency
        )
      },
      stale = stale,
      description = paste0(
        "Population affected or covered by social protection and other modeled policy components, ",
        "including overlap."
      )
    )
    invisible(NULL)
  })
}
