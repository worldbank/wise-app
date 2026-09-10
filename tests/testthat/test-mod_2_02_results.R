# ============================================================================ #
# tests/testthat/test-mod_2_02_results.R                                       #
# Regression tests for the Step 2 results module: aggregation-cache keying     #
# (PERF-30) and the resolve_band_q contract (DUP-01).                          #
# ============================================================================ #

library(testthat)
library(shiny)

# ---- DUP-01: single authoritative resolve_band_q ----------------------------

test_that("resolve_band_q maps every UI band key to its quantile pair", {
  expect_identical(resolve_band_q("p25_p75"),   c(lo = 0.25,  hi = 0.75))
  expect_identical(resolve_band_q("p20_p80"),   c(lo = 0.20,  hi = 0.80))
  expect_identical(resolve_band_q("p10_p90"),   c(lo = 0.10,  hi = 0.90))
  expect_identical(resolve_band_q("p05_p95"),   c(lo = 0.05,  hi = 0.95))
  expect_identical(resolve_band_q("p025_p975"), c(lo = 0.025, hi = 0.975))
  expect_identical(resolve_band_q("p005_p995"), c(lo = 0.005, hi = 0.995))
  # minmax is the full observed range, not a winsorised pair (the deleted
  # fct_aggregation.R duplicate winsorised to 0.001/0.999 - DUP-01).
  expect_identical(resolve_band_q("minmax"),    c(lo = 0.00,  hi = 1.00))
})

test_that("resolve_band_q falls back to p10_p90 for unknown keys", {
  expect_identical(resolve_band_q("bogus"), c(lo = 0.10, hi = 0.90))
})

# ---- PERF-30: aggregation cache keyed only by value-affecting inputs -------

make_hist_sim_fixture <- function() {
  n <- 400
  set.seed(7)
  pl <- data.frame(
    sim_year = rep(2020:2021, each = n / 2),
    y_point  = rnorm(n, 1.2, 0.4),
    weight   = rep(c(1, 2), length.out = n)
  )
  list(
    so          = list(type = "numeric", name = "welfare", transform = "log"),
    residuals   = "none",
    has_weights = TRUE,
    pipeline    = list(
      sim_year  = pl$sim_year,
      y_point   = pl$y_point,
      weight    = pl$weight,
      # Tiny loadings keep the auto-tuned kernel bandwidth below the user
      # bandwidth, so bandwidth_p0 changes must visibly alter headcount SEs.
      F_loading = matrix(rnorm(2 * n) * 0.01, nrow = n),
      train_aug = NULL, id_vec = NULL, id_col = NULL
    )
  )
}

test_that("agg cache: display-only controls do not invalidate unaffected methods", {
  skip_if_not_installed("shiny")

  hist_sim <- shiny::reactiveVal(make_hist_sim_fixture())

  shiny::testServer(
    mod_2_02_results_server,
    args = list(
      id              = "results",
      hist_sim        = hist_sim,
      saved_scenarios = shiny::reactiveVal(list()),
      selected_hist   = shiny::reactiveVal(NULL),
      tabset_id       = "step2_output_tabs"
    ),
    {
      settle <- function() { session$elapse(500); session$flushReact() }
      ws <- function() agg_workspace()

      session$flushReact()
      h1 <- .get_hist_agg("mean")
      stopifnot(length(ls(envir = ws()$cache)) == 1L)

      # Poverty-line move: mean does not read it -> entry survives untouched
      session$setInputs(pov_line = 5.50); settle()
      expect_true(isTRUE(all.equal(pov_line_val(), 5.5)))
      h2 <- .get_hist_agg("mean")
      expect_identical(h1, h2)
      expect_length(ls(envir = ws()$cache), 1L)

      # gap at first line, then at a new one: new key, recompute, old kept
      g1 <- .get_hist_agg("gap")
      expect_length(ls(envir = ws()$cache), 2L)
      session$setInputs(pov_line = 7.25); settle()
      g2 <- .get_hist_agg("gap")
      expect_false(identical(g1, g2))
      expect_length(ls(envir = ws()$cache), 3L)
      m2 <- .get_hist_agg("mean")
      expect_identical(h1, m2)
      expect_true(all(g2$unweighted$gap$value > g1$unweighted$gap$value))

      # headcount reads both pl and bandwidth; gap ignores bandwidth
      session$setInputs(bandwidth_p0 = 0.10); settle()
      hc1 <- .get_hist_agg("headcount_ratio")
      expect_length(ls(envir = ws()$cache), 4L)
      hc2 <- .get_hist_agg("headcount_ratio")
      expect_identical(hc1, hc2)
      g3 <- .get_hist_agg("gap")
      expect_identical(g2, g3)
      m3 <- .get_hist_agg("mean")
      expect_identical(h1, m3)
      expect_length(ls(envir = ws()$cache), 4L)

      # New bandwidth invalidates only headcount
      session$setInputs(bandwidth_p0 = 0.20); settle()
      hc3 <- .get_hist_agg("headcount_ratio")
      expect_false(identical(hc2, hc3))
      expect_length(ls(envir = ws()$cache), 5L)
      g4 <- .get_hist_agg("gap")
      expect_identical(g2, g4)
      m4 <- .get_hist_agg("mean")
      expect_identical(h1, m4)
    }
  )
})

# ---- INT-08: stale banner on the Step 2 results pane ------------------------

test_that("Step 2 results pane shows the stale banner while stale", {
  skip_if_not_installed("shiny")

  hist_sim <- shiny::reactiveVal(make_hist_sim_fixture())
  stale    <- shiny::reactiveVal(FALSE)

  shiny::testServer(
    mod_2_02_results_server,
    args = list(
      id              = "results",
      hist_sim        = hist_sim,
      saved_scenarios = shiny::reactiveVal(list()),
      selected_hist   = shiny::reactiveVal(NULL),
      tabset_id       = "step2_output_tabs",
      stale           = stale
    ),
    {
      settle <- function() { session$elapse(500); session$flushReact() }

      stale(TRUE); settle()
      html <- paste(as.character(session$output$stale_banner), collapse = " ")
      expect_match(html, "Results are out of date", fixed = TRUE)
      expect_match(html, "Step 2 simulation results", fixed = TRUE)

      stale(FALSE); settle()
      html <- paste(as.character(session$output$stale_banner), collapse = " ")
      expect_identical(nchar(html), 0L)
    }
  )
})

# ---- INT-07: results tab follows the hist_sim lifecycle ---------------------

test_that("results tab is appended, removed on clear, re-appended on rerun", {
  skip_if_not_installed("shiny")

  hist_sim <- shiny::reactiveVal(NULL)

  shiny::testServer(
    mod_2_02_results_server,
    args = list(
      id              = "results",
      hist_sim        = hist_sim,
      saved_scenarios = shiny::reactiveVal(list()),
      selected_hist   = shiny::reactiveVal(NULL),
      tabset_id       = "step2_output_tabs"
    ),
    {
      settle <- function() { session$elapse(500); session$flushReact() }

      session$flushReact()
      expect_false(results_tab_added())

      hist_sim(make_hist_sim_fixture()); settle()
      expect_true(results_tab_added())

      # Clearing the run removes the tab so the empty state returns (INT-07)
      hist_sim(NULL); settle()
      expect_false(results_tab_added())

      # ...and a later run re-inserts it (never fired again under once = TRUE)
      hist_sim(make_hist_sim_fixture()); settle()
      expect_true(results_tab_added())
    }
  )
})

# ---- Scenario coverage ------------------------------------------------------

test_that("all saved scenarios feed results when no scenario filter is shown", {
  skip_if_not_installed("shiny")

  hist_sim <- shiny::reactiveVal(make_hist_sim_fixture())
  saved    <- shiny::reactiveVal(list(
    "SSP2-4.5 / 2030" = list(scenario_name = "SSP2-4.5 / 2030"),
    "SSP5-8.5 / 2030" = list(scenario_name = "SSP5-8.5 / 2030")
  ))

  shiny::testServer(
    mod_2_02_results_server,
    args = list(
      id              = "results",
      hist_sim        = hist_sim,
      saved_scenarios = saved,
      selected_hist   = shiny::reactiveVal(NULL),
      tabset_id       = "step2_output_tabs"
    ),
    {
      settle <- function() { session$elapse(500); session$flushReact() }
      settle()
      expect_setequal(
        selected_scenario_names(),
        c("SSP2-4.5 / 2030", "SSP5-8.5 / 2030")
      )
    }
  )
})

test_that("all Module 2 summaries use the same complete scenario set", {
  skip_if_not_installed("shiny")

  hist <- make_hist_sim_fixture()
  shifted_pipeline <- function(shift) {
    pipe <- hist$pipeline
    pipe$y_point <- pipe$y_point + shift
    pipe
  }
  scenario_entry <- function(shift) {
    list(
      so = hist$so,
      pipelines = list(model_1 = shifted_pipeline(shift)),
      n_models = 1L
    )
  }
  scenario_names <- c("SSP2-4.5 / 2030", "SSP5-8.5 / 2050")
  saved <- stats::setNames(
    list(scenario_entry(0.10), scenario_entry(0.30)),
    scenario_names
  )

  shiny::testServer(
    mod_2_02_results_server,
    args = list(
      id              = "results",
      hist_sim        = shiny::reactiveVal(hist),
      saved_scenarios = shiny::reactiveVal(saved),
      selected_hist   = shiny::reactiveVal(NULL),
      tabset_id       = "step2_output_tabs"
    ),
    {
      session$setInputs(
        cmp_agg_method = "mean",
        cmp_deviation = "none",
        ensemble_band = "minmax",
        uncertainty_band = "p10_p90"
      )
      session$flushReact()

      expected <- c("Historical", scenario_names)
      annual <- annual_distribution_curves_rv()
      bands <- pointrange_bands_rv()
      thresholds <- threshold_table_rv()
      exceedance <- exceedance_curves_rv()

      expect_setequal(unique(annual$scenario), expected)
      expect_setequal(unique(bands$scenario), expected)
      expect_setequal(unique(thresholds$scenario), expected)
      expect_setequal(unique(exceedance$scenario), expected)
      expect_equal(dplyr::n_distinct(round(bands$value, 8)), 3L)

      central <- thresholds[thresholds$Estimate == "Central (P50)" &
                              thresholds$rp_name == "1:1", , drop = FALSE]
      expect_equal(dplyr::n_distinct(round(central$value, 8)), 3L)
    }
  )
})

# ---- Step 2 Headline Cards -------------------------------------------------

test_that("step2_headline_cards returns 5 cards with mod_1 styling", {
  bands <- tibble::tibble(
    scenario      = c("Historical", "SSP3-7.0 / 2025-2035"),
    value         = c(4.50, 4.52),
    coef_lo       = c(4.45, 4.47),
    coef_hi       = c(4.55, 4.57),
    interann_lo   = c(4.20, 4.25),
    interann_hi   = c(4.80, 4.85),
    intermod_lo   = c(4.50, 4.48),
    intermod_hi   = c(4.50, 4.56),
    total_lo      = c(NA_real_, 4.40),
    total_hi      = c(NA_real_, 4.64),
    is_historical = c(TRUE, FALSE),
    n_models      = c(1L, 22L)
  )

  thresh_tbl <- tibble::tibble(
    scenario = c(rep("Historical", 4L), rep("SSP3-7.0 / 2025-2035", 4L)),
    Estimate = rep("Central (P50)", 8L),
    rp_name  = rep(c("1:1", "4:5", "9:10", "19:20"), 2L),
    value    = c(4.50, 4.30, 4.20, 4.05, 4.52, 4.38, 4.25, 4.10)
  )

  hist_sim <- list(
    so = list(type = "numeric", name = "welfare", label = "Consumption", units = "$/day"),
    sim_summary = list(
      total_runs = 690L,
      historical_years = c(1991L, 2020L)
    )
  )

  saved <- list("SSP3-7.0 / 2025-2035" = list(n_models = 22L))

  cards <- step2_headline_cards(
    bands            = bands,
    threshold_tbl    = thresh_tbl,
    hist_sim         = hist_sim,
    saved_scenarios  = saved,
    method           = "mean",
    deviation        = "none",
    ensemble_band    = "minmax",
    uncertainty_band = "p10_p90"
  )

  expect_length(cards, 5L)

  # Check labels
  labels <- vapply(cards, function(c) c$label, character(1L))
  expect_identical(
    labels,
    c("Typical outcome", "Adverse weather years", "Range across years",
      "Climate-model spread", "Simulation years")
  )

  # Every card has non-empty fields
  for (card in cards) {
    expect_true(nzchar(card$label))
    expect_true(nzchar(card$value))
    expect_true(nzchar(card$note))
    expect_s3_class(card$note_html, "shiny.tag.list")
    expect_true(nzchar(card$info))
  }

  # Card 1: Typical outcome
  expect_identical(cards[[1]]$value, "4.50 vs 4.52")
  expect_match(cards[[1]]$note, "Historical vs SSP", fixed = TRUE)

  # Card 2: Adverse weather years (1-in-20 year)
  expect_identical(cards[[2]]$value, "4.05 vs 4.10")
  expect_match(cards[[2]]$note, "Historical vs SSP", fixed = TRUE)
  expect_match(cards[[2]]$note, "1-in-20 year", fixed = TRUE)

  # Card 3: Range across years
  expect_identical(cards[[3]]$value, "4.25 to 4.85")
  expect_match(cards[[3]]$note, "Hist: 4.20 to 4.80", fixed = TRUE)
  expect_match(cards[[3]]$note, "Inter-annual weather variability", fixed = TRUE)

  # Card 4: Climate-model spread
  expect_identical(cards[[4]]$value, "4.48 to 4.56")
  expect_match(cards[[4]]$note, "Ensemble spread (22 models)", fixed = TRUE)
  expect_match(cards[[4]]$note, "CMIP6 model disagreement", fixed = TRUE)
  expect_false(grepl("Coef", cards[[4]]$note, fixed = TRUE))

  # Card 5: Simulation years
  expect_identical(cards[[5]]$value, "690")
  expect_match(cards[[5]]$note, "(1 SSP \u00d7 22 models + 1 historical) \u00d7 30 yrs", fixed = TRUE)
  expect_identical(cards[[5]]$class, "neutral")

  # Table conversion
  df <- step2_headline_df(cards)
  expect_equal(nrow(df), 5L)
  expect_identical(names(df), c("Metric", "Value", "Note"))
  expect_identical(df$Metric, labels)
})

test_that("step2_headline_cards handles historical-only simulation gracefully", {
  bands <- tibble::tibble(
    scenario      = "Historical",
    value         = 4.50,
    coef_lo       = 4.45,
    coef_hi       = 4.55,
    interann_lo   = 4.20,
    interann_hi   = 4.80,
    intermod_lo   = 4.50,
    intermod_hi   = 4.50,
    total_lo      = NA_real_,
    total_hi      = NA_real_,
    is_historical = TRUE,
    n_models      = 1L
  )

  hist_sim <- list(
    so = list(type = "numeric", name = "welfare", label = "Consumption"),
    sim_summary = list(
      total_runs = 30L,
      historical_years = c(1991L, 2020L)
    )
  )

  cards <- step2_headline_cards(
    bands           = bands,
    threshold_tbl   = NULL,
    hist_sim        = hist_sim,
    saved_scenarios = list()
  )

  expect_length(cards, 5L)
  expect_identical(cards[[1]]$value, "4.50")
  expect_identical(cards[[4]]$value, "Not applicable")
  expect_match(cards[[5]]$note, "1 historical \u00d7 30 yrs", fixed = TRUE)
})

test_that("results content UI produces clear aggregation panel with question and pill selector", {
  so <- list(
    name    = "welfare",
    type    = "numeric",
    label   = "Consumption",
    level   = "hh",
    units   = "$/day, 2021 PPP",
    povline = 3.00
  )
  ui <- wiseapp:::.results_content_ui(shiny::NS("results"), so)
  html <- as.character(htmltools::renderTags(ui)$html)

  expect_match(html, "results-aggregation-panel", fixed = TRUE)
  expect_match(html, "How to summarise consumption across households?", fixed = TRUE)
  expect_match(html, "results-cmp_agg_method", fixed = TRUE)
  expect_match(html, "results-pov_line", fixed = TRUE)
  expect_match(html, "Poverty line ($/day, 2021 PPP):", fixed = TRUE)
  expect_match(html, "toggle-slider pill-toggle", fixed = TRUE)

  # Verify removed controls are NOT in the aggregation panel
  agg_panel_html <- as.character(htmltools::renderTags(ui[[3]])$html)
  expect_match(agg_panel_html, "results-aggregation-panel", fixed = TRUE)
  expect_false(grepl("results-controls", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-cmp_deviation", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-uncertainty_band", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-ensemble_band", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-show_coef_uncertainty", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-show_model_spread", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-bandwidth_p0", agg_panel_html, fixed = TRUE))
  expect_false(grepl("results-cmp_group_order", agg_panel_html, fixed = TRUE))

  # Verify the 5 sections in the overall page
  expect_match(html, "How is consumption predicted to vary across climate scenarios and weather years?", fixed = TRUE)
  expect_match(html, "What outcomes are predicted in adverse weather years?", fixed = TRUE)
  expect_match(html, "What is the probability of severe outcomes occurring?", fixed = TRUE)
  expect_match(html, "results-exceedance_model_spread", fixed = TRUE)
  expect_match(html, "Climate model spread", fixed = TRUE)
  expect_match(html, "Full ensemble spread", fixed = TRUE)
  expect_match(html, "results-ensemble_band", fixed = TRUE)
  expect_match(html, "What drives the uncertainty in these predictions?", fixed = TRUE)
  expect_match(html, "Detailed return-period outcomes and uncertainty", fixed = TRUE)

  # Verify distributional incidence is removed from this page
  expect_false(grepl("results-incidence_plot", html, fixed = TRUE))
  expect_false(grepl("results-incidence_table", html, fixed = TRUE))
})

test_that("annual distribution UI includes a plot type selector", {
  so <- list(name = "welfare", type = "numeric", label = "Welfare")
  html <- as.character(htmltools::renderTags(
    wiseapp:::.results_content_ui(shiny::NS("results"), so)
  )$html)

  expect_match(html, "results-annual_distribution_type", fixed = TRUE)
  expect_match(html, "Violin", fixed = TRUE)
  expect_match(html, "Boxplot", fixed = TRUE)
})

test_that("adverse plot uses the selected climate-model spread", {
  threshold_tbl <- tibble::tibble(
    scenario = rep("SSP2-4.5 / 2030", 6L),
    Estimate = c("Central (P50)", "Central (P50)",
                 "Ensemble min", "Ensemble min", "Ensemble max", "Ensemble max"),
    rp_name = c("1:1", "4:5", "1:1", "4:5", "1:1", "4:5"),
    value = c(5, 5, 4, 3, 6, 7),
    is_historical = FALSE,
    n_obs = 30L
  )

  dot <- step2_adverse_dot_data(threshold_tbl, method = "mean")
  expect_equal(dot$intermod_lo, c(4, 3))
  expect_equal(dot$intermod_hi, c(6, 7))

  plot <- plot_step2_adverse_dot(dot)
  expect_equal(plot$data$intermod_lo, c(4, 3))
  expect_equal(plot$data$intermod_hi, c(6, 7))
})

test_that("adverse plot legend identifies projection periods", {
  threshold_tbl <- tibble::tibble(
    scenario = c(rep("SSP2-4.5 / 2030-2040", 6L),
                 rep("SSP2-4.5 / 2050-2060", 6L)),
    Estimate = rep(c("Central (P50)", "Central (P50)",
                     "Ensemble min", "Ensemble min",
                     "Ensemble max", "Ensemble max"), 2L),
    rp_name = rep(c("1:1", "4:5", "1:1", "4:5", "1:1", "4:5"), 2L),
    value = rep(c(5, 5, 4, 3, 6, 7), 2L),
    is_historical = FALSE,
    n_obs = 30L
  )

  dot <- step2_adverse_dot_data(threshold_tbl, method = "mean")
  plot <- plot_step2_adverse_dot(dot)
  colour_scale <- plot$scales$get_scales("colour")

  expect_identical(colour_scale$name, "Climate scenario and period")
  expect_true(all(c("SSP2-4.5 / 2030-2040", "SSP2-4.5 / 2050-2060") %in%
                  colour_scale$breaks))
  expect_true("yr_lbl" %in% names(plot$facet$params$facets))
})

test_that("exceedance plot omits unsupported return-period warning annotation", {
  curves <- tibble::tibble(
    scenario = rep("SSP2-4.5 / 2030-2040", 30L),
    model_id = rep(c("m1", "m2"), each = 15L),
    rank = rep(seq_len(15L), 2L),
    welfare_val = seq_len(30L),
    coef_sd = 0,
    exceed_prob = rep((seq_len(15L) - 0.5) / 30, 2L),
    is_historical = FALSE
  )

  plot <- enhance_exceedance(
    curves, x_label = "Outcome", n_sim_years = 30L,
    logit_x = TRUE, band_q = NULL, ensemble_band_q = c(lo = 0, hi = 1)
  )
  labels <- vapply(plot$layers, function(layer) {
    if (!inherits(layer$geom, "GeomText")) return("")
    as.character(layer$stat_params$label %||% "")
  }, character(1L))
  expect_false(any(grepl("unreliable", labels, fixed = TRUE)))
  expect_false(any(grepl("1:50", labels, fixed = TRUE)))
})

test_that("make_decision_table_html produces clean .wise-table HTML", {
  df <- data.frame(
    scenario = c("Historical", "SSP3-7.0 / 2030"),
    Expected = c(4.5, 4.6),
    `Change from historical` = c(NA, 0.1),
    check.names = FALSE
  )
  tag <- make_decision_table_html(df, subheader = "Welfare outcomes", footnotes = "Footnote 1")
  html <- as.character(htmltools::renderTags(tag)$html)

  expect_match(html, "wise-table", fixed = TRUE)
  expect_match(html, "wise-subheader", fixed = TRUE)
  expect_match(html, "Welfare outcomes", fixed = TRUE)
  expect_match(html, "historical-row", fixed = TRUE)
  expect_match(html, "+0.10", fixed = TRUE)
  expect_match(html, "Footnote 1", fixed = TRUE)
})
