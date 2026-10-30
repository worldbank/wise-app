# Tell the user when rows were left out of the Step 2 results (missing
# predictions, weights or coefficient loadings). Silent when nothing was.
.notify_data_quality <- function(dq) {
  msg <- step2_data_quality_notice(dq)
  if (!is.null(msg)) {
    shiny::showNotification(paste("Data check:", msg), type = "warning", duration = 15)
  }
  invisible(NULL)
}

# Tell the user which baseline households were left out for missing weather
# or model data (`step2_baseline_complete()`). Silent when none were.
.notify_baseline_dropped <- function(dropped) {
  msg <- step2_dropped_note(dropped)
  if (!is.null(msg)) {
    shiny::showNotification(paste("Baseline:", msg), type = "warning", duration = NULL)
  }
  invisible(NULL)
}

# Tell the user when baseline households have no estimation row for the
# "original" residual rule (`step2_residual_match_note()`). Silent otherwise.
.notify_residual_match <- function(residual_match) {
  msg <- step2_residual_match_note(residual_match)
  if (!is.null(msg)) {
    shiny::showNotification(paste("Residuals:", msg), type = "warning", duration = 15)
  }
  invisible(NULL)
}

#' 2_01_weathersim UI Function
#'
#' @description A shiny Module. Unified sidebar for configuring and running
#'   both historical and future welfare simulations.
#'
#' @param id Internal parameter for {shiny}.
#'
#' @section Simulation inputs (configured in server via input$):
#'   \describe{
#'     \item{\code{pov_line_sim}}{Numeric. Poverty line in daily 2021 PPP USD.
#'       Fixed at simulation time.}
#'     \item{\code{skip_coef_draws}}{Logical. If TRUE, bypasses VCV draws
#'       and uses point estimates only. Default TRUE.}
#'   }
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_2_01_weathersim_ui <- function(id) {
  ns <- NS(id)
  d <- wise_default_sim()
  tags$div(
    class = "step2-sidebar",
    # Settings summary banner (always visible) ----
    shiny::uiOutput(ns("settings_summary")),

    # Simulation settings flyout (same pattern as Step 1 'Configure') ----
    # UI-02: shared flyout block - anchored to its toggle, one-open state,
    # aria-expanded, focus management, Escape to close (see custom.js).
    # Settings that apply to every scenario; the climate projection and the
    # seasonal forecast controls have their own flyouts below.
    config_flyout_block(
      ns("settings_toggle"),
      "Simulation settings",
      toggle_label = "Simulation settings",
      display_label = "Survey, history, residuals",

      # Baseline survey ----
      shiny::tags$div(
        class = "step2-section-label",
        "Baseline survey"
      ),
      shiny::uiOutput(ns("baseline_survey_ui")),
      shiny::uiOutput(ns("baseline_warning_ui")),
      shiny::tags$hr(style = "margin: 6px 0;"),

      # Historical period ----
      shiny::tags$h6(
        "Historical weather distribution period",
        info_popover(
          title = "Historical weather distribution period",
          shiny::p(
            "Historical weather informs the underlying variability, which is then",
            "perturbed with climate scenario projections. The historical period",
            "does not affect the seasonal forecast, which is adjusted by the data pipeline."
          )
        ),
        style = "font-weight:600; margin-top:8px; margin-bottom:4px;"
      ),
      shiny::sliderInput(
        inputId = ns("hist_years"),
        label = shiny::tags$span(
          class = "visually-hidden",
          "Historical weather distribution period"
        ),
        min = WISEAPP_SIM_HIST_RANGE[[1L]],
        max = WISEAPP_SIM_HIST_RANGE[[2L]],
        value = d$hist_years,
        sep = ""
      ),
      shiny::uiOutput(ns("hist_years_warning")),
      shiny::helpText(
        tags$b("30 years is the recommended default."),
        style = "font-size: 11px; color: #555; margin-top: 2px; margin-bottom: 8px;"
      ),
      shiny::tags$hr(style = "margin: 6px 0;"),

      # Residual method ----
      shiny::tags$h6(
        "Simulation residuals",
        info_popover(
          title = "Simulation residuals",
          shiny::p(
            shiny::tags$b("original:"),
            paste0(
              " Recommended default. Each household keeps its own unexplained component, the same in ",
              "every year. The simulated distribution stays close to the observed one, and the ",
              "coefficient band covers only the change from the weather at the interview."
            )
          ),
          shiny::p(
            shiny::tags$b("resample:"),
            paste0(
              " Adds residual noise drawn from the pooled estimation residuals, independent of ",
              "household and location. It changes the level and spread of the simulated distribution, ",
              "so it does not reproduce the observed distribution. The coefficient band then uses ",
              "all covariates and is several times wider than under original."
            )
          ),
          docs = TRUE
        ),
        style = "font-weight:600; margin-bottom:4px;"
      ),
      pill_toggle(
        inputId = ns("residuals"),
        label = shiny::tags$span(
          class = "visually-hidden",
          "Simulation residuals"
        ),
        choices = residual_choices(),
        selected = d$residuals
      ),
      shiny::tags$hr(style = "margin: 6px 0;"),

      # Coefficient uncertainty ----
      shiny::tags$h6(
        "Model coefficient uncertainty",
        info_popover(
          title = "Model coefficient uncertainty",
          shiny::p(
            "Checking this box adds the sampling error of the estimated coefficients, via the",
            "analytic delta method, for the model as specified. It does not cover the choice of",
            "covariates, the Lasso selection, the functional form or the bins.",
            "Disable to use point estimates only."
          ),
          shiny::p(
            "Only coefficients on variables that change between baseline and counterfactual",
            "contribute: weather variables and their interactions in Step 2; weather plus",
            "the policy-modified variables and their interactions in Step 3.",
            "Under 'original' residuals the household's own residual holds the fitted value at",
            "its interview weather, so a level's band is zero at that weather and grows with the",
            "distance from it. Under 'resample' the band of a level uses every covariate and is",
            "several times wider; a difference between two results is much closer under both rules."
          ),
          shiny::p(
            "Coefficient uncertainty is propagated analytically via the",
            "delta method for all aggregates (mean, total, headcount,",
            "poverty gap, FGT2, Gini, 'avg_poverty'). There is no Monte Carlo",
            "draw fallback in the current implementation."
          ),
          docs = TRUE
        ),
        style = "font-weight:600; margin-bottom:4px;"
      ),
      shiny::checkboxInput(
        inputId = ns("include_coef_uncertainty"),
        label   = "Include coefficient uncertainty",
        value   = d$coef_uncertainty
      )
    ),

    # Climate projections flyout ----
    config_flyout_block(
      ns("projections_toggle"),
      "Climate projections",
      toggle_label = "Climate projections",
      toggle_icon = "chart-line",
      display_label = shiny::textOutput(ns("projections_summary"), inline = TRUE),

      # Climate scenarios ----
      shiny::tags$div(
        class = "step2-section-label",
        "Climate scenarios"
      ),
      shiny::checkboxGroupInput(
        inputId = ns("climate"),
        label = shiny::tags$span(class = "visually-hidden", "Climate scenarios"),
        choices = c(
          "SSP2" = "ssp2_4_5",
          "SSP3" = "ssp3_7_0",
          "SSP5" = "ssp5_8_5"
        ),
        selected = d$ssps,
        inline = TRUE
      ),
      shiny::tags$hr(style = "margin: 6px 0;"),

      # Projection period ----
      shiny::tags$div(
        class = "step2-section-label",
        "Projection period"
      ),
      shiny::tags$div(
        class = "step2-projection-period",
        with_grid_num(
          shiny::sliderInput(
            ns("fut_period_1"),
            label = shiny::tags$span(class = "visually-hidden", "Projection period 1"),
            min = .STEP2_SSP_START_YEAR, max = .STEP2_SSP_END_YEAR, value = d$future_periods[[1L]],
            step = 1, sep = ""
          ),
          9
        )
      ),
      shiny::uiOutput(ns("fut_years_warning")),
      shiny::tags$hr(style = "margin: 6px 0;"),

      # Additional future periods ----
      shiny::tags$h6("Additional projection periods",
        style = "font-weight:600; margin-bottom:4px;"
      ),

      # Period 2 (optional)
      shiny::tags$div(
        class = "step2-projection-period",
        shiny::tags$span("Period 2", class = "step2-projection-label"),
        with_grid_num(
          shiny::sliderInput(
            ns("fut_period_2"),
            label = shiny::tags$span(class = "visually-hidden", "Projection period 2"),
            min = .STEP2_SSP_START_YEAR, max = 2100, value = c(2015, 2015), step = 1, sep = ""
          ),
          9
        )
      ),
      # Period 3 (optional)
      shiny::tags$div(
        class = "step2-projection-period",
        shiny::tags$span("Period 3", class = "step2-projection-label"),
        with_grid_num(
          shiny::sliderInput(
            ns("fut_period_3"),
            label = shiny::tags$span(class = "visually-hidden", "Projection period 3"),
            min = .STEP2_SSP_START_YEAR, max = 2100, value = c(2015, 2015), step = 1, sep = ""
          ),
          9
        )
      )
    ),

    # Seasonal forecast flyout ----
    # Scaffold: nothing here reaches the simulation run yet (utils_forecast_ui.R).
    config_flyout_block(
      ns("forecast_toggle"),
      "Seasonal forecast",
      toggle_label = "Seasonal forecast",
      toggle_icon = "calendar-days",
      display_label = shiny::textOutput(ns("forecast_summary"), inline = TRUE),

      shiny::checkboxInput(
        inputId = ns("fc_include"),
        label   = "Include seasonal forecast",
        value   = FALSE
      ),
      shiny::uiOutput(ns("forecast_status_ui")),
      shiny::uiOutput(ns("forecast_body_ui")),
      shiny::uiOutput(ns("forecast_readout_ui")),
      shiny::uiOutput(ns("forecast_notes_ui"))
    ),
    shiny::tags$hr(style = "margin: 10px 0;"),

    # Run simulation button (hidden for RIF engine) ----
    shiny::uiOutput(ns("run_sim_ui"))
  )
}

# Expected scenario labels of a run, in run order: the forecast (when given)
# first, then SSP outer, period inner (the order of get_weather()'s
# .process_ssp loop), keyed exactly like the worker's partials and the adopted
# scenarios.
.step2_scenario_labels <- function(ssps, periods, forecast_key = NULL) {
  ssp_labels <- if (!length(ssps) || !length(periods)) {
    character(0)
  } else {
    unlist(lapply(ssps, function(ssp) {
      vapply(periods, function(yr) {
        .step2_scenario_display_key(ssp, c(yr[[1L]], yr[[2L]]))
      }, character(1))
    }), use.names = FALSE)
  }
  c(forecast_key, ssp_labels)
}

# Mean seconds per completed scenario group times the remaining groups.
# NULL until one group is done or when nothing remains.
.step2_live_eta <- function(groups_done, groups_total, base, now = Sys.time()) {
  if (is.null(groups_done) || is.null(groups_total) || is.null(base) ||
      groups_done < 1L || groups_total <= groups_done) return(NULL)
  per_group <- as.numeric(difftime(now, base, units = "secs")) / groups_done
  max(0, per_group * (groups_total - groups_done))
}

.step2_eta_text <- function(eta_seconds) {
  if (is.null(eta_seconds) || !is.finite(eta_seconds)) return(NULL)
  if (eta_seconds < 60) return("under a minute remaining")
  paste0("about ", ceiling(eta_seconds / 60), " min remaining")
}

# Fraction complete of a streaming run, or NULL when it cannot be determined.
# `view` carries has_hist, groups_total, groups_done, current_label,
# member_index, period_members and done_labels.
.step2_live_pct <- function(view) {
  total <- view$groups_total %||% 0L
  done <- view$groups_done %||% 0L
  hist_done <- if (isTRUE(view$has_hist)) 1L else 0L
  if (total <= 0L && !hist_done && done == 0L) return(NULL)
  frac <- 0
  if (!is.null(view$member_index) && !is.null(view$period_members) &&
      view$period_members > 0L && !(view$current_label %in% view$done_labels)) {
    frac <- min(1, view$member_index / view$period_members)
  }
  min(1, (hist_done + done + frac) / (1 + total))
}

.step2_progress_ui <- function(view) {
  pct <- .step2_live_pct(view)
  bar <- if (is.null(pct)) {
    shiny::div(class = "progress-bar progress-bar-striped active",
      role = "progressbar", style = "width: 100%;")
  } else {
    shiny::div(class = "progress-bar", role = "progressbar",
      `aria-valuenow` = round(100 * pct), `aria-valuemin` = 0,
      `aria-valuemax` = 100, style = sprintf("width: %d%%;", round(100 * pct)))
  }
  row <- function(label, done, current, detail = NULL) {
    shiny::div(
      class = if (done || current) "" else "text-muted",
      shiny::icon(if (done) "check" else if (current) "spinner" else "circle"),
      " ", label, if (!done && !is.null(detail)) paste0(" (", detail, ")")
    )
  }
  rows <- NULL
  if (isTRUE(view$has_hist) || length(view$scenario_labels)) {
    cur <- view$current_label
    models <- if (!is.null(view$member_index) && !is.null(view$period_members) &&
        view$period_members > 0L) {
      paste0(view$member_index, " / ", view$period_members, " climate models")
    }
    rows <- c(
      list(row("Historical", isTRUE(view$has_hist), FALSE)),
      lapply(view$scenario_labels, function(lbl) {
        done <- lbl %in% view$done_labels
        is_cur <- !done && identical(lbl, cur)
        row(lbl, done, is_cur, if (is_cur) models)
      })
    )
  }
  shiny::tagList(
    shiny::div(class = "progress", style = "height: 4px; margin: 4px 0 2px;", bar),
    if (length(rows)) shiny::div(
      class = "small", style = paste0("font-size: 12px;",
        if (length(rows) > 8L) " max-height: 160px; overflow-y: auto;" else ""),
      rows)
  )
}


#' 2_01_weathersim Server Functions
#'
#' Handles the unified simulation sidebar: validates settings, runs historical
#' and future simulations on button click, and returns reactive results.
#'
#' @param id               Module id.
#' @param connection_params Reactive named list from mod_0_overview.
#' @param selected_outcome Reactive one-row data frame of selected outcome.
#' @param selected_weather Reactive data frame of selected weather variables.
#' @param selected_surveys Reactive data frame from the survey list.
#' @param survey_weather   Reactive data frame of merged survey-weather data.
#' @param model_fit        Reactive list with fit3, engine, train_data.
#' @param stored_breaks Reactive returning a named list of pre-computed
#'   histogram break points for the weather density plot. Defaults to
#'   \code{reactive(NULL)} - breaks computed on demand when not supplied.
#' @param run_trigger Optional reactive trigger for a programmatic run.
#' @param display_settings Optional reactive list(method, pov_line,
#'   bandwidth_p0) read at submit so the worker streams the Results tab's
#'   current metric.
#'
#' @noRd
mod_2_01_weathersim_server <- function(id,
                                       connection_params,
                                       selected_outcome,
                                       selected_weather,
                                       selected_surveys,
                                       survey_weather,
                                       model_fit,
                                       stored_breaks = reactive(NULL),
                                       survey_version = reactive(0L),
                                       run_trigger = reactive(NULL),
                                       display_settings = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Internal state ----
    hist_sim <- reactiveVal(NULL)
    saved_scenarios <- reactiveVal(list())
    # INT-08: TRUE while the stored simulation's run signature no longer
    # matches the current fit/climate inputs.
    sim_stale <- reactiveVal(FALSE)
    run_generation <- reactiveVal(0L)
    run_status <- reactiveVal("idle")
    run_detail <- reactiveVal(NULL)
    weather_store_lease <- reactiveVal(NULL)
    # File of the retained Step 2 result artifact (CR-PERF-04); removed when
    # the result is replaced and at session end.
    retained_artifact <- reactiveVal(NULL)
    # Streaming state of the current async run (see
    # review/step2_live_run_contract.md) and the partials of the last adopted
    # run. live_hist_at times the historical partial for the ETA.
    live_run <- reactiveVal(NULL)
    adopted_partials <- reactiveVal(NULL)
    live_hist_at <- NULL
    session_ended <- FALSE

    session_callback <- function(fn) {
      force(fn)
      function(...) {
        if (session_ended) return(invisible(FALSE))
        args <- list(...)
        shiny::withReactiveDomain(session, shiny::isolate(do.call(fn, args)))
      }
    }

    cleanup_weather_stores <- function() {
      session_ended <<- TRUE
      # Session-end callbacks are not reactive consumers. Isolate the final
      # state read so cleanup does not try to register a dependency after the
      # session's reactive graph has been torn down.
      step2_weather_store_release(shiny::isolate(weather_store_lease()))
      weather_store_lease(NULL)
      unlink(shiny::isolate(retained_artifact())$file, force = TRUE)
      retained_artifact(NULL)
    }
    session$onSessionEnded(cleanup_weather_stores)

    # Baseline survey reactives ----

    # Derive available survey x year choices from survey_weather.
    # Returns a named character vector: label -> "survname|year" value.

    baseline_survey_choices <- reactive({
      req(survey_weather())
      step2_baseline_choices(
        survey_weather(), tryCatch(selected_surveys(), error = function(e) NULL)
      )
    })

    # Default selection: latest year per unique economy (code), not survname.
    baseline_default <- reactive({
      wise_default_baseline(unname(baseline_survey_choices()))
    })


    # Settings summary banner ----

    output$baseline_survey_ui <- shiny::renderUI({
      ch <- baseline_survey_choices()
      def <- baseline_default()
      if (length(ch) == 0) {
        return(shiny::helpText("No survey data loaded.", style = "font-size:11px;"))
      }
      # INT-01: keep the user's baseline selection across rebuilds (e.g. the
      # survey list changing after a Step 1 reload); only invalid values are
      # dropped, and the default applies only when nothing survives.
      prev_bs <- shiny::isolate(input$baseline_survey)
      shiny::selectInput(
        ns("baseline_survey"),
        label = shiny::tags$span(
          class = "visually-hidden",
          "Baseline survey"
        ),
        choices = ch,
        selected = .restore_selection(prev_bs, ch, fallback = def),
        multiple = TRUE,
        selectize = TRUE
      )
    })
    shiny::outputOptions(output, "baseline_survey_ui",
      suspendWhenHidden = FALSE
    )

    output$baseline_warning_ui <- shiny::renderUI({
      sel <- input$baseline_survey %||% baseline_default()
      if (length(sel) <= 1) {
        return(NULL)
      }
      # Multiple economies or years selected -- show warning
      n_economies <- length(unique(sub("\\|.*$", "", sel)))
      n_years <- length(unique(sub("^.*\\|", "", sel)))
      if (n_economies > 1 || n_years > 1) {
        shiny::helpText(
          shiny::tags$b("\u26a0 Warning:"),
          paste0(
            "Using multiple survey years or economies is not recommended. Requires normalizing weights based on ",
            "sample design, which is not currently implemented - verify before interpreting results."
          ),
          style = "color: #c0392b; font-size: 11px; margin-top: 2px;"
        )
      }
    })

    # Seasonal forecast (scaffold: not part of the simulation run) ----

    forecast_runs <- reactive(.step2_forecast_runs())

    forecast_weather_names <- reactive({
      tryCatch(as.character(selected_weather()$name), error = function(e) character(0))
    })

    # Months the fitted lagged predictors reach back (Step 1 lag windows).
    forecast_lag <- reactive({
      tryCatch(.step2_forecast_lag(selected_weather()), error = function(e) 0L)
    })

    # NULL when the forecast can be used, else the reason it cannot.
    forecast_block <- reactive({
      .step2_forecast_block_reason(
        forecast_runs(), .step2_forecast_unsupported(forecast_weather_names()), forecast_months()
      )
    })

    forecast_run <- reactive({
      runs <- forecast_runs()
      if (!length(runs)) return(NULL)
      runs[[input$fc_run %||% names(runs)[[1L]]]] %||% runs[[1L]]
    })

    forecast_months <- reactive({
      run <- forecast_run()
      if (is.null(run)) return(NULL)
      .step2_forecast_months(run, forecast_lag(), selected_weather())
    })

    forecast_on <- reactive({
      isTRUE(input$fc_include) && is.null(forecast_block()) && !is.null(forecast_window())
    })

    forecast_window <- reactive({
      run <- forecast_run()
      if (is.null(run)) return(NULL)
      .step2_forecast_window(forecast_months(), input$fc_start, input$fc_len %||% "3")
    })

    shiny::observe({
      why <- forecast_block()
      update_input_disabled(session, "fc_include", disabled = !is.null(why), tooltip = why)
    })

    # Keep the start on a complete window when the run, length or fitted lags change.
    shiny::observe({
      w <- forecast_window()
      if (!is.null(w) && !identical(w$start, input$fc_start)) {
        shiny::updateRadioButtons(session, "fc_start", selected = w$start)
      }
    })

    output$forecast_status_ui <- shiny::renderUI({
      why <- forecast_block()
      if (is.null(why) && is.null(forecast_window())) {
        why <- .step2_forecast_block_reason(
          forecast_runs(), character(0), forecast_months(), input$fc_len %||% "3"
        )
      }
      if (!is.null(why)) {
        return(shiny::div(
          class = "alert alert-warning warning-message", role = "alert",
          style = "font-size: 12px; margin: 4px 0;", why
        ))
      }
      if (.step2_forecast_scaffold()) {
        shiny::helpText("Preview only: the forecast is not yet used by simulation runs.")
      }
    })

    output$forecast_body_ui <- shiny::renderUI({
      run <- forecast_run()
      if (is.null(run)) return(NULL)
      runs <- forecast_runs()
      off <- !isTRUE(input$fc_include) || !is.null(forecast_block())
      months <- forecast_months()
      len <- input$fc_len
      if (!isTRUE(len %in% .STEP2_FORECAST_LEN_CHOICES)) len <- "3"
      start <- .step2_forecast_clamp_start(months, shiny::isolate(input$fc_start), len)
      day <- function(d) sub("^0", "", format(d, "%d %b %Y"))
      shiny::tagList(
        shiny::tags$hr(style = "margin: 6px 0;"),
        shiny::tags$div(class = "step2-section-label", "Forecast run"),
        shiny::selectInput(
          ns("fc_run"),
          label = shiny::tags$span(class = "visually-hidden", "Forecast run"),
          choices = stats::setNames(
            names(runs),
            vapply(runs, function(r) {
              paste0(r$label, " \u00b7 ", r$model, ", ", r$n_members, " members")
            }, character(1))
          ),
          selected = run$id, width = "100%"
        ),
        shiny::helpText(paste0(
          "Released ", day(run$released), ". Next run expected ", day(run$next_release), "."
        )),
        shiny::tags$hr(style = "margin: 6px 0;"),
        shiny::tags$div(class = "step2-section-label", "Target window"),
        pill_toggle(
          ns("fc_len"),
          choices = .STEP2_FORECAST_LEN_CHOICES, selected = len,
          disabled = off, aria_label = "Window length"
        ),
        forecast_strip_input(
          ns("fc_start"), ns("fc_len"), months, start, lag = forecast_lag(), disabled = off, len = len
        ),
        forecast_strip_legend()
      )
    })
    shiny::outputOptions(output, "forecast_body_ui", suspendWhenHidden = FALSE)

    output$forecast_readout_ui <- shiny::renderUI({
      w <- forecast_window()
      if (!forecast_on() || is.null(w)) return(NULL)
      lag <- .step2_forecast_lag_text(
        forecast_months(), w, forecast_lag(), selected_weather()
      )
      shiny::tagList(
        shiny::tags$div(
          class = "forecast-readout",
          shiny::tags$span("Target ", shiny::tags$b(w$label)),
          shiny::tags$span(
            "Lead ",
            shiny::tags$b(if (w$lead_from == w$lead_to) w$lead_from else paste0(w$lead_from, "\u2013", w$lead_to))
          )
        ),
        if (!is.null(lag)) shiny::helpText(lag)
      )
    })

    output$forecast_notes_ui <- shiny::renderUI({
      wx <- forecast_weather_names()
      bad <- .step2_forecast_unsupported(wx)
      shiny::tagList(
        if (length(wx)) {
          shiny::tagList(
            shiny::tags$hr(style = "margin: 6px 0;"),
            shiny::tags$div(class = "step2-section-label", "Weather predictors in the fitted model"),
            shiny::tags$div(
              class = "forecast-vars",
              lapply(unique(wx), function(v) {
                ok <- !(v %in% bad)
                shiny::tags$span(
                  class = paste("selection-card-pill", if (!ok) "forecast-var-bad"),
                  paste(v, if (ok) "\u2713" else "\u2717"),
                  shiny::tags$span(
                    class = "visually-hidden",
                    if (ok) "available in the forecast" else "not available in the forecast"
                  )
                )
              })
            )
          )
        },
        if (!is.null(forecast_run())) {
          shiny::helpText(
            "Forecast values are anchored to the ERA5-Land climate by the data pipeline, ",
            "so the historical period in Simulation settings does not change them."
          )
        }
      )
    })

    output$projections_summary <- shiny::renderText({
      n_ssp <- length(input$climate %||% character(0))
      n_per <- sum(!vapply(seq_len(3), function(i) {
        is.null(.step2_valid_future_period(input[[paste0("fut_period_", i)]]))
      }, logical(1)))
      if (n_ssp == 0L) return("None selected")
      paste0(n_ssp, if (n_ssp == 1L) " SSP" else " SSPs", " \u00b7 ",
        n_per, if (n_per == 1L) " period" else " periods")
    })

    output$forecast_summary <- shiny::renderText({
      w <- forecast_window()
      if (!is.null(forecast_block())) "Not available"
      else if (isTRUE(input$fc_include) && is.null(w)) "Window unavailable"
      else if (forecast_on() && !is.null(w)) paste0(w$short, " \u00b7 on")
      else "Off"
    })

    output$settings_summary <- shiny::renderUI({
      hist_yr <- input$hist_years %||% c(1991, 2020)
      ssp_map <- c(
        "ssp2_4_5" = "SSP2-4.5",
        "ssp3_7_0" = "SSP3-7.0",
        "ssp5_8_5" = "SSP5-8.5"
      )
      ssp_sel <- input$climate %||% character(0)
      sel <- input$baseline_survey %||% baseline_default()
      ch <- baseline_survey_choices()
      survey_txt <- {
        nms <- names(ch)[ch %in% sel]
        if (length(nms) == 0) "None" else paste(nms, collapse = ", ")
      }

      period_values <- lapply(seq_len(3), function(i) {
        .step2_valid_future_period(input[[paste0("fut_period_", i)]])
      })
      period_values <- Filter(Negate(is.null), period_values)

      item <- function(label, value, pill = TRUE) {
        shiny::tags$span(
          class = "step2-summary-item",
          shiny::tags$span(class = "step2-summary-label", label),
          if (isTRUE(pill)) {
            shiny::tags$span(class = "selection-card-pill", value)
          } else {
            shiny::tags$span(class = "step2-summary-value", value)
          }
        )
      }
      separator <- shiny::tags$span(class = "step2-summary-separator", "\u00b7")
      scenario_items <- unlist(lapply(ssp_sel, function(ssp) {
        lapply(period_values, function(period) {
          shiny::tags$span(
            class = "step2-summary-item",
            shiny::tags$span(
              class = "step2-summary-label step2-summary-scenario-label",
              unname(ssp_map[[ssp]])
            ),
            shiny::tags$span(
              class = "step2-summary-value",
              paste0(period[1], "\u2013", period[2])
            )
          )
        })
      }), recursive = FALSE)
      climate_items <- if (length(scenario_items)) {
        do.call(c, lapply(seq_along(scenario_items), function(i) {
          c(
            if (i > 1L) list(separator) else list(),
            list(scenario_items[[i]])
          )
        }))
      } else {
        list(item("Climate scenarios", "None", pill = FALSE))
      }

      fc_window <- if (forecast_on()) forecast_window()
      forecast_items <- if (!is.null(fc_window)) {
        list(item("Forecast", fc_window$label), separator)
      }

      summary_row <- c(
        forecast_items,
        climate_items,
        list(separator),
        list(item("Reference climate", paste0(hist_yr[1], "\u2013", hist_yr[2]))),
        list(separator),
        list(item("Baseline survey", survey_txt))
      )

      selection_summary_card(
        title = NULL,
        badge = NULL,
        rows = list(shiny::tags$div(
          class = "selection-card-row step2-summary-row",
          summary_row
        )),
        compact = TRUE
      )
    })

    # 30-year minimum window warning ----

    output$hist_years_warning <- shiny::renderUI({
      req(input$hist_years)
      if (length(input$hist_years[1]:input$hist_years[2]) < 30) {
        shiny::helpText(
          paste0(
            "\u26a0\ufe0f Window is less than 30 years. This may not capture the full range of weather variability, ",
            "which could lead to underestimation of future risks."
          ),
          style = "color: #c0392b; font-size: 12px;"
        )
      }
    })

    # Display-only check for fully supplied future periods with end < start or
    # a start before the SSP projections. Mirrors future_periods() below, which
    # excludes such periods; Run is not disabled.
    output$fut_years_warning <- shiny::renderUI({
      issues <- character(0)
      for (i in 1:3) {
        period <- input[[paste0("fut_period_", i)]]
        if (length(period) >= 2 && all(is.finite(period)) && period[2] < period[1]) {
          issues <- c(issues, paste0(
            "Period ", i, " (", period[1], "-", period[2],
            "): end year is not after start year."
          ))
        } else if (length(period) >= 2 && all(is.finite(period)) &&
                   period[2] > period[1] && period[1] < .STEP2_SSP_START_YEAR) {
          issues <- c(issues, paste0(
            "Period ", i, " (", period[1], "-", period[2],
            "): starts before ", .STEP2_SSP_START_YEAR,
            ", the first year of the climate projections."
          ))
        }
      }
      if (length(issues) == 0) {
        return(NULL)
      }
      shiny::helpText(
        shiny::tags$b("Warning:"),
        " invalid projection period(s) will be excluded from the simulation: ",
        paste(issues, collapse = " "),
        style = "color: #c0392b; font-size: 11px; margin-top: 2px;"
      )
    })

    # Derived config reactives ----

    # survey_weather filtered to the selected baseline rows and to the
    # households the model can predict for (complete weather and model data).
    # Returns list(svy, dropped); NULL, with a notification, when none is left.
    baseline_run <- function(sw, so, mf) {
      tryCatch(
        step2_baseline_run(
          survey_weather(), input$baseline_survey %||% baseline_default(), sw, mf, so
        ),
        error = function(e) {
          shiny::showNotification(wise_user_error(e, "Simulation"), type = "error", duration = NULL)
          NULL
        }
      )
    }

    # Keep weather retrieval on the same code/year waves as the baseline
    # population. Retain every matching metadata row so same-year survey rounds
    # and duplicate file references keep their existing filename semantics.
    baseline_surveys <- reactive({
      ss <- selected_surveys()
      req(ss)
      sel <- input$baseline_survey %||% baseline_default()
      .step2_filter_baseline_surveys(ss, sel)
    })

    selected_hist <- reactive({
      req(input$hist_years)
      data.frame(
        type = "historical",
        year_range = I(list(input$hist_years)),
        residuals = input$residuals %||% "original",
        scenario_name = step2_hist_label(input$hist_years),
        stringsAsFactors = FALSE
      )
    })

    future_periods <- reactive({
      periods <- list()
      for (i in 1:3) {
        period <- input[[paste0("fut_period_", i)]]
        if (!is.null(.step2_valid_future_period(period))) {
          periods[[length(periods) + 1L]] <- period[1:2]
        }
      }
      periods
    })

    selected_fut <- reactive({
      req(input$climate)
      fp <- future_periods()
      if (length(fp) == 0) {
        return(NULL)
      }

      ssp_choices <- c(
        "ssp2_4_5" = "SSP2-4.5",
        "ssp3_7_0" = "SSP3-7.0",
        "ssp5_8_5" = "SSP5-8.5"
      )

      rows <- lapply(input$climate, function(ssp) {
        prefix <- ssp_choices[[ssp]]
        lapply(fp, function(yr) {
          scene_name <- paste0(prefix, " / ", yr[1], "-", yr[2])
          data.frame(
            type = "future",
            year_range = I(list(yr)),
            ssp = ssp,
            method = "delta",
            residuals = input$residuals %||% "original",
            scenario_name = scene_name,
            stringsAsFactors = FALSE
          )
        })
      })

      do.call(rbind, do.call(c, rows))
    })

    # Run simulation button (hidden for non-linear or RIF engine) ----

    output$run_sim_ui <- shiny::renderUI({
      mf <- model_fit()
      engine <- if (!is.null(mf)) mf$engine %||% "fixest" else "fixest"

      # Block only unsupported engines - linear (fixest) and RIF both supported
      unsupported <- !is.null(mf) &&
        !engine %in% c("fixest", "rif")

      # UI-29: name the missing prerequisites before the click instead of
      # letting the button silently no-op (the click observer req()s on all
      # of these).
      missing <- character(0)
      swd <- tryCatch(selected_weather(), error = function(e) NULL)
      so <- tryCatch(selected_outcome(), error = function(e) NULL)
      svy <- tryCatch(survey_weather(), error = function(e) NULL)
      ss <- tryCatch(selected_surveys(), error = function(e) NULL)
      hist_ok <- tryCatch(
        {
          selected_hist()
          TRUE
        },
        error = function(e) FALSE
      )
      if (is.null(so) || nrow(as.data.frame(so)) == 0) {
        missing <- c(missing, "an outcome")
      }
      if (is.null(swd) || nrow(as.data.frame(swd)) == 0) {
        missing <- c(missing, "weather variables")
      }
      if (is.null(svy) || nrow(as.data.frame(svy)) == 0) {
        missing <- c(missing, "survey and weather data")
      }
      if (is.null(ss) || nrow(as.data.frame(ss)) == 0) {
        missing <- c(missing, "a baseline survey")
      }
      if (!hist_ok) {
        missing <- c(missing, "a historical period")
      }
      if (is.null(mf)) {
        missing <- c(missing, "a fitted Step 1 model (run the Step 1 model first)")
      }

      if (unsupported) {
        shiny::div(
          class = "alert alert-warning",
          style = "font-size: 13px; margin-top: 4px;",
          shiny::tags$b(
            "\u26a0 Simulations are not yet implemented for ",
            engine, " models."
          ),
          " Please select a linear or RIF model engine to run simulations."
        )
      } else {
        shiny::tagList(
          if (length(missing)) {
            shiny::div(
              class = "alert alert-warning warning-message",
              role = "alert",
              style = "font-size: 13px; margin-top: 4px;",
              shiny::tags$b("To run the simulation, first select "),
              paste(missing, collapse = ", "), "."
            )
          },
           shiny::actionButton(
             ns("run_sim"),
             label = "Run simulation",
             class = "btn-primary",
             icon = shiny::icon("play"),
             style = "width: 100%; margin-top: 4px;",
              disabled = length(missing) > 0 || run_status() %in% c("queued", "running", "adopting")
           ),
            if (run_status() %in% c("queued", "running", "adopting")) {
             shiny::tagList(
                shiny::div(
                  class = "text-muted",
                  style = "font-size: 12px; margin-top: 5px;",
                   shiny::icon("spinner"),
                  shiny::textOutput(ns("simulation_progress"), inline = TRUE)
               ),
               shiny::uiOutput(ns("run_progress_ui")),
               shiny::actionButton(
                 ns("stop_sim"), "Stop simulation",
                 class = "btn btn-link btn-sm text-muted p-0",
                 style = "font-size: 12px; margin-top: 2px;"
                )
              )
            },
            if (run_status() %in% c("cancelled", "stale")) {
              shiny::tags$p(class = "small text-muted mt-1",
                shiny::textOutput(ns("simulation_progress"), inline = TRUE))
            }
         )
      }
    })

    # Run simulation on button click ----

    # REACT-02: one simulation at a time - double-clicks are ignored and the
    # button is disabled for the duration of the run.
    sim_guard <- .busy_guard(session, run_sim)
    async_job_id <- shiny::reactiveVal(NULL)
    pending_submission <- FALSE
    submission_sequence <- 0L
    session$onSessionEnded(function() {
      session_ended <<- TRUE
      try(shiny::isolate(live_run(NULL)), silent = TRUE)
      pending_submission <<- FALSE
      submission_sequence <<- submission_sequence + 1L
      .wise_step2_async_detach_session(session$token)
    })

    output$simulation_progress <- shiny::renderText({
      lr <- live_run()
      paste0(" ", run_detail() %||% "Simulation running",
        if (!is.null(lr$eta_seconds)) paste0(" | ", .step2_eta_text(lr$eta_seconds)))
    })

    # The bar and checklist re-render only when their inputs change, not on
    # every progress tick (elapsed/eta live in live_run only).
    live_view <- shiny::reactiveVal(NULL)
    shiny::observe({
      lr <- live_run()
      view <- if (is.null(lr)) NULL else list(
        has_hist = !is.null(lr$partials$historical),
        done_labels = names(lr$partials$scenarios) %||% character(0),
        groups_total = lr$groups_total, groups_done = lr$groups_done,
        scenario_labels = lr$scenario_labels, current_label = lr$current_label,
        member_index = lr$member_index, period_members = lr$period_members
      )
      if (!identical(shiny::isolate(live_view()), view)) live_view(view)
    })
    output$run_progress_ui <- shiny::renderUI({
      if (!run_status() %in% c("queued", "running", "adopting")) return(NULL)
      view <- live_view()
      if (is.null(view)) return(.step2_progress_ui(list()))
      .step2_progress_ui(view)
    })

    shiny::observeEvent(input$stop_sim, {
      job_id <- async_job_id()
      if (!is.null(job_id) || pending_submission) {
        pending_submission <<- FALSE
        submission_sequence <<- submission_sequence + 1L
        if (!is.null(job_id)) .wise_step2_async_cancel(job_id)
        async_job_id(NULL)
        run_generation(run_generation() + 1L)
        live_run(NULL)
        run_status("cancelled")
        run_detail("Cancelled; the worker will finish its current operation before another run starts")
        sim_guard$end()
      }
    }, ignoreInit = TRUE)


    # Run signature (INT-08) ----
    # Everything the simulation depends on, captured at run time into the
    # result and recomputed from live inputs for the staleness comparison.

    .sim_sig_from_live <- function(fit_sig) {
      sig <- list(
        step = "sim",
        fit_sig = fit_sig,
        survey_version = survey_version(),
        selected_surveys = .sig_plain(selected_surveys()),
        hist_years = input$hist_years,
        climate = input$climate,
        future_periods = future_periods(),
        fut_sel = .sig_plain(selected_fut()),
        baseline_survey = input$baseline_survey,
        residuals = input$residuals,
        skip_coef_draws = !isTRUE(input$include_coef_uncertainty)
      )
      # Added only when the forecast is on, so runs without it keep their signature.
      if (forecast_on()) {
        sig$forecast <- .step2_forecast_signature(forecast_run(), forecast_window())
      }
      sig
    }

    live_sim_sig <- reactive({
      mf <- model_fit()
      .sim_sig_from_live(mf$.sig %||% NULL)
    })

    stale_dependencies <- reactive(list(
      model_fit(), survey_version(), selected_surveys(),
      input$hist_years, input$climate,
      input$baseline_survey, input$residuals, input$include_coef_uncertainty,
      input$fut_period_1, input$fut_period_2, input$fut_period_3,
      input$fc_include, input$fc_run, input$fc_start, input$fc_len
    ))

    observeEvent(stale_dependencies(),
      {
        hs <- hist_sim()
        if (!is.null(hs) && !identical(live_sim_sig(), hs$.sig)) {
          sim_stale(TRUE)
        }
        if (!is.null(async_job_id())) {
          job <- get0(async_job_id(), envir = .wise_step2_async_state$jobs)
          if (!is.null(job) && !identical(live_sim_sig(), job$dependency_signature)) {
            .wise_step2_async_cancel(job$id, "Inputs changed.")
            async_job_id(NULL)
            run_generation(run_generation() + 1L)
            live_run(NULL)
            run_status("stale")
            run_detail("Inputs changed; run the simulation again")
            sim_guard$end()
          }
        }
      },
      ignoreInit = TRUE
    )

    observeEvent(hist_sim(), sim_stale(FALSE))

    sim_run_event <- shiny::reactiveVal(NULL)
    shiny::observeEvent(input$run_sim,
      {
        if (shiny::isTruthy(input$run_sim)) {
          sim_run_event(list(source = "manual", value = input$run_sim))
        }
      },
      ignoreInit = FALSE,
      ignoreNULL = TRUE
    )
    shiny::observeEvent(run_trigger(),
      {
        ext <- run_trigger()
        if (!is.null(ext)) sim_run_event(list(source = "pipeline", value = ext))
      },
      ignoreInit = FALSE,
      ignoreNULL = TRUE
    )

    # Use a reactive handoff rather than later::later(): the submission
    # function reads reactive inputs and therefore must execute inside Shiny's
    # reactive context. The click observer only paints the immediate queued
    # state, then this observer captures the snapshot safely.
    async_clicked_at_epoch <- shiny::reactiveVal(NA_real_)

    submit_step2_async <- function() {
      shiny::isolate({
      if (session_ended) return(invisible(NULL))
      if (!sim_guard$begin()) {
        return(invisible(NULL))
      }
      submitted <- FALSE
      on.exit(if (!submitted) {
        sim_guard$end()
        if (!session_ended && identical(shiny::isolate(run_status()), "queued")) {
          run_status("failure")
          run_detail("Simulation inputs are not ready; check the selected settings")
        }
      }, add = TRUE)
      req(
        selected_weather(), selected_outcome(), survey_weather(),
        selected_hist(), model_fit()
      )
      sw <- selected_weather()
      so <- selected_outcome()
      sh <- selected_hist()
      ss <- baseline_surveys()
      req(ss)
      mf <- model_fit()
      baseline <- baseline_run(sw, so, mf)
      req(baseline)
      svy <- baseline$svy
      cp <- connection_params()
      fut_periods <- future_periods()
      sf <- selected_fut()
      # R2-PERF-02: the worker gets a slim copy of the model fit (no fit1/fit2,
      # no captured fitting environments); the live fit stays untouched.
      step2_input <- wise_step2_input(
        sw, so, svy, ss, mf, .wise_step2_async_connection_params(cp),
        hist_years = unlist(sh$year_range), periods = fut_periods, ssps = sf$ssp,
        residuals = sh$residuals, coef_uncertainty = input$include_coef_uncertainty,
        stored_breaks = stored_breaks(), slim = TRUE
      )
      ssps <- step2_input$ssps
      fp_list <- step2_input$fp_list
      generation <- run_generation() + 1L
      run_generation(generation)
      dependency_signature <- .sim_sig_from_live(mf$.sig %||% NULL)
      captured_baseline <- step2_baseline_label(
        baseline_survey_choices(), input$baseline_survey %||% baseline_default()
      )
      snapshot <- list(input = c(step2_input, list(
        weather_storage = match.arg(
          Sys.getenv("WISEAPP_STEP2_WEATHER_STORAGE", "memory"),
          c("memory", "reference")
        ),
        weather_collect = match.arg(
          Sys.getenv("WISEAPP_STEP2_WEATHER_COLLECT", "fast"),
          c("fast", "bounded")
        ),
        weather_threads = match.arg(
          Sys.getenv("WISEAPP_STEP2_WEATHER_THREADS", "auto"),
          c("auto", "1", "2")
        ),
        display = isolate(display_settings())
      )))
      live_hist_at <<- NULL
      adopted_partials(NULL)
      started_at <- Sys.time()
      live_run(list(
        generation = generation, dependency_signature = dependency_signature,
        status = "queued", started_at = started_at, elapsed = 0,
        groups_total = length(ssps) * length(fp_list), groups_done = 0L,
        scenario_labels = .step2_scenario_labels(ssps, fut_periods),
        current_label = NULL, member_index = NULL, period_members = NULL,
        eta_seconds = NULL,
        display = isolate(display_settings()),
        partials = list(historical = NULL, scenarios = list())
      ))
      run_status("queued")
      clicked_at_epoch <- async_clicked_at_epoch()
      job <- tryCatch(
        .wise_step2_async_submit(
           snapshot = snapshot,
           generation = generation,
           session_id = session$token,
           seed = wise_current_seed(),
           dependency_signature = dependency_signature,
           clicked_at_epoch = clicked_at_epoch,
          on_status = session_callback(function(status, job, detail) {
            if (identical(job$generation, run_generation())) {
              run_status(status)
              lr <- live_run()
              if (status %in% c("cancelled", "failed", "stale")) {
                live_run(NULL)
              } else if (!is.null(lr)) {
                lr$status <- status
                live_run(lr)
              }
              if (identical(status, "queued")) run_detail("Simulation queued; waiting for the shared worker")
              if (identical(status, "running")) run_detail("Dispatched; waiting for worker acknowledgement")
              if (identical(status, "adopting")) run_detail("Loading completed results")
            }
          }),
          on_progress = session_callback(function(record, job) {
            if (!identical(job$generation, run_generation()) ||
                !identical(live_sim_sig(), job$dependency_signature)) return(invisible(FALSE))
            phase_labels <- c(
              worker_started = "Worker started", initialize = "Initializing simulation",
              weather = "Loading weather", pipeline = "Predicting welfare",
              simulation = "Computing scenarios", historical_ready = "Historical prediction ready",
              preview_ready = "Historical preview ready; computing future scenarios",
              group_completed = "Summarising scenario results",
              finalizing = "Finalizing simulation", writing_result = "Writing completed results",
              result_written = "Results written", manifest_written = "Results ready to load"
            )
            label <- unname(phase_labels[record$phase])
            if (length(label) != 1L || is.na(label)) label <- "Simulation running"
            if (!is.null(record$completed)) label <- paste0(label, " (", record$completed, " predictions completed)")
            run_detail(paste0(label, " | ", round(record$elapsed), " s"))
            lr <- live_run()
            if (!is.null(lr)) {
              lr$elapsed <- as.numeric(record$elapsed)
              lr$status <- "running"
              if (!is.null(record$groups_total)) lr$groups_total <- record$groups_total
              if (!is.null(record$groups_done)) lr$groups_done <- record$groups_done
              lr$current_label <- record$current_label
              lr$member_index <- record$member_index
              lr$period_members <- record$period_members
              lr$eta_seconds <- .step2_live_eta(
                lr$groups_done, lr$groups_total, live_hist_at %||% lr$started_at
              )
              live_run(lr)
            }
            invisible(TRUE)
          }),
          on_partial = session_callback(function(partial, job) {
            if (!identical(job$generation, run_generation()) ||
                !identical(live_sim_sig(), job$dependency_signature)) return(invisible(FALSE))
            lr <- live_run()
            if (is.null(lr)) return(invisible(FALSE))
            if (identical(partial$kind, "historical")) {
              live_hist_at <<- Sys.time()
              lr$partials$historical <- partial
            } else {
              lr$partials$scenarios[[partial$label]] <- partial
            }
            if (!isTRUE(lr$groups_total > 0L) && !is.null(partial$groups_total)) {
              lr$groups_total <- as.integer(partial$groups_total)
            }
            live_run(lr)
            invisible(TRUE)
          }),
          on_result = session_callback(function(manifest, job) {
            if (!identical(job$generation, run_generation()) ||
                !identical(live_sim_sig(), job$dependency_signature)) {
              sim_stale(TRUE)
              run_status("stale")
              async_job_id(NULL)
              live_run(NULL)
              sim_guard$end()
              return(invisible(FALSE))
            }
            result <- wise_step2_annotate(
              .wise_step2_async_read_manifest(manifest, job),
              sw, unlist(sh$year_range), captured_baseline, baseline$dropped,
              attr(step2_input, "residual_match"), sh$residuals,
              step2_input$residuals
            )
             result$hist_sim_result$.sig <- job$dependency_signature
             committed <- .wise_step2_async_commit(job, function() {
               if (session_ended || !identical(job$generation, run_generation()) ||
                   !identical(live_sim_sig(), job$dependency_signature)) return(FALSE)
               old_lease <- weather_store_lease()
               new_lease <- step2_weather_store_acquire(result$weather_store %||% NULL)
               adopted <- FALSE
               on.exit(if (!adopted) step2_weather_store_release(new_lease), add = TRUE)
               new_artifact <- .wise_step2_async_retain_result(job, result$.sig)
               on.exit(if (!adopted) unlink(new_artifact$file, force = TRUE), add = TRUE)
               old_artifact <- retained_artifact()
               if (!is.null(new_artifact)) {
                 new_artifact$scenario_names <- names(result$new_scenarios)
               }
               result$hist_sim_result$.artifact <- new_artifact
               # R2-PERF-01: the Step 3 workers read member weather from the
               # retained artifact, so this process does not keep it.
               if (.step3_release_allowed(new_artifact)) {
                 result$new_scenarios <- .step3_release_member_weather(result$new_scenarios)
               }
               sim_stale(FALSE)
               weather_store_lease(new_lease)
               retained_artifact(new_artifact)
               hist_sim(result$hist_sim_result)
               saved_scenarios(result$new_scenarios)
               adopted_partials(list(
                 dependency_signature = job$dependency_signature,
                 partials = live_run()$partials %||%
                   list(historical = NULL, scenarios = list())
               ))
               live_run(NULL)
               adopted <- TRUE
               step2_weather_store_release(old_lease)
               unlink(old_artifact$file, force = TRUE)
               TRUE
             })
             if (!isTRUE(committed)) {
               live_run(NULL)
               return(committed)
             }
            run_status("success")
             run_detail("Results ready")
            async_job_id(NULL)
            sim_guard$end()
            sim_failures <- result$failures %||% list()
            if (length(sim_failures) > 0L) {
              fail_txt <- paste(vapply(sim_failures, function(f) {
                sprintf("%s: %s", f$key, f$error)
              }, character(1)), collapse = "\n")
              shiny::showNotification(
                ui = tagList(
                  tags$b("Simulation completed with some scenarios unavailable."),
                  tags$br(), tags$details(tags$summary("Show details"),
                    tags$div(style = "font-size: 12px; white-space: pre-wrap;", fail_txt)
                  )
                ), type = "warning", duration = NULL
              )
            } else {
              shiny::showNotification(
                "Climate scenario results are ready.", type = "message", duration = 3
              )
            }
            .notify_baseline_dropped(baseline$dropped)
            .notify_residual_match(attr(step2_input, "residual_match"))
            .notify_data_quality(result$data_quality)
             invisible(TRUE)
           }),
           on_error = session_callback(function(error, job) {
            if (identical(job$generation, run_generation())) {
              run_status("failure")
               async_job_id(NULL)
               live_run(NULL)
              sim_guard$end()
              shiny::showNotification(
                wise_user_error(error, "Simulation"),
                type = "error", duration = 8
              )
            }
           })
        ),
        error = function(e) {
          run_status("failure")
          live_run(NULL)
          sim_guard$end()
          shiny::showNotification(
            wise_user_error(e, "Simulation"),
            type = "error", duration = 8
          )
          NULL
        }
      )
      if (!is.null(job)) {
        submitted <- TRUE
        if (!isTRUE(job$settled)) async_job_id(job$id)
      }
      invisible(NULL)
      })
    }

    observeEvent(sim_run_event(),
      {
        if (.wise_step2_async_enabled()) {
          if (sim_guard$is_running() || pending_submission) return(invisible(NULL))
          pending_submission <<- TRUE
          submission_sequence <<- submission_sequence + 1L
          request_sequence <- submission_sequence
          # Return control to httpuv once the immediate queued state is
          # invalidated. Snapshot construction can be expensive, so deferring
          # it by one event-loop turn lets the user see progress instantly.
          run_status("queued")
          run_detail("Preparing simulation")
          async_clicked_at_epoch(as.numeric(Sys.time()))
          # Defer only the reactive signal. The callback must not read a
          # reactive value outside Shiny's context; the observer below performs
          # all reactive reads on the next event-loop turn.
          session$onFlushed(function() {
            later::later(function() {
              if (!session_ended && pending_submission &&
                  identical(request_sequence, submission_sequence)) {
                pending_submission <<- FALSE
                shiny::withReactiveDomain(session, submit_step2_async())
              }
            }, delay = 0)
          }, once = TRUE)
          return(invisible(NULL))
        }
        run_generation(run_generation() + 1L)
        adopted_partials(NULL)
        run_status("running")
        completed <- FALSE
        on.exit(
          {
            if (!completed) run_status("failure")
          },
          add = TRUE
        )
        req(
          selected_weather(), selected_outcome(),
          survey_weather(), selected_hist(), model_fit()
        )
        if (!sim_guard$begin()) {
          return(invisible(NULL))
        }
        on.exit(sim_guard$end(), add = TRUE)

        # Gather inputs ----
        sw <- selected_weather()
        so <- selected_outcome()
        sh <- selected_hist()
        ss <- baseline_surveys()
        req(ss)
        mf <- model_fit()
        baseline <- baseline_run(sw, so, mf)
        req(baseline)
        svy <- baseline$svy
        cp <- connection_params()
        fut_periods <- future_periods()
        sf <- selected_fut()

        # Residuals are forced to "none" for RIF (delta method, no residual
        # draw) and the RIF quantile fits travel with the input.
        step2_input <- wise_step2_input(
          sw, so, svy, ss, mf, cp,
          hist_years = unlist(sh$year_range), periods = fut_periods, ssps = sf$ssp,
          residuals = sh$residuals, coef_uncertainty = input$include_coef_uncertainty,
          stored_breaks = stored_breaks(), slim = FALSE
        )

        shiny::withProgress(message = "Running climate simulation...", value = 0, {
          # Run simulation ----
          result <- tryCatch(
            do.call(fct_run_simulation, c(step2_input, list(
              weather_storage = match.arg(
                Sys.getenv("WISEAPP_STEP2_WEATHER_STORAGE", "memory"),
                c("memory", "reference")
              ),
              weather_collect = match.arg(
                Sys.getenv("WISEAPP_STEP2_WEATHER_COLLECT", "fast"),
                c("fast", "bounded")
              ),
              weather_threads = match.arg(
                Sys.getenv("WISEAPP_STEP2_WEATHER_THREADS", "auto"),
                c("auto", "1", "2")
              ),
              direct_rif_predictions = TRUE,
              seed = wise_current_seed(),
              payload_mode = "compact",
              progress_fn = function(value, detail) {
                shiny::setProgress(
                  value = value,
                  detail = detail
                )
              }
            ))),
            error = function(e) {
              shiny::showNotification(
                wise_user_error(e, "Simulation"),
                type = "error", duration = 8
              )
              NULL
            }
          )
          req(!is.null(result))

          # Store results (reactive side effects) ----
          # Aggregation now happens lazily in mod_2_02_results.R via the analytic
          # delta method - no pre-aggregation step here.
          # INT-05: bind the historical scenario label into the result so the
          # Step 3 pane describes the simulated run, not the live selection.
          result <- wise_step2_annotate(
            result, sw, unlist(sh$year_range),
            step2_baseline_label(
              baseline_survey_choices(), input$baseline_survey %||% baseline_default()
            ),
            baseline$dropped, attr(step2_input, "residual_match"),
            sh$residuals, step2_input$residuals
          )
          # INT-08: the immutable run signature travels with the result so
          # Step 3 can detect that it is consuming a superseded simulation.
          result$hist_sim_result$.sig <- .sim_sig_from_live(mf$.sig %||% NULL)
          sim_stale(FALSE)
          old_lease <- weather_store_lease()
          weather_store_lease(result$weather_store_lease %||% NULL)
          hist_sim(result$hist_sim_result)
          saved_scenarios(result$new_scenarios)
          step2_weather_store_release(old_lease)
          run_status("success")
          completed <- TRUE

          shiny::setProgress(value = 1, detail = "Results ready")
        })

        # REACT-12: partial failures get a prominent persistent warning ----
        # (Historical or whole-group failures throw inside fct_run_simulation,
        # so reaching this point means results are publishable.)
        sim_failures <- result$failures %||% list()
        if (length(sim_failures) > 0L) {
          fail_txt <- paste(vapply(sim_failures, function(f) {
            sprintf("%s: %s", f$key, f$error)
          }, character(1)), collapse = "\n")
          shiny::showNotification(
            ui = tagList(
              tags$b("Simulation completed with some scenarios unavailable."),
              tags$br(),
              tags$details(
                tags$summary("Show details"),
                tags$div(
                  style = "font-size: 12px; white-space: pre-wrap;",
                  fail_txt
                )
              )
            ),
            type = "warning", duration = NULL
          )
        }

        # Completion notification ----
        message(sprintf(
          "[wiseapp] TOTAL wall time: %s | weather: %s | pipelines: %s | %d/%d key(s)",
          format_elapsed(result$t_elapsed),
          format_elapsed(result$t_weather %||% 0),
          format_elapsed(result$t_elapsed - (result$t_weather %||% 0)),
          result$n_keys_ok %||% result$n_keys, result$n_keys
        ))

        if (!length(sim_failures)) {
          shiny::showNotification(
            "Climate scenario results are ready.",
            type = "message", duration = 3
          )
        }
        .notify_baseline_dropped(baseline$dropped)
        .notify_residual_match(attr(step2_input, "residual_match"))
        .notify_data_quality(result$data_quality)
      },
      ignoreInit = TRUE
    )


    # Return API ----

    list(
      hist_sim = hist_sim,
      saved_scenarios = saved_scenarios,
      selected_hist = selected_hist,
      residuals = reactive(input$residuals %||% "original"),
      skip_coef_draws = reactive(!isTRUE(input$include_coef_uncertainty)),
      # The "all covariates" control was removed (F3): it changed nothing.
      propagate_all_covariate_uncertainty = reactive(FALSE),
      stale = sim_stale,
      run_generation = run_generation,
      run_status = run_status,
      live_run = live_run,
      adopted_partials = adopted_partials
    )
  })
}
