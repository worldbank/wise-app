test_that("forecast windows preserve dates and all households in one member state", {
  train <- data.frame(welfare = c(1, 2, 3, 4), t = 0:3)
  model <- fixest::feols(welfare ~ t, data = train)
  svy <- data.frame(hhid = c("a", "b"), code = "TST", year = 2020L,
    survname = "SRV", loc_id = "L1", int_month = c(6L, 7L),
    welfare = c(1, 2), t = 0, weight = c(1, 3))
  forecast <- list(run = list(id = "2026-10", product = "seasonal", label = "October 2026",
    members = 0:1), start = "2026-12", len = 2L)
  expanded <- .step2_forecast_expand_survey(svy, forecast)
  expanded$.svy_row_id <- rep(seq_len(nrow(svy)), times = forecast$len)
  weather <- data.frame(code = "TST", year = 2020L, survname = "SRV", loc_id = "L1",
    timestamp = as.POSIXct(c("2026-12-01", "2027-01-01"), tz = "UTC"), t = c(10, 20))
  attr(weather, "forecast_window_year") <- 2026L
  pipeline <- run_sim_pipeline(weather_raw = weather, svy = expanded,
    sw = data.frame(name = "t"), so = list(name = "welfare", type = "numeric", transform = "none"),
    model = model, residuals = "none", train_data = train, engine = "fixest")
  expect_length(pipeline$y_point, 4L)
  expect_identical(unique(pipeline$sim_year), 2026L)
  expect_equal(sort(pipeline$y_point), c(11, 11, 21, 21), tolerance = 1e-8)
  expect_equal(sort(pipeline$svy_row_id), c(1L, 1L, 2L, 2L))
  expect_equal(sum(pipeline$weight), sum(svy$weight))
  expect_identical(sort(unique(as.Date(pipeline$weather_raw$timestamp))), as.Date(weather$timestamp))
  expect_equal(expanded$year, rep(svy$year, 2L))
  expect_equal(expanded$int_month, c(12L, 12L, 1L, 1L))
  svy$weights <- c(5, 7)
  svy$weight <- NULL
  expect_equal(.step2_forecast_expand_survey(svy, forecast)$weights, rep(c(5, 7), 2L))
})

test_that("forecast off keeps the original signature and versioned runs separate", {
  forecast <- list(run = list(id = "2026-10", product = "seasonal", label = "October 2026",
    members = 0:1, data_sha256 = "version-a", manifest_sha256 = "manifest-a"),
    start = "2026-12", len = 2L)
  first <- .step2_forecast_group(forecast)
  forecast$run$data_sha256 <- "version-b"
  second <- .step2_forecast_group(forecast)
  expect_false(identical(first$gk, second$gk))
  expect_identical(first$sim_year, 2026L)
  expect_match(first$label, "Dec 2026 - Jan 2027", fixed = TRUE)
})

test_that("forecast member callbacks and prepared replay agree with SSPs alongside", {
  train <- data.frame(welfare = 1:4, t = 0:3)
  model <- fixest::feols(welfare ~ t, data = train)
  svy <- data.frame(hhid = c("a", "b"), code = "TST", year = 2020L,
    survname = "SRV", loc_id = "L1", int_month = c(6L, 7L),
    welfare = c(1, 2), t = 0, weight = c(1, 3))
  forecast <- list(run = list(id = "2026-10", product = "seasonal", label = "October 2026",
    members = 0:1), start = "2026-12", len = 2L)
  historical <- data.frame(code = "TST", year = 2020L, survname = "SRV", loc_id = "L1",
    timestamp = as.POSIXct(c("2020-06-01", "2020-07-01"), tz = "UTC"), t = c(1, 2))
  frames <- list(historical = historical, ssp2_4_5_2030_2040_ensemble_mean = historical,
    member_0 = transform(historical,
      timestamp = as.POSIXct(c("2026-12-01", "2027-01-01"), tz = "UTC"), t = c(10, 20)),
    member_1 = transform(historical,
      timestamp = as.POSIXct(c("2026-12-01", "2027-01-01"), tz = "UTC"), t = c(20, 30)))
  loader <- function(weather_consumer = NULL, ...) {
    if (is.null(weather_consumer)) return(frames)
    for (key in names(frames)) {
      meta <- if (startsWith(key, "member_")) list(forecast = TRUE,
        forecast_member = as.integer(sub("member_", "", key)),
        member_index = match(key, names(frames)) - 2L, period_members = 2L)
      weather_consumer(key, frames[[key]], meta)
    }
    list()
  }
  args <- list(sw = data.frame(name = "t"), so = list(name = "welfare", type = "numeric", transform = "none"),
    svy = svy, ss = NULL, mf = list(fit3 = model, engine = "fixest", train_data = train, weather_terms = "t"),
    cp = list(type = "local", path = tempdir()), fp_list = list(c("2030-01-01", "2040-12-31")),
    ssps = "ssp2_4_5", residuals = "none", skip_coef_draws = TRUE,
    sim_dates = as.Date(c("2020-01-01", "2020-12-31")), perturbation_method = NULL,
    stored_breaks = NULL, weather_fn = loader, progress_fn = function(...) NULL, forecast = forecast)
  streamed <- do.call(fct_run_simulation, args)
  replay <- do.call(fct_run_simulation, c(args, list(prepared_weather_cache = "auto")))
  label <- .step2_forecast_group(forecast)$label
  expect_length(streamed$failures, 0L)
  expect_identical(names(streamed$new_scenarios[[label]]$pipelines), c("member_0", "member_1"))
  for (member in c("member_0", "member_1")) {
    a <- streamed$new_scenarios[[label]]$pipelines[[member]]
    b <- replay$new_scenarios[[label]]$pipelines[[member]]
    expect_equal(a$y_point, b$y_point)
    expect_identical(unique(a$sim_year), 2026L)
    expect_equal(sum(a$weight), sum(svy$weight))
    raw <- step2_resolve_weather(a$weather_raw, streamed$new_scenarios[[label]])
    expect_equal(sort(unique(as.Date(raw$timestamp))), as.Date(c("2026-12-01", "2027-01-01")))
  }
  expect_null(streamed$new_scenarios[["SSP2-4.5 / 2030-2040"]]$forecast)
  expect_equal(streamed$n_keys, 4L)
})
