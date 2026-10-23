#' 3_10_cost_effectiveness UI Function
#'
#' @description The Step 3 cost-effectiveness tab (P2-2): what the cash
#'   transfer costs and what the Results effect on the selected metric buys, in
#'   an average year and a 1-in-20 year, for regular and shock-responsive
#'   programs.
#'
#' @param id Module id.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_3_10_cost_effectiveness_ui <- function(id) {
  ns <- NS(id)
  tagList(
    shiny::uiOutput(ns("stale_banner_ui")),
    shiny::h4(
      "What does the cash transfer cost, and what does it buy?",
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::uiOutput(ns("context_ui")),
      shiny::uiOutput(ns("ce_body_ui")),
      shiny::tags$details(
        class = "decomposition-data-details",
        shiny::tags$summary("What is and is not counted"),
        shiny::uiOutput(ns("scope_ui")),
        shiny::uiOutput(ns("ce_note_ui"))
      )
    ),
    shiny::uiOutput(ns("climate_ui")),
    shiny::uiOutput(ns("reach_ui"))
  )
}

#' 3_10_cost_effectiveness Server Functions
#'
#' Joins the program's annual cost to the Results effect (`sp_cost_effectiveness()`).
#' It follows the Results metric and poverty line (plan rule 15) and prints
#' them. Cash transfers only (decision 5).
#'
#' @param id Module id.
#' @param sp_scenario,infra_scenario,digital_scenario,labor_scenario,education_scenario
#'   Reactive scenario lists of the finished run.
#' @param baseline_svy,policy_svy Reactive survey frames of the run.
#' @param shock_summary Reactive list (`rows`, `summary`, ...) of a shock run.
#' @param metric_context Reactive Results metric metadata.
#' @param effect_summary Reactive expected paired effect per scenario.
#' @param annual_effects Reactive paired effect per scenario, member and year.
#' @param metric_decomposition Reactive metric decomposition (tails, supports).
#' @param poverty_line Reactive Results poverty line (outcome currency per day).
#' @param hist_label Reactive label of the historical scenario.
#' @param analysis_unit Reactive analysis unit.
#' @param stale Reactive; TRUE when the run is out of date.
#'
#' @noRd
mod_3_10_cost_effectiveness_server <- function(id,
                                               sp_scenario = reactive(NULL),
                                               infra_scenario = reactive(NULL),
                                               digital_scenario = reactive(NULL),
                                               labor_scenario = reactive(NULL),
                                               education_scenario = reactive(NULL),
                                               baseline_svy = reactive(NULL),
                                               policy_svy = reactive(NULL),
                                               shock_summary = reactive(NULL),
                                               metric_context = reactive(NULL),
                                               effect_summary = reactive(NULL),
                                               annual_effects = reactive(NULL),
                                               metric_decomposition = reactive(NULL),
                                               poverty_line = reactive(NULL),
                                               reach_poverty_line = reactive(NULL),
                                               hist_label = reactive("Historical"),
                                               analysis_unit = reactive("hh"),
                                               stale = reactive(FALSE)) {
  shiny::moduleServer(id, function(input, output, session) {
    ns <- session$ns
    session$userData$wise_step3_stale <- stale

    output$stale_banner_ui <- shiny::renderUI({
      if (isTRUE(stale())) .stale_banner("Step 3 cost-effectiveness", note = NULL)
    })

    output$scope_ui <- shiny::renderUI({
      shiny::tags$p(
        class = "diagnostic-note",
        shiny::tags$b("Scope. "),
        "Cash transfers only. Counted: the modelled transfer, the administration",
        "share set in Payment settings, and the modelled welfare and poverty",
        "effect from Results. Not counted: delivery of other levers, targeting",
        "surveys, financing, and benefits the model does not represent. The",
        "infrastructure, digital, labour and education levers have no unit costs,",
        "so they get no cost-effectiveness figure."
      )
    })

    # Everything the tab shows, computed once per state of the run.
    ce <- reactive({
      if (isTRUE(stale())) {
        return(list(status = "stale"))
      }
      step3_cost_effectiveness(
        sp = sp_scenario(), infra = infra_scenario(), digital = digital_scenario(),
        labor = labor_scenario(), education = education_scenario(),
        metric_context = metric_context(), effect_summary = effect_summary(),
        decomp = metric_decomposition(), shock_summary = shock_summary(),
        annual_effects = annual_effects(), policy_svy = policy_svy(),
        baseline_svy = baseline_svy(), hist_label = hist_label(),
        analysis_unit = analysis_unit(), poverty_line = poverty_line()
      )
    })

    output$context_ui <- shiny::renderUI({
      x <- ce()
      if (!identical(x$status, "ok")) {
        return(NULL)
      }
      prefix <- .sp_currency_prefix(x$currency)
      shiny::tags$p(
        class = "text-muted small",
        paste(
          c(
            paste0("Program: ", if (x$shock) "shock-responsive" else "regular"),
            paste0("Metric: ", x$label),
            if (x$uses_line) {
              if (is.finite(suppressWarnings(as.numeric(x$line)[1L]))) {
                paste0("Poverty line: ", prefix, fmt_num(x$line, 2), " per day (Results)")
              } else {
                "Poverty line: not available"
              }
            },
            paste0("Administration: ", fmt_num(100 * x$admin, 1), "% of cost")
          ),
          collapse = " \u00b7 "
        )
      )
    })

    empty_message <- function(x) {
      switch(x$status,
        stale = "Results are out of date. Re-run Step 3.",
        no_sp = paste(
          "No cash transfer to evaluate. Configure a transfer in Social protection",
          "and run Step 3."
        ),
        no_effect = x$reason %||% paste(
          "The policy effect is not available yet, so there is nothing to divide",
          "the cost by."
        ),
        NULL
      )
    }

    ce_display <- reactive({
      x <- ce()
      if (!identical(x$status, "ok")) {
        return(NULL)
      }
      .sp_ce_display(x$res, x$currency)
    })

    output$ce_body_ui <- shiny::renderUI({
      x <- ce()
      if (!identical(x$status, "ok")) {
        return(shiny::div(
          class = "empty-state",
          shiny::tags$p(empty_message(x))
        ))
      }
      n_rows <- nrow(.sp_ce_plot_rows(x$res, x$currency))
      per_person <- identical(x$method, "headcount_ratio")
      # Only the poverty rate and gap have a per-dollar reading; say so once.
      has_ratio <- x$method %in% c("headcount_ratio", "gap")
      shiny::tagList(
        shiny::uiOutput(ns("ce_cards_ui")),
        if (has_ratio) {
          shiny::tagList(
            shiny::h6(
              if (per_person) "What does it buy? Cost per person-year lifted out of poverty (lower is better)" else
                "What does it buy? Poverty gap closed per $1 of cost (higher is better)",
              style = .diag_subheading_style
            ),
            wise_chart_output(
              ns("ce_ratio_plot"),
              "Cost-effectiveness ratio by scenario and weather year, with 95% intervals for the average year",
              height = paste0(max(160, 100 + 40 * n_rows), "px")
            ),
            shiny::uiOutput(ns("ce_ratio_note_ui"))
          )
        } else {
          shiny::tags$p(
            class = "diagnostic-note",
            paste0(
              "The Results metric (", x$label, ") has no per-dollar reading: the ",
              "transfer is added to welfare, so a gain per $1 would only restate ",
              "the cost. Choose Poverty rate or Poverty gap in Results to see ",
              "what the transfer buys."
            )
          )
        },
        shiny::h6("What does it cost?", style = .diag_subheading_style),
        wise_chart_output(
          ns("ce_cost_plot"), "Annual cost of the cash transfer by scenario",
          height = "320px"
        ),
        if (has_ratio) {
          shiny::tags$details(
            class = "decomposition-data-details",
            shiny::tags$summary("View cost-effectiveness data"),
            shiny::div(
              class = "wise-reactable-controls",
              wise_reactable_csv_button(ns("ce_table"), "policy_cost_effectiveness")
            ),
            reactable::reactableOutput(ns("ce_table"))
          )
        }
      )
    })
    outputOptions(output, "ce_body_ui", suspendWhenHidden = FALSE)

    # The Results focus scenario drives the cards; without one, the first.
    focus_scenario <- reactive({
      f <- tryCatch(metric_decomposition()$metadata$focus_scenario, error = function(e) NULL)
      .sp_ce_focus(ce()$res, f)
    })

    output$ce_cards_ui <- shiny::renderUI({
      x <- ce()
      req(identical(x$status, "ok"))
      sc <- focus_scenario()
      shiny::tagList(
        if (length(unique(x$res$scenario)) > 1L) {
          shiny::tags$p(class = "diagnostic-note", style = "margin: 0 0 6px;", paste("Scenario:", sc))
        },
        headline_cards_ui(.sp_ce_cards(x$res, x$currency, sc))
      )
    })

    output$ce_ratio_note_ui <- shiny::renderUI({
      x <- ce()
      req(identical(x$status, "ok"))
      skipped <- .sp_ce_unshown(x$res)
      shiny::tags$p(
        class = "diagnostic-note",
        "Dots are the ratio; lines are the 95% interval from the weather-coefficient",
        "uncertainty (average year only).",
        if (identical(x$method, "headcount_ratio")) {
          "A hollow dot means the interval reaches zero effect, so the cost per person is not bounded."
        },
        if (length(skipped)) paste("Not shown:", paste(skipped, collapse = "; "))
      )
    })

    ce_ratio_chart <- function() {
      x <- ce()
      if (!identical(x$status, "ok")) NULL else echart_sp_ce_ratio(x$res, x$currency)
    }
    ce_cost_chart <- function() {
      x <- ce()
      if (!identical(x$status, "ok")) NULL else echart_sp_ce_cost(x$res, x$currency, x$admin, x$leakage)
    }
    output$ce_ratio_plot <- echarts4r::renderEcharts4r({
      ch <- ce_ratio_chart()
      req(!is.null(ch))
      ch
    })
    output$ce_cost_plot <- echarts4r::renderEcharts4r({
      ch <- ce_cost_chart()
      req(!is.null(ch))
      ch
    })

    output$ce_table <- reactable::renderReactable({
      df <- ce_display()
      req(!is.null(df))
      .wise_diag_reactable(df)
    })

    output$ce_note_ui <- shiny::renderUI({
      x <- ce()
      if (!identical(x$status, "ok")) {
        return(NULL)
      }
      shiny::tags$ul(
        class = "diagnostic-note",
        if (identical(x$method, "headcount_ratio")) {
          shiny::tags$li(
            "Net people lifted is the net change in the number of poor. Households",
            "that fall into poverty offset those that leave it; gross movements",
            "are not modelled."
          )
        },
        shiny::tags$li(
          "Average year: the equal-model mean over the simulated years. Adverse",
          "1-in-20 year: the baseline-anchored adverse weather year used in Results",
          if (x$shock) {
            ", with the program's cost in the same member-years."
          } else {
            "; a regular program costs the same every year."
          }
        ),
        shiny::tags$li(
          "The interval reflects uncertainty in the estimated weather",
          "coefficients only. \"Not bounded\" means the interval reaches zero.",
          "\"Not applicable\" means no meaningful ratio exists (no effect, a wrong",
          "sign, or no spending)."
        ),
        shiny::tags$li(
          "Targeting errors come from one seeded draw. The model is static and",
          "annual: it has no poverty traps, price effects or multipliers."
        )
      )
    })

    # Shock programs: the bill under each climate scenario against history ----

    climate <- reactive({
      x <- ce()
      s <- shock_summary()
      if (!identical(x$status, "ok") || !isTRUE(x$shock) || is.null(s)) {
        return(NULL)
      }
      sp_shock_climate_cost(s$summary, reference = hist_label())
    })

    output$climate_ui <- shiny::renderUI({
      d <- climate()
      if (is.null(d)) {
        return(NULL)
      }
      shiny::tagList(
        shiny::h4("Climate-adjusted cost", class = "diagnostic-section-heading"),
        shiny::div(
          class = "results-section-card diagnostic-section-card",
          shiny::tags$p(
            class = "diagnostic-note",
            style = "margin-top: 0;",
            "The trigger is fixed on the historical record, so under climate",
            "change it fires more or less often and the bill moves with it. Costs",
            "include administration. The 95th percentile is taken over all",
            "simulated years; it is not the cost in the adverse 1-in-20 weather",
            "year used above."
          ),
          wise_chart_output(
            ns("climate_plot"),
            "Mean and 95th percentile annual cost of the shock-responsive program by scenario",
            height = "380px"
          ),
          shiny::tags$details(
            class = "decomposition-data-details",
            shiny::tags$summary("View climate-adjusted cost data"),
            shiny::div(
              class = "wise-reactable-controls",
              wise_reactable_csv_button(ns("climate_table"), "policy_shock_climate_cost")
            ),
            reactable::reactableOutput(ns("climate_table"))
          )
        )
      )
    })
    outputOptions(output, "climate_ui", suspendWhenHidden = FALSE)

    climate_chart <- function() {
      d <- climate()
      if (is.null(d)) NULL else echart_shock_climate_cost(d, ce()$currency)
    }
    output$climate_plot <- echarts4r::renderEcharts4r({
      ch <- climate_chart()
      req(!is.null(ch))
      ch
    })

    output$climate_table <- reactable::renderReactable({
      d <- climate()
      req(!is.null(d))
      .wise_diag_reactable(.sp_climate_cost_display(d, ce()$currency))
    })

    # Shock-affected poor: coverage and adequacy over loss-event years ----

    reach <- reactive({
      x <- ce()
      s <- shock_summary()
      if (!identical(x$status, "ok") || !isTRUE(x$shock) || is.null(s$reach)) {
        return(NULL)
      }
      line <- reach_poverty_line() %||% poverty_line()
      list(
        line = line,
        res = sp_shock_reach(
          s$reach, baseline_svy(), line, x$currency, analysis_unit() %||% "hh"
        ),
        event_pct = s$reach_loss_event_pct
      )
    })

    output$reach_ui <- shiny::renderUI({
      r <- reach()
      if (is.null(r)) {
        return(NULL)
      }
      prefix <- .sp_currency_prefix(ce()$currency)
      line_ok <- is.finite(suppressWarnings(as.numeric(r$line)[1L]))
      shiny::tagList(
        shiny::h4("Shock-affected poor", class = "diagnostic-section-heading"),
        shiny::div(
          class = "results-section-card diagnostic-section-card",
          shiny::tags$p(
            class = "diagnostic-note",
            style = "margin-top: 0;",
            paste0(
              "Household-years in which a household that was poor at baseline lost ",
              "at least ", fmt_num(r$event_pct, 0), "% of its own typical welfare "
            ),
            "(the loss-event share of the run). Coverage is the share of those",
            "household-years in which the household was paid. Adequacy is the",
            "payment as a share of the modelled loss. This table keeps the share the",
            "run used: changing the loss-event share in Policy profile re-scores basis",
            "risk there live, but needs a new Step 3 run to change the figures here.",
            if (line_ok) {
              paste0(" Poverty line: ", prefix, fmt_num(r$line, 2), " per day (Results).")
            }
          ),
          if (nrow(r$res)) {
            shiny::tagList(
              wise_chart_output(
                ns("reach_plot"),
                "Coverage and adequacy of the shock-affected poor by scenario",
                height = "300px"
              ),
              shiny::tags$details(
                class = "decomposition-data-details",
                shiny::tags$summary("View shock-affected poor data"),
                shiny::div(
                  class = "wise-reactable-controls",
                  wise_reactable_csv_button(ns("reach_table"), "policy_shock_affected_poor")
                ),
                reactable::reactableOutput(ns("reach_table"))
              )
            )
          } else {
            shiny::tags$p(class = "text-muted small", "Needs a positive poverty line.")
          }
        )
      )
    })
    outputOptions(output, "reach_ui", suspendWhenHidden = FALSE)

    reach_display <- reactive({
      r <- reach()
      if (is.null(r) || !nrow(r$res)) {
        return(NULL)
      }
      pct <- function(x) fmt_num(100 * x, digits = 1, suffix = "%", na = "Not available")
      data.frame(
        Scenario = r$res$scenario,
        `Poor household-years with a loss event` = fmt_num(
          r$res$poor_affected_years, digits = 0, na = "Not available"
        ),
        `Coverage (paid)` = pct(r$res$coverage),
        `Adequacy (payment / loss)` = pct(r$res$adequacy),
        check.names = FALSE, stringsAsFactors = FALSE
      )
    })
    reach_chart <- function() {
      r <- reach()
      if (is.null(r) || !nrow(r$res)) NULL else echart_shock_affected_poor(r$res)
    }
    output$reach_plot <- echarts4r::renderEcharts4r({
      ch <- reach_chart()
      req(!is.null(ch))
      ch
    })

    output$reach_table <- reactable::renderReactable({
      df <- reach_display()
      req(!is.null(df))
      .wise_diag_reactable(df)
    })

    # Exports ----

    wise_export_figure(
      key = "policy_ce_ratio",
      label = "Cost-effectiveness ratio by scenario",
      step = 3L,
      fun = ce_ratio_chart,
      description = "Cost per person-year lifted or poverty gap closed per $1 of cost, with 95% intervals for the average year.",
      width = 9, height = 5,
      stale = stale
    )
    wise_export_figure(
      key = "policy_ce_cost",
      label = "Annual cost of the cash transfer",
      step = 3L,
      fun = ce_cost_chart,
      description = "Annual cost by scenario, in the average and the adverse 1-in-20 year.",
      width = 9, height = 5,
      stale = stale
    )
    wise_export_figure(
      key = "policy_shock_climate_cost_chart",
      label = "Shock-responsive climate-adjusted cost",
      step = 3L,
      fun = climate_chart,
      description = "Mean and 95th percentile annual cost per scenario, with payment frequency and cost change against history.",
      width = 9, height = 5,
      stale = stale
    )
    wise_export_figure(
      key = "policy_shock_affected_poor_chart",
      label = "Shock-responsive coverage and adequacy of the affected poor",
      step = 3L,
      fun = reach_chart,
      description = "Coverage and adequacy of the affected poor by scenario.",
      width = 9, height = 5,
      stale = stale
    )
    wise_export_table(
      key = "policy_cost_effectiveness",
      label = "Cost-effectiveness of the cash transfer",
      step = 3L,
      fun = function() {
        x <- ce()
        if (!identical(x$status, "ok")) {
          return(NULL)
        }
        cbind(
          x$res,
          metric = x$method, poverty_line = suppressWarnings(as.numeric(x$line)[1L]),
          admin_share = x$admin, currency = x$currency,
          program = if (x$shock) "shock-responsive" else "regular"
        )
      },
      stale = stale,
      description = paste(
        "Annual cost, net change in the number of poor or value of the change,",
        "and the ratio per scenario, in the average and a 1-in-20 year, at the",
        "Results metric and poverty line."
      )
    )
    wise_export_table(
      key = "policy_shock_affected_poor",
      label = "Shock-responsive coverage and adequacy of the affected poor",
      step = 3L,
      fun = function() {
        r <- reach()
        if (is.null(r) || !nrow(r$res)) NULL else cbind(
          r$res, poverty_line = suppressWarnings(as.numeric(r$line)[1L]),
          loss_event_pct = r$event_pct
        )
      },
      stale = stale,
      description = paste(
        "Share of loss-event household-years of the baseline poor in which the",
        "household was paid, and payments as a share of the modelled loss, by",
        "scenario, at the Results poverty line."
      )
    )
    wise_export_table(
      key = "policy_shock_climate_cost",
      label = "Shock-responsive climate-adjusted cost",
      step = 3L,
      fun = function() climate(),
      stale = stale,
      description = paste(
        "Activation frequency and mean annual cost per scenario and their change",
        "against the historical scenario, with the trigger fixed on history."
      )
    )
  })
}
