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

    # ---- 0. Scenario filters -----------------------------------------------
    shiny::uiOutput(ns("scenario_filter_panel")),

    # ---- 1. Weather inputs panel -------------------------------------------
    shiny::wellPanel(
      shiny::h4(
        "Weather input distributions",
        info_popover(
          title = "Weather input distributions",
          shiny::p(shiny::tags$b("Grey fill = Full historical:"),
            " all years at survey locations and months."),
          shiny::p(shiny::tags$b("Black dashed = Regression input"),
            " (shown when 'Include regression output' is selected above)."),
          shiny::p(shiny::tags$b("Coloured lines = Future scenarios:"),
            " solid = earliest simulation year, dashed = middle, dotted = latest."),
          docs = TRUE
        )
      ),
      shiny::tags$div(
        style = "display:flex; align-items:flex-end; gap:12px; flex-wrap:wrap; margin-bottom:8px;",
        shiny::tags$div(style = "flex:3; min-width:200px;",
          shiny::selectInput(
            ns("diag_weather_vars"),
            label    = "Weather variables (select one or more)",
            choices  = character(0),
            selected = NULL,
            multiple = TRUE
          )
        )
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
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:4px;",
        "Grey fill = historical; black dashed = regression input; coloured lines = future scenarios."
      )
    ),

    # ---- 2. Variance contribution panel ------------------------------------
    shiny::wellPanel(
      shiny::h4(
        "Sources of variation and uncertainty",
        info_popover(
          title = "Sources of variation and uncertainty",
          shiny::p(shiny::tags$b("Each bar"),
            " is one source's standard deviation in outcome units."),
          shiny::p(shiny::tags$b("Important:"),
            " bars are aligned, not stacked. Inter-annual weather variability,",
            " inter-model climate spread, and coefficient uncertainty are",
            " different quantities and are not combined into an unlabeled band."),
          shiny::p(shiny::tags$b("Coefficient uncertainty"),
            " = SD of the regression-fit per-outcome variance, averaged."),
          shiny::p(shiny::tags$b("Inter-annual variability"),
            " = SD of within-model year-to-year spread of the aggregate. This",
            " characterises the spread of simulated years, not uncertainty",
            " about the central tendency."),
          shiny::p(shiny::tags$b("Inter-model spread"),
            " (future scenarios only) = SD of across-model disagreement in",
            " the per-model mean aggregate - uncertainty about the central",
            " tendency arising from model choice."),
          docs = TRUE
        )
      ),
      wise_plot_output(ns("variance_contribution_plot"),
                       "Bar plot of each weather variable's contribution to simulated outcome variance",
                       height = "320px"),
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:6px;",
        "Aligned bars show separate SD components; they are not additive - click ",
        shiny::icon("circle-info"), " above for details."
      )
    ),

    # ---- 3. Per-model trajectories (moved from Simulation Results) ----------
    shiny::wellPanel(
      shiny::h4(
        "Per-model trajectories across simulation years",
        info_popover(
          title = "Reading this chart",
          shiny::p(shiny::tags$b("Thin coloured lines"),
            " = one CMIP6 ensemble member each (a 'spaghetti' trace of model trajectories)."),
          shiny::p(shiny::tags$b("Bold line"),
            " = across-model median curve for each scenario."),
          shiny::p(shiny::tags$b("Translucent ribbon"),
            " (future scenarios only) = inter-model spread at the selected band quantiles."),
          shiny::p(
            "Each scenario \u00D7 projection period gets its own colour (SSP",
            "family) and linetype (period), shown as one entry in the legend."
          ),
          docs = TRUE
        )
      ),
      wise_plot_output(ns("timeseries_plot"),
                       "Time series of the outcome across survey years",
                       height = "380px"),
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:6px;",
        "Thin lines = ensemble members; bold = median; ribbon = inter-model spread."
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
        selected_hist   = NULL,
        selected_weather = if (!is.null(selected_weather)) selected_weather() else NULL
      )
    })

    if (is.null(tabset_session)) tabset_session <- session$parent %||% session

    # ---- Reactive computations ---------------------------------------------

    active_scenarios_data <- reactive({
      sc_all <- if (!is.null(saved_scenarios)) names(saved_scenarios()) else character(0)
      if (length(sc_all) == 0) return(character(0))

      sel_ssps <- input$filter_ssps %||% character(0)
      sel_yrs  <- input$filter_yrs  %||% character(0)

      if (length(sel_ssps) == 0L && length(sel_yrs) == 0L) return(character(0))

      Filter(function(nm) {
        ssp    <- .normalise_ssp(nm)
        yr     <- .parse_year(nm)
        ssp_ok <- length(sel_ssps) == 0L || isTRUE(ssp %in% sel_ssps)
        yr_ok  <- length(sel_yrs)  == 0L || isTRUE(yr  %in% sel_yrs)
        ssp_ok && yr_ok
      }, sc_all)
    })

    scenario_weather_data <- reactive({
      sc <- if (!is.null(saved_scenarios)) saved_scenarios() else list()
      if (length(sc) == 0) return(NULL)
      out <- lapply(sc, function(e) e$weather_raw)
      out <- Filter(Negate(is.null), out)
      if (length(out) == 0) NULL else out
    })

    output$weight_status_diag_ui <- shiny::renderUI({
      req(hist_sim())
      # Detect weight column independently of the toggle -- this allows
      # the amber state when the column exists but the toggle is OFF.
      has_w  <- !is.null(hist_sim()$pipeline$weight)
      tog_on <- isTRUE(input$use_weights_diag)
      if (has_w && tog_on)
        NULL
      else if (has_w && !tog_on)
        shiny::tags$p(
          style = "font-size:11px; color:#e65100; margin:2px 0 6px 0;",
          "\u26A0 Survey weights available but not applied")
      else
        shiny::tags$p(
          style = "font-size:11px; color:#c62828; margin:2px 0 6px 0;",
          "\U0001F534 No weight column found - unweighted")
    })



    # ---- renderUI / render* outputs ----------------------------------------

    output$scenario_filter_panel <- shiny::renderUI({
      sc_all      <- if (!is.null(saved_scenarios)) names(saved_scenarios()) else character(0)
      unique_ssps <- sort(unique(Filter(Negate(is.na),
                                        vapply(sc_all, .normalise_ssp, character(1)))))
      unique_yrs  <- sort(unique(Filter(Negate(is.na),
                                        vapply(sc_all, .parse_year,    character(1)))))

      shiny::wellPanel(
        style = "padding: 10px 16px 8px 16px; background:#f8f8f8; margin-bottom:10px;",
        shiny::tags$div(
          style = "display:flex; align-items:baseline; gap:8px; margin-bottom:10px;",
          shiny::tags$b("Scenario Filters", style = "font-size:13px;"),
          shiny::tags$span(
            style = "font-size:11px; color:#888;",
            "\u2014 applies to all panels below"
          )
        ),
        shiny::tags$div(
          style = "display:flex; flex-wrap:wrap; gap:24px; align-items:flex-start;",
          if (length(unique_ssps) > 0)
            shiny::tags$div(
              shiny::checkboxGroupInput(
                inputId  = ns("filter_ssps"),
                label    = shiny::tags$b("Climate scenario",
                             style = "font-size:11px; font-weight:600;"),
                choices  = setNames(unique_ssps, unique_ssps),
                selected = character(0),
                inline   = TRUE
              )
            ),
          if (length(unique_yrs) > 0)
            shiny::tags$div(
              shiny::checkboxGroupInput(
                inputId  = ns("filter_yrs"),
                label    = shiny::tags$b("Simulation year",
                             style = "font-size:11px; font-weight:600;"),
                choices  = setNames(unique_yrs, unique_yrs),
                selected = character(0),
                inline   = TRUE
              )
            )
        ),
        shiny::tags$div(
          style = "margin-top:8px; border-top:1px solid #e0e0e0; padding-top:6px;",
          shiny::checkboxInput(
            ns("show_regression_input"),
            label = "Include regression output",
            value = TRUE
          ),
          shiny::checkboxInput(
            ns("use_weights_diag"),
            label = "Use survey weights (if available)",
            value = TRUE
          ),
          shiny::uiOutput(ns("weight_status_diag_ui"))
        )
      )
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
        active_scenarios = active_scenarios_data(),
        log_x            = log_x_vec,
        show_regression  = input$show_regression_input %||% TRUE
      )
    }) |> shiny::bindEvent(input$diag_update_weather, hist_sim(),
                           ignoreNULL = TRUE, ignoreInit = FALSE)

    # UI-48: Step 2 diagnostic figures for the export bundle.
    wise_export_figure(
      key   = "simulation_variance_contribution",
      label = "Variance contribution by source",
      step  = 2L,
      fun   = function() {
        vb <- variance_breakdown()
        if (is.null(vb) || !nrow(vb)) return(NULL)
        active <- active_scenarios_data()
        if (length(active) > 0L) {
          vb <- vb[vb$is_historical | vb$scenario %in% active, , drop = FALSE]
        }
        if (!nrow(vb)) return(NULL)
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
        annotate_visualization_export(
          vb, hist_sim()$so$method %||% "mean", hist_sim()$so,
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
          active_scenarios = active_scenarios_data(),
          show_regression = input$show_regression_input %||% TRUE
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
            scenario_weather_data(), active_scenarios_data(),
            input$show_regression_input %||% TRUE
          ),
          hist_sim()$so$method %||% "mean", hist_sim()$so,
          observation_unit = "weather input value entering the simulation",
          aggregation_order = "raw weather inputs retained by source and scenario",
          uncertainty = "distributional support comparison"
        )
      },
      description = "Underlying tidy weather values used by the support comparison."
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
      # Filter to currently active scenarios when filters are set; otherwise
      # show all available rows (Historical + all scenarios in vb).
      active <- active_scenarios_data()
      if (length(active) > 0L) {
        keep <- vb$is_historical | vb$scenario %in% active
        vb <- vb[keep, , drop = FALSE]
      }
      plot_variance_contribution(vb)
    })

    output$timeseries_plot <- renderPlot({
      req(timeseries_curves)
      tc <- timeseries_curves()
      req(!is.null(tc$tbl) && nrow(tc$tbl) > 0L)
      ts_tbl <- tc$tbl
      # Honour the Diagnostics scenario filters (historical always shown).
      active <- active_scenarios_data()
      if (length(active) > 0L) {
        keep <- ts_tbl$is_historical | ts_tbl$scenario %in% active
        ts_tbl <- ts_tbl[keep, , drop = FALSE]
      }
      plot_timeseries_spaghetti(
        ts_tbl          = ts_tbl,
        x_label         = tc$x_label,
        ensemble_band_q = tc$ens_q
      )
    })



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

      shiny::updateSelectInput(session, "diag_weather_vars",
                               choices  = choices,
                               selected = choices[seq_len(min(2, length(choices)))])
    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    observeEvent(selected_weather(), {
      sw      <- if (!is.null(selected_weather)) selected_weather() else NULL
      choices <- if (!is.null(sw) && "name" %in% names(sw)) {
        if ("label" %in% names(sw)) setNames(sw$name, sw$label) else sw$name
      } else character(0)
      current <- isolate(input$diag_weather_vars)
      new_sel <- if (length(current) > 0) intersect(current, choices) else character(0)
      if (length(new_sel) == 0) new_sel <- choices[seq_len(min(2, length(choices)))]
      shiny::updateSelectInput(session, "diag_weather_vars",
                               choices  = choices,
                               selected = new_sel)
    }, ignoreInit = TRUE)

    # ---- Suspend outputs when Results tab is hidden ----------------------
    outputOptions(output, "scenario_filter_panel",   suspendWhenHidden = TRUE)
    outputOptions(output, "diag_weather_log_ui",     suspendWhenHidden = TRUE)
    outputOptions(output, "diag_weather_density",    suspendWhenHidden = TRUE)
    outputOptions(output, "variance_contribution_plot", suspendWhenHidden = TRUE)
    outputOptions(output, "timeseries_plot",         suspendWhenHidden = TRUE)
    outputOptions(output, "weight_status_diag_ui",   suspendWhenHidden = TRUE)

    # ---- Return API --------------------------------------------------------
    list(diag_tab_added = diag_tab_added)
  })
}
