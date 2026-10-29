library(testthat)

run <- list(
  id = "2026-10", label = "October 2026", model = "ECMWF SEAS5",
  init = as.Date("2026-10-01"), released = as.Date("2026-10-06"),
  next_release = as.Date("2026-11-06"), n_members = 51L, n_leads = 6L
)

test_that("the placeholder run source is off unless the scaffold option is set", {
  expect_null(.step2_forecast_runs(scaffold = FALSE))
  withr::with_options(list(wiseapp.forecast_scaffold = NULL), expect_null(.step2_forecast_runs()))
  withr::with_options(list(wiseapp.forecast_scaffold = TRUE), {
    runs <- .step2_forecast_runs()
    expect_named(runs, "2026-10")
    expect_identical(runs[[1L]]$n_leads, 6L)
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
    .step2_forecast_lag_text(m, .step2_forecast_window(m, "2026-11", 3)),
    "Lagged predictors also use observed Sep 2026 and forecast Oct 2026."
  )
  expect_match(
    .step2_forecast_lag_text(m, .step2_forecast_window(m, "2027-01", 3)),
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
