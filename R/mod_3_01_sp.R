#' 3_01_sp UI Function
#'
#' @description A shiny Module. Social protection scenario configuration.
#'   Allows the user to define a cash transfer program (shock-responsive
#'   or regular) with budget, targeting, transfer amount, timing and
#'   delivery parameters to be applied in the policy simulation.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_3_01_sp_ui <- function(id) {
  ns <- NS(id)
  tagList(
    # UI-32: live reach/cost summary, matching the Step 1 weather/model cards.
    uiOutput(ns("sp_reach_ui")),

    # Program type - always visible ----
    uiOutput(ns("sp_type_ui")),

    # Collapsible configuration panel ----
    # Order: trigger (shock only), amount with its payment settings, targeting
    uiOutput(ns("sp_trigger_ui")),
    uiOutput(ns("sp_budget_amount_ui")),
    uiOutput(ns("sp_timing_ui")),
    uiOutput(ns("sp_targeting_ui"))
  )
}

#' 3_01_sp Server Functions
#'
#' @param id Module id.
#' @param selected_outcome Reactive one-row data frame of selected outcome
#'   from \code{mod_1_modelling_server()}.
#' @param survey_weather Reactive data frame of merged survey-weather data
#'   from \code{mod_1_modelling_server()}.
#'
#' @return A named list of reactives:
#'   \describe{
#'     \item{sp_scenario}{Named list of social protection scenario parameters.}
#'   }
#'
#' @noRd
mod_3_01_sp_server <- function(id,
                               selected_outcome = reactive(NULL),
                               survey_weather = reactive(NULL),
                               variable_list = reactive(NULL),
                               analysis_unit = reactive("hh"),
                               hist_sim = reactive(NULL),
                               selected_weather = reactive(NULL)) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    # Helper: human-readable unit word ("individual" / "individuals" /
    # "Household" / "Households" / "Firm" / "Firms") driven by the user's
    # selection in mod_1_01_sample (`input$unit`).
    unit_word <- function(plural = TRUE, capitalize = FALSE, au = NULL) {
      au <- au %||% tryCatch(analysis_unit(), error = function(e) "hh")
      .sp_unit_word(plural, capitalize, au)
    }

    # Currency label of the amount inputs: the outcome's units; LCU amounts are
    # in 2021 prices, matching the "LCU (2021)" outcome option (see R2-BUG-04).
    amount_currency_label <- function() {
      currency <- tryCatch(
        {
          so <- selected_outcome()
          if (is.null(so) || nrow(so) == 0 || !"units" %in% names(so)) {
            "PPP"
          } else {
            as.character(so$units[[1]])
          }
        },
        error = function(e) "PPP"
      )
      .sp_amount_currency_label(currency)
    }

    # Proxy variable candidates (numeric, non-missing for welfare rows) ----
    pmt_candidates <- reactive({
      svy <- survey_weather()
      vl <- variable_list()
      so <- selected_outcome()
      if (is.null(svy) || is.null(vl) || is.null(so) || nrow(vl) == 0) {
        return(character(0))
      }

      # Filter variable_list to ind/hh/firm/area level only
      level_mask <- vapply(seq_len(nrow(vl)), function(i) {
        isTRUE(vl$ind[i] == 1L) || isTRUE(vl$hh[i] == 1L) || isTRUE(vl$firm[i] == 1L) || isTRUE(vl$area[i] == 1L)
      }, logical(1))
      cands <- vl$name[level_mask]

      # Intersect with survey columns
      cands <- intersect(cands, names(svy))
      if (length(cands) == 0) {
        return(character(0))
      }

      # Keep only numeric vars with no NAs where outcome is non-missing
      outcome_rows <- !is.na(svy[[so$name]])
      keep <- Filter(function(v) {
        col <- svy[[v]]
        is.numeric(col) && !any(is.na(col[outcome_rows]))
      }, cands)

      # Return named character: display_label -> variable_name
      setNames(keep, vapply(keep, function(v) {
        lbl <- vl$label[vl$name == v]
        if (length(lbl) > 0 && nzchar(lbl[[1]])) lbl[[1]] else v
      }, character(1)))
    })

    # 1. program type ----

    output$sp_type_ui <- renderUI({
      tagList(
        tags$div(
          class = "sp-program-label",
          tags$span(
            class = "sp-inline-label",
            tags$i(class = "fa fa-hand-holding-dollar me-1"),
            "Cash transfer"
          )
        ),
        tags$div(
          class = "sp-program-choice",
          pill_toggle(
            inputId = ns("sp_type"),
            label = NULL,
            aria_label = "Cash transfer type",
            choices = c(
              "Regular"          = "regular",
              "Shock-responsive" = "shock"
            ),
            selected = "regular"
          )
        ),
        tags$hr(style = "margin: 8px 0;")
      )
    })

    # 2. Trigger (shock-responsive only) ----
    #
    # Weather variables a trigger can use: continuous columns of the historical
    # exposure (binned variables reach the model as categories, see
    # `.sp_trigger_variables()`). Read from the baseline survey so no exposure
    # table has to be rebuilt just to fill a dropdown.
    trigger_candidates <- reactive({
      hs <- tryCatch(hist_sim(), error = function(e) NULL)
      cols <- hs$pipeline$weather_exposure$weather_columns
      svy <- hs$svy
      if (is.null(cols) || is.null(svy)) {
        return(character(0))
      }
      # A binned variable reaches the model as a category, but Step 2 keeps its
      # continuous value in a companion `<var>_cont` column (P2-4): offer that.
      companion <- vapply(cols, function(v) {
        base <- sub("_cont$", "", v)
        grepl("_cont$", v) && base %in% cols && !is.numeric(svy[[base]])
      }, logical(1))
      cols <- cols[companion | (cols %in% names(svy) & vapply(
        cols, function(v) is.numeric(svy[[v]]), logical(1)
      ))]
      vl <- tryCatch(variable_list(), error = function(e) NULL)
      labels <- vapply(cols, function(v) {
        base <- if (v %in% names(svy)) v else sub("_cont$", "", v)
        lbl <- if (is.data.frame(vl)) vl$label[vl$name == base] else character(0)
        lbl <- if (length(lbl) && !is.na(lbl[[1]]) && nzchar(lbl[[1]])) lbl[[1]] else base
        if (identical(base, v)) lbl else paste0(lbl, " (continuous)")
      }, character(1))
      stats::setNames(cols, labels)
    })

    # Offer only the impact levels the survey frame supports (P2-5); keep the
    # current choice when it is still offered.
    observe({
      svy <- tryCatch(hist_sim()$svy, error = function(e) NULL)
      choices <- .sp_impact_level_choices(svy)
      current <- shiny::isolate(input$trigger_level)
      if (!is.null(current) && !current %in% choices) {
        shiny::showNotification(
          sprintf(
            "Impact level '%s' is not available for this survey. Using National.",
            current
          ),
          type = "warning", duration = 8
        )
      }
      updateSelectInput(
        session, "trigger_level", choices = choices,
        selected = if (!is.null(current) && current %in% choices) current else "national"
      )
    })

    # Prefill the trigger's poverty line from the outcome's own line
    # An edited or imported value is kept: the prefill only replaces the value
    # it set itself (or the static initial one)
    last_pov_default <- 3
    observeEvent(tryCatch(selected_outcome(), error = function(e) NULL), {
      so <- tryCatch(selected_outcome(), error = function(e) NULL)
      pl <- .sp_default_pov_line(so)
      current <- suppressWarnings(as.numeric(shiny::isolate(input$trigger_pov_line)))[1L]
      if (!is.na(pl) && (is.na(current) || isTRUE(all.equal(current, last_pov_default)))) {
        updateNumericInput(session, "trigger_pov_line", value = pl)
        last_pov_default <<- pl
      }
    }, ignoreNULL = TRUE)

    output$sp_trigger_ui <- renderUI({
      .sp_trigger_tags(ns, trigger_candidates)
    })

    # The trigger's own validation message, or its summary beside the button.
    output$trigger_summary <- renderText({
      spec <- sp_scenario_spec()
      problem <- .sp_shock_problem(spec)
      if (!is.null(problem)) {
        return(problem)
      }
      trig <- .sp_spec_trigger(spec)
      impact_label <- c(
        loss = "modelled loss (%)", poverty_rate = "poverty rate (%)",
        poor_count = "number of poor"
      )[spec[["trigger_metric"]]]
      either <- identical(trig$direction, "either")
      side <- if (either) {
        "beyond"
      } else if (identical(trig$direction, "below")) {
        "at or below"
      } else {
        "at or above"
      }
      level <- if (identical(spec$trigger_type, "return_period")) {
        paste0(
          "its 1-in-", spec$trigger_return_period_years, "-year level",
          if (either) " at either end" else ""
        )
      } else if (either) {
        paste(spec$trigger_value_low, "or", spec$trigger_value)
      } else {
        paste(spec$trigger_value)
      }
      layers <- c(
        if (identical(spec[["dyn_geo"]], "worst_share")) {
          paste0("worst-affected ", spec$dyn_geo_pct, "% of triggered population")
        },
        if (isTRUE(spec[["dyn_welfare"]])) {
          paste0("poorest ", spec$dyn_welfare_pct, "% by predicted welfare")
        },
        if (identical(spec[["transfer_timing"]], "anticipatory")) {
          paste0("forecast POD ", spec$forecast_pod_pct, "%, false alarms ", spec$forecast_far_pct, "%")
        }
      )
      paste0(
        if (is.na(impact_label)) {
          spec$trigger_variable
        } else {
          paste0(impact_label, ", ", spec[["trigger_level"]])
        }, " ", side, " ", level, "; ",
        spec$payments_per_activation, " payment(s)",
        if (length(layers)) paste0("; ", paste(layers, collapse = ", "))
      )
    })

    # Unit the thresholds are read in (the Step 2 transformation of the variable).
    output$trigger_unit <- renderText({
      unit <- .sp_trigger_unit(
        input$trigger_variable,
        tryCatch(selected_weather(), error = function(e) NULL)
      )
      if (nzchar(unit)) paste0("Thresholds are in: ", unit, ".") else ""
    })

    # Unit and historical range of an impact metric (PR-9)
    output$impact_info <- renderText({
      metric <- input$trigger_metric %||% "weather"
      if (identical(metric, "weather")) {
        return("")
      }
      unit <- switch(metric,
        loss = "percent of the households' own typical welfare (positive = loss)",
        poverty_rate = "percent of people below the poverty line",
        poor_count = "people below the poverty line"
      )
      st <- sp_shock_state()
      r <- if (is.list(st) && is.null(st$problem)) st$impact_range
      paste0(
        "Thresholds are in: ", unit, ".",
        if (length(r) == 3L && all(is.finite(r))) {
          paste0(
            " Historical years: lowest ", fmt_num(r[[1L]], digits = 1), ", median ",
            fmt_num(r[[2L]], digits = 1), ", highest ", fmt_num(r[[3L]], digits = 1), "."
          )
        }
      )
    })

    # Response check (P2-1): modelled loss by decile of the chosen variable, so
    # the user sees which end of the variable is adverse before setting a
    # direction. Depends on the variable only, not on the other trigger fields.
    trigger_response <- reactive({
      var <- input$trigger_variable
      hs <- tryCatch(hist_sim(), error = function(e) NULL)
      ex <- hist_exposure()
      if (is.null(var) || !nzchar(var) || is.null(hs$pipeline) || is.null(ex)) {
        return(NULL)
      }
      tryCatch(
        sp_response_check(
          hs$pipeline, ex, var,
          is_log = identical(hs$so$transform %||% "", "log")
        ),
        error = function(e) list(problem = wise_user_error(e, "Response check"))
      )
    })

    output$trigger_response <- renderUI({
      r <- trigger_response()
      if (is.null(r)) {
        return(NULL)
      }
      if (!is.null(r$problem)) {
        return(tags$p(class = "text-muted small", r$problem))
      }
      d <- r$deciles
      pct <- function(x) fmt_num(100 * x, digits = 1, suffix = "%", na = "n/a")
      st <- sp_shock_state()
      basis <- if (is.list(st) && is.null(st$problem) &&
        is.finite(st$false_negative_rate %||% NA_real_)) {
        tags$p(
          class = "text-muted small",
          "Current trigger: misses ", pct(st$false_negative_rate),
          " of loss events, ", pct(st$false_positive_rate %||% NA_real_),
          " false positives (loss event as set below)."
        )
      }
      tags$div(
        class = "sp-response-check",
        tags$p(class = "small mb-1", tags$b("Response check. "), r$hint),
        tags$details(
          class = "small mb-1",
          tags$summary("Loss by decile"),
          tags$table(
            class = "table table-sm small mb-1",
            tags$caption(
              class = "small text-muted",
              "Mean modelled loss by decile of ", r$variable,
              " over household-years (negative = loss, survey-weighted)."
            ),
            tags$thead(tags$tr(
              tags$th("Decile"), tags$th("Range"), tags$th("Mean loss")
            )),
            tags$tbody(lapply(seq_len(nrow(d)), function(i) {
              tags$tr(
                tags$td(d$decile[[i]]),
                tags$td(paste(
                  fmt_num(d$min_value[[i]], digits = 2), "to",
                  fmt_num(d$max_value[[i]], digits = 2)
                )),
                tags$td(pct(d$mean_loss[[i]]))
              )
            }))
          )
        ),
        basis
      )
    })

    output$trigger_value_hint <- renderText({
      if (identical(input$trigger_direction, "either")) "(high threshold)" else ""
    })

    # Record length behind a return-period trigger.
    output$trigger_support <- renderText({
      tbl <- hist_exposure()$table
      var <- input$trigger_variable
      if (!identical(input$trigger_metric %||% "weather", "weather")) {
        return("")
      }
      if (is.null(tbl) || is.null(var) || !var %in% names(tbl) ||
        !"sim_year" %in% names(tbl)) {
        return("")
      }
      years <- length(unique(tbl$sim_year[is.finite(as.numeric(tbl[[var]]))]))
      either <- identical(input$trigger_direction, "either")
      paste0(
        "Historical record: ", years, " years, so a trigger of up to 1 in ",
        if (either) years %/% 2L else years,
        " years is supported", if (either) " at either extreme" else "",
        ". Annual probability: ",
        format(round(100 / max(1, suppressWarnings(as.numeric(
          input$trigger_return_period_years %||% 10
        ))), 1), nsmall = 1), "%."
      )
    })

    # Defaults that let a shock-responsive run start without opening the flyout.
    # Like the poverty-line prefill, an edited or imported value is kept: a
    # default only replaces the value it set itself (or the static initial one).
    #
    # Return period: 1 in 10 years, or the longest return period the historical
    # record supports when it is shorter (half of it at either extreme).
    last_rp_default <- 10
    observe({
      tbl <- hist_exposure()$table
      var <- input$trigger_variable
      if (is.null(tbl) || is.null(var) || !var %in% names(tbl) ||
        !"sim_year" %in% names(tbl)) {
        return()
      }
      years <- length(unique(tbl$sim_year[is.finite(as.numeric(tbl[[var]]))]))
      supported <- if (identical(input$trigger_direction, "either")) years %/% 2L else years
      default <- max(2L, min(10L, supported))
      current <- suppressWarnings(as.numeric(shiny::isolate(input$trigger_return_period_years)))[1L]
      if (is.na(current) || isTRUE(all.equal(current, last_rp_default))) {
        updateNumericInput(session, "trigger_return_period_years", value = default)
        last_rp_default <<- default
      }
    })

    # Direction: the adverse end the response check finds for the variable.
    last_dir_default <- "above"
    observeEvent(trigger_response(), {
      direction <- trigger_response()$direction
      if (is.null(direction) || !direction %in% c("above", "below", "either")) {
        return()
      }
      current <- shiny::isolate(input$trigger_direction)
      if (is.null(current) || identical(current, last_dir_default)) {
        shiny::updateRadioButtons(session, "trigger_direction", selected = direction)
        last_dir_default <<- direction
      }
    })

    # 3. Targeting ----

    output$sp_targeting_ui <- renderUI({
      .sp_targeting_tags(ns, unit_word)
    })

    # Proxy variable selector ----
    output$pmt_variable_ui <- renderUI({
      cands <- pmt_candidates()
      if (length(cands) == 0) {
        return(no_data_warning(
          "No suitable Proxy variable found. No covariates with",
          "non-missing values found (for selected outcome)."
        ))
      }
      selectInput(
        ns("pmt_variable"),
        label = tags$span(
          tags$i(class = "fa fa-list me-1"),
          "Proxy variable"
        ),
        choices = cands,
        selected = cands[[1]]
      )
    })

    # Proxy cutoff selector (type depends on variable) ----
    output$pmt_cutoff_ui <- renderUI({
      v <- input$pmt_variable
      req(v)
      svy <- survey_weather()
      req(svy, v %in% names(svy))

      col <- svy[[v]]
      col <- col[!is.na(col)]
      uniq <- sort(unique(col))

      if (length(uniq) == 2 && all(uniq %in% c(0, 1))) {
        # Binary variable: choose target value
        pill_toggle(
          ns("pmt_cutoff"),
          label = paste(
            "Target", unit_word(plural = TRUE),
            "where variable equals"
          ),
          choices = c("0" = 0, "1" = 1),
          selected = 0
        )
      } else {
        # Continuous variable: choose threshold
        sliderInput(
          ns("pmt_cutoff"),
          label = paste(
            "Include", unit_word(plural = TRUE),
            "with value \u2264"
          ),
          min = floor(min(col)),
          max = ceiling(max(col)),
          value = stats::quantile(col, 0.2),
          step = if (diff(range(col)) > 10) 1 else 0.1
        )
      }
    })

    # 4. Budget / transfer amount (linked) ----
    #
    # Two budget modes:
    #   "budget_first"   - user sets total budget (net of admin cost)
    #                      -> transfer per HH = (budget * (1 - admin%)) / n_beneficiaries
    #   "transfer_first" - user sets transfer per HH
    #                      -> total budget = (amount * n_beneficiaries) / (1 - admin%)
    #
    # Admin cost reduces the amount available for direct transfers in both modes.

    output$sp_budget_amount_ui <- renderUI({
      .sp_budget_amount_tags(ns, unit_word, amount_currency_label)
    })

    # 5. Frequency and timing ----
    #
    # If sp_type == "regular":
    #   - hide one-off vs regular radio (always regular)
    #   - hide anticipatory vs ex-post (not applicable)
    #   - hide timeliness (not applicable)
    #   - show only number of payments

    output$sp_timing_ui <- renderUI({
      .sp_timing_tags(ns, amount_currency_label)
    })

    # Amount basis (household analysis only) ----
    output$amount_basis_ui <- renderUI({
      au <- tryCatch(analysis_unit(), error = function(e) "hh")
      if (!identical(au, "hh")) {
        return(tags$p(
          class = "text-muted small",
          "Amounts are per unit; a per-person basis applies to household analysis only."
        ))
      }
      tagList(
        tags$label(
          class = "control-label",
          tags$i(class = "fa fa-people-roof me-1"),
          "Amount basis",
          info_popover(
            title = "Amount basis",
            tags$p(
              tags$b("Per household:"),
              "each recipient household receives the amount, shared across its",
              "members, so larger households gain less per person."
            ),
            tags$p(
              tags$b("Per person:"),
              "each member of a recipient household receives the amount, so cost",
              "and welfare gain grow with household size. A total budget is",
              "shared across recipient people."
            )
          )
        ),
        pill_toggle(
          inputId = ns("amount_basis"),
          label = NULL,
          aria_label = "Amount basis",
          choices = c("Per household" = "per_household", "Per person" = "per_capita"),
          selected = shiny::isolate(input$amount_basis) %||% "per_household"
        )
      )
    })

    # One-line summaries shown beside the flyout buttons ----
    output$targeting_summary <- renderText({
      .sp_targeting_summary(
        input$targeting %||% "universal",
        input$error_concentration %||% 0,
        input$inclusion_error_pct %||% 10,
        input$exclusion_error_pct %||% 10
      )
    })

    # Kept out of sp_budget_amount_ui so a basis change does not re-render
    # (and reset) the amount inputs.
    output$payment_summary <- renderText({
      admin <- input$admin_cost_pct %||% 0
      basis <- input$amount_basis %||% "per_household"
      n_payments <- if (identical(input$budget_mode %||% "transfer_first", "transfer_first") &&
        !identical(input$sp_type, "shock")) {
        input$transfer_n_payments %||% 6L
      }
      .sp_payment_summary(
        admin, basis, n_payments,
        tryCatch(analysis_unit(), error = function(e) "hh")
      )
    })

    # Scenario specification ----
    #
    # UI-43: the whole module sits in a bslib accordion panel that starts
    # collapsed, and hidden outputs are suspended - so none of these inputs
    # existed until the user expanded "Social protection", and the scenario
    # below silently fell back to the `%||%` defaults (including sp_type
    # "shock", which is no longer one of the offered choices). Render them
    # eagerly so an untouched panel still reports its real defaults.
    lapply(
      c(
        "sp_type_ui", "sp_budget_amount_ui", "sp_targeting_ui",
        "pmt_variable_ui", "pmt_cutoff_ui", "sp_timing_ui", "amount_basis_ui",
        "targeting_summary", "payment_summary",
        "sp_trigger_ui", "trigger_summary", "trigger_value_hint", "trigger_unit"
      ),
      function(out_id) {
        shiny::outputOptions(output, out_id, suspendWhenHidden = FALSE)
      }
    )

    # Currency the amounts are entered in: the selected outcome's units. The
    # transfer is converted to the stored welfare scale (2021 PPP) per row when
    # this is "LCU" (R2-BUG-04), and costs are reported back in this currency.
    sp_currency <- reactive({
      so <- tryCatch(selected_outcome(), error = function(e) NULL)
      units <- if (is.null(so) || nrow(so) == 0 || !"units" %in% names(so)) {
        NULL
      } else {
        so$units[[1]]
      }
      .sp_currency(units)
    })

    # One definition of the scenario, read by both the reach preview below and
    # the module's return API - the preview cannot drift from what is run.
    sp_scenario_spec <- reactive({
      sp <- wise_sp_config(
        step3_read_inputs(STEP3_SP_IDS, function(id) input[[id]]),
        currency = sp_currency(),
        analysis_unit = tryCatch(analysis_unit(), error = function(e) "hh")
      )
      if (!identical(sp$transfer_amount_mode, "pctile")) {
        return(sp)
      }
      # A percentile amount is read once, from the frame the run will use
      # (the Step 2 baseline round; every round before Step 2 has run).
      hs <- tryCatch(hist_sim(), error = function(e) NULL)
      svy <- if (!is.null(hs$svy)) hs$svy else tryCatch(survey_weather(), error = function(e) NULL)
      wise_sp_resolve_amount(sp, svy)
    })

    output$transfer_amount_resolved <- renderText({
      ar <- sp_scenario_spec()$amount_resolved
      if (is.null(ar)) {
        return("")
      }
      if (!identical(ar$status, "ok")) {
        return("Percentile not available: the baseline survey has no usable welfare.")
      }
      prefix <- .sp_currency_prefix(ar$currency)
      paste0(
        "P", ar$pctile, " of daily welfare = ", prefix, format(round(ar$daily_value, 2), nsmall = 2),
        " \u2192 ", prefix, format(round(ar$per_payment, 2), nsmall = 2, big.mark = ","),
        " per payment, ", prefix, format(round(ar$per_year, 0), big.mark = ","), " per year"
      )
    })

    # Live reach / cost preview (UI-32) ----
    #
    # Answers "who does this reach and what does it cost?" while the user is
    # still choosing a cutoff, instead of only after a full policy run. The
    # figures come from `.sp_scenario_reach()`, which reuses the run's own
    # eligibility function under the run's analysis seed and the diagnostics
    # tab's cost arithmetic - so this is the number the simulation will
    # produce, not a separate approximation of it.

    sp_preview_inputs <- shiny::debounce(reactive({
      hs <- tryCatch(hist_sim(), error = function(e) NULL)
      svy <- if (!is.null(hs$svy)) {
        hs$svy
      } else {
        tryCatch(survey_weather(), error = function(e) NULL)
      }
      list(
        hs = hs, svy = svy, spec = sp_scenario_spec(),
        analysis_unit = tryCatch(analysis_unit(), error = function(e) "hh"),
        display_type = input$sp_type %||% "regular"
      )
    }), 250)

    # Exposure of the historical pipeline, rebuilt once per Step 2 run.
    hist_exposure <- reactive({
      hs <- tryCatch(hist_sim(), error = function(e) NULL)
      if (is.null(hs$pipeline)) {
        return(NULL)
      }
      tryCatch(step2_exposure_resolve(hs$pipeline, hs), error = function(e) NULL)
    })

    # Expected activation and cost of a shock program from the historical years
    # (NULL for a regular program).
    sp_shock_state <- reactive({
      preview <- sp_preview_inputs()
      if (!identical(preview$spec$sp_type, "shock")) {
        return(NULL)
      }
      tryCatch(
        sp_shock_preview(
          preview$spec, preview$hs, preview$svy, preview$analysis_unit,
          seed = wise_current_seed(), exposure = hist_exposure()
        ),
        error = function(e) list(problem = wise_user_error(e, "Shock preview"))
      )
    })

    sp_reach <- reactive({
      # The frame must be the one the policy run will use. Step 2 may have
      # filtered survey_weather() down to a single baseline round; estimating
      # over every round instead inflates both the eligible population and the
      # cost, and shifts the welfare quantile that defines "ex-ante poor".
      # This mirrors `svy <- hs$svy %||% survey_weather()` in mod_3_06.
      preview <- sp_preview_inputs()
      hs <- preview$hs
      svy <- preview$svy
      if (is.null(svy)) {
        return(NULL)
      }
      r <- .sp_scenario_reach(
        svy           = svy,
        sp            = preview$spec,
        analysis_unit = preview$analysis_unit,
        seed          = wise_current_seed()
      )
      if (is.null(r)) {
        return(NULL)
      }
      # Record which frame these figures describe. Before Step 2 has run there
      # is no baseline round to filter to, so the preview covers every survey
      # round and will drop once Step 2 narrows it - worth saying, rather than
      # letting the number appear to change on its own.
      r$on_baseline <- !is.null(hs$svy)
      r
    })

    output$sp_reach_ui <- renderUI({
      preview <- sp_preview_inputs()
      r <- sp_reach()
      shock_state <- if (!is.null(r) && identical(preview$spec$sp_type, "shock")) {
        sp_shock_state()
      }
      analysis_unit_now <- if (!is.null(r)) analysis_unit()
      .sp_reach_card(
        r, preview$spec, preview$analysis_unit, preview$display_type,
        shock_state, analysis_unit_now
      )
    })

    # Rendered eagerly for the same reason as the panels above (UI-43).
    shiny::outputOptions(output, "sp_reach_ui", suspendWhenHidden = FALSE)

    # Return API ----

    list(
      sp_scenario = sp_scenario_spec,
      sp_preview_inputs = sp_preview_inputs,
      sp_reach = sp_reach
    )
  })
}
