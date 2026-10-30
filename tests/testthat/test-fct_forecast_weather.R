library(testthat)

make_forecast_weather_fixture <- function() {
  skip_if_not_installed("arrow")
  skip_if_not_installed("duckdb")
  skip_if_not_installed("bit64")

  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  loaded <- tryCatch({ DBI::dbExecute(con, "LOAD h3"); TRUE }, error = function(e) FALSE)
  if (!loaded) skip("DuckDB h3 extension unavailable")
  .duck_load_ext("h3")
  if (!requireNamespace("arrow", quietly = TRUE)) skip("arrow Parquet writer unavailable")

  h3 <- DBI::dbGetQuery(con, paste(
    "SELECT h3_h3_to_string(h3_string_to_h3('85283473fffffff')) AS text,",
    "h3_string_to_h3('85283473fffffff') AS value"
  ))
  root <- tempfile("forecast-weather-")
  dir.create(root)
  withr::defer(unlink(root, recursive = TRUE), envir = parent.frame())
  dir.create(file.path(root, "microdata", "h3", "TST"), recursive = TRUE)
  dir.create(file.path(root, "hazard", "weather", "historical", "TST"), recursive = TRUE)
  dir.create(file.path(root, "hazard", "weather", "forecasts", "TST"), recursive = TRUE)

  h3_map <- data.frame(
    h3 = h3$text, code = "TST", year = 2020L, survname = "SRV", loc_id = "L1",
    pop_2020 = 100L, stringsAsFactors = FALSE
  )
  arrow::write_parquet(
    h3_map,
    file.path(root, "microdata", "h3", "TST", "TST_2020_SRV_lsms_h3.parquet")
  )

  history_months <- seq.Date(as.Date("1991-01-01"), as.Date("2023-09-01"), by = "month")
  historical <- data.frame(
    h3 = rep(h3$value, length(history_months)),
    timestamp = history_months,
    t = as.numeric(format(history_months, "%Y")) + as.integer(format(history_months, "%m")) / 100,
    check.names = FALSE
  )
  arrow::write_parquet(
    historical,
    file.path(root, "hazard", "weather", "historical", "TST", "TST_era5land.parquet")
  )

  forecast_months <- seq.Date(as.Date("2023-10-01"), by = "month", length.out = 6L)
  forecast <- expand.grid(
    member = 0:1,
    timestamp = forecast_months,
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  forecast$model <- "ecmwf_seas51"
  forecast$initialized_at <- as.Date("2023-10-01")
  forecast$lead_month <- match(forecast$timestamp, forecast_months)
  forecast$h3 <- h3$value[rep(1L, nrow(forecast))]
  forecast$t <- 30 + forecast$member * 10 + match(forecast$timestamp, forecast_months)
  forecast <- forecast[, c("model", "initialized_at", "member", "h3", "timestamp", "lead_month", "t")]
  forecast_path <- "hazard/weather/forecasts/TST/run.parquet"
  arrow::write_parquet(forecast, file.path(root, forecast_path))

  list(
    connection_params = list(type = "local", path = root),
    survey_data = data.frame(
      code = "TST", year = 2020L, survname = "SRV", loc_id = "L1",
      timestamp = as.Date("2023-09-01"), int_month = 9L, int_year = 2023L,
      stringsAsFactors = FALSE
    ),
    selected_surveys = data.frame(
      code = "TST", year = 2020L, survname = "SRV", source = "lsms",
      stringsAsFactors = FALSE
    ),
    selected_weather = data.frame(
      name = "t", ref_start = 0L, ref_end = 0L, temporalAgg = "Mean",
      cont_binned = "Continuous", binning_method = NA_character_, num_bins = NA_integer_,
      transformation = "Deviation from mean", stringsAsFactors = FALSE
    ),
    run = list(
      id = "2023-10", product = "seasonal", model_id = "ecmwf_seas51",
      init = as.Date("2023-10-01"), observed_through = as.Date("2023-09-01"),
      n_leads = 6L, members = 0:1, variables = "t", file = forecast_path,
      adjustment = "additive_mean_bias_only"
    )
  )
}

test_that("forecast weather returns aligned member frames for leap-year windows", {
  fx <- make_forecast_weather_fixture()
  result <- .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 3L
  )

  expect_named(result, c("member_0", "member_1"))
  expect_identical(attr(result, "forecast_members"), 0:1)
  expect_identical(attr(result, "forecast_window")$months,
    as.Date(c("2024-01-01", "2024-02-01", "2024-03-01")))
  for (i in seq_along(result)) {
    expect_equal(result[[i]]$timestamp,
      as.Date(c("2024-01-01", "2024-02-01", "2024-03-01")))
    expect_equal(result[[i]]$year, rep(2020L, 3L))
    expect_equal(attr(result[[i]], "forecast_member"), i - 1L)
  }
  expect_equal(result$member_0$t, c(34, 35, 36) - c(2005.51, 2005.52, 2005.53))
  expect_equal(result$member_1$t, c(44, 45, 46) - c(2005.51, 2005.52, 2005.53))
})

test_that("stored breaks and continuous companions are applied to forecast values", {
  fx <- make_forecast_weather_fixture()
  fx$selected_weather$transformation <- "None"
  fx$selected_weather$cont_binned <- "Binned"
  breaks <- list(t = c(-Inf, 35, Inf))
  result <- .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 3L,
    stored_breaks = breaks, keep_continuous = TRUE
  )

  expect_equal(attr(result, "stored_breaks"), breaks)
  expect_true(is.factor(result$member_0$t))
  expect_equal(result$member_0$t_cont, c(34, 35, 36))
  expect_equal(result$member_1$t_cont, c(44, 45, 46))
})

test_that("weather consumer receives one aligned frame per original member", {
  fx <- make_forecast_weather_fixture()
  received <- list()
  result <- .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 3L,
    weather_consumer = function(frame, info) {
      received[[info$member_index]] <<- list(frame = frame, info = info)
    }
  )

  expect_length(result, 0L)
  expect_identical(attr(result, "forecast_members"), 0:1)
  expect_length(received, 2L)
  expect_equal(vapply(received, function(x) x$info$forecast_member, integer(1L)), 0:1)
  expect_true(all(vapply(received, function(x) isTRUE(x$info$forecast), logical(1L))))
  expect_true(all(vapply(received, function(x) nrow(x$frame) == 3L, logical(1L))))
})

test_that("forecast windows reject unavailable predictor months and identity drift", {
  fx <- make_forecast_weather_fixture()
  fx$selected_weather$ref_start <- 1L
  fx$selected_weather$ref_end <- 1L
  fx$run$observed_through <- as.Date("2023-08-01")
  expect_error(.get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2023-10", len = 1L
  ), "observed_through")

  fx$run$observed_through <- as.Date("2023-09-01")
  fx$run$adjustment <- "none"
  expect_error(.get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 1L
  ), "additive mean-bias")
})
