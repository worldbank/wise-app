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
    shiny::uiOutput(ns("decomp_header_ui")),
    shiny::uiOutput(ns("decomp_explanation_ui")),
    shiny::uiOutput(ns("decomp_headline_cards_ui")),
    shiny::wellPanel(
      shiny::h4("Headline decomposition"),
      wise_plot_output(ns("headline_decomp_plot"),
                       "Level, resilience, and total policy effect decomposition",
                       height = "360px"),
      shiny::uiOutput(ns("reconciliation_status_ui")),
      DT::DTOutput(ns("headline_decomp_table"))
    ),
    shiny::wellPanel(
      shiny::h4(
        "Policy effect decomposition by welfare decile",
        info_popover(
          p(paste(
            "Bars show the average effect in each channel by baseline",
            "welfare decile. Decile 1 = poorest. Effects in percentage",
            "change. Weather hazard: mean of historical baseline."
          ))
        )
      ),
      wise_plot_output(ns("decomp_bar_plot"),
                       "Level and resilience policy effects by baseline welfare decile",
                       height = "450px"),
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:6px;",
        "Bars = average effect by channel and welfare decile (decile 1 = poorest)."
      )
    ),
    shiny::wellPanel(
      shiny::h4("Paired policy incidence by baseline welfare decile"),
      wise_plot_output(ns("incidence_plot"),
                       "Paired policy minus baseline effect by fixed baseline welfare decile",
                       height = "420px"),
      DT::DTOutput(ns("incidence_table")),
      shiny::tags$p(class = "text-muted small",
                    "Deciles are fixed from weighted observed baseline welfare; policy effects are not re-ranked after treatment.")
    ),
    shiny::uiOutput(ns("beta_curve_ui")),
    shiny::uiOutput(ns("scenario_range_ui")),
    shiny::wellPanel(
      shiny::h4(
        "Decomposition summary",
        info_popover(
          title = "\u00B1 SE columns",
          shiny::p(
            "Report the standard error of each channel's mean policy effect,",
            "propagated from the regression coefficient covariance via the",
            "delta method (", shiny::tags$code("SE = sqrt(\u03A3 w\u00B2 \u00B7 ||F_loading_i||\u00B2)"),
            "where F_loading_i is each household's per-coefficient gradient",
            "of that channel's contribution). Because this is a paired",
            "counterfactual on the same population, the residual and",
            "survey-sampling components cancel; only coefficient uncertainty",
            "remains."
          ),
          shiny::p(
            "The Total row's SE is computed directly from the row-summed",
            "F_loading (F_main + F_res1 + F_res2), which preserves the",
            "covariance across channels. It is ", shiny::tags$em("not"),
            "the sum of the per-channel SEs."
          ),
          docs = TRUE
        )
      ),
      DT::DTOutput(ns("decomp_summary_table")),
      shiny::h5("Hierarchical channel details"),
      DT::DTOutput(ns("decomp_channel_table")),
      shiny::uiOutput(ns("interaction_warning_ui")),
      shiny::tags$p(
        style = "font-size:11px; color:#666; margin-top:6px;",
        "\u00B1 SE = standard error of each channel's mean effect - click ",
        shiny::icon("circle-info"), " above for the formula."
      )
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
                                           baseline_hist_sim = reactive(NULL),
                                           baseline_svy = reactive(NULL),
                                           policy_svy = reactive(NULL),
                                           selected_weather = reactive(NULL),
                                           sp_scenario = reactive(NULL),
                                           policy_saved_scenarios = reactive(list())) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    is_rif <- reactive({
      mf <- model_fit()
      !is.null(mf) && identical(mf$engine, "rif")
    })

    output$policy_summary_ui <- shiny::renderUI({
      policy_summary_card(
        selected_policies = selected_policies(),
        baseline_hist_sim = baseline_hist_sim(),
        selected_weather = selected_weather(),
        sp_scenario = sp_scenario(),
        policy_saved_scenarios = policy_saved_scenarios()
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

    output$decomp_header_ui <- renderUI({
      req(decomp_result())
      engine_label <- if (is_rif()) "RIF (full: main + repositioning + interaction)"
                      else "OLS (simplified: main + interaction)"
      shiny::div(
        style = paste0(
          "border-left: 4px solid #7b3294; background: #faf5fd; ",
          "padding: 10px 14px; margin-bottom: 12px; border-radius: 3px;"
        ),
        shiny::tags$strong(style = "font-size:15px;",
                           "Policy Effect Decomposition"),
        shiny::tags$br(),
        shiny::tags$span(style = "color:#555; font-size:12px;",
                         paste0("Engine: ", engine_label)),
        shiny::tags$br(),
        shiny::div(
          class = "alert alert-info",
          style = "margin-top:8px; margin-bottom:0; font-size:12px; padding:6px 10px;",
          shiny::icon("info-circle"),
          " The decile bar chart and summary table use the ",
          shiny::tags$strong("mean weather from the historical baseline"),
          " as the weather hazard. Because weather changes across climate ",
          "scenarios and years, the decomposition channels - especially ",
          "repositioning and interaction - will differ. ",
          "See the ", shiny::tags$em("Scenario Range"), " panel below."
        )
      )
    })

    headline_decomp_data <- reactive({
      decomposition_summary_data(decomp_result(), is_rif())
    })
    output$decomp_explanation_ui <- renderUI({
      e <- decomposition_explanation(is_rif())
      shiny::tags$div(class = "alert alert-info", role = "note",
                      shiny::tags$strong(e$title), shiny::tags$br(), e$text)
    })
    output$decomp_headline_cards_ui <- renderUI({
      tbl <- headline_decomp_data()
      if (is.null(tbl) || !nrow(tbl)) return(NULL)
      value_for <- function(id) {
        x <- tbl$percent[tbl$channel_id == id]
        if (length(x) && is.finite(x[[1L]])) fmt_num(x[[1L]], 2) else "Unavailable"
      }
      sp <- sp_scenario()
      cost <- if (is.list(sp) && is.finite(sp$budget_fixed %||% NA_real_))
        paste0("$", format(round(sp$budget_fixed), big.mark = ",")) else "Not specified"
      realized <- tryCatch(.sp_transfer_totals(policy_svy(), "hh"),
                           error = function(e) NULL)
      recipients <- if (!is.null(realized)) {
        format(round(realized$n_recipients_weighted), big.mark = ",")
      } else "Unavailable"
      headline_cards_ui(list(
        list(label = "Level effect", value = value_for("level"), note = "Percent change"),
        list(label = "Resilience effect", value = value_for("resilience"), note = "Percent change"),
        list(label = "Total policy effect", value = value_for("total"), note = "Reconciled on model scale"),
        list(label = "Program cost", value = cost, note = "Configured annual budget"),
        list(label = "Beneficiaries", value = recipients,
             note = "Realized weighted recipient count")
      ))
    })
    output$headline_decomp_plot <- renderPlot({
      req(headline_decomp_data())
      plot_decomposition_headline(headline_decomp_data())
    }, height = 360)
    outputOptions(output, "headline_decomp_plot", suspendWhenHidden = TRUE)
    output$headline_decomp_table <- DT::renderDT({
      req(headline_decomp_data())
      DT::datatable(
        headline_decomp_data()[headline_decomp_data()$channel_id %in%
                                 c("level", "resilience", "total"),
                               c("channel", "log_points", "percent", "share_of_total")],
        rownames = FALSE, class = "compact stripe", options = list(dom = "t")
      )
    })
    outputOptions(output, "headline_decomp_table", suspendWhenHidden = FALSE)
    output$reconciliation_status_ui <- renderUI({
      rec <- decomposition_reconciliation(headline_decomp_data())
      if (identical(rec$status, "reconciled")) {
        shiny::tags$div(class = "alert alert-success", role = "status",
                        shiny::icon("check"),
                        " Reconciled: level plus resilience equals total on the model scale.")
      } else {
        shiny::tags$div(class = "alert alert-warning", role = "alert",
                        shiny::icon("triangle-exclamation"),
                        " Decomposition reconciliation is unavailable or outside tolerance.")
      }
    })
    wise_export_figure(
      key = "policy_decomposition_headline",
      label = "Headline level and resilience decomposition",
      step = 3L,
      fun = function() plot_decomposition_headline(headline_decomp_data()),
      description = "Headline decomposition into level, resilience, and total effects with reconciliation on the model scale.",
      width = 9, height = 5
    )
    wise_export_table(
      key = "policy_decomposition_headline_data",
      label = "Headline decomposition data",
      step = 3L,
      fun = function() {
        out <- headline_decomp_data()
        rec <- decomposition_reconciliation(out)
        out$reconciliation_status <- rec$status
        out$reconciliation_residual <- rec$residual
        out
      },
      description = "Level, resilience, total, and technical channel values with reconciliation metadata."
    )

    # --- Stacked bar chart by decile ---
    # UI-48: register Step 3's decomposition figures for the export bundle.
    wise_export_figure(
      key   = "policy_decomposition_channels",
      label = "Policy effect by channel",
      step  = 3L,
      fun   = function() {
        res <- decomp_result()
        if (is.null(res) || !is.data.frame(res) || nrow(res) == 0) return(NULL)
        plot_decomposition_channels_by_decile(
          decomposition_channels_by_decile(res, baseline_svy(), so()$name %||% "welfare")
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
      fun = function() decomposition_channels_by_decile(
        decomp_result(), baseline_svy(), so()$name %||% "welfare"
      ),
      description = "Level, resilience, total, and counts by fixed weighted baseline welfare decile."
    )

    wise_export_figure(
      key   = "policy_decomposition_by_scenario",
      label = "Policy effect range across scenarios",
      step  = 3L,
      fun   = function() {
        sc <- decomp_scenarios()
        if (is.null(sc) || !is.data.frame(sc) || nrow(sc) == 0) return(NULL)
        .plot_decomp_scenario_range(sc, is_rif())
      },
      description = paste(
        "Year-to-year range of the decomposed policy effect across the saved",
        "climate scenarios."
      ),
      width = 9, height = 6
    )
    wise_export_table(
      key = "policy_decomposition_scenario_data",
      label = "Decomposition by climate scenario",
      step = 3L,
      fun = decomp_scenarios,
      description = "Scenario-period decomposition with annual weather variation retained by channel."
    )

    output$decomp_bar_plot <- shiny::renderPlot({
      req(decomp_result())
      plot_decomposition_channels_by_decile(
        decomposition_channels_by_decile(decomp_result(), baseline_svy(), so()$name %||% "welfare")
      )
    })

    incidence_data <- reactive({
      res <- decomp_result()
      bh <- baseline_hist_sim()
      outcome <- so()
      if (is.null(res) || is.null(bh) || is.null(outcome)) return(tibble::tibble())
      step3_incidence_by_decile(res, baseline_svy(), outcome$name)
    })
    output$incidence_plot <- shiny::renderPlot({
      req(incidence_data())
      plot_incidence_by_decile(incidence_data(), "Paired policy minus baseline effect")
    }, height = 420)
    outputOptions(output, "incidence_plot", suspendWhenHidden = TRUE)
    output$incidence_table <- DT::renderDT({
      req(incidence_data())
      DT::datatable(incidence_data(), rownames = FALSE,
                    class = "compact stripe", options = list(pageLength = 10))
    })
    outputOptions(output, "incidence_table", suspendWhenHidden = FALSE)
    wise_export_figure(
      key = "policy_distributional_incidence",
      label = "Paired policy incidence by baseline decile",
      step = 3L,
      fun = function() plot_incidence_by_decile(
        incidence_data(), "Paired policy minus baseline effect"
      ),
      description = "Weighted paired policy-minus-baseline effects by fixed observed baseline welfare decile.",
      width = 10, height = 6
    )
    wise_export_table(
      key = "policy_distributional_incidence_data",
      label = "Paired policy incidence data",
      step = 3L,
      fun = function() annotate_visualization_export(
        incidence_data(), "mean", outcome,
        observation_unit = "household-level paired policy-minus-baseline effect",
        aggregation_order = "fixed weighted observed baseline decile; weighted mean over households",
        uncertainty = "paired policy contrast"
      ),
      description = "Tidy paired policy effects by fixed baseline welfare decile."
    )

    # --- Beta curve (RIF only): one panel per weather variable -------------
    output$beta_curve_ui <- renderUI({
      if (!is_rif()) return(NULL)
      mf <- model_fit()
      if (is.null(mf$rif_grid)) return(NULL)
      n_vars <- length(mf$weather_terms %||% character(0))
      if (n_vars == 0) return(NULL)

      shiny::wellPanel(
        shiny::h4("Weather beta curve across welfare distribution"),
        weather_plot_layout(
          ns, n_vars,
          ids    = c("beta_curve_plot1", "beta_curve_plot2"),
          height = "400px",
          alts   = paste("Beta curve plot: unconditional quantile regression weather",
                         "sensitivity across welfare quantiles for",
                         mf$weather_terms)
        ),
        shiny::tags$p(
          style = "font-size:11px; color:#666; margin-top:6px;",
          "Shows how weather sensitivity varies by quantile.",
          "Repositioning effect arises from households moving along this curve."
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

    # --- Scenario range panel ---
    output$scenario_range_ui <- renderUI({
      sc <- decomp_scenarios()
      if (is.null(sc) || (is.data.frame(sc) && nrow(sc) == 0) ||
          (!is.data.frame(sc) && length(sc) == 0)) return(NULL)
      shiny::wellPanel(
        shiny::h4("Policy effect decomposition across climate scenarios"),
        shiny::tags$p(
          style = "font-size:12px; color:#555; margin-bottom:8px;",
          "Each point/line is one SSP scenario \u00d7 period combination.",
          "Variation reflects changing weather conditions rather than uncertainty",
          "in the model coefficients.",
          "The dashed reference line (0) is the historical baseline mean."
        ),
         wise_plot_output(ns("scenario_range_plot"),
                          "Dot-and-line plot of the policy effect for each climate scenario and period against the historical baseline",
                          height = "420px"),
         DT::DTOutput(ns("scenario_range_table"))
      )
    })

    output$scenario_range_plot <- shiny::renderPlot({
      sc <- decomp_scenarios()
      req(!is.null(sc), is.data.frame(sc), nrow(sc) > 0)
      .plot_decomp_scenario_range(sc, is_rif())
    })
    output$scenario_range_table <- DT::renderDT({
      sc <- decomp_scenarios()
      req(!is.null(sc), is.data.frame(sc), nrow(sc) > 0)
      DT::datatable(sc, rownames = FALSE, class = "compact stripe",
                    options = list(pageLength = 20))
    })
    outputOptions(output, "scenario_range_table", suspendWhenHidden = FALSE)

    # --- Summary table ---
    output$decomp_summary_table <- DT::renderDT({
      req(decomp_result())
      .build_decomp_table(decomp_result(), is_rif())
    })

    output$decomp_channel_table <- DT::renderDT({
      req(headline_decomp_data())
      DT::datatable(
        headline_decomp_data(), rownames = FALSE, class = "compact stripe",
        extensions = "Buttons",
        options = list(dom = wise_csv_dom("tp"), pageLength = 20,
                       buttons = wise_csv_button("policy_decomposition_headline_data"))
      )
    })
    outputOptions(output, "decomp_channel_table", suspendWhenHidden = FALSE)

    # UI-48: the decomposition summary, as tidy numbers rather than the
    # rendered table's formatted strings.
    wise_export_table(
      key   = "policy_effect_decomposition",
      label = "Policy effect decomposition",
      step  = 3L,
      fun   = function() {
        res <- decomp_result()
        if (is.null(res) || !is.data.frame(res) || nrow(res) == 0) return(NULL)
        res
      },
      description = paste(
        "Per-household decomposition of the policy effect into its main",
        "effect (including the cash transfer) and resilience channels",
        "(repositioning and weather interaction), with per-channel standard",
        "deviations where available."
      )
    )

    # --- Interaction warning ---
    output$interaction_warning_ui <- renderUI({
      res <- decomp_result()
      if (is.null(res)) return(NULL)
      if (all(abs(res$delta_res2) < 1e-10)) {
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
.plot_decomp_bars <- function(decomp_df, is_rif, show_coef = TRUE) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  if (is.null(decomp_df) || nrow(decomp_df) == 0) return(NULL)

  # Aggregate by decile (weighted mean) - point estimates only. Per-channel
  # uncertainty is read off the summary table's +/- SE columns.
  agg <- do.call(rbind, lapply(sort(unique(decomp_df$decile)), function(d) {
    idx <- decomp_df$decile == d
    w <- decomp_df$weight[idx]
    if (length(w) == 0 || all(is.na(w))) return(NULL)
    data.frame(
      decile   = d,
      pct_main = stats::weighted.mean(decomp_df$pct_main[idx], w, na.rm = TRUE),
      pct_res1 = stats::weighted.mean(decomp_df$pct_res1[idx], w, na.rm = TRUE),
      pct_res2 = stats::weighted.mean(decomp_df$pct_res2[idx], w, na.rm = TRUE)
    )
  }))
  if (is.null(agg) || nrow(agg) == 0) return(NULL)

  if (is_rif) {
    long <- data.frame(
      decile  = rep(agg$decile, 3),
      channel = rep(c("Main effect", "Repositioning", "Interaction"),
                    each = nrow(agg)),
      value   = c(agg$pct_main, agg$pct_res1, agg$pct_res2)
    )
    long$channel <- factor(long$channel,
                           levels = c("Interaction", "Repositioning", "Main effect"))
  } else {
    long <- data.frame(
      decile  = rep(agg$decile, 2),
      channel = rep(c("Main effect", "Interaction"), each = nrow(agg)),
      value   = c(agg$pct_main, agg$pct_res2)
    )
    long$channel <- factor(long$channel,
                           levels = c("Interaction", "Main effect"))
  }

  ggplot2::ggplot(long, ggplot2::aes(x = factor(decile), y = value, fill = channel)) +
    ggplot2::geom_col(position = "stack", width = 0.7) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = "grey40") +
    ggplot2::scale_fill_manual(
      values = c("Main effect" = "#2166ac",
                 "Repositioning" = "#b2182b",
                 "Interaction" = "#fdae61")
    ) +
    ggplot2::labs(
      x = "Baseline welfare decile (1 = poorest)",
      y = "Effect (% change in welfare)",
      fill = "Channel"
    ) +
    theme_wise() +
    ggplot2::theme(legend.position = "bottom")
}


#' @noRd
.plot_decomp_scenario_range <- function(sc_df, is_rif = TRUE) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(NULL)
  if (is.null(sc_df) || nrow(sc_df) == 0) return(NULL)

  channels <- if (is_rif) {
    c("delta_main"  = "Main effect",
      "delta_res1"  = "Repositioning",
      "delta_res2"  = "Interaction",
      "delta_total" = "Total")
  } else {
    c("delta_main"  = "Main effect",
      "delta_res2"  = "Interaction",
      "delta_total" = "Total")
  }

  # Weighted mean per channel per scenario * sim_year
  # (each row in sc_df is a household; aggregate to year-level first).
  # One shared grouping, one grouped pass per channel (PERF-05 follow-up):
  # the old code re-split the full frame for every channel.
  has_years <- "sim_year" %in% names(sc_df) && !all(is.na(sc_df$sim_year))

  key_cols <- if (has_years) {
    c("scenario", "year_start", "year_end", "sim_year")
  } else {
    c("scenario", "year_start", "year_end")
  }

  # interaction()/split() dropped rows with missing grouping keys
  keep <- complete.cases(sc_df[key_cols])
  sc   <- sc_df[keep, , drop = FALSE]
  if (nrow(sc) == 0) return(NULL)

  g   <- collapse::GRP(sc, by = key_cols)
  first_idx <- match(seq_len(g$N.groups), g$group.id)
  w   <- sc$weight
  w[is.na(w)] <- NA_real_
  key_at <- function(col) sc[[col]][first_idx]

  agg_df <- do.call(rbind, Filter(Negate(is.null), lapply(names(channels), function(col) {
    if (!col %in% names(sc)) return(NULL)

    # weighted.mean(..., na.rm = TRUE) drops NA values but keeps Inf and
    # zero/negative weights, so only NAs are folded out here
    z <- (exp(sc[[col]]) - 1) * 100
    z[is.na(w)] <- NA_real_

    pct <- as.numeric(collapse::fmean(z, g = g, w = w, na.rm = TRUE))
    pct[is.nan(pct)] <- NA_real_

    data.frame(
      scenario   = key_at("scenario"),
      year_start = key_at("year_start"),
      year_end   = key_at("year_end"),
      sim_year   = if (has_years) key_at("sim_year") else NA_integer_,
      channel    = unname(channels[[col]]),
      pct        = pct,
      stringsAsFactors = FALSE
    )
  })))
  if (is.null(agg_df) || nrow(agg_df) == 0) return(NULL)

  agg_df$channel    <- factor(agg_df$channel, levels = unname(channels))
  agg_df$period_lbl <- ifelse(
    is.na(agg_df$year_start),
    agg_df$scenario,
    paste0(agg_df$year_start, "\u2013", agg_df$year_end)
  )
  agg_df$ssp <- sub(" / .*$", "", agg_df$scenario)

  # Channels where weather variation drives spread vs. those that are constant
  weather_sensitive <- if (is_rif) {
    c("Repositioning", "Interaction", "Total")
  } else {
    c("Interaction", "Total")
  }
  agg_df$weather_sensitive <- agg_df$channel %in% weather_sensitive

  ggplot2::ggplot(
    agg_df,
    ggplot2::aes(x = period_lbl, y = pct, colour = ssp, fill = ssp)
  ) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed",
                        colour = "grey50", linewidth = 0.5) +
    # For weather-sensitive channels: boxplot to show within-period year spread
    ggplot2::geom_boxplot(
      data = ~ dplyr::filter(.x, weather_sensitive),
      ggplot2::aes(group = interaction(period_lbl, ssp)),
      alpha = 0.25, outlier.size = 1, linewidth = 0.5,
      position = ggplot2::position_dodge(width = 0.6)
    ) +
    # For main effect (constant across years): point + line across periods
    ggplot2::geom_point(
      data = ~ dplyr::filter(.x, !weather_sensitive),
      size = 3,
      position = ggplot2::position_dodge(width = 0.6)
    ) +
    ggplot2::geom_line(
      data = ~ dplyr::filter(.x, !weather_sensitive),
      ggplot2::aes(group = ssp),
      linewidth = 0.8
    ) +
    ggplot2::facet_wrap(
      ~channel, scales = "free_y",
      ncol = if (is_rif) 2L else 3L
    ) +
    wise_scale_colour_okabe_ito(name = "SSP scenario") +
    wise_scale_fill_okabe_ito(name = "SSP scenario") +
    ggplot2::labs(
      x        = "Projection period",
      y        = "Effect (% change in welfare)",
      subtitle = paste0(
        "Main effect is constant across weather years; ",
        "boxes show within-period year-to-year variation for weather-sensitive channels"
      )
    ) +
    theme_wise() +
    ggplot2::theme(
      legend.position  = "bottom",
      axis.text.x      = ggplot2::element_text(angle = 30, hjust = 1),
      strip.text       = ggplot2::element_text(face = "bold"),
      panel.grid.minor = ggplot2::element_blank()
    )
}


#' @noRd
.build_decomp_table <- function(decomp_df, is_rif) {
  w <- decomp_df$weight
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
    summary_row("  Main effect", decomp_df$delta_main, sd_col = "sd_main"),
    summary_row("    of which: SP transfer", decomp_df$delta_sp)
  )

  if (is_rif) {
    rows <- c(rows, list(
      summary_row("  Resilience: Repositioning", decomp_df$delta_res1, sd_col = "sd_res1"),
      summary_row("  Resilience: Interaction",   decomp_df$delta_res2, sd_col = "sd_res2")
    ))
  } else {
    rows <- c(rows, list(
      summary_row("  Resilience: Interaction",   decomp_df$delta_res2, sd_col = "sd_res2")
    ))
  }

  df <- do.call(rbind, rows)

  DT::datatable(
    df, rownames = FALSE, class = "compact stripe",
    extensions = "Buttons",
    options = list(dom = wise_csv_dom("t"), ordering = FALSE,
                   buttons = wise_csv_button("policy_decomposition"),
                   columnDefs = list(list(className = "dt-right", targets = 1:5)))
  )
}
