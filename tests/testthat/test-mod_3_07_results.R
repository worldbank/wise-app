# ============================================================================ #
# tests/testthat/test-mod_3_07_results.R                                       #
# Step 3 Results visualization and UI redesign unit tests                      #
# ============================================================================ #

library(testthat)
library(shiny)

test_that("step3_headline_cards builds 5 concise policy cards", {
  paired_sum <- tibble::tibble(
    scenario    = c("Historical", "SSP2-4.5 / 2030-2040"),
    value       = c(0.00, 0.45),
    intermod_lo = c(0.00, 0.32),
    intermod_hi = c(0.00, 0.58),
    n_models    = c(1L, 4L),
    n_years     = c(30L, 30L)
  )

  thresh <- tibble::tibble(
    scenario      = rep(c("Historical", "SSP2-4.5 / 2030-2040"), each = 4),
    source        = rep(c("Baseline", "Baseline", "Policy", "Policy"), 2),
    Estimate      = rep("Central (P50)", 8),
    rp_name       = rep(c("1:1", "9:10"), 4),
    value         = c(3.0, 2.0, 3.0, 2.0,
                      3.2, 2.1, 3.65, 2.68),
    n_obs         = 30L,
    is_historical = rep(c(TRUE, FALSE), each = 4)
  )

  cards <- step3_headline_cards(
    paired_summary    = paired_sum,
    threshold_tbl     = thresh,
    baseline_agg      = list("SSP2-4.5 / 2030-2040" = list(out = data.frame(value = 3.2))),
    policy_agg        = list("SSP2-4.5 / 2030-2040" = list(out = data.frame(value = 3.65))),
    decomp_res        = NULL,
    policy_svy        = NULL,
    sp_scenario       = list(budget_fixed = 12500000),
    timeseries_curves = data.frame(scenario = "SSP2-4.5 / 2030-2040", source = "Policy", sim_year = 2030:2039),
    method            = "mean",
    deviation         = "none",
    so                = list(type = "numeric", name = "welfare")
  )

  expect_length(cards, 5L)

  # Card 1: Expected policy effect
  expect_identical(cards[[1]]$label, "Expected policy effect")
  expect_identical(cards[[1]]$value, "+0.45")
  expect_match(cards[[1]]$note, "Policy: 3.65 vs Base: 3.20", fixed = TRUE)

  # Card 2: Adverse 1-in-10 protection
  expect_identical(cards[[2]]$label, "Adverse 1-in-20 year protection")
  expect_identical(cards[[2]]$value, "Unavailable")
  expect_match(cards[[2]]$note, "1-in-10: +0.58", fixed = TRUE)

  # Card 3: Policy channels
  expect_identical(cards[[3]]$label, "Resilience effect")
  expect_identical(cards[[3]]$value, "Unavailable")

  # Card 4: Program scale & reach
  expect_identical(cards[[4]]$label, "Program scale & reach")
  expect_identical(cards[[4]]$value, "Unavailable")
  expect_match(cards[[4]]$note, "Population reached", fixed = TRUE)

  # Card 5: Policy robustness
  expect_identical(cards[[5]]$label, "Policy robustness")
  expect_identical(cards[[5]]$value, "100% positive")
  expect_match(cards[[5]]$note, "Model range: +0.32 to +0.58", fixed = TRUE)

  # Serializer
  df <- step3_headline_df(cards)
  expect_s3_class(df, "data.frame")
  expect_equal(nrow(df), 5L)
  expect_identical(df$label, c("Expected policy effect", "Adverse 1-in-20 year protection",
                               "Resilience effect", "Program scale & reach", "Policy robustness"))
})

test_that("step3_adverse_dot_data and plot_step3_adverse_dot work correctly", {
  thresh <- tibble::tibble(
    scenario      = rep(c("Historical", "SSP2-4.5 / 2030-2040"), each = 8),
    source        = rep(rep(c("Baseline", "Policy"), each = 4), 2),
    Estimate      = rep(c("Central (P50)", "Ensemble 0%", "Ensemble 100%", "Central (P50)"), 4),
    rp_name       = rep(c("1:1", "9:10", "9:10", "9:10"), 4),
    value         = c(3.0, 2.0, 2.0, 2.0, 3.0, 2.0, 2.0, 2.0,
                      3.2, 2.1, 2.1, 2.1, 3.65, 2.4, 2.9, 2.68),
    n_obs         = 30L,
    is_historical = rep(c(TRUE, FALSE), each = 8)
  )

  dot_df <- step3_adverse_dot_data(thresh, method = "mean", so = list(type = "numeric", name = "welfare"))
  expect_s3_class(dot_df, "data.frame")
  expect_true(nrow(dot_df) > 0L)
  expect_true(all(c("scenario", "rp_label", "baseline_val", "policy_val", "effect") %in% names(dot_df)))

  plt <- plot_step3_adverse_dot(dot_df, x_label = "Consumption ($/day)")
  expect_s3_class(plt, "ggplot")
})

test_that("step3_variance_breakdown and plot_step3_variance_contribution work correctly", {
  hist_entry <- list(out = tibble::tibble(
    sim_year = 2020:2029,
    value_all_sd = list(rep(0.1, 2)),
    model_id = list(c("M1", "M2")),
    value_all = list(c(3.0, 3.1))
  ))
  fut_entry <- list(out = tibble::tibble(
    sim_year = 2030:2039,
    value_all_sd = list(rep(0.12, 2)),
    model_id = list(c("M1", "M2")),
    value_all = list(c(3.2, 3.5))
  ))

  b_series <- list("Historical" = hist_entry, "SSP2-4.5 / 2030-2040" = fut_entry)
  p_series <- list("Historical" = hist_entry, "SSP2-4.5 / 2030-2040" = fut_entry)

  vb <- step3_variance_breakdown(b_series, p_series, selected_scenarios = "SSP2-4.5 / 2030-2040")
  expect_s3_class(vb, "data.frame")
  expect_true(all(c("scenario", "source", "sd_coef", "sd_within", "sd_across") %in% names(vb)))
  expect_setequal(unique(vb$source), c("Baseline", "Policy"))

  plt <- plot_step3_variance_contribution(vb)
  expect_s3_class(plt, "ggplot")
})

test_that("step3_decision_table_data and make_step3_decision_table_html work correctly", {
  thresh <- tibble::tibble(
    scenario      = rep(c("Historical", "SSP2-4.5 / 2030-2040"), each = 4),
    source        = rep(c("Baseline", "Baseline", "Policy", "Policy"), 2),
    Estimate      = rep("Central (P50)", 8),
    rp_name       = rep(c("1:1", "9:10"), 4),
    value         = c(3.0, 2.0, 3.0, 2.0,
                      3.2, 2.1, 3.65, 2.68),
    n_obs         = 30L,
    is_historical = rep(c(TRUE, FALSE), each = 4)
  )

  dt_df <- step3_decision_table_data(thresh, method = "mean", so = list(type = "numeric", name = "welfare"))
  expect_s3_class(dt_df, "data.frame")
  expect_true(all(c("scenario", "source", "Expected", "Policy effect") %in% names(dt_df)))
  # Policy row under SSP2-4.5 should have Policy effect = 3.65 - 3.2 = 0.45
  pol_row <- dt_df[dt_df$scenario == "SSP2-4.5 / 2030-2040" & dt_df$source == "Policy", ]
  expect_equal(pol_row$`Policy effect`[[1L]], 0.45, tolerance = 1e-4)

  html_tag <- make_step3_decision_table_html(dt_df, subheader = "Welfare outcomes")
  rendered <- as.character(htmltools::renderTags(html_tag)$html)
  expect_match(rendered, "wise-table", fixed = TRUE)
  expect_match(rendered, "policy-row", fixed = TRUE)
  expect_match(rendered, "policy-effect-badge", fixed = TRUE)
  expect_match(rendered, "+0.45", fixed = TRUE)
  expect_match(rendered, "historical-row", fixed = TRUE)
})

test_that(".results_pane_ui renders aggregation panel and 5 question sections", {
  so <- list(name = "welfare", type = "numeric", label = "Consumption", level = "hh", units = "$/day")
  ui <- .results_pane_ui(shiny::NS("results3"), so)
  html <- as.character(htmltools::renderTags(ui)$html)

  # Aggregation panel
  expect_match(html, "results-aggregation-panel", fixed = TRUE)
  expect_match(html, "How to summarise consumption across households?", fixed = TRUE)
  expect_match(html, "results3-cmp_agg_method", fixed = TRUE)
  expect_match(html, "results3-cmp_pov_line", fixed = TRUE)

  # Five question-based section cards
  expect_match(html, "How does the policy shift consumption across climate scenarios and weather years?", fixed = TRUE)
  expect_match(html, "Does the policy protect against adverse weather years?", fixed = TRUE)
  expect_match(html, "How does the policy change the probability of severe outcomes?", fixed = TRUE)
  expect_match(html, "What drives uncertainty, and does the policy reduce outcome variance?", fixed = TRUE)
  expect_match(html, "Detailed baseline, policy, and return-period outcomes", fixed = TRUE)

  # Plot and table outputs
  expect_match(html, "results3-annual_distribution_plot", fixed = TRUE)
  expect_match(html, "results3-annual_distribution_type", fixed = TRUE)
  expect_match(html, "Violin", fixed = TRUE)
  expect_match(html, "Boxplot", fixed = TRUE)
  expect_match(html, "results3-adverse_dot_plot", fixed = TRUE)
  expect_match(html, "Climate model spread", fixed = TRUE)
  expect_match(html, "Full ensemble spread", fixed = TRUE)
  expect_match(html, "results3-ensemble_band", fixed = TRUE)
  expect_match(html, "results3-exceedance_plot", fixed = TRUE)
  expect_match(html, "results3-uncertainty_sources_plot", fixed = TRUE)
  expect_match(html, "results3-summary_threshold_table", fixed = TRUE)
  expect_match(html, "results3-threshold_csv", fixed = TRUE)
})

test_that("format_weather_heading_phrase handles scalar, vector, data.frame, and length 12 safely", {
  expect_identical(format_weather_heading_phrase(NULL), "")
  expect_identical(format_weather_heading_phrase("Precipitation"), "precipitation")
  expect_identical(format_weather_heading_phrase(c("Temperature", "Precipitation")), "temperature and precipitation")
  expect_identical(format_weather_heading_phrase("Temperature, Precipitation"), "temperature and precipitation")

  # 3+ variables / 12 months should yield empty string (no awkward 12-variable heading)
  twelve_vars <- paste0("month_", 1:12)
  expect_identical(format_weather_heading_phrase(twelve_vars), "")

  # Comma-separated list of 12 variables
  expect_identical(format_weather_heading_phrase(paste(twelve_vars, collapse = ", ")), "")

  # Data frames (single row, two rows, 12 rows)
  df_one <- data.frame(name = "temp", label = "Temperature", stringsAsFactors = FALSE)
  expect_identical(format_weather_heading_phrase(df_one), "temperature")

  df_two <- data.frame(name = c("temp", "precip"), label = c("Temperature", "Precipitation"), stringsAsFactors = FALSE)
  expect_identical(format_weather_heading_phrase(df_two), "temperature and precipitation")

  df_twelve <- data.frame(name = twelve_vars, label = paste("Month", 1:12), stringsAsFactors = FALSE)
  expect_identical(format_weather_heading_phrase(df_twelve), "")
})

test_that(".results_pane_ui handles tibble so without level and 12-element weather_var without warnings or errors", {
  # tibble without level column - must NOT emit 'Unknown or uninitialised column: level'
  so_tbl <- tibble::tibble(
    name  = "welfare",
    type  = "numeric",
    label = "Welfare",
    units = "$/day"
  )

  # weather_var of length 12 (as from a 12-month simulation)
  twelve_vars <- paste0("month_var_", 1:12)

  # Run without warnings or errors
  expect_no_warning({
    ui <- .results_pane_ui(shiny::NS("results3"), so_tbl, weather_var = twelve_vars)
  })

  html <- as.character(htmltools::renderTags(ui)$html)
  expect_match(html, "How does the policy shift welfare across climate scenarios and weather years?", fixed = TRUE)

  # Also test with 12-row data frame
  df_twelve <- data.frame(name = twelve_vars, label = paste("Month", 1:12), stringsAsFactors = FALSE)
  expect_no_warning({
    ui_df <- .results_pane_ui(shiny::NS("results3"), so_tbl, weather_var = df_twelve)
  })
  html_df <- as.character(htmltools::renderTags(ui_df)$html)
  expect_match(html_df, "How does the policy shift welfare across climate scenarios and weather years?", fixed = TRUE)
})
