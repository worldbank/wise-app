library(testthat)

run <- list(
  id = "2026-10", label = "October 2026", model = "ECMWF SEAS5",
  init = as.Date("2026-10-01"), released = as.Date("2026-10-06"),
  next_release = as.Date("2026-11-06"), n_members = 51L, n_leads = 6L,
  product = "seasonal", lead_unit = "month"
)

test_that("the placeholder run source is off unless the scaffold option is set", {
  expect_null(.step2_forecast_runs(scaffold = FALSE))
  withr::with_options(list(wiseapp.forecast_scaffold = NULL), expect_null(.step2_forecast_runs()))
  withr::with_options(list(wiseapp.forecast_scaffold = TRUE), {
    runs <- .step2_forecast_runs()
    expect_named(runs, "2026-10")
    expect_identical(runs[[1L]]$n_leads, 6L)
    expect_identical(runs[[1L]]$product, "seasonal")
    expect_identical(runs[[1L]]$lead_unit, "month")
  })
})

test_that("the month strip has observed context, forecast leads and months beyond", {
  m <- .step2_forecast_months(run)
  expect_identical(nrow(m), 11L)
  expect_identical(m$value[c(1L, 3L, 8L, 11L)], c("2026-08", "2026-10", "2027-03", "2027-06"))
  expect_identical(m$kind, c("obs", "obs", rep("fc", 6L), rep("na", 3L)))
})

test_that("a target window is kept inside the forecast horizon", {
  m <- .step2_forecast_months(run)
  expect_identical(.step2_forecast_clamp_start(m, "2026-11", "3"), "2026-11")
  # Unset, observed and beyond-horizon starts fall back to lead 2.
  expect_identical(.step2_forecast_clamp_start(m, NULL, 3), "2026-11")
  expect_identical(.step2_forecast_clamp_start(m, "2026-08", 3), "2026-11")
  expect_identical(.step2_forecast_clamp_start(m, "2027-05", 3), "2026-11")
  # A start that would overrun the last lead moves back.
  expect_identical(.step2_forecast_clamp_start(m, "2027-03", 3), "2027-01")
  expect_identical(.step2_forecast_clamp_start(m, "2027-03", 6), "2026-10")
  expect_identical(.step2_forecast_clamp_start(m, "2027-03", 1), "2027-03")
  expect_null(.step2_forecast_clamp_start(m[m$kind != "fc", ], "2026-11", 3))
})

test_that("window labels and leads follow the start and length", {
  m <- .step2_forecast_months(run)
  w <- .step2_forecast_window(m, "2026-11", "3")
  expect_identical(w$label, "Nov 2026 \u2013 Jan 2027")
  expect_identical(w$short, "Nov\u2013Jan")
  expect_identical(c(w$lead_from, w$lead_to), c(2L, 4L))
  w1 <- .step2_forecast_window(m, "2027-03", "1")
  expect_identical(w1$label, "Mar 2027")
  expect_identical(w1$short, "Mar")
  expect_identical(c(w1$lead_from, w1$lead_to), c(6L, 6L))
  expect_null(.step2_forecast_window(m[m$kind != "fc", ], "2026-11", "3"))
})

test_that("the lag sentence names observed and forecast months before the window", {
  m <- .step2_forecast_months(run)
  expect_identical(
    .step2_forecast_lag_text(m, .step2_forecast_window(m, "2026-11", 3), 2L),
    "Lagged predictors also use observed Sep 2026 and forecast Oct 2026."
  )
  expect_match(
    .step2_forecast_lag_text(m, .step2_forecast_window(m, "2027-01", 3), 2L),
    "forecast Nov 2026, Dec 2026", fixed = TRUE
  )
})

test_that("the forecast is blocked with a reason when it cannot be used", {
  expect_match(.step2_forecast_block_reason(NULL, character(0)), "No seasonal forecast")
  expect_identical(.step2_forecast_unsupported(c("t", "r", "tx35", "t")), "tx35")
  expect_match(
    .step2_forecast_block_reason(list(run), "tx35"), "uses tx35", fixed = TRUE
  )
  expect_null(.step2_forecast_block_reason(list(run), character(0)))
})

test_that("the strip disables months that are not forecast months", {
  m <- .step2_forecast_months(run)
  html <- as.character(forecast_strip_input("fc_start", "fc_len", m, "2026-11"))
  expect_match(html, 'data-len-input="fc_len"', fixed = TRUE)
  expect_match(html, "--fc-cols:11", fixed = TRUE)
  expect_equal(lengths(regmatches(html, gregexpr('disabled="disabled"', html))), 5L)
  expect_match(html, 'value="2026-11" checked', fixed = TRUE)
  all_off <- as.character(forecast_strip_input("fc_start", "fc_len", m, "2026-11", disabled = TRUE))
  expect_equal(lengths(regmatches(all_off, gregexpr('disabled="disabled"', all_off))), 10L)
})

test_that("the lag is the longest reach-back of the fitted weather predictors", {
  expect_identical(.step2_forecast_lag(data.frame(name = character(), ref_end = integer())), 0L)
  expect_identical(.step2_forecast_lag(data.frame(name = "t")), 0L)
  expect_identical(.step2_forecast_lag(data.frame(name = c("t", "r"), ref_start = 0L, ref_end = c(3L, 5L))), 5L)
  expect_identical(.step2_forecast_lag(data.frame(name = "t", ref_end = NA_integer_)), 0L)
})

test_that("the strip widens to the lag, up to a cap, and the lag text covers the excess", {
  expect_identical(sum(.step2_forecast_months(run, 4L)$kind == "obs"), 4L)
  expect_identical(sum(.step2_forecast_months(run, 12L)$kind == "obs"), .STEP2_FORECAST_BEFORE_MAX)
  expect_identical(sum(.step2_forecast_months(run, 0L)$kind == "obs"), .STEP2_FORECAST_BEFORE)
  m <- .step2_forecast_months(run, 12L)
  txt <- .step2_forecast_lag_text(m, .step2_forecast_window(m, "2026-11", 1), 12L)
  expect_match(txt, "reaches back 12 months", fixed = TRUE)
  expect_null(.step2_forecast_lag_text(m, .step2_forecast_window(m, "2026-11", 1), 0L))
  html <- as.character(forecast_strip_input("fc_start", "fc_len", m, "2026-11", lag = 12L))
  expect_match(html, 'data-lag="12"', fixed = TRUE)
})

test_that("the forecast scenario key and signature name the product, run and window", {
  m <- .step2_forecast_months(run)
  w <- .step2_forecast_window(m, "2026-11", 3)
  expect_identical(
    .step2_forecast_display_key(run, w),
    "Seasonal forecast / Nov 2026 \u2013 Jan 2027 (October 2026 run)"
  )
  expect_identical(
    .step2_forecast_signature(run, w),
    list(product = "seasonal", run = "2026-10", start = "2026-11", len = 3L)
  )
  run$product <- "subseasonal"
  expect_match(.step2_forecast_display_key(run, w), "^Subseasonal forecast / ")
})

test_that("forecast scenarios are recognised by name and have their own colour", {
  m <- .step2_forecast_months(run)
  key <- .step2_forecast_display_key(run, .step2_forecast_window(m, "2026-11", 3))
  expect_identical(
    .step2_is_forecast_scenario(c(key, "Historical", "SSP2-4.5 / 2030-2040", "Subseasonal forecast / X")),
    c(TRUE, FALSE, FALSE, TRUE)
  )
  expect_false(.wise_forecast %in% c(unname(.ssp_colours), .wise_history, .wise_support, .wise_slate))
})
