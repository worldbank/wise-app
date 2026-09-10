#' 2_03_diagnostics UI Function
#'
#' @description A shiny Module. Renders the Diagnostics tab content:
#'   weather input density panel and welfare output ridge plots.
#'   Consolidates the former mod_2_05_sim_diag.
#'
#' @param id Internal parameter for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_2_03_diagnostics_ui <- function(id) {
  ns <- NS(id)
  tagList(
    # ---- 0. Stale banner (INT-08) -------------------------------------------
    shiny::uiOutput(ns("stale_banner")),
    shiny::uiOutput(ns("simulation_summary_ui")),

    # ---- 1. Weather inputs panel -------------------------------------------
    shiny::h4(
      "Are simulated weather conditions within model support?",
      info_popover(
        title = "Weather support and overlap",
        shiny::p(
          "The Step 1 regression input is the reference distribution. Future",
          "scenario values are compared with its robust 1st-99th percentile",
          "interval. Values outside that interval require extrapolation of the",
          "estimated weather-outcome relationship."
        ),
        docs = TRUE
      ),
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::tags$div(
        style = "display:flex; align-items:flex-end; gap:18px; flex-wrap:wrap; margin-bottom:8px;",
        shiny::tags$div(style = "flex:1 1 220px; min-width:200px;",
          pill_toggle(ns("diag_weather_vars"), label = NULL,
                      choices = c("Loading weather variables" = ""), selected = "")
        ),
        shiny::uiOutput(ns("diag_weather_scenario_ui"))
      ),
      shiny::actionButton(
        ns("diag_update_weather"),
        "Update weather plot",
        class = "btn-sm btn-default",
        style = "margin-bottom:8px;"
      ),
      wise_plot_output(ns("diag_weather_density"),
                       "Density plot comparing the selected weather variable in the historical sample against its own climate history",
                       height = "340px"),
      shiny::uiOutput(ns("diag_weather_log_ui")),
      shiny::uiOutput(ns("weather_support_warning_ui")),
      DT::DTOutput(ns("weather_support_table")),
      shiny::tags$p(
        class = "diagnostic-note",
        "Distributions are normalized separately so samples with different sizes can be compared. Overlap does not by itself establish model validity."
      )
    ),

    # ---- 2. Climate-model robustness (Figure D2-3A default) -----------------
    shiny::h4(
      "Are expected outcomes consistent across climate models?",
      info_popover(
        title = "Climate-model agreement",
        shiny::p(
          "Each point is one climate model's mean outcome across simulated",
          "weather years for a scenario and projection period. Historical is",
          "shown once as the neutral reference."
        ),
        docs = TRUE
      ),
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::h5("Expected outcome across climate models"),
      wise_plot_output(ns("model_robustness_plot"),
                       "Climate-model mean outcome by scenario and period",
                       height = "420px"),
      shiny::tags$p(class = "diagnostic-note",
                    "Each point is one climate model's mean across simulated weather-year draws; intervals show ensemble disagreement, not probabilities.")
    ),

    # ---- 3. Weather-year trajectories (Figure D2-3B advanced) ---------------
    shiny::h4(
      "How much can outcomes vary across weather-year draws?",
      info_popover(
        title = "Weather-year variation",
        shiny::p(
          "This technical view shows annual outcome variation within each",
          "climate model. It is useful for understanding the inter-annual",
          "component behind the Results summaries."
        ),
        docs = TRUE
      ),
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::tags$details(
        shiny::tags$summary(
          "Advanced detail: Weather-year trajectories by climate model"
        ),
        shiny::p(
          class = "diagnostic-note",
          "Thin lines show model-specific simulation draws; the bold line is the across-model median. Projection windows are separate regimes, not a continuous forecast."
        ),
        wise_plot_output(ns("timeseries_plot"),
                         "Outcome across simulated weather-year draws",
                         height = "380px"),
        shiny::tags$p(class = "diagnostic-note",
                      "These are simulation draws within each climate projection window, not annual socioeconomic forecasts.")
      )
    ),

    # ---- 4. Technical definitions ------------------------------------------
    shiny::tags$details(
      shiny::tags$summary("Technical definitions and interpretation"),
      shiny::tags$ul(
        shiny::tags$li("Regression input: weather observations entering the Step 1 estimation sample."),
        shiny::tags$li("Annual aggregate: the selected outcome summarized for one weather-year draw."),
        shiny::tags$li("Climate-model mean: the average annual aggregate within one model and scenario period."),
        shiny::tags$li("Model agreement and weather-year spread describe different dimensions of variation and should not be combined by adding standard deviations.")
      )
    )
  )
}


#' 2_03_diagnostics Server Functions
#'
#' Appends a Diagnostics tab to the main tabset once the historical simulation
#' has run. Weather density and welfare ridge panels refresh only when their
#' respective Update button is clicked.
#'
#' @param id               Module id.
#' @param hist_sim         ReactiveVal list with preds, so, weather_raw, train_data.
#' @param saved_scenarios  ReactiveVal holding named scenario entries.
#' @param survey_weather   Reactive data frame of merged survey-weather data.
#' @param selected_weather Reactive data frame of selected weather variable metadata.
#' @param tabset_id        Character id of the parent tabset panel.
#' @param tabset_session   Shiny session for the tabset.
#'
#' @noRd
mod_2_03_diagnostics_server <- function(id,
                                         hist_sim,
                                         saved_scenarios,
                                         selected_hist = NULL,
                                         survey_weather,
                                         selected_weather,
                                         variance_breakdown = NULL,
                                         timeseries_curves = NULL,
                                         tabset_id,
                                         tabset_session = NULL,
                                         stale = reactive(FALSE)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # INT-08: stale banner above the diagnostics pane.
    output$stale_banner <- shiny::renderUI({
      if (isTRUE(stale())) .stale_banner("Step 2 diagnostics") else NULL
    })

    output$simulation_summary_ui <- shiny::renderUI({
      simulation_summary_card(
        hist_sim        = hist_sim(),
        saved_scenarios = if (!is.null(saved_scenarios)) saved_scenarios() else list(),
        selected_hist   = if (is.function(selected_hist)) selected_hist() else selected_hist,
        selected_weather = if (!is.null(selected_weather)) selected_weather() else NULL
      )
    })

    if (is.null(tabset_session)) tabset_session <- session$parent %||% session

    # ---- Reactive computations ---------------------------------------------

    scenario_weather_data <- reactive({
      sc <- if (!is.null(saved_scenarios)) saved_scenarios() else list()
      if (length(sc) == 0) return(NULL)
      out <- lapply(sc, function(e) step2_resolve_weather(e$weather_raw, e))
      out <- Filter(Negate(is.null), out)
      if (length(out) == 0) NULL else out
    })

    # ---- renderUI / render* outputs ----------------------------------------

    output$diag_weather_scenario_ui <- shiny::renderUI({
      sc_all <- if (!is.null(saved_scenarios)) names(saved_scenarios()) else character(0)
      if (!length(sc_all)) return(NULL)
      pill_toggle(
        ns("diag_weather_scenario"), label = NULL,
        choices = c("All scenarios and periods" = "all",
                    stats::setNames(sc_all, sc_all)),
        selected = "all"
      )
    })

    active_weather_scenarios <- reactive({
      selected <- input$diag_weather_scenario %||% "all"
      if (identical(selected, "all")) NULL else selected
    })

    output$diag_weather_log_ui <- shiny::renderUI({
      vars <- input$diag_weather_vars
      req(length(vars) > 0)
      sw      <- if (!is.null(selected_weather)) selected_weather() else NULL
      lbl_map <- if (!is.null(sw) && all(c("name", "label") %in% names(sw)))
        setNames(sw$label, sw$name) else setNames(vars, vars)
      shiny::tags$div(
        style = "display:flex; flex-wrap:wrap; gap:16px; margin-top:6px;",
        lapply(seq_along(vars), function(i) {
          v   <- vars[[i]]
          lbl <- lbl_map[[v]] %||% v
          shiny::checkboxInput(
            inputId = ns(paste0("diag_log_var_", i)),
            label   = paste0("Log\u2081\u2080: ", lbl),
            value   = FALSE
          )
        })
      )
    })

    output$diag_weather_density <- renderPlot({
      req(hist_sim(), survey_weather())
      req(!is.null(hist_sim()$weather_raw))
      vars <- input$diag_weather_vars
      req(length(vars) > 0)

      sw      <- if (!is.null(selected_weather)) selected_weather() else NULL
      lbl_map <- if (!is.null(sw) && all(c("name", "label") %in% names(sw)))
        setNames(sw$label, sw$name) else NULL

      log_x_vec <- vapply(seq_along(vars), function(i)
        isTRUE(input[[paste0("diag_log_var_", i)]]), logical(1))

      plot_weather_density_panel(
        survey_weather   = survey_weather(),
        weather_raw      = hist_sim()$weather_raw,
        weather_vars     = vars,
        weather_labels   = lbl_map,
        scenario_weather = scenario_weather_data(),
        active_scenarios = active_weather_scenarios(),
        log_x            = log_x_vec,
        show_regression  = TRUE
      )
    }) |> shiny::bindEvent(input$diag_update_weather, input$diag_weather_scenario,
                           hist_sim(),
                           ignoreNULL = TRUE, ignoreInit = FALSE)

    weather_support_data <- reactive({
      req(hist_sim(), survey_weather())
      vars <- input$diag_weather_vars
      req(length(vars) > 0L, !is.null(hist_sim()$weather_raw))
      ref <- .filter_hist_weather(hist_sim()$weather_raw, survey_weather())
      scenarios <- scenario_weather_data()
      weather_support_summary(ref, scenarios, vars)
    })

    output$weather_support_table <- DT::renderDT({
      tbl <- weather_support_data()
      if (is.null(tbl) || !nrow(tbl)) {
        return(DT::datatable(
          data.frame(Message = "No weather-support summary is available."),
          rownames = FALSE, options = list(dom = "t")
        ))
      }
      display <- data.frame(
        `Weather variable` = tbl$weather_variable,
        `Scenario / period` = tbl$scenario,
        `Reference interval (1%-99%)` = paste0(
          formatC(tbl$robust_lo, format = "fg", digits = 4), " to ",
          formatC(tbl$robust_hi, format = "fg", digits = 4)),
        `Scenario values` = tbl$n_scenario,
        `Outside interval` = paste0(tbl$outside_n, " (", round(100 * tbl$outside_share, 1), "%)"),
        Status = ifelse(tbl$warning, "Review: extrapolation", "Within support"),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      DT::datatable(
        display, rownames = FALSE, class = "compact stripe",
        extensions = "Buttons",
        options = list(dom = wise_csv_dom("tp"), pageLength = 10,
                       buttons = wise_csv_button("simulation_weather_support_summary"))
      )
    })
    outputOptions(output, "weather_support_table", suspendWhenHidden = TRUE)
    output$weather_support_warning_ui <- renderUI({
      tbl <- weather_support_data()
      if (is.null(tbl) || !nrow(tbl) || !any(tbl$warning)) return(NULL)
      bad <- unique(tbl$weather_variable[tbl$warning])
      shiny::tags$div(class = "alert alert-warning", role = "alert",
                      shiny::tags$strong("Weather support warning: "),
                      paste(bad, collapse = ", "),
                      " has more than 5% of scenario values outside the robust Step 1 1%-99% support interval. Extrapolation may be required.")
    })

    # UI-48: Step 2 diagnostic figures for the export bundle.
    wise_export_figure(
      key   = "simulation_variance_contribution",
      label = "Variance contribution by source",
      step  = 2L,
      fun   = function() {
        vb <- variance_breakdown()
        if (is.null(vb) || !nrow(vb)) return(NULL)
        plot_variance_contribution(vb)
      },
      description = paste(
        "How much of the simulated welfare variance comes from each source",
        "(weather, coefficients, residuals, inter-model spread)."
      ),
      width = 9, height = 6
    )

    wise_export_table(
      key = "simulation_variance_data",
      label = "Simulation uncertainty components",
      step = 2L,
      fun = function() {
        vb <- variance_breakdown()
        if (is.null(vb) || !nrow(vb)) return(NULL)
        out <- variance_component_data(vb, isTRUE(input$show_variance_shares))
        annotate_visualization_export(
          out, hist_sim()$agg_method %||% hist_sim()$method %||% "mean", hist_sim()$so,
          observation_unit = "scenario-level annual aggregate summary",
          aggregation_order = "weighted aggregate by model and weather-year; components retained separately",
          uncertainty = "coefficient, inter-annual, and inter-model components"
        )
      },
      description = "Tidy uncertainty components behind the aligned standard-deviation chart."
    )
    wise_export_figure(
      key = "simulation_weather_support",
      label = "Weather inputs and Step 1 model support",
      step = 2L,
      fun = function() {
        req(hist_sim(), survey_weather())
        vars <- input$diag_weather_vars
        req(length(vars) > 0L)
        plot_weather_density_panel(
          survey_weather(), hist_sim()$weather_raw, vars,
          scenario_weather = scenario_weather_data(),
          active_scenarios = active_weather_scenarios(),
          show_regression = TRUE
        )
      },
      description = "Weather input distributions compared with the Step 1 regression support.",
      width = 10, height = 6.5
    )
    wise_export_table(
      key = "simulation_weather_support_data",
      label = "Weather support data",
      step = 2L,
      fun = function() {
        req(hist_sim(), survey_weather())
        vars <- input$diag_weather_vars
        req(length(vars) > 0L)
        annotate_visualization_export(
          weather_density_data(
            survey_weather(), hist_sim()$weather_raw, vars,
            scenario_weather_data(), active_weather_scenarios(), TRUE
          ),
          hist_sim()$so$method %||% "mean", hist_sim()$so,
          observation_unit = "weather input value entering the simulation",
          aggregation_order = "raw weather inputs retained by source and scenario",
          uncertainty = "distributional support comparison"
        )
      },
      description = "Underlying tidy weather values used by the support comparison."
    )
    wise_export_table(
      key = "simulation_weather_support_summary",
      label = "Weather support summary",
      step = 2L,
      fun = weather_support_data,
      description = "Sample sizes, robust Step 1 support intervals, outside-support shares, and warnings."
    )
    wise_export_figure(
      key = "simulation_model_robustness",
      label = "Climate-model robustness",
      step = 2L,
      fun = function() {
        tc <- timeseries_curves(); req(!is.null(tc$tbl), nrow(tc$tbl) > 0L)
        plot_model_robustness(model_robustness_data(tc$tbl), tc$x_label)
      },
      description = "One point per climate model's mean across weather-year draws with ensemble spread.",
      width = 10, height = 6
    )
    wise_export_table(
      key = "simulation_model_robustness_data",
      label = "Climate-model robustness data",
      step = 2L,
      fun = function() {
        tc <- timeseries_curves(); req(!is.null(tc$tbl), nrow(tc$tbl) > 0L)
        annotate_visualization_export(model_robustness_data(tc$tbl),
          hist_sim()$so$method %||% "mean", hist_sim()$so,
          observation_unit = "climate-model mean across weather-year draws",
          aggregation_order = "annual aggregate by model and weather year, then model mean",
          uncertainty = "ensemble spread")
      },
      description = "Tidy climate-model robustness summaries."
    )
    wise_export_figure(
      key = "simulation_model_trajectories",
      label = "Climate-model annual trajectories",
      step = 2L,
      fun = function() {
        req(timeseries_curves)
        tc <- timeseries_curves()
        req(!is.null(tc$tbl), nrow(tc$tbl) > 0L)
        plot_timeseries_spaghetti(tc$tbl, x_label = tc$x_label)
      },
      description = "Advanced climate-model trajectories by discrete simulation window.",
      width = 10, height = 6.5
    )
    wise_export_table(
      key = "simulation_model_trajectories_data",
      label = "Climate-model trajectory data",
      step = 2L,
      fun = function() {
        req(timeseries_curves)
        tc <- timeseries_curves()
        req(!is.null(tc$tbl), nrow(tc$tbl) > 0L)
        annotate_visualization_export(
          tc$tbl, hist_sim()$so$method %||% "mean", hist_sim()$so,
          observation_unit = "annual aggregate for one climate model and weather-year draw",
          aggregation_order = "weighted aggregate retained by model, simulation year, and scenario",
          uncertainty = "inter-model spread shown separately from annual draws"
        )
      },
      description = "Tidy data behind the advanced climate-model trajectory view."
    )

    output$variance_contribution_plot <- renderPlot({
      req(variance_breakdown)
      vb <- variance_breakdown()
      req(!is.null(vb) && nrow(vb) > 0L)
      plot_variance_contribution(vb)
    })
    output$variance_share_warning <- renderUI({
      if (!isTRUE(input$show_variance_shares)) return(NULL)
      shiny::tags$p(class = "text-warning small",
                    "Approximate shares assume zero covariance between components and may not sum to the uncertainty of the combined estimand.")
    })
    output$variance_share_table <- DT::renderDT({
      req(variance_breakdown())
      if (!isTRUE(input$show_variance_shares)) {
        return(DT::datatable(data.frame(Message = "Approximate shares are hidden by default."),
                            rownames = FALSE, options = list(dom = "t")))
      }
      DT::datatable(
        variance_component_data(variance_breakdown(), TRUE),
        rownames = FALSE, class = "compact stripe",
        extensions = "Buttons",
        options = list(dom = wise_csv_dom("tp"), pageLength = 20,
                       buttons = wise_csv_button("simulation_variance_shares"))
      )
    })
    outputOptions(output, "variance_share_table", suspendWhenHidden = FALSE)

    output$timeseries_plot <- renderPlot({
      req(timeseries_curves)
      tc <- timeseries_curves()
      req(!is.null(tc$tbl) && nrow(tc$tbl) > 0L)
      ts_tbl <- tc$tbl
      plot_timeseries_spaghetti(
        ts_tbl          = ts_tbl,
        x_label         = tc$x_label,
        ensemble_band_q = tc$ens_q
      )
    })

    output$model_robustness_plot <- renderPlot({
      req(timeseries_curves)
      tc <- timeseries_curves()
      req(!is.null(tc$tbl) && nrow(tc$tbl) > 0L)
      plot_model_robustness(model_robustness_data(tc$tbl), tc$x_label)
    }, height = 420)
    outputOptions(output, "model_robustness_plot", suspendWhenHidden = TRUE)



    # ---- Insert Diagnostics tab on first hist_sim; remove when cleared -----

    diag_tab_added <- reactiveVal(FALSE)

    observeEvent(hist_sim(), {
      if (is.null(hist_sim())) {
        if (diag_tab_added()) {
          shiny::removeTab(
            inputId = tabset_id,
            target  = "diag_tab",
            session = tabset_session
          )
          diag_tab_added(FALSE)
        }
        return()
      }

      sw      <- if (!is.null(selected_weather)) selected_weather() else NULL
      choices <- if (!is.null(sw) && "name" %in% names(sw)) {
        if ("label" %in% names(sw)) setNames(sw$name, sw$label) else sw$name
      } else character(0)

      # UI-50: one Diagnostics tab, not one per Step 2 run. The tab's contents
      # are a module UI bound to fixed output ids, so an already-present tab
      # needs no rebuild - only its weather choices refreshed below.
      if (!diag_tab_added()) {
        shiny::appendTab(
          inputId = tabset_id,
          shiny::tabPanel(
            title = "Diagnostics",
            value = "diag_tab",
            mod_2_03_diagnostics_ui(sub("-$", "", session$ns("")))
          ),
          select  = FALSE,
          session = tabset_session
        )
        diag_tab_added(TRUE)
      }

      selected <- if (length(choices)) choices[[1L]] else character(0)
      shiny::updateRadioButtons(session, "diag_weather_vars",
                                choices  = choices,
                                selected = selected)
    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    observeEvent(selected_weather(), {
      sw      <- if (!is.null(selected_weather)) selected_weather() else NULL
      choices <- if (!is.null(sw) && "name" %in% names(sw)) {
        if ("label" %in% names(sw)) setNames(sw$name, sw$label) else sw$name
      } else character(0)
      current <- isolate(input$diag_weather_vars)
      new_sel <- if (length(current) > 0) intersect(current, choices) else character(0)
      if (length(new_sel) == 0) {
        new_sel <- if (length(choices)) choices[[1L]] else character(0)
      }
      shiny::updateRadioButtons(session, "diag_weather_vars",
                                choices  = choices,
                                selected = new_sel)
    }, ignoreInit = TRUE)

    # ---- Suspend outputs when Results tab is hidden ----------------------
    outputOptions(output, "diag_weather_scenario_ui", suspendWhenHidden = TRUE)
    outputOptions(output, "diag_weather_log_ui",     suspendWhenHidden = TRUE)
    outputOptions(output, "diag_weather_density",    suspendWhenHidden = TRUE)
    outputOptions(output, "variance_contribution_plot", suspendWhenHidden = TRUE)
    outputOptions(output, "timeseries_plot",         suspendWhenHidden = TRUE)
    outputOptions(output, "variance_share_warning",  suspendWhenHidden = FALSE)

    # ---- Return API --------------------------------------------------------
    list(diag_tab_added = diag_tab_added)
  })
}
