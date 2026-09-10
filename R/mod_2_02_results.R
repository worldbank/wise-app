#' 2_02_results UI Function
#'
#' @description A shiny Module. Renders the Results tab content: point-range
#'   chart, threshold table/bar, and exceedance curve. Consolidates logic from
#'   the former mod_2_02_historical_sim (tab insertion) and
#'   mod_2_06_sim_compare (all visualisations).
#'
#' @param id Internal parameter for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_2_02_results_ui <- function(id) {
  # Placeholder - the real content is injected via insertUI in the server.
  tagList()
}


#' Results tab content UI (inserted into the Results tabPanel once).
#' @noRd
.results_content_ui <- function(ns, so, weather_var = NULL) {
  so_name  <- if (!is.null(so) && "name" %in% names(so) && !is.null(so[["name"]])) as.character(so[["name"]][1]) else "welfare"
  so_type  <- if (!is.null(so) && "type" %in% names(so) && !is.null(so[["type"]])) as.character(so[["type"]][1]) else "numeric"
  so_label <- if (!is.null(so) && "label" %in% names(so) && !is.null(so[["label"]])) as.character(so[["label"]][1]) else so_name
  so_level <- if (!is.null(so) && "level" %in% names(so) && !is.null(so[["level"]])) as.character(so[["level"]][1]) else ""

  outcome_lbl <- tolower(so_label)
  unit_lbl <- switch(tolower(so_level),
    ind  = "individuals",
    firm = "firms",
    "households"
  )
  panel_title <- paste0("How to summarise ", outcome_lbl, " across ", unit_lbl, "?")

  wx_phrase <- format_weather_heading_phrase(weather_var)
  sec1_heading <- if (nzchar(wx_phrase)) {
    paste0("How is ", outcome_lbl, " predicted to vary with ", wx_phrase, " across climate scenarios?")
  } else {
    paste0("How is ", outcome_lbl, " predicted to vary across climate scenarios and weather years?")
  }

  agg_choices <- hist_aggregate_choices(so_type, so_name)

  pov_units <- if (!is.null(so) && "units" %in% names(so) && !is.null(so[["units"]]) && nzchar(as.character(so[["units"]][1]))) {
    as.character(so[["units"]][1])
  } else {
    "$/day, 2021 PPP"
  }
  pov_val <- if (!is.null(so) && "povline" %in% names(so) && !is.null(so[["povline"]]) && is.finite(so[["povline"]][1]) && so[["povline"]][1] > 0) {
    so[["povline"]][1]
  } else {
    3.00
  }

  tagList(
    # ---- 0. Stale banner (INT-08) -------------------------------------------
    shiny::uiOutput(ns("stale_banner")),
    shiny::uiOutput(ns("simulation_summary_ui")),
    shiny::uiOutput(ns("headline_cards_ui")),

    # ---- 1. Analysis controls: Aggregation method & poverty line ------------
    shiny::div(
      class = "results-aggregation-panel",
      shiny::div(
        class = "results-aggregation-head",
        style = "margin-bottom: 8px;",
        shiny::h5(
          panel_title,
          info_popover(
            title = "Aggregation method",
            shiny::p(
              "Choose how household-level welfare is aggregated into an annual",
              "population outcome for each simulated weather year and climate model.",
              "Poverty and prosperity metrics evaluate outcomes relative to the",
              "specified poverty line."
            )
          ),
          style = "font-size: 0.92rem; font-weight: 700; color: #173042; margin: 0;"
        )
      ),
      shiny::div(
        style = "display: flex; align-items: center; gap: 14px; flex-wrap: wrap;",
        pill_toggle(
          inputId  = ns("cmp_agg_method"),
          label    = NULL,
          choices  = agg_choices,
          selected = "mean",
          layout   = "horizontal"
        ),
        shiny::conditionalPanel(
          condition = paste0(
            "['headcount_ratio','gap','fgt2','prosperity_gap','avg_poverty']",
            ".indexOf(input['", ns("cmp_agg_method"), "']) > -1"
          ),
          shiny::div(
            style = "display: flex; align-items: center; gap: 6px;",
            shiny::tags$label(
              `for` = ns("pov_line"),
              style = "font-size: 0.8rem; font-weight: 600; color: #526575; margin: 0; white-space: nowrap;",
              paste0("Poverty line (", pov_units, "):")
            ),
            shiny::numericInput(
              ns("pov_line"),
              label = NULL,
              value = pov_val,
              min   = 0,
              step  = 0.5,
              width = "105px"
            )
          )
        )
      )
    ),

    # ---- Section 1: Central outcomes & weather-year variation ---------------
    shiny::div(
      class = "results-section-card",
      shiny::div(
        style = "display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 10px; margin-bottom: 8px;",
        shiny::h4(
          sec1_heading,
          info_popover(
            title = "Annual weather variation",
            shiny::p(
              "Each dot represents the population aggregate outcome under one simulated",
              "weather year. The box and violin illustrate the full range of annual",
              "weather-year variation for the fixed baseline population under each",
              "climate regime."
            ),
            shiny::p(
              "The dashed horizontal line marks the historical baseline mean. The white diamond",
              "shows the central expected outcome."
            ),
            docs = TRUE
          ),
          style = "font-size: 1.05rem; font-weight: 700; color: #173042; margin: 0;"
        ),
        shiny::div(
          style = "display: flex; align-items: center; gap: 8px;",
          pill_toggle(
            ns("cmp_deviation"),
            label    = NULL,
            choices  = c(
              "Outcome level"                   = "none",
              "Change from historical mean"     = "mean",
              "Change from historical median"   = "median"
            ),
            selected = "none",
            layout   = "horizontal"
          )
        )
      ),
      shiny::div(
        style = "margin-bottom: 8px;",
        shiny::uiOutput(ns("scenario_filter_ui"))
      ),
      wise_plot_output(
        ns("annual_distribution_plot"),
        "Distribution of annual aggregates across simulated weather years by climate scenario",
        height = "420px"
      ),
      shiny::tags$p(
        class = "text-muted small",
        style = "margin-top: 8px; margin-bottom: 0;",
        "Each dot is one simulated weather-year annual aggregate for the fixed baseline population. Boxes show interquartile ranges; diamonds show scenario means. This captures weather-year variability, not household inequality."
      )
    ),

    # ---- Section 2: Adverse weather years (tail risk) -----------------------
    shiny::div(
      class = "results-section-card",
      shiny::div(
        style = "display: flex; justify-content: space-between; align-items: flex-start; flex-wrap: wrap; gap: 10px; margin-bottom: 8px;",
        shiny::h4(
          "What outcomes are predicted in adverse weather years?",
          info_popover(
            title = "Adverse weather-year risk",
            shiny::p(
              "Adverse return-period outcomes represent severe annual weather conditions.",
              "An adverse 1-in-10-year outcome is reached or exceeded in the unfavorable",
              "direction in approximately one out of ten simulated weather years."
            ),
            shiny::p(
              "Points show expected outcomes and adverse-year thresholds; intervals",
              "show disagreement across CMIP6 climate models (ensemble spread)."
            ),
            docs = TRUE
          ),
          style = "font-size: 1.05rem; font-weight: 700; color: #173042; margin: 0;"
        ),
        shiny::div(
          style = "display: flex; align-items: center; gap: 8px;",
          shiny::tags$span(style = "font-size: 0.8rem; font-weight: 600; color: #526575; white-space: nowrap;", "Model spread:"),
          shiny::selectInput(
            ns("ensemble_band"),
            label    = NULL,
            choices  = c(
              "Full range (min-max)" = "minmax",
              "95% (p025-p975)"      = "p025_p975",
              "90% (p05-p95)"        = "p05_p95",
              "80% (p10-p90)"        = "p10_p90"
            ),
            selected = "minmax",
            width    = "160px"
          )
        )
      ),
      wise_plot_output(
        ns("adverse_dot_plot"),
        "Expected and adverse-year outcomes with climate-model ensemble spread",
        height = "380px"
      ),
      shiny::tags$p(
        class = "text-muted small",
        style = "margin-top: 8px; margin-bottom: 0;",
        "Adverse tail direction is mapped automatically according to the selected outcome metric. Horizontal bars show inter-model ensemble spread across climate projections."
      )
    ),

    # ---- Section 3: Exceedance probability curves --------------------------
    shiny::div(
      class = "results-section-card",
      shiny::div(
        style = "margin-bottom: 8px;",
        shiny::h4(
          "What is the probability of severe outcomes occurring?",
          info_popover(
            title = "Exceedance probability",
            shiny::p(
              "Shows the annual probability of reaching or exceeding severe outcome",
              "thresholds across simulated weather years under each climate regime.",
              "Dashed lines indicate standard return periods (e.g. 1-in-10 or 1-in-20 year events)."
            ),
            shiny::p(
              "Solid black curve is the historical baseline. Coloured curves show the",
              "ensemble median across climate models, with shaded ribbons indicating inter-model spread."
            ),
            docs = TRUE
          ),
          style = "font-size: 1.05rem; font-weight: 700; color: #173042; margin: 0;"
        )
      ),
      shiny::div(
        style = "display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 8px;",
        shiny::checkboxInput(
          ns("exceedance_logit_x"),
          "Expand rare-event tails (logit scale)",
          value = FALSE
        ),
        shiny::checkboxInput(
          ns("show_return_period"),
          "Show return period lines",
          value = TRUE
        ),
        shiny::checkboxInput(
          ns("show_model_spread"),
          "Show climate-model ribbon",
          value = TRUE
        ),
        shiny::checkboxInput(
          ns("show_coef_uncertainty"),
          "Show coefficient uncertainty",
          value = FALSE
        )
      ),
      wise_plot_output(
        ns("exceedance_plot"),
        "Exceedance probability curves across simulated climate scenarios",
        height = "400px"
      ),
      shiny::tags$p(
        class = "text-muted small",
        style = "margin-top: 8px; margin-bottom: 0;",
        "Curves depict annual probability of exceeding outcome levels in the adverse direction. Shaded regions capture disagreement across climate models."
      )
    ),

    # ---- Section 4: Uncertainty decomposition ------------------------------
    shiny::div(
      class = "results-section-card",
      shiny::div(
        style = "margin-bottom: 8px;",
        shiny::h4(
          "What drives the uncertainty in these predictions?",
          info_popover(
            title = "Uncertainty sources",
            shiny::p(
              "Compares the absolute standard deviation contributed by each distinct source:",
              "annual weather variability, climate-model disagreement, and econometric coefficient uncertainty."
            ),
            shiny::p(
              "Because standard deviations are not additive, bars are displayed side-by-side on a common scale."
            ),
            docs = TRUE
          ),
          style = "font-size: 1.05rem; font-weight: 700; color: #173042; margin: 0;"
        )
      ),
      wise_plot_output(
        ns("uncertainty_sources_plot"),
        "Standard deviation of outcome by uncertainty source",
        height = "300px"
      ),
      shiny::tags$p(
        class = "text-muted small",
        style = "margin-top: 8px; margin-bottom: 0;",
        "Separate standard deviations in outcome units. Annual weather variability reflects year-to-year swings; inter-model spread reflects CMIP6 model disagreement; coefficient uncertainty reflects econometric estimation precision."
      )
    ),

    # ---- Section 5: Decision & return-period table -------------------------
    shiny::div(
      class = "results-section-card",
      shiny::div(
        style = "display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;",
        shiny::h4(
          "Detailed return-period outcomes and uncertainty",
          info_popover(
            title = "Return-period decision table",
            shiny::p(
              "Summary of central expected outcomes and severe weather-year thresholds",
              "for each scenario, along with change from the historical baseline."
            ),
            docs = TRUE
          ),
          style = "font-size: 1.05rem; font-weight: 700; color: #173042; margin: 0;"
        ),
        csv_download_link(ns("decision_csv"), "Download CSV")
      ),
      shiny::uiOutput(ns("decision_table_html")),
      shiny::tags$details(
        style = "margin-top: 14px;",
        shiny::tags$summary(
          style = "cursor: pointer; font-size: 0.85rem; font-weight: 600; color: #526575;",
          "Complete technical uncertainty table (all bounds & quantiles)"
        ),
        shiny::div(
          style = "margin-top: 8px;",
          DT::DTOutput(ns("summary_threshold_table")),
          shiny::div(style = "margin-top: 6px;", csv_download_link(ns("threshold_csv"), "Download technical table CSV"))
        )
      )
    )
  )
}


#' 2_02_results Server Functions
#'
#' Appends a Results tab to the main tabset once the historical simulation
#' has run. All comparison outputs update reactively as saved_scenarios change.
#'
#' @param id              Module id.
#' @param hist_sim        ReactiveVal. Named list with slots:
#'   \code{$preds} (full prediction data frame), \code{$agg} (pre-aggregated
#'   summary by method x weighted x deviation x sim_year), \code{$so}
#'   (selected outcome metadata), \code{$pov_line} (simulation-time poverty
#'   line), \code{$has_weights} (logical weight flag), \code{$weather_raw},
#'   \code{$train_data}, \code{$n_pre_join}.
#' @param saved_scenarios ReactiveVal holding named scenario entries.
#' @param selected_hist   Reactive one-row data frame from weathersim.
#' @param selected_weather Reactive data frame of selected weather variables.
#' @param tabset_id       Character id of the parent tabset panel.
#' @param tabset_session  Shiny session for the tabset.
#'
#' @noRd
mod_2_02_results_server <- function(id,
                                     hist_sim,
                                     saved_scenarios,
                                     selected_hist,
                                     selected_weather = NULL,
                                     tabset_id,
                                     tabset_session = NULL,
                                     residuals = reactive("original"),
                                     skip_coef_draws = reactive(FALSE),
                                     stale = reactive(FALSE)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    if (is.null(tabset_session)) tabset_session <- session$parent %||% session

    # INT-08: stale banner above the results pane. This surface gates its
    # CSV export while stale.
    output$stale_banner <- renderUI({
      if (isTRUE(stale())) .stale_banner(
        "Step 2 simulation results",
        note = "Interpretation and exports are disabled until then."
      ) else NULL
    })

    output$simulation_summary_ui <- renderUI({
      simulation_summary_card(
        hist_sim        = hist_sim(),
        saved_scenarios = saved_scenarios(),
        selected_hist   = if (!is.null(selected_hist)) selected_hist() else NULL,
        selected_weather = if (is.function(selected_weather)) selected_weather() else selected_weather
      )
    })

    headline_cards_data_rv <- reactive({
      req(pointrange_bands_rv())
      bands <- pointrange_bands_rv()
      if (!nrow(bands) ||
          !all(c("is_historical", "scenario") %in% names(bands))) {
        return(NULL)
      }
      step2_headline_cards(
        bands             = bands,
        threshold_tbl     = tryCatch(threshold_table_rv(), error = function(e) NULL),
        hist_sim          = tryCatch(hist_sim(), error = function(e) NULL),
        saved_scenarios   = tryCatch(if (!is.null(saved_scenarios)) saved_scenarios() else list(),
                                     error = function(e) list()),
        method            = input$cmp_agg_method %||% "mean",
        deviation         = input$cmp_deviation %||% "none",
        ensemble_band     = input$ensemble_band %||% "minmax",
        uncertainty_band  = input$uncertainty_band %||% "p10_p90",
        skip_coef_draws   = tryCatch(if (is.function(skip_coef_draws)) skip_coef_draws() else skip_coef_draws,
                                     error = function(e) FALSE),
        timeseries_curves = tryCatch(timeseries_curves_rv(), error = function(e) NULL)
      )
    })

    output$headline_cards_ui <- renderUI({
      cards <- headline_cards_data_rv()
      if (is.null(cards)) return(NULL)
      headline_cards_ui(cards)
    })

    # ---- Lazy delta-method aggregation -------------------------------------
    # Replaces the eager compute_hist_agg / compute_scenario_agg path. Returns
    # the same nested list shape (weighted/unweighted -> method -> tibble) so
    # downstream consumers in fct_sim_compare.R see a compatible schema.
    agg_methods <- reactive({
      req(hist_sim())
      so <- hist_sim()$so
      unname(hist_aggregate_choices(so$type, so$name))
    })

    # pov_line is always supplied (the aggregation pre-computes every method
    # per year, not just the currently selected one). Non-poverty methods
    # ignore it; poverty methods need it. Default 3.00 USD/day if the input
    # hasn't been initialised yet.
    pov_line_val <- debounce(reactive({
      as.numeric(input$pov_line %||% 3.00)
    }), 400)

    bandwidth_p0 <- reactive({
      as.numeric(input$bandwidth_p0 %||% 0.05)
    })

    # ---- Value-affecting aggregation inputs ---------------------------------
    # The aggregation cache is keyed by the inputs each method actually
    # consumes (PERF-30), so moving the coefficient-band or poverty-line
    # control only invalidates the methods that read it. band_q is display-
    # only: aggregate_with_uncertainty_delta() applies it to value_lo/hi,
    # which no builder below consumes - the band is re-derived from the
    # cached SDs at render time. Display uses a fixed neutral pair.
    AGG_BAND_Q <- c(lo = 0.10, hi = 0.90)
    .POV_LINE_METHODS   <- c("headcount_ratio", "gap", "fgt2")
    .BANDWIDTH_METHODS  <- "headcount_ratio"

    # ---- Aggregation workspace + per-method cache --------------------------
    # Captures the heavy dependencies that invalidate every cached method
    # (hist_sim, saved scenarios, residuals, coef-draw skipping) into a
    # workspace that's recreated whenever any of them changes. The workspace
    # carries a mutable cache so we only compute each aggregation method once
    # per workspace version. The Results tab reads only the currently selected
    # method, and an eager observer pre-computes the default ("mean") as soon
    # as hist_sim() arrives - so the first render is fast even before the
    # user clicks anything.
    #
    # Display-only controls (coefficient band, poverty line, headcount
    # bandwidth) are deliberately NOT workspace dependencies: changing them
    # used to destroy the whole cache. Instead they are read at cache-lookup
    # time and folded into the per-method cache key for exactly the methods
    # that consume them (see .pl_bw_key).
    agg_workspace <- reactive({
      req(hist_sim())
      list(
        hs       = hist_sim(),
        sc       = saved_scenarios(),
        res      = hist_sim()$residuals %||% residuals() %||% "original",
        skip     = isTRUE(skip_coef_draws()),
        cache    = new.env(parent = emptyenv())
      )
    })

    # Cache-key suffix for the poverty line / bandwidth values a method reads.
    # Methods that ignore them get a constant key so moving the poverty-line
    # slider does not force their recomputation.
    .pl_bw_key <- function(method, pl_v, bw) {
      parts <- character(0)
      if (method %in% .POV_LINE_METHODS)  parts <- c(parts, format(pl_v))
      if (method %in% .BANDWIDTH_METHODS) parts <- c(parts, format(bw))
      if (length(parts) == 0L) "" else paste0("_", paste(parts, collapse = "_"))
    }

    .build_hist_for_method <- function(ws, method, pl_v) {
      pl   <- ws$hs$pipeline
      bq   <- AGG_BAND_Q
      is_log <- isTRUE(ws$hs$so$transform == "log")
      build_for <- function(weighted) {
        out <- aggregate_pipeline_table(
          pipelines    = pl,
          method       = method,
          weighted     = weighted,
          pov_line     = pl_v,
          residuals    = ws$res,
          is_log       = is_log,
          band_q       = bq,
          skip_coef    = ws$skip,
          bandwidth_p0 = bandwidth_p0(),
          model_ids    = "Historical",
            scenario     = "Historical",
            shared_context = ws$hs$shared_context
        )
        setNames(list(out), method)
      }
      has_w <- !is.null(pl$weight)
      list(
        unweighted = build_for(FALSE),
        weighted   = if (has_w) build_for(TRUE) else build_for(FALSE)
      )
    }

    .build_scn_for_method <- function(ws, method, pl_v) {
      sc <- ws$sc
      if (length(sc) == 0L) return(NULL)
      bq   <- AGG_BAND_Q
      setNames(lapply(sc, function(s) {
        pipes  <- s$pipelines
        is_log <- isTRUE(s$so$transform == "log")
        has_w  <- !is.null(pipes[[1L]]$weight)
        build_for <- function(weighted) {
          out <- aggregate_pipeline_table(
            pipelines    = pipes,
            method       = method,
            weighted     = weighted,
            pov_line     = pl_v,
            residuals    = ws$res,
            is_log       = is_log,
            band_q       = bq,
            skip_coef    = ws$skip,
            bandwidth_p0 = bandwidth_p0(),
            model_ids    = names(pipes) %||% paste0("m", seq_along(pipes)),
            shared_context = s$shared_context
          )
          setNames(list(out), method)
        }
        list(
          unweighted = build_for(FALSE),
          weighted   = if (has_w) build_for(TRUE) else build_for(FALSE)
        )
      }), names(sc))
    }

    .get_hist_agg <- function(method) {
      ws   <- agg_workspace()
      pl_v <- pov_line_val()
      bw   <- bandwidth_p0()
      key <- paste0("h_", method, .pl_bw_key(method, pl_v, bw))
      if (!exists(key, envir = ws$cache, inherits = FALSE)) {
        assign(key, .build_hist_for_method(ws, method, pl_v), envir = ws$cache)
      }
      get(key, envir = ws$cache, inherits = FALSE)
    }

    .get_scn_agg <- function(method) {
      ws   <- agg_workspace()
      pl_v <- pov_line_val()
      bw   <- bandwidth_p0()
      key <- paste0("s_", method, .pl_bw_key(method, pl_v, bw))
      if (!exists(key, envir = ws$cache, inherits = FALSE)) {
        assign(key, .build_scn_for_method(ws, method, pl_v), envir = ws$cache)
      }
      get(key, envir = ws$cache, inherits = FALSE)
    }

    # Eagerly pre-compute the default ("mean") aggregation as soon as the
    # simulation finishes, so the Results tab renders immediately when the
    # user opens it. Subsequent method changes are computed on-demand and
    # cached within the current workspace.
    observeEvent(agg_workspace(), {
      req(agg_workspace())
      isolate({
        .get_hist_agg("mean")
        if (length(agg_workspace()$sc) > 0L) .get_scn_agg("mean")
      })
    }, priority = 100, ignoreInit = FALSE)

    hist_agg_rv <- reactive({
      method <- input$cmp_agg_method %||% "mean"
      .get_hist_agg(method)
    })

    scenario_agg_rv <- reactive({
      req(saved_scenarios())
      if (length(saved_scenarios()) == 0L) return(NULL)
      method <- input$cmp_agg_method %||% "mean"
      .get_scn_agg(method)
    })

    # ---- Reactive computations (carried over from mod_2_06) ----------------

    hist_label <- reactive({
      nm <- if (!is.null(selected_hist)) selected_hist()$scenario_name else NULL
      if (!is.null(nm) && nzchar(nm)) nm else "Historical"
    })

    all_ssps <- reactive({
      sc <- saved_scenarios()
      if (length(sc) == 0) return(character(0))
      ssps <- unique(.normalise_ssp(names(sc)))
      sort(ssps[!is.na(ssps) & grepl("^SSP", ssps)])
    })

    all_anchor_years <- reactive({
      sc <- saved_scenarios()
      if (length(sc) == 0) return(character(0))
      ranges <- sort(na.omit(unique(.parse_year(names(sc)))))
      setNames(sub("-", "_", ranges), ranges)
    })

    all_models_info <- reactive({
      sc <- saved_scenarios()
      if (length(sc) == 0) return(character(0))
      # Return model counts per scenario for display
      vapply(sc, function(s) s$n_models %||% 1L, integer(1))
    })



  output$coef_uncertainty_status_ui <- shiny::renderUI({
      req(hist_sim())
      if (!has_draws()) {
        shiny::tags$p(
          style = "font-size:11px; color:#c62828; margin:2px 0 6px 0;",
          "\U0001f534 Coefficient draws skipped at simulation time"
        )
      } else if (!isTRUE(input$show_coef_uncertainty)) {
        shiny::tags$p(
          style = "font-size:11px; color:#e65100; margin:2px 0 6px 0;",
          "\u26a0 Coefficient uncertainty available but not shown"
        )
      } else {
        NULL
      }
    })
    outputOptions(output, "coef_uncertainty_status_ui",
                  suspendWhenHidden = TRUE)

    # Always use survey weights when available (UI toggle removed - weighting
    # is the correct default for survey-based welfare estimates).
    weight_key <- reactive({
      if (!is.null(hist_sim()) && isTRUE(hist_sim()$has_weights))
        "weighted" else "unweighted"
    })

    # Shared deviation reference - used by all_series_tbl and exceedance_ribbon
        hist_ref_val <- reactive({
          req(hist_agg_rv())
          method    <- input$cmp_agg_method %||% "mean"
          wk        <- weight_key()
          deviation <- input$cmp_deviation %||% "none"
          if (identical(deviation, "none")) return(0)
          raw_vals <- hist_agg_rv()[[wk]][[method]]$value
          if (identical(deviation, "mean"))
            mean(raw_vals, na.rm = TRUE)
          else
            stats::median(raw_vals, na.rm = TRUE)
        })

    # Per-coefficient gradient of the historical reference being subtracted.
    # When deviation = mean: average of per-year F_agg across historical years.
    # When deviation = median: F_agg at the historical year closest to the median.
    # Used by .apply_contrast_sd() below to switch coefficient SE from
    # level-CI (||F_s||) to contrast-CI (||F_s - F_ref||), the correct SE for
    # paired counterfactual analysis on the same population.
    hist_F_agg_ref <- reactive({
      req(hist_agg_rv())
      method    <- input$cmp_agg_method %||% "mean"
      wk        <- weight_key()
      deviation <- input$cmp_deviation %||% "none"
      if (identical(deviation, "none")) return(NULL)
      ht <- hist_agg_rv()[[wk]][[method]]
      if (is.null(ht) || nrow(ht) == 0L || !"F_agg_all" %in% names(ht))
        return(NULL)
      # Historical has one "model" so each F_agg_all row is a 1 x K matrix.
      F_list <- lapply(ht$F_agg_all, function(m) {
        if (is.null(m) || !is.matrix(m) || nrow(m) == 0L) NULL
        else as.numeric(m[1L, ])
      })
      F_list <- Filter(Negate(is.null), F_list)
      if (length(F_list) == 0L) return(NULL)
      if (identical(deviation, "mean")) {
        Reduce(`+`, F_list) / length(F_list)
      } else {
        vals    <- ht$value
        med_v   <- stats::median(vals, na.rm = TRUE)
        med_idx <- which.min(abs(vals - med_v))
        if (length(med_idx) == 0L) Reduce(`+`, F_list) / length(F_list)
        else F_list[[med_idx]]
      }
    })

    # Replace per-(model, year) coefficient SDs with paired-contrast SDs
    # when a deviation reference is active. By overwriting `value_all_sd`
    # here, every downstream consumer (pointrange_bands_rv,
    # threshold_table_rv, exceedance_curves_rv) automatically uses the
    # tightened contrast variance.
    .apply_contrast_sd <- function(tbl, F_ref) {
      if (is.null(F_ref) || is.null(tbl) || nrow(tbl) == 0L) return(tbl)
      if (!"F_agg_all" %in% names(tbl) || !"value_all_sd" %in% names(tbl))
        return(tbl)
      for (k in seq_len(nrow(tbl))) {
        F_mat <- tbl$F_agg_all[[k]]
        if (is.null(F_mat) || !is.matrix(F_mat) || ncol(F_mat) != length(F_ref))
          next
        F_diff <- sweep(F_mat, 2L, F_ref, "-")
        tbl$value_all_sd[[k]] <- sqrt(rowSums(F_diff * F_diff))
      }
      tbl
    }


        # ---- Coefficient draws availability -----------------------------------
    has_draws <- reactive({
      req(hist_sim())
      !is.null(hist_sim()$chol_obj)
    })

    # Sync the "Show coefficient uncertainty" toggle to the current sim:
    #   - When the new sim has no chol_obj (skip_coef_draws was TRUE), force
    #     the box off so the user sees the toggle reflect reality.
    #   - When the new sim does have chol_obj (uncertainty was included),
    #     re-enable the box. Without this re-set, a prior simulation that
    #     ran without draws would leave the box stuck OFF even after the
    #     user enables coefficient uncertainty and re-runs.
    observeEvent(hist_sim(), {
      req(hist_sim())
      shiny::updateCheckboxInput(
        session, "show_coef_uncertainty",
        value = isTRUE(has_draws())
      )
    }, ignoreInit = TRUE)





    # UI-38: hold the most recent non-empty grid selection so unchecking the
    # final scenario never silently re-displays the first one.
    last_selected_scenarios <- reactiveVal(NULL)

    observe({
      sc   <- saved_scenarios()
      if (length(sc) == 0L) return(invisible(NULL))
      keys <- names(sc)

      selected <- Filter(Negate(is.null), lapply(keys, function(key) {
        cb_id <- paste0("sc_", gsub("[^a-zA-Z0-9]", "_", key))
        if (isTRUE(input[[cb_id]])) key else NULL
      }))

      if (length(selected) > 0L) {
        last_selected_scenarios(unlist(selected))
      } else {
        # Re-check the held boxes so the grid never sits fully unchecked.
        held <- last_selected_scenarios()
        held <- held[held %in% keys]
        if (length(held) == 0L) held <- keys[1L]
        for (key in held) {
          shiny::updateCheckboxInput(
            session,
            inputId = paste0("sc_", gsub("[^a-zA-Z0-9]", "_", key)),
            value   = TRUE
          )
        }
      }
    })

    selected_scenario_names <- reactive({
      sc   <- saved_scenarios()
      if (length(sc) == 0L) return(character(0))
      keys <- names(sc)

      # Read each grid checkbox
      selected <- Filter(Negate(is.null), lapply(keys, function(key) {
        cb_id <- paste0("sc_", gsub("[^a-zA-Z0-9]", "_", key))
        val   <- input[[cb_id]]
        if (isTRUE(val)) key else NULL
      }))

      # Enforce minimum 1 selected: hold the last real selection (UI-38)
      # rather than silently re-adding the first scenario.
      if (length(selected) == 0L) {
        held <- last_selected_scenarios()
        held <- held[held %in% keys]
        if (length(held) == 0L) held <- keys[1L]
        held
      } else {
        unlist(selected)
      }
    })

    agg_hist <- reactive({
      req(hist_agg_rv())
      method    <- input$cmp_agg_method %||% "mean"
      deviation <- input$cmp_deviation  %||% "none"
      out       <- hist_agg_rv()[[weight_key()]][[method]]
      req(!is.null(out))
      hist_ref  <- hist_ref_val()
      if (!identical(deviation, "none") && nrow(out) > 0)
        out <- dplyr::mutate(out, value = value - hist_ref)
      x_label <- if (identical(deviation, "none")) label_agg_method(method) else
        paste0(label_agg_method(method), " \u2014 ", label_deviation(deviation))
      list(out = out, x_label = x_label)
    })

    agg_scenarios <- reactive({
      req(scenario_agg_rv())
      sc <- saved_scenarios()
      if (length(sc) == 0) return(list())
      method    <- input$cmp_agg_method %||% "mean"
      deviation <- input$cmp_deviation  %||% "none"
      hist_ref <- hist_ref_val() 
      x_label <- if (identical(deviation, "none")) label_agg_method(method) else
        paste0(label_agg_method(method), " \u2014 ", label_deviation(deviation))
        selected <- selected_scenario_names()
        result <- setNames(lapply(names(sc), function(display_key) {
          if (!display_key %in% selected) return(NULL)
          out <- scenario_agg_rv()[[display_key]][[weight_key()]][[method]]
          if (is.null(out) || nrow(out) == 0L) return(NULL)
          if (!identical(deviation, "none"))
            out <- dplyr::mutate(out, value = value - hist_ref)
          list(out = out, x_label = x_label)
        }), names(sc))
      Filter(function(x) !is.null(x) && !is.null(x$out) && nrow(x$out) > 0, result)
    })

    # `exceedance_ribbon` removed - the ribbon is now built inside
    # enhance_exceedance() directly from each series' (value_all, value_all_sd)
    # using analytic delta-method bands, so there is nothing to precompute here.
    

    # `all_series` is now a thin passthrough: it gathers the deviation-shifted
    # tibbles from agg_hist()/agg_scenarios() and tags each with its scenario
    # name. No analytic band augmentation - each plot/table reactive below
    # constructs its own bands from value_all + value_all_sd directly.
    all_series <- reactive({
      req(agg_hist())
      hist_list <- list(Historical = list(
        out      = dplyr::mutate(agg_hist()$out, scenario = "Historical"),
        x_label  = agg_hist()$x_label
      ))
      sc <- agg_scenarios()
      if (length(sc) == 0L) return(hist_list)
      sc_list <- setNames(lapply(names(sc), function(dk) {
        out <- sc[[dk]]$out
        if (is.null(out) || nrow(out) == 0L) return(NULL)
        list(out = dplyr::mutate(out, scenario = dk),
             x_label = sc[[dk]]$x_label)
      }), names(sc))
      c(hist_list, Filter(Negate(is.null), sc_list))
    })




    table_subtitle <- reactive({
      req(agg_hist(), input$cmp_agg_method)
      deviation <- input$cmp_deviation %||% "none"
      paste0(
        agg_hist()$x_label, " \u2014 ",
        label_agg_method(input$cmp_agg_method %||% "mean"), " | ",
        label_deviation(deviation)
      )
    })

    # ---- renderUI / render* outputs ----------------------------------------

    output$scenario_filter_ui <- renderUI({
      sc <- saved_scenarios()
      if (length(sc) == 0L)
        return(shiny::helpText("Run a simulation."))

      # Parse scenario keys into SSP * period grid
      keys  <- names(sc)
      ssps  <- sort(unique(sub(" / .*$", "", keys)))
      yrs   <- sort(unique(sub("^.* / ", "", keys)))

      # Build header row
      header <- shiny::tags$tr(
        shiny::tags$th(""),
        lapply(ssps, function(s)
          shiny::tags$th(s,
            style = "text-align:center; font-size:11px;
                    font-weight:600; padding:2px 8px;"))
      )

      # Build one row per period
      period_rows <- lapply(yrs, function(yr) {
        shiny::tags$tr(
          shiny::tags$td(yr,
            style = "font-size:11px; font-weight:600;
                    padding:2px 8px; white-space:nowrap;"),
          lapply(ssps, function(s) {
            key     <- paste0(s, " / ", yr)
            exists  <- key %in% keys
            cb_id   <- ns(paste0("sc_", gsub("[^a-zA-Z0-9]", "_", key)))
            shiny::tags$td(
              style = "text-align:center; padding:2px 4px;",
              if (exists)
                # UI-03: the grid's row/column headers carry the meaning
                # visually; give each checkbox its own accessible name.
                shiny::checkboxInput(
                  cb_id,
                  label = shiny::tags$span(class = "visually-hidden",
                                           paste("Include", s, yr,
                                                 "in the comparison")),
                  value = TRUE
                )
              else
                shiny::tags$span(
                  style = "color:#ccc; font-size:11px;",
                  "-"
                )
            )
          })
        )
      })

      shiny::tags$table(
        id    = "scenario-filter-grid",
        style = "border-collapse:collapse; margin-top:4px;",
        shiny::tags$style(shiny::HTML("
          #scenario-filter-grid .checkbox { margin: 0; padding: 0; }
          #scenario-filter-grid .checkbox label { 
            padding-left: 0; 
            min-height: 0;
          }
          #scenario-filter-grid .checkbox label span { display: none; }
          #scenario-filter-grid input[type='checkbox'] { 
            width: 16px; height: 16px; 
            margin: 0 auto; 
            display: block;
            position: static;
          }
          #scenario-filter-grid td { padding: 4px 12px; }
          #scenario-filter-grid th { padding: 4px 12px; font-size: 11px; }
        ")),
        shiny::tags$thead(header),
        shiny::tags$tbody(period_rows)
      )
    })

    # ---- Three-source uncertainty decomposition ----------------------------
    # All three downstream displays (hero, exceedance, table) source their
    # bands from the helpers below. Each helper produces a per-scenario view
    # that decomposes uncertainty into:
    #   - coefficient (per-outcome SE from value_all_sd)
    #   - inter-annual (within-model spread of value_all across years)
    #   - inter-model  (across-model spread of model means; future only)

    # Helpers are now defined in R/fct_uncertainty_helpers.R as package-internal
    # functions so Module 3 can call the same code path. Aliases keep the
    # existing inline call sites below readable.
    .by_model_matrix <- by_model_matrix
    .pct_label       <- pct_label
    .rank_interp     <- rank_interp

    # ---- pointrange_bands_rv: one row per scenario, three nested bands -----
    pointrange_bands_rv <- reactive({
      req(hist_agg_rv())
      bq_coef <- resolve_band_q(input$uncertainty_band %||% "p10_p90")
      bq_ens  <- resolve_band_q(input$ensemble_band    %||% "minmax")
      z_coef_lo <- stats::qnorm(bq_coef[["lo"]])
      z_coef_hi <- stats::qnorm(bq_coef[["hi"]])
      hist_ref  <- hist_ref_val()
      wk        <- weight_key()
      method    <- input$cmp_agg_method %||% "mean"

      one_scenario <- function(tbl, scenario_label, is_hist) {
        if (is.null(tbl) || nrow(tbl) == 0L) return(NULL)
        mm <- .by_model_matrix(tbl)
        if (is.null(mm)) return(NULL)
        vals <- mm$vals; sds <- mm$sds

        # Inter-model spread: per-model mean across years, then quantile across models.
        model_means <- rowMeans(vals, na.rm = TRUE)
        intermod <- if (is_hist || length(model_means) <= 1L) {
          mean_v <- mean(model_means, na.rm = TRUE)
          c(lo = mean_v, hi = mean_v)
        } else {
          c(lo = unname(stats::quantile(model_means, bq_ens[["lo"]], na.rm = TRUE)),
            hi = unname(stats::quantile(model_means, bq_ens[["hi"]], na.rm = TRUE)))
        }

        # Inter-annual variability: for each model take the band_q quantile
        # across years, then average across models.
        if (is_hist) {
          v_flat <- as.numeric(vals)
          interann <- c(
            lo = unname(stats::quantile(v_flat, bq_ens[["lo"]], na.rm = TRUE)),
            hi = unname(stats::quantile(v_flat, bq_ens[["hi"]], na.rm = TRUE))
          )
        } else {
          per_mod_lo <- apply(vals, 1L, stats::quantile,
                              probs = bq_ens[["lo"]], na.rm = TRUE)
          per_mod_hi <- apply(vals, 1L, stats::quantile,
                              probs = bq_ens[["hi"]], na.rm = TRUE)
          interann <- c(lo = mean(per_mod_lo, na.rm = TRUE),
                        hi = mean(per_mod_hi, na.rm = TRUE))
        }

        # Coefficient uncertainty: per-outcome SE, centred on ensemble mean.
        # Owner-approved convention: summarise each model across its weather
        # years, then take the median across equally weighted models.
        ens_mean <- if (is_hist) mean(as.numeric(vals), na.rm = TRUE) else
          stats::median(model_means, na.rm = TRUE)
        sd_mean  <- mean(as.numeric(sds),  na.rm = TRUE)
        coef     <- c(lo = ens_mean + z_coef_lo * sd_mean,
                      hi = ens_mean + z_coef_hi * sd_mean)

        # "Pooled" band: pooled SE on the central (year- and model-
        # averaged) estimate. Mirrors the return-period table's "Pooled"
        # convention (see fct_sim_compare.R::build_threshold_table_df) -
        # inter-annual variability is a property of the simulated
        # distribution, not uncertainty about the central tendency, and
        # is shown separately as the middle band.
        # var_coef     = mean per-outcome regression-fit variance (uses
        #                paired-contrast SEs when deviation is selected,
        #                via .apply_contrast_sd above).
        # var_across   = variance across model means; matches the inter-
        #                model band's underlying statistic.
        # When var_across is zero (historical or single-member future),
        # the pooled SE degenerates to the coef SE; we suppress the
        # outer whisker (NA) to avoid drawing a duplicate of the coef
        # band.
        var_coef_total <- mean(as.numeric(sds)^2, na.rm = TRUE)
        var_across <- if (!is_hist && nrow(vals) > 1L) {
          v <- stats::var(rowMeans(vals, na.rm = TRUE), na.rm = TRUE)
          if (is.finite(v)) v else 0
        } else 0
        if (var_across > 0) {
          sd_total <- sqrt(max(var_coef_total + var_across, 0,
                               na.rm = TRUE))
          total <- c(lo = ens_mean + z_coef_lo * sd_total,
                     hi = ens_mean + z_coef_hi * sd_total)
        } else {
          total <- c(lo = NA_real_, hi = NA_real_)
        }

        tibble::tibble(
          scenario     = scenario_label,
          value        = ens_mean - hist_ref,
          coef_lo      = unname(coef[["lo"]])       - hist_ref,
          coef_hi      = unname(coef[["hi"]])       - hist_ref,
          interann_lo  = unname(interann[["lo"]])   - hist_ref,
          interann_hi  = unname(interann[["hi"]])   - hist_ref,
          intermod_lo  = unname(intermod[["lo"]])   - hist_ref,
          intermod_hi  = unname(intermod[["hi"]])   - hist_ref,
          total_lo     = unname(total[["lo"]])      - hist_ref,
          total_hi     = unname(total[["hi"]])      - hist_ref,
          is_historical = is_hist,
          n_models     = length(mm$model_ids)
        )
      }

      rows <- list(one_scenario(.apply_contrast_sd(hist_agg_rv()[[wk]][[method]], hist_F_agg_ref()),
                                "Historical", TRUE))
      sa <- scenario_agg_rv()
      if (!is.null(sa) && length(sa) > 0L) {
        for (dk in names(sa)) {
          if (!dk %in% selected_scenario_names()) next
          rows[[length(rows) + 1L]] <- one_scenario(.apply_contrast_sd(sa[[dk]][[wk]][[method]], hist_F_agg_ref()),
                                                    dk, FALSE)
        }
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    })

    # ---- timeseries_curves_rv: per (scenario, model, sim_year) values ------
    timeseries_curves_rv <- reactive({
      req(hist_agg_rv())
      hist_ref <- hist_ref_val()
      wk       <- weight_key()
      method   <- input$cmp_agg_method %||% "mean"

      one_scenario <- function(tbl, scenario_label, is_hist) {
        if (is.null(tbl) || nrow(tbl) == 0L) return(NULL)
        mm <- .by_model_matrix(tbl)
        if (is.null(mm)) return(NULL)
        vals <- mm$vals
        rows <- lapply(seq_len(nrow(vals)), function(i) {
          tibble::tibble(
            scenario      = scenario_label,
            model_id      = mm$model_ids[[i]],
            sim_year      = as.integer(mm$sim_years),
            value         = vals[i, ] - hist_ref,
            is_historical = is_hist
          )
        })
        dplyr::bind_rows(rows)
      }

      rows <- list(one_scenario(.apply_contrast_sd(hist_agg_rv()[[wk]][[method]], hist_F_agg_ref()),
                                "Historical", TRUE))
      sa <- scenario_agg_rv()
      if (!is.null(sa) && length(sa) > 0L) {
        for (dk in names(sa)) {
          if (!dk %in% selected_scenario_names()) next
          rows[[length(rows) + 1L]] <- one_scenario(.apply_contrast_sd(sa[[dk]][[wk]][[method]], hist_F_agg_ref()),
                                                    dk, FALSE)
        }
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    })

    # ---- variance_breakdown_rv: one row per scenario, three components -----
    # Aggregates the per-(sim_year) var_within / var_across columns to scalars
    # and re-computes var_coef from the per-(model, year) SD list-column.
    variance_breakdown_rv <- reactive({
      req(hist_agg_rv())
      wk     <- weight_key()
      method <- input$cmp_agg_method %||% "mean"

      one_scenario <- function(tbl, scenario_label, is_hist) {
        if (is.null(tbl) || nrow(tbl) == 0L) return(NULL)
        sds_flat <- as.numeric(unlist(tbl$value_all_sd))
        var_coef <- if (length(sds_flat))
          mean(sds_flat^2, na.rm = TRUE) else 0
        # Use value-matrix-derived var_within / var_across so the metric
        # matches what the inter-annual / inter-model bands visualise and
        # avoids double-counting var_coef. (Unlike the pointrange total
        # band, this decomposition panel intentionally includes
        # var_within - its purpose is to show the share of every source,
        # including year-to-year spread.)
        mm <- by_model_matrix(tbl)
        vals <- if (is.null(mm)) NULL else mm$vals
        var_within <- if (!is.null(vals) && ncol(vals) > 1L) {
          v <- mean(apply(vals, 1L, stats::var, na.rm = TRUE), na.rm = TRUE)
          if (is.finite(v)) v else 0
        } else 0
        var_across <- if (!is_hist && !is.null(vals) && nrow(vals) > 1L) {
          v <- stats::var(rowMeans(vals, na.rm = TRUE), na.rm = TRUE)
          if (is.finite(v)) v else 0
        } else 0
        tibble::tibble(
          scenario      = scenario_label,
          var_coef      = var_coef,
          var_within    = var_within,
          var_across    = var_across,
          is_historical = is_hist
        )
      }

      rows <- list(one_scenario(.apply_contrast_sd(hist_agg_rv()[[wk]][[method]], hist_F_agg_ref()),
                                "Historical", TRUE))
      sa <- scenario_agg_rv()
      if (!is.null(sa) && length(sa) > 0L) {
        for (dk in names(sa)) {
          if (!dk %in% selected_scenario_names()) next
          rows[[length(rows) + 1L]] <- one_scenario(.apply_contrast_sd(sa[[dk]][[wk]][[method]], hist_F_agg_ref()),
                                                    dk, FALSE)
        }
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    })

    # ---- exceedance_curves_rv: per (scenario, model) ECDF rows -------------
    # One row per (scenario, model, rank). welfare_val is sorted ascending per
    # model; exceed_prob is rev((seq - 0.5)/n_years). coef_sd is the per-
    # (model, year) SD reordered to match the welfare sort.
    exceedance_curves_rv <- reactive({
      req(hist_agg_rv())
      hist_ref <- hist_ref_val()
      wk       <- weight_key()
      method   <- input$cmp_agg_method %||% "mean"

      one_scenario <- function(tbl, scenario_label, is_hist) {
        if (is.null(tbl) || nrow(tbl) == 0L) return(NULL)
        mm <- .by_model_matrix(tbl)
        if (is.null(mm)) return(NULL)
        vals <- mm$vals; sds <- mm$sds
        n_yrs <- ncol(vals)
        if (n_yrs == 0L) return(NULL)
        probs <- rev((seq_len(n_yrs) - 0.5) / n_yrs)

        do.call(dplyr::bind_rows, lapply(seq_len(nrow(vals)), function(i) {
          v <- vals[i, ]; s <- sds[i, ]
          ok <- is.finite(v)
          if (!any(ok)) return(NULL)
          v <- v[ok]; s <- s[ok]
          ord <- order(v)
          tibble::tibble(
            scenario    = scenario_label,
            model_id    = mm$model_ids[[i]],
            rank        = seq_along(ord),
            welfare_val = v[ord] - hist_ref,
            coef_sd     = if (length(s) == length(ord)) s[ord] else rep(0, length(ord)),
            exceed_prob = rev((seq_len(length(ord)) - 0.5) / length(ord)),
            is_historical = is_hist
          )
        }))
      }

      rows <- list(one_scenario(.apply_contrast_sd(hist_agg_rv()[[wk]][[method]], hist_F_agg_ref()),
                                "Historical", TRUE))
      sa <- scenario_agg_rv()
      if (!is.null(sa) && length(sa) > 0L) {
        for (dk in names(sa)) {
          if (!dk %in% selected_scenario_names()) next
          rows[[length(rows) + 1L]] <- one_scenario(.apply_contrast_sd(sa[[dk]][[wk]][[method]], hist_F_agg_ref()),
                                                    dk, FALSE)
        }
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    })

    # ---- threshold_table_rv: long-format rows ready to pivot wide ---------
    # One row per (scenario, Estimate, RP). Estimate names are derived from
    # the user's band quantile selection: e.g., with coef=p10_p90 and
    # ensemble=minmax the rows are "Central (P50)", "Coef P10", "Coef P90",
    # "Ensemble min", "Ensemble max", "Pooled P10", "Pooled P90". Pooled
    # rows combine the coefficient and inter-model components assuming
    # independence: SE_pooled = sqrt(coef_sd^2 + var_across_at_rp).
    # Historical (no inter-model component) does not emit Pooled rows -
    # they would duplicate the Coef rows.
    threshold_table_rv <- reactive({
      req(hist_agg_rv())
      bq_coef <- resolve_band_q(input$uncertainty_band %||% "p10_p90")
      bq_ens  <- resolve_band_q(input$ensemble_band    %||% "minmax")
      z_coef_lo <- stats::qnorm(bq_coef[["lo"]])
      z_coef_hi <- stats::qnorm(bq_coef[["hi"]])
      hist_ref  <- hist_ref_val()
      wk        <- weight_key()
      method    <- input$cmp_agg_method %||% "mean"

      RPs <- c(RP_LOW, c("1:1" = 0.5), RP_HIGH)

      one_scenario <- function(tbl, scenario_label, is_hist) {
        if (is.null(tbl) || nrow(tbl) == 0L) return(NULL)
        mm <- .by_model_matrix(tbl)
        if (is.null(mm)) return(NULL)
        vals <- mm$vals; sds <- mm$sds
        n_yrs <- ncol(vals)
        n_pts <- if (is_hist) sum(is.finite(as.numeric(vals))) else n_yrs

        # Drop RPs that aren't comfortably supported by n_yrs of data. A 1-in-N
        # return period needs at least N observations (p in [1/n, 1-1/n]); we
        # don't report tighter probabilities - they'd rest on the single most
        # extreme observed year and are not meaningful as a "1-in-N" estimate.
        rp_ok    <- RPs >= (1 / n_yrs) & RPs <= (1 - 1 / n_yrs)
        RPs_keep <- RPs[rp_ok]
        if (length(RPs_keep) == 0L) return(NULL)

        # Per-model rank-interp at each kept RP (matrix: model * RP) - shape
        # guaranteed by the helper (see by_model_rp_matrix()).
        mm        <- by_model_rp_matrix(vals, sds, RPs_keep)
        per_model_rp       <- mm$rp
        per_model_sd_at_rp <- mm$sd

        # Aggregate across models for each RP
        central_vec <- if (is_hist) per_model_rp[1L, ] else
          apply(per_model_rp, 2L, stats::median, na.rm = TRUE)
        coef_sd_vec <- if (is_hist) per_model_sd_at_rp[1L, ] else
          apply(per_model_sd_at_rp, 2L, stats::median, na.rm = TRUE)
        coef_lo_vec <- central_vec + z_coef_lo * coef_sd_vec
        coef_hi_vec <- central_vec + z_coef_hi * coef_sd_vec

        intermod_lo_vec <- if (is_hist) rep(NA_real_, length(RPs_keep)) else
          apply(per_model_rp, 2L, stats::quantile,
                probs = bq_ens[["lo"]], na.rm = TRUE)
        intermod_hi_vec <- if (is_hist) rep(NA_real_, length(RPs_keep)) else
          apply(per_model_rp, 2L, stats::quantile,
                probs = bq_ens[["hi"]], na.rm = TRUE)

        # Total band combines coefficient and inter-model variance at each RP,
        # assuming independence. Inter-annual variability is already baked
        # into the per-rank value so it isn't added a second time here.
        var_across_at_rp <- if (is_hist) rep(0, length(RPs_keep)) else
          apply(per_model_rp, 2L, stats::var, na.rm = TRUE)
        var_across_at_rp[is.na(var_across_at_rp)] <- 0
        sd_total_vec <- sqrt(pmax(coef_sd_vec^2 + var_across_at_rp, 0,
                                  na.rm = FALSE))
        total_lo_vec <- central_vec + z_coef_lo * sd_total_vec
        total_hi_vec <- central_vec + z_coef_hi * sd_total_vec

        make_row <- function(estimate, vec) {
          tibble::tibble(
            scenario   = scenario_label,
            Estimate   = estimate,
            rp_name    = names(RPs_keep),
            rp_label   = names(RPs_keep),
            value      = vec - hist_ref,
            n_obs      = n_pts,
            is_historical = is_hist
          )
        }
        coef_lo_lbl <- paste0("Coef ",  .pct_label(bq_coef[["lo"]]))
        coef_hi_lbl <- paste0("Coef ",  .pct_label(bq_coef[["hi"]]))
        ens_lo_lbl  <- paste0("Ensemble ", .pct_label(bq_ens[["lo"]],
                                                       use_minmax = TRUE))
        ens_hi_lbl  <- paste0("Ensemble ", .pct_label(bq_ens[["hi"]],
                                                       use_minmax = TRUE))
        pooled_lo_lbl <- paste0("Pooled ", .pct_label(bq_coef[["lo"]]))
        pooled_hi_lbl <- paste0("Pooled ", .pct_label(bq_coef[["hi"]]))

        rows <- list(
          make_row("Central (P50)", central_vec),
          make_row(coef_lo_lbl,     coef_lo_vec),
          make_row(coef_hi_lbl,     coef_hi_vec)
        )
        if (!is_hist) {
          rows <- c(rows, list(
            make_row(ens_lo_lbl,    intermod_lo_vec),
            make_row(ens_hi_lbl,    intermod_hi_vec),
            make_row(pooled_lo_lbl, total_lo_vec),
            make_row(pooled_hi_lbl, total_hi_vec)
          ))
        }
        dplyr::bind_rows(rows)
      }

      rows <- list(one_scenario(.apply_contrast_sd(hist_agg_rv()[[wk]][[method]], hist_F_agg_ref()),
                                "Historical", TRUE))
      sa <- scenario_agg_rv()
      if (!is.null(sa) && length(sa) > 0L) {
        for (dk in names(sa)) {
          if (!dk %in% selected_scenario_names()) next
          rows[[length(rows) + 1L]] <- one_scenario(.apply_contrast_sd(sa[[dk]][[wk]][[method]], hist_F_agg_ref()),
                                                    dk, FALSE)
        }
      }
      dplyr::bind_rows(Filter(Negate(is.null), rows))
    })

    # UI-48: register Step 2's result figures for the export bundle.
    wise_export_table(
      key   = "climate_headline_summary",
      label = "Climate headline summary cards",
      step  = 2L,
      fun   = function() {
        step2_headline_df(headline_cards_data_rv())
      },
      description = "At-a-glance summary cards for the focus climate scenario: typical outcome, adverse weather years, weather-year range, model spread, and simulation coverage."
    )

    wise_export_figure(
      key   = "climate_outcome_distribution",
      label = "Simulated welfare by scenario and period",
      step  = 2L,
      fun   = function() {
        bands <- pointrange_bands_rv()
        if (is.null(bands)) return(NULL)
        if (!isTRUE(input$show_model_spread)) {
          bands$intermod_lo <- NA_real_
          bands$intermod_hi <- NA_real_
        }
        plot_pointrange_climate(
          bands_tbl    = bands,
          x_label      = agg_hist()$x_label,
          group_order  = input$cmp_group_order %||% "scenario_x_year",
          show_coef    = isTRUE(input$show_coef_uncertainty) && has_draws()
        )
      },
      description = paste(
        "Simulated welfare by climate scenario and projection period, with",
        "coefficient and inter-model uncertainty bands where enabled."
      ),
      width = 10, height = 6.5
    )

    output$summary_box_plot <- renderPlot({
      req(pointrange_bands_rv())
      bands <- pointrange_bands_rv()
      if (!isTRUE(input$show_model_spread)) {
        bands$intermod_lo <- NA_real_
        bands$intermod_hi <- NA_real_
      }
      plot_pointrange_climate(
        bands_tbl    = bands,
        x_label      = agg_hist()$x_label,
        group_order  = input$cmp_group_order %||% "scenario_x_year",
        show_coef    = isTRUE(input$show_coef_uncertainty) && has_draws()
      )
    }, height = 600)

    output$annual_distribution_plot <- renderPlot({
      req(timeseries_curves_rv())
      curves <- timeseries_curves_rv()
      plot_annual_distribution(
        curves,
        x_label = metric_axis_label(
          input$cmp_agg_method %||% "mean",
          hist_sim()$so,
          input$cmp_deviation %||% "none"
        ),
        title = "Distribution of annual outcome across simulated weather years"
      )
    }, height = 460)

    incidence_data_rv <- reactive({
      req(hist_sim(), saved_scenarios(), shiny::isolate(input$cmp_agg_method))
      sc <- selected_scenario_names()
      if (!length(sc)) return(tibble::tibble())
      is_log <- identical(hist_sim()$so$transform, "log")
      svy <- hist_sim()$svy %||% hist_sim()$survey
      if (is.null(svy)) return(tibble::tibble())
      dplyr::bind_rows(lapply(sc, function(nm) {
        entry <- saved_scenarios()[[nm]]
        pipes <- entry$pipelines %||% list(entry$pipeline %||% entry)
        step2_incidence_by_decile(
          svy, hist_sim()$so$name, hist_sim()$pipeline, pipes, is_log, nm
        )
      }))
    })

    output$incidence_plot <- renderPlot({
      req(incidence_data_rv())
      plot_incidence_by_decile(incidence_data_rv())
    }, height = 420)
    outputOptions(output, "incidence_plot", suspendWhenHidden = TRUE)
    output$incidence_table <- DT::renderDT({
      req(incidence_data_rv())
      DT::datatable(
        incidence_data_rv(), rownames = FALSE, class = "compact stripe",
        extensions = "Buttons",
        options = list(dom = wise_csv_dom("tp"), pageLength = 10,
                       buttons = wise_csv_button("climate_distributional_incidence"))
      )
    })
    outputOptions(output, "incidence_table", suspendWhenHidden = TRUE)

    wise_export_figure(
      key = "climate_distributional_incidence",
      label = "Distributional incidence by baseline decile",
      step = 2L,
      fun = function() plot_incidence_by_decile(incidence_data_rv()),
      description = "Weighted household-level simulated effects by fixed observed baseline welfare decile.",
      width = 10, height = 6
    )
    wise_export_table(
      key = "climate_distributional_incidence_data",
      label = "Distributional incidence data",
      step = 2L,
      fun = function() annotate_visualization_export(
        incidence_data_rv(), input$cmp_agg_method %||% "mean", hist_sim()$so,
        observation_unit = "household-level simulated welfare effect",
        aggregation_order = "fixed weighted observed baseline decile; weighted mean over households and model summaries",
        uncertainty = "scenario/model variation summarized by selected model set"
      ),
      description = "Tidy weighted incidence data by fixed baseline welfare decile."
    )

    # Export the same tidy annual aggregates used by the distribution plot.
    annual_distribution_export <- function() {
      curves <- timeseries_curves_rv()
      req(curves)
      annotate_visualization_export(
        curves,
        input$cmp_agg_method %||% "mean",
        hist_sim()$so,
        observation_unit = "annual aggregate for fixed survey population under one weather-year draw",
        aggregation_order = "weighted household aggregate by model and weather-year; model means retained",
        uncertainty = "inter-annual weather variation"
      )
    }
    wise_export_figure(
      key = "climate_annual_distribution",
      label = "Annual outcome distribution across weather years",
      step = 2L,
      fun = function() {
        plot_annual_distribution(
          timeseries_curves_rv(),
          x_label = metric_axis_label(input$cmp_agg_method %||% "mean",
                                      hist_sim()$so,
                                      input$cmp_deviation %||% "none")
        )
      },
      description = "Annual aggregate distribution for the fixed population; one observation is one model-weather-year draw.",
      width = 10, height = 6.5
    )
    wise_export_table(
      key = "climate_annual_distribution_data",
      label = "Annual outcome distribution data",
      step = 2L,
      fun = annual_distribution_export,
      description = "Tidy data behind the annual aggregate distribution, including metric and aggregation metadata."
    )
    wise_export_table(
      key = "climate_expected_outcomes",
      label = "Expected outcome summaries",
      step = 2L,
      fun = function() {
        annotate_visualization_export(
          pointrange_bands_rv(), input$cmp_agg_method %||% "mean",
          hist_sim()$so,
          observation_unit = "scenario-period annual aggregate summary",
          aggregation_order = "model means across weather-year draws, then median across equally weighted models",
          uncertainty = "inter-model ensemble spread and coefficient uncertainty"
        )
      },
      description = "Expected annual outcomes by scenario and projection window with separately labelled uncertainty sources."
    )

    # UI-48: one builder behind the on-screen table, its CSV button and the
    # export bundle.
    threshold_table_df <- function() {
      tbl <- threshold_table_rv()
      if (is.null(tbl) || !nrow(tbl) || !"Estimate" %in% names(tbl)) {
        return(NULL)
      }
      if (!isTRUE(input$show_model_spread)) {
        tbl <- tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
      }
      build_threshold_table_df(
        threshold_tbl = tbl,
        group_order   = input$cmp_group_order %||% "scenario_x_year",
        show_coef     = isTRUE(input$show_coef_uncertainty) && has_draws()
      )
    }

    decision_threshold_df <- reactive({
      tbl <- threshold_table_rv()
      if (is.null(tbl) || !nrow(tbl) || !"Estimate" %in% names(tbl)) {
        return(NULL)
      }
      tbl <- tbl[tbl$Estimate == "Central (P50)", , drop = FALSE]
      if (!nrow(tbl)) return(NULL)
      rp_map <- metric_decision_return_periods(
        input$cmp_agg_method %||% "mean", hist_sim()$so
      )
      keep <- tbl$rp_name %in% unname(rp_map)
      out <- tbl[keep, c("scenario", "rp_name", "value", "n_obs"), drop = FALSE]
      if (!nrow(out)) return(NULL)
      out$rp_label <- names(rp_map)[match(out$rp_name, unname(rp_map))]
      rp_order <- c("Expected", "Adverse 1-in-5", "Adverse 1-in-10", "Adverse 1-in-20", "Adverse 1-in-50")
      out <- out[order(out$scenario, match(out$rp_label, rp_order)), ]
      wide <- tidyr::pivot_wider(out, names_from = rp_label, values_from = value)

      hist_val <- if ("Expected" %in% names(wide) && any(wide$scenario == "Historical")) {
        wide$Expected[wide$scenario == "Historical"][1L]
      } else NA_real_

      if (is.finite(hist_val) && "Expected" %in% names(wide)) {
        wide$`Change from historical` <- ifelse(
          wide$scenario == "Historical",
          NA_real_,
          wide$Expected - hist_val
        )
      }
      wide
    })
    wise_export_table(
      key = "climate_decision_thresholds",
      label = "Decision return-period summary",
      step = 2L,
      fun = function() annotate_visualization_export(
        decision_threshold_df(), input$cmp_agg_method %||% "mean", hist_sim()$so,
        observation_unit = "scenario-period annual aggregate at supported return period",
        aggregation_order = "per-model return-period interpolation, then median across equally weighted models",
        uncertainty = "central estimate; technical uncertainty rows exported separately"
      ),
      description = "Decision-first expected and adverse return-period summary."
    )

    output$decision_table_html <- renderUI({
      req(decision_threshold_df())
      df <- decision_threshold_df()
      so <- if (!is.null(hist_sim())) hist_sim()$so else NULL
      meta <- metric_metadata(input$cmp_agg_method %||% "mean", so)
      sub_txt <- paste0("Outcome: ", meta$label, if (nzchar(meta$unit)) paste0(" (", meta$unit, ")") else "")
      make_decision_table_html(
        df,
        subheader = sub_txt,
        footnotes = c(
          "Typical (Expected) shows the central annual aggregate across weather years and climate models.",
          "Adverse return-period thresholds reflect simulated outcomes reached or exceeded in the unfavorable direction.",
          "Change from historical compares scenario expected outcome to the fixed baseline population under historical weather."
        )
      )
    })
    outputOptions(output, "decision_table_html", suspendWhenHidden = TRUE)

    output$decision_csv <- csv_download_handler("climate_decision_summary", function() decision_threshold_df())
    output$threshold_csv <- csv_download_handler("climate_technical_thresholds", function() threshold_table_df())

    output$uncertainty_sources_plot <- renderPlot({
      req(variance_breakdown_rv())
      plot_variance_contribution(variance_breakdown_rv())
    }, height = 300)
    outputOptions(output, "uncertainty_sources_plot", suspendWhenHidden = TRUE)

    adverse_dot_data_rv <- reactive({
      req(threshold_table_rv())
      step2_adverse_dot_data(
        threshold_table_rv(),
        method = input$cmp_agg_method %||% "mean",
        so = hist_sim()$so
      )
    })
    output$adverse_dot_plot <- renderPlot({
      req(adverse_dot_data_rv())
      plot_step2_adverse_dot(
        adverse_dot_data_rv(),
        x_label = metric_axis_label(
          input$cmp_agg_method %||% "mean",
          hist_sim()$so,
          input$cmp_deviation %||% "none"
        )
      )
    }, height = 380)
    outputOptions(output, "adverse_dot_plot", suspendWhenHidden = TRUE)

    wise_export_figure(
      key = "climate_adverse_return_periods",
      label = "Outcome in adverse weather years",
      step = 2L,
      fun = function() {
        plot_step2_adverse_dot(
          adverse_dot_data_rv(),
          x_label = metric_axis_label(
            input$cmp_agg_method %||% "mean",
            hist_sim()$so,
            input$cmp_deviation %||% "none"
          )
        )
      },
      description = "Expected and adverse return-period outcomes with inter-model ensemble spread.",
      width = 9, height = 5
    )

    wise_export_table(
      key   = "climate_outcome_thresholds",
      label = "Outcome threshold exceedance",
      step  = 2L,
      fun   = threshold_table_df,
      description = paste(
        "Simulated welfare outcomes against each threshold, by climate",
        "scenario and projection period, with uncertainty bounds."
      )
    )

    output$summary_threshold_table <- DT::renderDT({
      req(threshold_table_rv())
      tbl <- threshold_table_rv()
      if (!nrow(tbl) || !"Estimate" %in% names(tbl)) {
        return(DT::datatable(data.frame(Message = "Insufficient data"),
                             rownames = FALSE, class = "compact stripe",
                             options  = list(dom = "t")))
      }
      if (!isTRUE(input$show_model_spread)) {
        tbl <- tbl[!grepl("^Ensemble |^Pooled ", tbl$Estimate), , drop = FALSE]
      }
      df <- build_threshold_table_df(
        threshold_tbl = tbl,
        group_order   = input$cmp_group_order %||% "scenario_x_year",
        show_coef     = isTRUE(input$show_coef_uncertainty) && has_draws()
      )
      if (is.null(df) || nrow(df) == 0L)
        return(DT::datatable(data.frame(Message = "Insufficient data"),
                             rownames = FALSE, class = "compact stripe",
                             options  = list(dom = "t")))
      # INT-08: export is disabled while the results are stale - the table
      # stays visible, the CSV button does not.
      dt_buttons <- wise_csv_button("outcome_thresholds",
                                    enabled = !isTRUE(stale()))
      DT::datatable(
        df, rownames = FALSE, class = "compact stripe",
        options = list(
          pageLength = 15, dom = wise_csv_dom("tip"),
          ordering = list(list(2, "desc")),
          columnDefs = list(list(className = "dt-center", targets = "_all")),
          buttons = dt_buttons
        ),
        extensions = "Buttons"
      )
    })

    output$threshold_table_header <- renderUI({
      req(agg_hist())
      tagList(
        shiny::h4(
          "Outcome value at return-period thresholds (both tails)",
          info_popover(
            title = "Return-period thresholds",
            shiny::p(shiny::tags$b("Central (P50)"),
              " = across-model median of each model's return-period value (or the single historical curve)."),
            shiny::p(shiny::tags$b("Coef Pxx"),
              " = analytic per-outcome SE band around the central value (coefficient + residual uncertainty). Percentiles follow the 'Coefficient uncertainty band' selector."),
            shiny::p(shiny::tags$b("Ensemble Pxx / min / max"),
              " (future only) = quantile of per-model return-period values across CMIP6 ensemble members. Percentiles follow the 'Weather + model spread band' selector."),
            shiny::p(shiny::tags$b("Pooled Pxx"),
              " = combined band assuming independence: SE_pooled = sqrt(coef_SE\u00B2 + var_across_models). Future scenarios only - for historical (no inter-model component) Pooled would equal Coef and is not reported."),
            shiny::p(
              "Low odds show the value exceeded in only 1-in-N years; high odds",
              "= value reached in all but 1-in-N years; 1:1 is the median year."
            ),
            shiny::p(
              "Obs = number of simulated years feeding each per-model exceedance",
              "curve. Return periods that fall outside the empirical range",
              "supported by Obs (probability < 0.5/Obs or > 1 - 0.5/Obs) are not",
              "reported rather than extrapolated."
            ),
            docs = TRUE
          )
        ),
        shiny::tags$small(class = "text-muted", table_subtitle())
      )
    })

    output$threshold_table_footer <- renderUI({
      req(agg_hist())
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:6px;",
        "Central = median estimate; Coef/Ensemble/Pooled = uncertainty bands - click ",
        shiny::icon("circle-info"), " above for definitions."
      )
    })

    # UI-48: the exceedance curve, for the export bundle.
    wise_export_figure(
      key   = "climate_exceedance_curve",
      label = "Welfare exceedance probability",
      step  = 2L,
      fun   = function() {
        curves <- exceedance_curves_rv()
        ah     <- agg_hist()
        if (is.null(curves) || is.null(ah)) return(NULL)
        ens_q <- if (isTRUE(input$show_model_spread))
          resolve_band_q(input$ensemble_band %||% "minmax")
        else c(lo = 0.5, hi = 0.5)
        enhance_exceedance(
          curves_tbl      = curves,
          x_label         = ah$x_label,
          return_period   = isTRUE(input$show_return_period),
          n_sim_years     = nrow(ah$out),
          logit_x         = isTRUE(input$exceedance_logit_x),
          band_q          = if (isTRUE(input$show_coef_uncertainty) && has_draws())
                              resolve_band_q(input$uncertainty_band %||% "p10_p90")
                            else NULL,
          ensemble_band_q = ens_q
        )
      },
      description = paste(
        "Probability of welfare falling below each level, by climate scenario",
        "and projection period."
      ),
      width = 10, height = 6.5
    )

    output$exceedance_plot <- renderPlot({
      req(exceedance_curves_rv())
      ens_q <- if (isTRUE(input$show_model_spread))
        resolve_band_q(input$ensemble_band %||% "minmax")
      else c(lo = 0.5, hi = 0.5)
      enhance_exceedance(
        curves_tbl      = exceedance_curves_rv(),
        x_label         = agg_hist()$x_label,
        return_period   = isTRUE(input$show_return_period),
        n_sim_years     = nrow(agg_hist()$out),
        logit_x         = isTRUE(input$exceedance_logit_x),
        band_q          = if (isTRUE(input$show_coef_uncertainty) && has_draws())
                            resolve_band_q(input$uncertainty_band %||% "p10_p90")
                          else NULL,
        ensemble_band_q = ens_q
      )
    })

    output$exceedance_caption <- renderUI({
      req(agg_hist())
      axis_txt <- if (isTRUE(input$exceedance_logit_x))
        "Probability axis is logit-scaled, giving equal visual weight to both tails."
      else
        "Annual exceedance probability - each curve is computed over the simulation years."
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:6px;",
        axis_txt
      )
    })


    # ---- observeEvent handlers ---------------------------------------------

    # Insert Results tab + content on first hist_sim; remove it again when
    # hist_sim is cleared (INT-07) so the empty state returns and a later
    # run re-inserts a fresh tab instead of writing into a stale one.
    results_tab_added <- reactiveVal(FALSE)

    observeEvent(hist_sim(), {
      if (is.null(hist_sim())) {
        if (results_tab_added()) {
          shiny::removeTab(
            inputId = tabset_id,
            target  = "sim_tab",
            session = tabset_session
          )
          results_tab_added(FALSE)
        }
        return()
      }

      # UI-50: only ever one Results tab. This used to append unconditionally,
      # so every re-run of Step 2 added another copy - and because the new tab
      # carried a second `#results_section`, the `insertUI()` below targeted
      # the *first* match, filling the original tab and leaving the new one
      # empty. Steps 1 and 3 already guarded their appends; this brings Step 2
      # into line.
      if (!results_tab_added()) {
        shiny::appendTab(
          inputId = tabset_id,
          shiny::tabPanel(
            title = "Results",
            value = "sim_tab",
            shiny::div(id = "results_section")
          ),
          select  = TRUE,
          session = tabset_session
        )
        results_tab_added(TRUE)
      } else {
        # The tab is already there. Clear its contents so the re-run's results
        # replace the previous run's rather than stacking beneath them - the
        # pane is built from `hist_sim()$so`, which a new run may have changed.
        # Both this and the insert below are deferred to the end of the flush
        # and run in call order, so the clear always precedes the rewrite.
        # Deferring also keeps the first-run path byte-for-byte as it was:
        # appendTab's DOM insertion lands before anything targets
        # #results_section.
        shiny::removeUI(selector = "#results_section > *", multiple = TRUE)
        try(shiny::updateTabsetPanel(tabset_session, inputId = tabset_id,
                                     selected = "sim_tab"), silent = TRUE)
      }

      sw_obj <- tryCatch(if (is.function(selected_weather)) selected_weather() else selected_weather, error = function(e) NULL)
      wx_lbl <- if (!is.null(sw_obj) && "label" %in% names(sw_obj) && length(sw_obj$label)) {
        paste(tolower(sw_obj$label), collapse = ", ")
      } else if (!is.null(sw_obj) && "name" %in% names(sw_obj) && length(sw_obj$name)) {
        paste(tolower(sw_obj$name), collapse = ", ")
      } else {
        ""
      }

      shiny::insertUI(
        selector = "#results_section",
        where    = "afterBegin",
        ui       = .results_content_ui(ns, hist_sim()$so, weather_var = wx_lbl)
      )
    }, ignoreInit = TRUE, ignoreNULL = FALSE)

    # On subsequent runs, just re-select the tab.
    observeEvent(hist_sim(), {
      if (!is.null(hist_sim())) {
        shiny::updateTabsetPanel(
          session  = tabset_session,
          inputId  = tabset_id,
          selected = "sim_tab"
        )
      }
    }, ignoreInit = TRUE)

    # Keep agg method choices in sync with outcome.
    observeEvent(hist_sim(), {
      req(hist_sim()$so)
      so      <- hist_sim()$so
      choices <- hist_aggregate_choices(so$type, so$name)
      current <- isolate(input$cmp_agg_method)
      new_sel <- if (!is.null(current) && current %in% choices) current else "mean"
      shiny::updateRadioButtons(session, "cmp_agg_method",
                                choices  = choices,
                                selected = new_sel,
                                inline   = TRUE)
    }, ignoreInit = TRUE)

    # ---- Suspend outputs when Results tab is hidden ----------------------
    outputOptions(output, "summary_box_plot",        suspendWhenHidden = TRUE)
    outputOptions(output, "annual_distribution_plot", suspendWhenHidden = TRUE)
    outputOptions(output, "summary_threshold_table", suspendWhenHidden = TRUE)
    outputOptions(output, "exceedance_plot",         suspendWhenHidden = TRUE)
    outputOptions(output, "scenario_filter_ui",      suspendWhenHidden = TRUE)
    outputOptions(output, "threshold_table_header",  suspendWhenHidden = TRUE)
    outputOptions(output, "threshold_table_footer",  suspendWhenHidden = TRUE)
    outputOptions(output, "exceedance_caption",      suspendWhenHidden = TRUE)
    
    # ---- Return API --------------------------------------------------------
    # timeseries_curves bundles everything the Diagnostics tab needs to render
    # the per-model trajectories plot (the plot lives there now): the
    # per-(scenario, model, sim_year) table, the x-axis label, and the
    # inter-model band quantiles resolved from the Results-tab controls.
    list(
      variance_breakdown = variance_breakdown_rv,
      results_tab_added  = results_tab_added,
      timeseries_curves  = reactive({
        req(timeseries_curves_rv())
        ens_q <- if (isTRUE(input$show_model_spread))
          resolve_band_q(input$ensemble_band %||% "minmax")
        else c(lo = 0.5, hi = 0.5)
        list(
          tbl     = timeseries_curves_rv(),
          x_label = agg_hist()$x_label,
          ens_q   = ens_q
        )
      })
    )
  })
}
