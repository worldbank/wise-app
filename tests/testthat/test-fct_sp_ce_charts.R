# Cost-effectiveness tab: cards and charts.

ce_chart_res <- function(method = "headcount_ratio", tail_cost = 9e6) {
  # tail_cost = NULL: a regular program, the same cost in every year
  cost_avg <- c(4e6, 5e6)
  sp_cost_effectiveness(
    data.frame(
      scenario = c("Historical", "SSP"), effect_avg = c(-0.02, -0.01),
      effect_avg_sd = c(0.005, 0.002), effect_tail = c(-0.03, NA)
    ),
    data.frame(
      scenario = c("Historical", "SSP"), cost_avg = cost_avg,
      cost_tail = if (is.null(tail_cost)) cost_avg else rep(tail_cost, 2L)
    ),
    method, pop = 1e6, poverty_line = 3, level_unit = "$ per day"
  )
}

test_that("the cards show the ratio in both weather years and the annual cost", {
  cards <- .sp_ce_cards(ce_chart_res(), "PPP", "Historical")
  expect_length(cards, 3L)
  expect_identical(cards[[1L]]$label, "Cost per person lifted, average year")
  expect_identical(cards[[1L]]$value, "$200.00")
  expect_match(cards[[1L]]$note, "Net people lifted: 20,000")
  expect_match(cards[[1L]]$note, "95% interval")
  expect_identical(cards[[2L]]$label, "Cost per person lifted, adverse 1-in-20 year")
  expect_match(cards[[2L]]$note, "Net people lifted: 30,000")
  expect_identical(cards[[3L]]$value, "$4,000,000")
  expect_match(cards[[3L]]$note, "Adverse 1-in-20 year: \\$9,000,000")
  # A regular program costs the same every year
  same <- .sp_ce_cards(ce_chart_res(tail_cost = NULL), "PPP", "Historical")
  expect_match(same[[3L]]$note, "Same in every weather year")
  # The unavailable adverse year of the second scenario gives a reason, not a number
  ssp <- .sp_ce_cards(ce_chart_res(), "PPP", "SSP")
  expect_identical(ssp[[2L]]$value, "Not available")
  expect_match(ssp[[2L]]$note, "not available")
  # An unknown focus scenario falls back to the first
  expect_identical(.sp_ce_focus(ce_chart_res(), "nope"), "Historical")
  expect_null(.sp_ce_cards(NULL))
})

test_that("the ratio chart draws one dot per readable row and a whisker for intervals", {
  res <- ce_chart_res()
  rows <- .sp_ce_plot_rows(res, "PPP")
  # SSP adverse year has no effect, so three rows are plotted
  expect_equal(nrow(rows), 3L)
  expect_true(all(c("Historical · Average year", "Historical · Adverse 1-in-20 year") %in% rows$label))
  expect_match(.sp_ce_unshown(res), "SSP, adverse 1-in-20 year")
  ch <- echart_sp_ce_ratio(res, "PPP")
  expect_s3_class(ch, "echarts4r")
  names <- vapply(ch$x$opts$series, `[[`, "", "name")
  expect_setequal(names, c("95% interval", "Average year", "Adverse 1-in-20 year"))
  whisker <- ch$x$opts$series[[match("95% interval", names)]]
  # Only the average-year rows carry an interval
  expect_length(whisker$data, 2L)
  expect_identical(ch$x$opts$yAxis$data, rows$label)
  # Nothing readable gives a placeholder
  none <- ce_chart_res()
  none$status <- "not_applicable"
  expect_null(echart_sp_ce_ratio(none)$x$opts$series)
  expect_s3_class(echart_sp_ce_ratio(NULL), "echarts4r")
})

test_that("a cost per person whose interval reaches zero is a hollow dot", {
  res <- sp_cost_effectiveness(
    data.frame(scenario = "H", effect_avg = -0.01, effect_avg_sd = 0.01, effect_tail = NA),
    data.frame(scenario = "H", cost_avg = 1e6, cost_tail = 1e6),
    "headcount_ratio", pop = 1e6, poverty_line = 3
  )
  expect_identical(res$interval[res$basis == "Average year"], "not bounded")
  ch <- echart_sp_ce_ratio(res)
  dots <- ch$x$opts$series[[1L]]
  expect_identical(dots$name, "Average year")
  expect_identical(dots$data[[1L]]$itemStyle$color, "#FFFFFF")
  expect_false("95% interval" %in% vapply(ch$x$opts$series, `[[`, "", "name"))
})

test_that("the cost chart has one bar for a regular program and two when cost varies", {
  expect_length(echart_sp_ce_cost(ce_chart_res(tail_cost = NULL))$x$opts$series, 1L)
  varying <- echart_sp_ce_cost(ce_chart_res())
  expect_length(varying$x$opts$series, 2L)
  expect_identical(varying$x$opts$xAxis$data, c("Historical", "SSP"))
  # Series data must serialise as arrays, not named objects
  expect_null(names(varying$x$opts$series[[1L]]$data))
  expect_s3_class(echart_sp_ce_cost(NULL), "echarts4r")
})

test_that("shock charts carry the change against history and plot shares above 100%", {
  d <- sp_shock_climate_cost(data.frame(
    scenario = c("Historical", "SSP"), activation_freq = c(0.2, 0.4),
    mean_total_cost = c(100, 150), cost_1_in_20 = c(300, NA)
  ), "Historical")
  ch <- echart_shock_climate_cost(d, "PPP")
  cats <- ch$x$opts$xAxis$data
  expect_match(cats[[1L]], "Reference")
  expect_match(cats[[2L]], "Cost \\+50% vs historical")
  expect_match(cats[[2L]], "Payments in 40% of years")
  expect_s3_class(echart_shock_climate_cost(NULL), "echarts4r")

  poor <- data.frame(scenario = "H", coverage = 0.5, adequacy = 1.3)
  p <- echart_shock_affected_poor(poor)
  expect_gte(p$x$opts$yAxis$max, 130)
  expect_s3_class(echart_shock_affected_poor(poor[0, ]), "echarts4r")
})
