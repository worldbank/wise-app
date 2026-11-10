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

  # Draft-2 run file: 12 observed context months (identical for every member), then the forecast leads.
  init <- as.Date("2023-10-01")
  forecast_months <- seq.Date(init, by = "month", length.out = 6L)
  context_months <- seq.Date(as.Date("2022-10-01"), by = "month", length.out = 12L)
  forecast <- expand.grid(
    member = 0:1,
    timestamp = c(context_months, forecast_months),
    KEEP.OUT.ATTRS = FALSE,
    stringsAsFactors = FALSE
  )
  is_forecast <- forecast$timestamp >= init
  forecast$lead_month <- ifelse(is_forecast, match(forecast$timestamp, forecast_months),
    -(12L - match(forecast$timestamp, context_months)))
  forecast$source <- ifelse(is_forecast, "forecast", ifelse(forecast$timestamp > as.Date("2023-07-01"),
    "era5land_t", "era5land"))
  forecast$h3 <- h3$value[rep(1L, nrow(forecast))]
  forecast$t <- ifelse(is_forecast,
    30 + forecast$member * 10 + match(forecast$timestamp, forecast_months),
    as.numeric(format(forecast$timestamp, "%Y")) + as.integer(format(forecast$timestamp, "%m")) / 100)
  forecast <- forecast[order(forecast$member, forecast$timestamp),
    c("member", "h3", "timestamp", "lead_month", "source", "t")]
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
      init = as.Date("2023-10-01"), observed_through = as.Date("2023-09-01"), context_months = 12L,
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

test_that("lagged predictors read observed context and forecast months from the run file", {
  fx <- make_forecast_weather_fixture()
  fx$selected_weather$ref_start <- 1L
  fx$selected_weather$ref_end <- 3L
  fx$selected_weather$transformation <- "None"
  result <- .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2023-11", len = 1L
  )
  # Nov 2023 lags 1-3: Oct (forecast lead 1), Sep and Aug (observed context).
  expect_equal(result$member_0$t, mean(c(31, 2023.09, 2023.08)))
  expect_equal(result$member_1$t, mean(c(41, 2023.09, 2023.08)))
  # Only the preliminary (ERA5-Land-T) months of the run are reported, not every context month.
  expect_equal(attr(result, "forecast_preliminary_months"), as.Date(c("2023-08-01", "2023-09-01")))
})

test_that("forecast windows reject predictors outside the run's context and unsupported adjustments", {
  fx <- make_forecast_weather_fixture()
  fx$selected_weather$ref_start <- 1L
  fx$selected_weather$ref_end <- 13L
  expect_error(.get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2023-10", len = 1L
  ), "observed context")

  fx$run$adjustment <- "none"
  expect_error(.get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 1L
  ), "supported pipeline adjustment")
})

test_that("a run file with a missing member month or missing value stops the run", {
  fx <- make_forecast_weather_fixture()
  path <- file.path(fx$connection_params$path, fx$run$file)
  data <- arrow::read_parquet(path)
  arrow::write_parquet(data[!(data$member == 1L & data$timestamp == as.Date("2024-01-01")), ], path)
  expect_error(.get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 2L
  ), "missing for selected locations")
  data$t[data$member == 1L & data$timestamp == as.Date("2024-01-01")] <- NA_real_
  arrow::write_parquet(data, path)
  expect_error(.get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 1L
  ), "coverage is incomplete")
})

test_that("the same-window reference rebuilds the target months from observed weather per year", {
  fx <- make_forecast_weather_fixture()
  result <- .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 3L, reference_years = c(2020L, 2021L, 2030L)
  )
  reference <- attr(result, "forecast_reference")
  expect_named(reference, c("refyear_2020", "refyear_2021"))
  expect_identical(attr(result, "forecast_reference_skipped"), 2030L)
  expect_named(result, c("member_0", "member_1"))
  expect_equal(reference$refyear_2020$timestamp, as.Date(c("2020-01-01", "2020-02-01", "2020-03-01")))
  expect_equal(reference$refyear_2021$timestamp, as.Date(c("2021-01-01", "2021-02-01", "2021-03-01")))
  # Deviation from the 1991-2020 monthly mean (2005.5 + month / 100).
  expect_equal(reference$refyear_2020$t, 2020 + (1:3) / 100 - (2005.5 + (1:3) / 100))
  expect_equal(reference$refyear_2021$t, 2021 + (1:3) / 100 - (2005.5 + (1:3) / 100))
  expect_identical(names(reference$refyear_2020), names(result$member_0))
  expect_identical(attr(reference$refyear_2021, "forecast_reference_year"), 2021L)

  received <- list()
  .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 3L, reference_years = 2020L,
    weather_consumer = function(frame, info) received[[length(received) + 1L]] <<- info
  )
  kinds <- vapply(received, function(i) isTRUE(i$forecast_reference), logical(1L))
  expect_identical(sum(kinds), 1L)
  expect_identical(received[kinds][[1L]]$forecast_reference_year, 2020L)
})

test_that("reference years are not built when none are requested", {
  fx <- make_forecast_weather_fixture()
  result <- .get_forecast_weather(
    fx$survey_data, fx$selected_surveys, fx$selected_weather, fx$connection_params,
    fx$run, start = "2024-01", len = 1L
  )
  expect_length(attr(result, "forecast_reference"), 0L)
})
