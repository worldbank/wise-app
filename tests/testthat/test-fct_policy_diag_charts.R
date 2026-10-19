# Step 3 diagnostics charts, reach summary and card builders.

diag_series_names <- function(chart) {
  vapply(chart$x$opts$series, function(s) s$name %||% "", character(1))
}

test_that("the reach chart has one bar per component and drops missing shares", {
  comp <- data.frame(
    component = c("Social protection", "Education", "Overlap: reached by both"),
    population_share = c(0.4, 0.1, 0.05), weighted_affected = c(4e5, 1e5, 5e4)
  )
  ch <- echart_policy_reach(comp)
  expect_s3_class(ch, "echarts4r")
  expect_equal(
    vapply(ch$x$opts$series[[1L]]$data, function(x) x$value, numeric(1)), c(40, 10, 5)
  )
  expect_identical(ch$x$opts$yAxis$data, comp$component)
  expect_match(ch$x$opts$series[[1L]]$data[[1L]]$note, "400,000 people")
  comp$population_share[2L] <- NA
  expect_length(echart_policy_reach(comp)$x$opts$series[[1L]]$data, 2L)
  expect_s3_class(echart_policy_reach(NULL), "echarts4r")
  expect_s3_class(echart_policy_reach(comp[0, ]), "echarts4r")
})

test_that("the treatment chart stacks the four assignment states to 100%", {
  tm <- data.frame(
    status = c(
      "Not eligible, not treated", "Inclusion error: not eligible, treated",
      "Exclusion error: eligible, not treated", "Eligible and treated"
    ),
    weighted_share = c(0.6, 0.05, 0.1, 0.25)
  )
  ch <- echart_sp_treatment(tm)
  expect_setequal(diag_series_names(ch), tm$status)
  total <- sum(vapply(ch$x$opts$series, function(s) s$data[[1L]]$value, numeric(1)))
  expect_equal(total, 100)
  expect_true(all(vapply(ch$x$opts$series, function(s) identical(s$stack, "population"), logical(1))))
  expect_s3_class(echart_sp_treatment(NULL), "echarts4r")
  tm$weighted_share[1L] <- NA
  expect_s3_class(echart_sp_treatment(tm), "echarts4r")
  expect_null(echart_sp_treatment(tm)$x$opts$series)
})

test_that("the targeting metrics chart keeps only the poverty-line measures", {
  m <- data.frame(
    metric = c(
      "Annual cost per person in the population", "Inclusion error (realised)",
      "Coverage of the poor", "Leakage to the non-poor", "Adequacy for poor recipients"
    ),
    value = c(1.2, 0.1, 0.5, 0.2, 1.4), kind = c("money", rep("percent", 4L)),
    note = "n", stringsAsFactors = FALSE
  )
  ch <- echart_sp_targeting_metrics(m)
  expect_identical(ch$x$opts$yAxis$data, m$metric[3:5])
  # Adequacy above 100% stays on the axis
  expect_gte(ch$x$opts$xAxis$max, 140)
  # No poverty line: every value is missing, so a placeholder is drawn
  m$value[3:5] <- NA
  expect_null(echart_sp_targeting_metrics(m)$x$opts$series)
  expect_s3_class(echart_sp_targeting_metrics(NULL), "echarts4r")
})

test_that("the shock charts draw one group per scenario and skip empty measures", {
  s <- data.frame(
    scenario = c("Historical", "SSP"), activation_freq = c(0.2, 0.4),
    false_positive_rate = c(0.1, 0.2), false_negative_rate = c(0.3, NA)
  )
  a <- echart_shock_activation(s)
  expect_identical(a$x$opts$xAxis$data, s$scenario)
  expect_equal(
    vapply(a$x$opts$series[[1L]]$data, function(x) x$value, numeric(1)), c(20, 40)
  )
  b <- echart_shock_basis_risk(s)
  expect_length(b$x$opts$series, 2L)
  s$false_negative_rate <- NA_real_
  expect_length(echart_shock_basis_risk(s)$x$opts$series, 1L)
  expect_s3_class(echart_shock_activation(NULL), "echarts4r")
  expect_s3_class(echart_shock_basis_risk(NULL), "echarts4r")
})

test_that("the reach summary counts units with a transfer or a changed covariate", {
  base <- data.frame(x = c(1, 1, 1, 1), hhsize = c(2, 2, 4, 4), weight = c(10, 10, 20, 20))
  pol <- base
  pol$x[2L] <- 2
  pol[[SP_TRANSFER_COL]] <- c(0, 0, 1, 0)
  r <- policy_reach_summary(base, pol, candidates = c("x", SP_TRANSFER_COL))
  expect_equal(r$people, 30)
  expect_equal(r$share, 30 / 60)
  expect_equal(r$households, 10 / 2 + 20 / 4)
  # Candidates limit what counts as a policy change
  expect_equal(policy_reach_summary(base, pol, candidates = SP_TRANSFER_COL)$people, 20)
  expect_null(policy_reach_summary(base, pol[-1, ]))
  expect_null(policy_reach_summary(NULL, pol))
})

test_that("the reach and cost cards describe annual and shock programs", {
  expect_null(.policy_reach_cards(NULL))
  cards <- .policy_reach_cards(list(share = 0.25, people = 1500, households = 300), "hh")
  expect_identical(cards[[1L]]$value, "25.0%")
  expect_match(cards[[1L]]$note, "1,500 people")
  expect_length(cards, 2L)
  expect_length(.policy_reach_cards(list(share = 0.25, people = 1500, households = NA)), 1L)

  d <- list(
    transfer_sum = 900, admin_sum = 100, total_cost_sum = 1000, admin_share = 0.1111,
    transfer_pp = 2.5, transfer_households = 400, transfer_currency = "PPP",
    analysis_unit = "hh"
  )
  per <- data.frame(metric = "Annual cost per person in the population", value = 1.234)
  cost <- .sp_cost_cards(d, shock = FALSE, per_person = per)
  expect_identical(cost[[1L]]$label, "Annual cost")
  expect_match(cost[[1L]]$note, "Transfers \\$900; administration \\$100")
  expect_length(cost, 4L)
  shock <- .sp_cost_cards(d, shock = TRUE)
  expect_identical(shock[[1L]]$label, "Mean annual cost")
  expect_identical(shock[[3L]]$label, "Households paid at least once")
  d$admin_share <- 0
  expect_match(.sp_cost_cards(d)[[1L]]$note, "No administration")
  expect_null(.sp_cost_cards(NULL))
})

test_that("the overlap bar is styled apart and a shock program renames the unreached segment", {
  comp <- data.frame(
    component = c("Social protection", "Electricity", "Overlap: reached by both"),
    population_share = c(0.96, 0.225, 0.214), weighted_affected = c(9.6e5, 2.25e5, 2.14e5)
  )
  d <- echart_policy_reach(comp)$x$opts$series[[1L]]$data
  expect_null(d[[1L]]$itemStyle$borderType)
  expect_identical(d[[3L]]$itemStyle$borderType, "dashed")
  expect_match(d[[3L]]$note, "not additional")

  tm <- data.frame(
    status = c(
      "Not eligible, not treated", "Inclusion error: not eligible, treated",
      "Exclusion error: eligible, not treated", "Eligible and treated"
    ),
    weighted_share = c(0.6, 0.05, 0.1, 0.25)
  )
  expect_true("Exclusion error: eligible, not treated" %in% diag_series_names(echart_sp_treatment(tm)))
  s <- echart_sp_treatment(tm, shock = TRUE)
  expect_true("Eligible, never paid (error or no trigger)" %in% diag_series_names(s))
  expect_false("Exclusion error: eligible, not treated" %in% diag_series_names(s))
})

test_that("fmt_compact shortens large numbers and keeps small ones exact", {
  expect_identical(fmt_compact(c(164569659, 21283160, 3202444)), c("164.6M", "21.3M", "3.2M"))
  expect_identical(fmt_compact(1.9e9, prefix = "$"), "$1.9B")
  expect_identical(fmt_compact(2e6, prefix = "$"), "$2M")
  expect_identical(fmt_compact(12500), "12.5K")
  expect_identical(fmt_compact(c(50, 38.64), prefix = "$", small_digits = 2), c("$50.00", "$38.64"))
  expect_identical(fmt_compact(9999), "9,999")
  expect_identical(fmt_compact(NA), "—")
  expect_identical(fmt_compact(-2.5e6), "-2.5M")
})
