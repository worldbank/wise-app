#' Select the simulated year corresponding to a weather basis.
#'
#' @noRd
select_decomp_weather_basis <- function(decomp_df, basis = "mean", so = NULL) {
  if (is.null(decomp_df) || !is.data.frame(decomp_df) || !nrow(decomp_df) ||
      identical(basis, "mean") || !"sim_year" %in% names(decomp_df) ||
      !"delta_total" %in% names(decomp_df)) {
    return(decomp_df)
  }

  target <- if (identical(basis, "adverse_10")) 0.10 else 0.05
  year_total <- tapply(seq_len(nrow(decomp_df)), decomp_df$sim_year, function(idx) {
    vals <- as.numeric(decomp_df$delta_total[idx])
    w <- if ("weight" %in% names(decomp_df)) as.numeric(decomp_df$weight[idx]) else rep(1, length(idx))
    ok <- is.finite(vals) & is.finite(w) & w > 0
    if (!any(ok)) return(NA_real_)
    stats::weighted.mean(vals[ok], w[ok])
  })
  year_total <- year_total[is.finite(year_total)]
  if (!length(year_total)) return(decomp_df)

  adverse_high <- identical(
    outcome_direction(so$name %||% "welfare", so$type %||% "numeric"),
    "lower_is_better"
  )
  ordered <- order(year_total, decreasing = adverse_high)
  take <- max(1L, min(length(ordered), round(length(ordered) * target)))
  selected_year <- names(year_total)[ordered[[take]]]
  decomp_df[as.character(decomp_df$sim_year) == selected_year, , drop = FALSE]
}

#' 3_09_decomposition UI Function
#'
#' @description A shiny Module. Renders the policy effect decomposition
#'   visualizations: stacked bar chart by decile, beta curve (RIF only),
#'   and summary table.
#'
#' @param id Internal parameter for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_3_09_decomposition_ui <- function(id) {
  ns <- NS(id)
  tagList(
    shiny::uiOutput(ns("policy_summary_ui")),
    shiny::h4(
      "What drives the total policy effect?",
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      pill_toggle(
        ns("decomp_weather_basis"),
        label = "Weather-year basis",
        choices = c(
          "Mean" = "mean",
          "Adverse 1-in-10" = "adverse_10",
          "Adverse 1-in-20" = "adverse_20"
        ),
        selected = "mean",
        layout = "horizontal"
      ),
      wise_plot_output(ns("headline_decomp_plot"),
                       "Main effect, resilience, and total policy effect decomposition",
                       height = "360px"),
      DT::DTOutput(ns("headline_decomp_table")),
      shiny::uiOutput(ns("headline_decomp_note_ui"))
    ),

    shiny::h4(
      "Who gains, and through which channel?",
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      shiny::div(
        style = "display: flex; gap: 14px; flex-wrap: wrap; align-items: center; margin-bottom: 8px;",
        pill_toggle(
          ns("decile_weather_basis"),
          label = "Weather-year basis",
          choices = c("Mean" = "mean", "Adverse 1-in-10" = "adverse_10", "Adverse 1-in-20" = "adverse_20"),
          selected = "mean",
          layout = "horizontal"
        ),
        shiny::uiOutput(ns("decile_scenario_ui"))
      ),
      wise_plot_output(ns("decomp_bar_plot"),
                       "Stacked policy-effect channels by baseline welfare decile",
                       height = "450px"),
      shiny::uiOutput(ns("decomp_bar_note_ui"))
    ),

    shiny::uiOutput(ns("beta_curve_ui")),

    shiny::h4(
      "How do decomposition channels vary by weather year?",
      class = "diagnostic-section-heading"
    ),
    shiny::div(
      class = "results-section-card diagnostic-section-card",
      DT::DTOutput(ns("decomp_summary_table")),
      shiny::uiOutput(ns("interaction_warning_ui")),
      shiny::tags$p(class = "diagnostic-note",
                    "Columns show weighted policy effects under mean weather and adverse historical weather years. Coefficient SE is the delta-method standard error from the fitted coefficient covariance; it is not a 95% confidence interval. Residual and survey-sampling uncertainty are not included.")
    )
  )
}

#' 3_09_decomposition Server Functions
#'
#' @param id Module id.
#' @param decomp_result Reactive data frame from decompose_policy_effect().
#' @param decomp_scenarios Reactive data frame: per-scenario decompositions.
#' @param model_fit Reactive model fit list (for rif_grid / engine detection).
#' @param so Reactive selected outcome metadata.
#' @param selected_policies Reactive selected policy scenario keys.
#' @param baseline_hist_sim Reactive Step 2-style baseline simulation result.
#' @param baseline_svy      Reactive baseline survey used for fixed deciles.
#' @param policy_svy        Reactive realized policy survey.
#' @param selected_weather Reactive selected weather specification.
#' @param policy_saved_scenarios Reactive named future scenario list.
#'
#' @noRd
mod_3_09_decomposition_server <- function(id,
                                           decomp_result     = reactive(NULL),
                                           decomp_scenarios  = reactive(list()),
                                           model_fit         = reactive(NULL),
                                           variable_list     = reactive(NULL),
                                           so                = reactive(NULL),
                                           show_coef_uncertainty = reactive(TRUE),
                                           selected_policies = reactive(NULL),
                                           policy_scenarios = reactive(list()),
                                           baseline_hist_sim = reactive(NULL),
                                           baseline_svy = reactive(NULL),
                                           policy_svy = reactive(NULL),
                                            selected_weather = reactive(NULL),
                                            sp_scenario = reactive(NULL),
                                            infra_scenario = reactive(NULL),
                                            digital_scenario = reactive(NULL),
                                            labor_scenario = reactive(NULL),
                                            education_scenario = reactive(NULL),
                                            policy_saved_scenarios = reactive(list())) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    is_rif <- reactive({
      mf <- model_fit()
      !is.null(mf) && identical(tolower(as.character(mf$engine %||% "")), "rif")
    })

    output$policy_summary_ui <- shiny::renderUI({
      policy_summary_card(
        selected_policies = selected_policies(),
        baseline_hist_sim = baseline_hist_sim(),
        selected_weather = selected_weather(),
        sp_scenario = sp_scenario(),
        infra_scenario = infra_scenario(),
        digital_scenario = digital_scenario(),
        labor_scenario = labor_scenario(),
        education_scenario = education_scenario(),
        policy_saved_scenarios = policy_saved_scenarios(),
        policy_scenarios = policy_scenarios()
      )
    })

    get_label <- function(var_name) {
      vl <- if (is.function(variable_list)) variable_list() else variable_list
      if (is.null(vl) || is.null(var_name) || length(var_name) == 0) {
        return(if (is.null(var_name)) "" else as.character(var_name))
      }
      idx <- match(var_name, vl$name)
      if (length(idx) == 0 || is.na(idx)) var_name
      else as.character(vl$label[idx])
    }

    weather_basis_label <- reactive({
      switch(input$decomp_weather_basis %||% "mean",
             mean = "mean historical-baseline weather",
             adverse_10 = "adverse 1-in-10 historical weather year",
             adverse_20 = "adverse 1-in-20 historical weather year",
             "mean historical-baseline weather")
    })

    historical_weather_basis_for_probability <- function(target_p) {
      hs <- baseline_hist_sim()
      if (is.null(hs) || is.null(hs$weather_raw)) return(NULL)
      raw <- step2_resolve_weather(hs$weather_raw, hs)
      if (is.null(raw) || !nrow(raw)) return(NULL)
      if (is.null(target_p)) return(raw)
      if (!"timestamp" %in% names(raw)) return(raw)
      years <- as.integer(format(raw$timestamp, "%Y"))
      year_values <- split(raw, years)
      pipe <- hs$pipeline
      if (is.null(pipe) || is.null(pipe$y_point) || is.null(pipe$sim_year)) return(raw)
      simulated_years <- split(seq_along(pipe$y_point), pipe$sim_year)
      annual_values <- vapply(simulated_years, function(idx) {
        vals <- as.numeric(pipe$y_point[idx])
        weights <- if (!is.null(pipe$weight)) as.numeric(pipe$weight[idx]) else NULL
        if (is.null(weights)) mean(vals, na.rm = TRUE) else
          stats::weighted.mean(vals, weights, na.rm = TRUE)
      }, numeric(1L))
      # Select the most adverse observed annual outcome using the same metric
      # direction contract as the Results plots.
      agg <- annual_values[names(annual_values) %in% names(year_values)]
      adverse_high <- identical(
        outcome_direction(hs$so$name %||% "welfare", hs$so$type %||% "numeric"),
        "lower_is_better"
      )
      ordered <- order(agg, decreasing = adverse_high)
      take <- max(1L, min(length(ordered), round(length(ordered) * target_p)))
      year_values[[names(agg)[ordered[[take]]]]]
    }

    historical_weather_for_basis <- function(basis) {
      if (identical(basis, "mean")) return(historical_weather_basis_for_probability(NULL))
      historical_weather_basis_for_probability(
        if (identical(basis, "adverse_10")) 0.10 else 0.05
      )
    }
    historical_weather_basis <- reactive({
      historical_weather_for_basis(input$decomp_weather_basis %||% "mean")
    })

    decomp_for_basis <- function(basis) {
      if (identical(basis, "mean")) return(decomp_result())
      hs <- baseline_hist_sim()
      svy_b <- baseline_svy(); svy_p <- policy_svy(); mf <- model_fit()
      if (is.null(hs) || is.null(svy_b) || is.null(svy_p) || is.null(mf)) return(decomp_result())
      tryCatch(
        decompose_policy_effect(
          svy_baseline = svy_b, svy_policy = svy_p, model_fit = mf,
          so = hs$so, weather_raw = historical_weather_for_basis(basis),
          skip_coef = !isTRUE(show_coef_uncertainty())
        ),
        error = function(e) decomp_result()
      )
    }
    selected_decomp_result <- reactive({
      decomp_for_basis(input$decomp_weather_basis %||% "mean")
    })

    headline_decomp_data <- reactive({
      basis <- input$decomp_weather_basis %||% "mean"
      outcome <- so() %||% list()
      hist <- decomposition_summary_data(selected_decomp_result(), is_rif())
      hist$scenario <- "Historical"
      sc <- decomp_scenarios()
      if (is.null(sc) || !is.data.frame(sc) || !nrow(sc)) return(hist)
      future <- dplyr::bind_rows(lapply(split(sc, sc$scenario), function(x) {
        x <- select_decomp_weather_basis(x, basis, outcome)
        out <- decomposition_summary_data(x, is_rif())
        out$scenario <- as.character(x$scenario[[1L]])
        out
      }))
      dplyr::bind_rows(hist, future)
    })
    output$headline_decomp_note_ui <- renderUI({
      shiny::tags$p(class = "diagnostic-note", paste0(
        "This figure summarizes the policy effect using ", weather_basis_label(),
        ". It is not a future climate-scenario result."
      ))
    })
    output$headline_decomp_plot <- renderPlot({
      req(headline_decomp_data())
      plot_decomposition_headline(headline_decomp_data())
    }, height = 360)
    # The Decomposition UI is inserted after the server starts. Keep plots
    # live before their DOM nodes exist so they render immediately on tab open.
    outputOptions(output, "headline_decomp_plot", suspendWhenHidden = FALSE)
    output$headline_decomp_table <- DT::renderDT({
      req(headline_decomp_data())
      tbl <- headline_decomp_data()
      tbl <- tbl[tbl$channel_id %in% c("level", "resilience", "total"), , drop = FALSE]
      tbl <- data.frame(
        Scenario = tbl$scenario,
        `Effect component` = tbl$channel,
        `Mean effect (%)` = round(tbl$percent, 2),
        `Share of total (%)` = round(100 * tbl$share_of_total, 1),
        check.names = FALSE
      )
      DT::datatable(
        tbl,
        rownames = FALSE, class = "compact stripe",
        extensions = "Buttons",
        options = list(dom = wise_csv_dom("t"),
                       buttons = wise_csv_button("policy_decomposition_headline_data"))
      )
    })
    outputOptions(output, "headline_decomp_table", suspendWhenHidden = FALSE)
    wise_export_figure(
      key = "policy_decomposition_headline",
      label = "Headline main effect and resilience decomposition",
      step = 3L,
      fun = function() plot_decomposition_headline(headline_decomp_data()),
      description = "Headline decomposition into main effect, resilience, and total effects with reconciliation on the model scale.",
      width = 9, height = 5
    )
    wise_export_table(
      key = "policy_decomposition_headline_data",
      label = "Headline decomposition data",
      step = 3L,
      fun = function() {
        out <- headline_decomp_data()
        out <- out[out$channel_id %in% c("level", "resilience", "total"), , drop = FALSE]
        data.frame(
          Scenario = out$scenario,
          `Effect component` = out$channel,
          `Mean effect (%)` = round(out$percent, 2),
          `Share of total (%)` = round(100 * out$share_of_total, 1),
          check.names = FALSE
        )
      },
      description = "Mean-historical-weather decomposition into main effect, resilience, and total policy effects."
    )

    # --- Stacked bar chart by decile ---
    # UI-48: register Step 3's decomposition figures for the export bundle.
    wise_export_figure(
      key   = "policy_decomposition_channels",
      label = "Policy effect by channel",
      step  = 3L,
      fun   = function() {
        res <- selected_decomp_result()
        if (is.null(res) || !is.data.frame(res) || nrow(res) == 0) return(NULL)
          plot_decomposition_channels_by_decile(
            decomposition_channels_by_decile(res, baseline_svy(), so()$name %||% "welfare", is_rif()),
            is_rif()
        )
      },
      description = paste(
        "The policy effect split into its main effect and resilience",
        "channels (repositioning and weather interaction)."
      ),
      width = 9, height = 6
    )
    wise_export_table(
      key = "policy_decomposition_channels_by_decile",
      label = "Decomposition channels by baseline decile",
      step = 3L,
       fun = function() decomposition_decile_export(
          decomposition_channels_by_decile(
            selected_decomp_result(), baseline_svy(), so()$name %||% "welfare", is_rif()
         ),
         is_rif()
       ),
        description = "Engine-specific decomposition channels, total, and counts by fixed weighted baseline welfare decile."
    )

    output$decile_scenario_ui <- shiny::renderUI({
      sc <- decomp_scenarios()
      choices <- c("Historical" = "Historical")
      if (is.data.frame(sc) && nrow(sc) && "scenario" %in% names(sc)) {
        future <- unique(as.character(sc$scenario))
        choices <- c(choices, stats::setNames(future, future))
      }
      pill_toggle(ns("decile_scenario"), label = "Scenario", choices = choices,
                  selected = isolate(input$decile_scenario) %||% "Historical",
                  layout = "horizontal")
    })

    decile_decomp_data <- reactive({
      outcome <- so()
      if (is.null(outcome)) {
        return(tibble::tibble())
      }
      scenario <- input$decile_scenario %||% "Historical"
      basis <- input$decile_weather_basis %||% "mean"
      if (identical(scenario, "Historical")) {
        res <- decomp_for_basis(basis)
      } else {
        sc <- decomp_scenarios()
        res <- if (is.data.frame(sc) && nrow(sc))
          sc[sc$scenario == scenario, , drop = FALSE] else NULL
        res <- select_decomp_weather_basis(res, basis, outcome)
      }
      if (is.null(res) || !is.data.frame(res) || !nrow(res)) return(tibble::tibble())
      decomposition_channels_by_decile(
        res, baseline_svy(), outcome$name %||% "welfare", is_rif()
      )
    })

    output$decomp_bar_plot <- shiny::renderPlot({
      plot_decomposition_channels_by_decile(
        decile_decomp_data(),
        is_rif()
      )
    }, height = 450)
    outputOptions(output, "decomp_bar_plot", suspendWhenHidden = FALSE)
    wise_export_figure(
      key = "policy_decomposition_channels_selected",
      label = "Selected policy decomposition channels",
      step = 3L,
      fun = function() {
        plot_decomposition_channels_by_decile(
          decile_decomp_data(),
          is_rif()
        )
      },
      description = "Policy-effect channels by fixed baseline welfare decile for the selected scenario and weather basis.",
      width = 9, height = 6
    )
    output$decomp_bar_note_ui <- renderUI({
      basis <- input$decile_weather_basis %||% "mean"
      basis_label <- switch(
        basis,
        adverse_10 = "adverse 1-in-10 historical weather year",
        adverse_20 = "adverse 1-in-20 historical weather year",
        "mean historical-baseline weather"
      )
      shiny::tags$p(
        class = "diagnostic-note",
        paste0(
          "Decile 1 is the poorest. Stacked bars separate direct transfer, covariate shift, weather-policy interaction, and - for RIF models only - repositioning. The marker shows the total policy effect for ",
          basis_label, " under the ", input$decile_scenario %||% "Historical",
          " scenario. Deciles are fixed from weighted observed baseline welfare."
        )
      )
    })

    # --- Beta curve (RIF only): one panel per weather variable -------------
    output$beta_curve_ui <- renderUI({
      if (!is_rif()) return(NULL)
      mf <- model_fit()
      if (is.null(mf$rif_grid)) return(NULL)
      n_vars <- length(mf$weather_terms %||% character(0))
      if (n_vars == 0) return(NULL)

      shiny::tagList(
        shiny::h4(
          "How does weather sensitivity vary across the welfare distribution?",
          class = "diagnostic-section-heading"
        ),
        shiny::div(
          class = "results-section-card diagnostic-section-card",
          weather_plot_layout(
            ns, n_vars,
            ids    = c("beta_curve_plot1", "beta_curve_plot2"),
            height = "400px",
            alts   = paste("Beta curve plot: unconditional quantile regression weather",
                           "sensitivity across welfare quantiles for",
                           mf$weather_terms)
          ),
          shiny::tags$p(
            class = "diagnostic-note",
            "Shows how weather sensitivity varies by quantile.",
            "Repositioning exists only for RIF models and arises when households move along this curve."
          )
        )
      )
    })

    .render_beta_curve <- function(idx) {
      shiny::renderPlot({
        req(is_rif(), model_fit())
        mf <- model_fit()
        req(length(mf$weather_terms) >= idx)
        make_weather_effect_plot(
          fit               = NULL,
          pred_var          = mf$weather_terms[idx],
          interaction_terms = mf$interaction_terms %||% character(0),
          is_binned         = FALSE,
          label_fun         = get_label,
          engine            = "rif",
          rif_grid          = mf$rif_grid
        )
      })
    }

    output$beta_curve_plot1 <- .render_beta_curve(1L)
    output$beta_curve_plot2 <- .render_beta_curve(2L)
    outputOptions(output, "beta_curve_plot1", suspendWhenHidden = FALSE)
    outputOptions(output, "beta_curve_plot2", suspendWhenHidden = FALSE)

    for (idx in seq_len(2L)) local({
      i <- idx
      wise_export_figure(
        key = paste0("policy_rif_weather_curve_", i),
        label = paste("RIF weather-sensitivity curve", i),
        step = 3L,
        fun = function() {
          req(is_rif(), model_fit())
          mf <- model_fit()
          req(length(mf$weather_terms) >= i)
          make_weather_effect_plot(
            fit = NULL, pred_var = mf$weather_terms[i],
            interaction_terms = mf$interaction_terms %||% character(0),
            is_binned = FALSE, label_fun = get_label,
            engine = "rif", rif_grid = mf$rif_grid
          )
        },
        description = "RIF weather coefficient by baseline welfare quantile; interpolation is limited to the estimated grid.",
        width = 9, height = 6
      )
    })

    technical_decomp_table <- reactive({
      bases <- list(
        `Mean weather` = decomp_result(),
        `Adverse 1-in-5` = tryCatch(
          decompose_policy_effect(
            baseline_svy(), policy_svy(), model_fit(), baseline_hist_sim()$so,
            weather_raw = historical_weather_basis_for_probability(0.20),
            skip_coef = !isTRUE(show_coef_uncertainty())
          ), error = function(e) NULL),
        `Adverse 1-in-10` = tryCatch(
          decompose_policy_effect(
            baseline_svy(), policy_svy(), model_fit(), baseline_hist_sim()$so,
            weather_raw = historical_weather_basis_for_probability(0.10),
            skip_coef = !isTRUE(show_coef_uncertainty())
          ), error = function(e) NULL),
        `Adverse 1-in-20` = tryCatch(
          decompose_policy_effect(
            baseline_svy(), policy_svy(), model_fit(), baseline_hist_sim()$so,
            weather_raw = historical_weather_basis_for_probability(0.05),
            skip_coef = !isTRUE(show_coef_uncertainty())
          ), error = function(e) NULL)
      )
      .build_decomp_table_by_basis(bases, is_rif())
    })

    # --- Summary table ---
    output$decomp_summary_table <- DT::renderDT({
      req(technical_decomp_table())
      tbl <- technical_decomp_table()
      numeric_targets <- if (ncol(tbl) > 1L) seq.int(1L, ncol(tbl) - 1L) else integer(0)
      DT::datatable(
        tbl,
        rownames = FALSE, class = "compact stripe", extensions = "Buttons",
        options = list(
          dom = wise_csv_dom("t"), ordering = FALSE,
          buttons = wise_csv_button("policy_decomposition_summary"),
          columnDefs = list(list(className = "dt-right", targets = numeric_targets))
        )
      )
    })
    outputOptions(output, "decomp_summary_table", suspendWhenHidden = FALSE)
    wise_export_table(
      key = "policy_decomposition_summary",
      label = "Policy decomposition summary",
      step = 3L,
      fun = function() {
        technical_decomp_table()
      },
      description = "Weighted policy-effect decomposition under mean weather and adverse historical weather years."
    )

    # --- Interaction warning ---
    output$interaction_warning_ui <- renderUI({
      res <- decomp_result()
      if (is.null(res)) return(NULL)
      if (!"delta_res2" %in% names(res) || all(abs(res$delta_res2) < 1e-10)) {
        shiny::div(
          class = "alert alert-warning",
          style = "margin-top: 10px; font-size: 13px;",
          shiny::icon("exclamation-triangle"),
          " No weather\u00d7policy interaction terms detected in the model. ",
          "The interaction channel is zero. To enable this channel, include ",
          "interaction terms between weather and policy variables in the ",
          "Step 1 model specification."
        )
      }
    })

    invisible(NULL)
  })
}


# ---------------------------------------------------------------------------- #
# Plot helpers
# ---------------------------------------------------------------------------- #

#' @noRd
.build_decomp_table <- function(decomp_df, is_rif) {
  w <- if ("weight" %in% names(decomp_df)) decomp_df$weight else rep(1, nrow(decomp_df))
  w[!is.finite(w) | w < 0] <- 0
  if (!sum(w) > 0) w <- rep(1, nrow(decomp_df))
  w_norm <- w / sum(w, na.rm = TRUE)
  has_sd <- all(c("sd_main", "sd_res1", "sd_res2", "sd_total") %in% names(decomp_df))

  # Aggregated SE on a log-scale delta given a per-household SD column.
  # Var(Sigma w*delta_i) ~ Sigma w_i^2 * Var(delta_i) under household independence.
  agg_se <- function(sd_col) {
    if (!has_sd || is.null(decomp_df[[sd_col]])) return(NA_real_)
    sqrt(sum((w_norm^2) * (decomp_df[[sd_col]])^2, na.rm = TRUE))
  }

  summary_row <- function(label, vals, sd_col = NULL) {
    mean_log <- stats::weighted.mean(vals, w, na.rm = TRUE)
    mean_pct <- (exp(mean_log) - 1) * 100
    se_log   <- if (is.null(sd_col)) NA_real_ else agg_se(sd_col)
    se_pct   <- if (is.na(se_log)) NA_real_ else abs(exp(mean_log)) * se_log * 100
    data.frame(
      Channel           = label,
      `Mean (log-pts)`  = round(mean_log, 4),
      `+/- SE (log-pts)`  = if (is.na(se_log)) NA_real_ else round(se_log, 4),
      `Mean (%)`        = round(mean_pct, 2),
      `+/- SE (%)`        = if (is.na(se_pct)) NA_real_ else round(se_pct, 2),
      `Median (%)`      = round(median((exp(vals) - 1) * 100), 2),
      check.names = FALSE
    )
  }

  rows <- list(
    summary_row("Total effect", decomp_df$delta_total, sd_col = "sd_total"),
    summary_row("Main effect (direct transfer and covariate shift)",
                decomp_df$delta_main, sd_col = "sd_main"),
    summary_row("Direct transfer component", decomp_df$delta_sp)
  )

  if (is_rif) {
    rows <- c(rows, list(
      summary_row("Repositioning effect", decomp_df$delta_res1, sd_col = "sd_res1"),
      summary_row("Weather-policy interaction", decomp_df$delta_res2, sd_col = "sd_res2")
    ))
  } else {
    rows <- c(rows, list(
      summary_row("Weather-policy interaction", decomp_df$delta_res2, sd_col = "sd_res2")
    ))
  }

  df <- do.call(rbind, rows)

  data.frame(
    `Effect component` = trimws(df$Channel),
    `Mean effect (%)` = df$`Mean (%)`,
    `Coefficient SE (%)` = df$`+/- SE (%)`,
    check.names = FALSE
  )
}

.build_decomp_table_by_basis <- function(bases, is_rif) {
  if (is.null(bases) || !length(bases)) return(data.frame())
  tables <- lapply(bases, function(x) {
    if (is.null(x) || !is.data.frame(x) || !nrow(x)) return(NULL)
    .build_decomp_table(x, is_rif)
  })
  available <- Filter(Negate(is.null), tables)
  if (!length(available)) return(data.frame())
  template <- available[[1L]]
  out <- template["Effect component"]
  for (nm in names(tables)) {
    tbl <- tables[[nm]]
    if (is.null(tbl)) {
      out[[paste0(nm, " (%)")]] <- NA_real_
      next
    }
    out[[paste0(nm, " (%)")]] <- tbl[["Mean effect (%)"]]
    if (identical(nm, "Mean weather")) {
      out[["Coefficient SE (%)"]] <- tbl[["Coefficient SE (%)"]]
    }
  }
  out
}
