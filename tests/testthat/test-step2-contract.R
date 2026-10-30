# Phase 2 characterization tests for the Step 2 result and pipeline contracts.
# These tests intentionally use injected weather/pipeline functions or small
# in-memory models. They are a serial reference characterization, not a new
# implementation.

library(testthat)

step2_contract_weather <- function() {
  hist <- data.frame(
    code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01",
    temp = 1, timestamp = as.POSIXct("2020-06-01", tz = "UTC"),
    stringsAsFactors = FALSE
  )
  mean_key <- hist
  mean_key$timestamp <- as.POSIXct("2030-06-01", tz = "UTC")
  mean_key$temp <- 2
  hi_key <- mean_key
  hi_key$temp <- 3
  list(
    historical = hist,
    ssp2_4_5_2030_2040_ensemble_mean = mean_key,
    ssp2_4_5_2030_2040_ensemble_hi = hi_key
  )
}

step2_contract_pipeline <- function(weather_raw, svy, ...) {
  list(
    y_point = c(1, 2),
    F_loading = NULL,
    sim_year = c(2030L, 2030L),
    weight = c(1, 2),
    id_vec = c("hh01", "hh02"),
    id_col = "hhid",
    svy_row_id = c(1L, 2L),
    n_pre_join = 2L,
    weather_raw = weather_raw,
    train_aug = data.frame(hhid = c("hh01", "hh02"), .resid = c(0.1, -0.1))
  )
}

step2_contract_run <- function(weather_result = step2_contract_weather(),
                               weather_fn = NULL,
                               fp_list = list(c("2030-01-01", "2040-12-31")),
                               ssps = "ssp2_4_5", ...) {
  fct_run_simulation(
    sw = data.frame(name = "temp", stringsAsFactors = FALSE),
    so = data.frame(
      name = "welfare", type = "numeric", transform = "log",
      label = "Welfare", stringsAsFactors = FALSE
    ),
    svy = data.frame(
      hhid = c("hh01", "hh02"), code = "TST", year = 2020L,
      survname = "SRV", loc_id = "loc01", int_month = 6L, welfare = c(1, 2),
      temp = c(1, 1), weight = c(1, 2), stringsAsFactors = FALSE
    ),
    ss = NULL,
    mf = list(
      fit3 = NULL, engine = "fixest", train_data = data.frame(x = 1:2),
      weather_terms = "temp"
    ),
    cp = list(type = "local", path = tempdir()),
    fp_list = fp_list,
    ssps = ssps,
    residuals = "none",
    skip_coef_draws = TRUE,
    sim_dates = c("2020-01-01", "2020-12-31"),
    perturbation_method = NULL,
    stored_breaks = NULL,
    progress_fn = function(...) invisible(NULL),
    weather_fn = weather_fn %||% function(...) weather_result,
    pipeline_fn = step2_contract_pipeline,
    ...
  )
}

test_that("callback weather consumption preserves producer order", {
  frames <- step2_contract_weather()
  loader <- function(weather_consumer, ...) {
    for (key in names(frames)) weather_consumer(key, frames[[key]])
    list()
  }
  result <- suppressWarnings(do.call(
    step2_contract_run,
    c(list(weather_result = frames), list(weather_fn = loader))
  ))
  expect_identical(result$n_keys, 3L)
  expect_identical(names(result$new_scenarios[[1L]]$pipelines),
                   c("ensemble_mean", "ensemble_hi"))
})

test_that("callback consumer receives one bounded member at a time", {
  frames <- step2_contract_weather()
  seen <- character(0)
  metadata_seen <- list()
  loader <- function(weather_consumer, ...) {
    for (key in names(frames)) {
      metadata <- list(order = length(seen) + 1L,
                       collection = "bounded", buffered_members = 1L)
      metadata_seen[[length(metadata_seen) + 1L]] <<- metadata
      weather_consumer(key, frames[[key]], metadata)
      seen <<- c(seen, key)
    }
    list()
  }
  result <- suppressWarnings(do.call(
    step2_contract_run,
    c(list(weather_result = frames), list(weather_fn = loader))
  ))
  expect_identical(result$n_keys, 3L)
  expect_identical(seen, names(frames))
  expect_identical(vapply(metadata_seen, `[[`, integer(1), "buffered_members"),
                   rep.int(1L, 3L))
})

test_that("Step 2 top-level result contract is stable", {
  result <- suppressWarnings(step2_contract_run())

  expect_identical(
    names(result),
    c(
      "hist_sim_result", "new_scenarios", "n_keys",
       "total_runs", "t_elapsed", "t_weather", "failures", "n_keys_ok",
       "data_quality", "payload_mode"
    )
  )
  expect_type(result$hist_sim_result, "list")
  expect_type(result$new_scenarios, "list")
  expect_identical(result$n_keys, 3L)
  expect_identical(result$n_keys_ok, 3L)
  expect_length(result$failures, 0L)
  expect_true(is.finite(result$t_elapsed))
  expect_true(is.finite(result$t_weather))
})

test_that("historical and scenario payload contracts preserve key fields", {
  result <- suppressWarnings(step2_contract_run())
  historical <- result$hist_sim_result
  scenario <- result$new_scenarios[["SSP2-4.5 / 2030-2040"]]

  expect_identical(
    names(historical),
    c(
       "pipeline", "chol_obj", "so", "has_weights", "weather_raw",
        "svy", "residuals", "seed", "shared_context"
    )
  )
  expect_identical(historical$seed, WISEAPP_DEFAULT_SEED)
  expect_identical(
    names(historical$pipeline),
    c(
       "y_point", "F_loading", "sim_year", "weight", "id_vec",
       "svy_row_id", "n_pre_join", "weather_raw"
    )
  )
  expect_identical(
    names(scenario),
    c(
       "pipelines", "weather_raw", "so", "year_range",
        "n_models", "n_models_requested", "residuals", "weather_shared",
        "shared_context"
    )
  )
  expect_identical(scenario$year_range, c("2030", "2040"))
  expect_identical(scenario$n_models, 2L)
  expect_identical(scenario$n_models_requested, 2L)
  expect_identical(scenario$residuals, "none")
})

test_that("scenario pipelines retain model-specific weather payloads", {
  result <- suppressWarnings(step2_contract_run())
  pipelines <- result$new_scenarios[["SSP2-4.5 / 2030-2040"]]$pipelines
  scenario <- result$new_scenarios[["SSP2-4.5 / 2030-2040"]]

  expect_setequal(names(pipelines), c("ensemble_mean", "ensemble_hi"))
  expect_false(identical(
    step2_resolve_weather(pipelines$ensemble_mean$weather_raw, scenario)$temp,
    step2_resolve_weather(pipelines$ensemble_hi$weather_raw, scenario)$temp
  ))
  expect_identical(
    step2_resolve_weather(pipelines$ensemble_mean$weather_raw, scenario)$temp, 2
  )
  expect_identical(
    step2_resolve_weather(pipelines$ensemble_hi$weather_raw, scenario)$temp, 3
  )
})

test_that("forecast members share one distinct forecast scenario and start-year state", {
  frames <- step2_contract_weather()
  forecast_member <- frames$ssp2_4_5_2030_2040_ensemble_mean
  forecast_member <- forecast_member[rep(1L, 3L), , drop = FALSE]
  forecast_member$year <- "2020"
  forecast_member$int_month <- c(11L, 12L, 1L)
  forecast_member$timestamp <- as.POSIXct(c("2030-11-01", "2030-12-01", "2031-01-01"), tz = "UTC")
  forecast_member$temp <- 8
  forecast_member$forecast_member <- NULL
  attr(forecast_member, "forecast_member") <- 0L
  forecast_member_1 <- forecast_member
  attr(forecast_member_1, "forecast_member") <- 1L
  forecast <- list(
    run = list(
      id = "pilot-1", product = "seasonal", label = "test",
      members = 0:1, variables = "temp", model_id = "test", init = as.Date("2030-01-01"),
      observed_through = as.Date("2029-12-01"), n_leads = 12L,
      file = "test.parquet", adjustment = "additive_mean_bias_only",
      data_sha256 = "data", manifest_sha256 = "manifest"
    ),
    start = "2030-11", len = 3L
  )
  loader <- function(weather_consumer, ...) {
    weather_consumer("member_0", forecast_member, list(
      forecast = TRUE, forecast_run = "pilot-1", forecast_member = 0L,
      member_index = 1L, period_members = 2L, start = "2030-11", len = 3L,
      label = "Nov 2030 - Jan 2031", order = 2L, is_historical = FALSE
    ))
    weather_consumer("member_1", forecast_member_1, list(
      forecast = TRUE, forecast_run = "pilot-1", forecast_member = 1L,
      member_index = 2L, period_members = 2L, start = "2030-11", len = 3L,
      label = "Nov 2030 - Jan 2031", order = 3L, is_historical = FALSE
    ))
    list()
  }
  result <- suppressWarnings(step2_contract_run(
    weather_result = list(), weather_fn = loader, fp_list = list(), ssps = character(0),
    forecast = forecast
  ))
  scenario <- result$new_scenarios[[1L]]
  expect_length(result$new_scenarios, 1L)
  expect_match(names(result$new_scenarios), "Seasonal forecast")
  expect_setequal(names(scenario$pipelines), c("member_0", "member_1"))
  expect_identical(scenario$forecast$start, "2030-11")
  expect_identical(scenario$forecast$len, 3L)
  expect_identical(scenario$forecast$sim_year, 2030L)
  expect_identical(scenario$pipelines$member_0$sim_year, c(2030L, 2030L))
  expect_identical(scenario$pipelines$member_1$sim_year, c(2030L, 2030L))
  expect_identical(scenario$pipelines$member_0$svy_row_id, c(1L, 2L))
  expect_identical(scenario$pipelines$member_1$svy_row_id, c(1L, 2L))
  expect_identical(result$n_forecast_members, 2L)
})


test_that("per-pipeline vector and row alignment contract is stable", {
  result <- suppressWarnings(step2_contract_run())
  pipe <- result$hist_sim_result$pipeline

  expect_length(pipe$y_point, 2L)
  expect_length(pipe$sim_year, 2L)
  expect_length(pipe$weight, 2L)
  expect_length(pipe$id_vec, 2L)
  expect_length(pipe$svy_row_id, 2L)
  expect_identical(length(pipe$y_point), length(pipe$sim_year))
  expect_identical(length(pipe$y_point), length(pipe$weight))
  expect_identical(length(pipe$y_point), length(pipe$id_vec))
  expect_identical(length(pipe$y_point), length(pipe$svy_row_id))
  expect_null(pipe$id_col)
  expect_identical(pipe$n_pre_join, 2L)
  expect_null(pipe$F_loading)
})

test_that("run_sim_pipeline contract preserves joins and disabled uncertainty", {

  train <- data.frame(
    welfare = c(1, 2, 3, 4), temp = c(0, 1, 2, 3),
    stringsAsFactors = FALSE
  )
  model <- stats::lm(welfare ~ temp, data = train)
  svy <- data.frame(
    hhid = c("hh01", "hh02"), code = "TST", year = 2020L,
    survname = "SRV", loc_id = c("loc01", "loc01"), int_month = c(1L, 2L),
    welfare = c(1, 2), temp = c(0, 0), weight = c(1, 2),
    stringsAsFactors = FALSE
  )
  weather <- data.frame(
    code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01",
    timestamp = as.POSIXct(c("2030-01-01", "2030-02-01"), tz = "UTC"),
    temp = c(0.5, 1.5), stringsAsFactors = FALSE
  )
  out <- run_sim_pipeline(
    weather_raw = weather,
    svy = svy,
    sw = data.frame(name = "temp", stringsAsFactors = FALSE),
    so = list(name = "welfare", type = "numeric", transform = "none"),
    model = model,
    residuals = "none",
    train_data = train,
    engine = "lm",
    chol_obj = NULL
  )

  expect_named(
    out,
    c(
      "y_point", "F_loading", "sim_year", "weight", "id_vec", "id_col",
      "svy_row_id", "weather_exposure", "n_pre_join", "weather_raw",
      "train_aug"
    )
  )
  expect_length(out$y_point, 2L)
  expect_identical(out$sim_year, c(2030L, 2030L))
  expect_identical(out$n_pre_join, 2L)
  expect_null(out$F_loading)
  expect_identical(out$weather_raw, weather)
  expect_length(out$svy_row_id, 2L)
  expect_true(all(is.finite(out$y_point)))
})

test_that("enabled coefficient uncertainty preserves F_loading dimensions and order", {

  train <- data.frame(
    welfare = c(1, 2, 3, 4), temp = c(0, 1, 2, 3),
    stringsAsFactors = FALSE
  )
  model <- fixest::feols(welfare ~ temp, data = train)
  svy <- data.frame(
    hhid = c("hh01", "hh02"), code = "TST", year = 2020L,
    survname = "SRV", loc_id = "loc01", int_month = c(1L, 2L),
    welfare = c(1, 2), temp = c(0, 0), weight = c(1, 2),
    stringsAsFactors = FALSE
  )
  weather <- data.frame(
    code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01",
    timestamp = as.POSIXct(c("2030-01-01", "2030-02-01"), tz = "UTC"),
    temp = c(0.5, 1.5), stringsAsFactors = FALSE
  )
  beta <- stats::coef(model)
  chol_obj <- list(
    L = diag(length(beta)),
    beta = beta
  )
  out <- run_sim_pipeline(
    weather_raw = weather,
    svy = svy,
    sw = data.frame(name = "temp", stringsAsFactors = FALSE),
    so = list(name = "welfare", type = "numeric", transform = "none"),
    model = model,
    residuals = "none",
    train_data = train,
    engine = "fixest",
    chol_obj = chol_obj
  )

  expect_true(is.matrix(out$F_loading))
  expect_identical(dim(out$F_loading), c(2L, length(beta)))
  expect_true(all(is.finite(out$F_loading)))

  expected <- cbind(`(Intercept)` = 1, temp = weather$temp) %*% chol_obj$L
  expect_equal(out$F_loading, expected, tolerance = 0)
})

test_that("aggregation residual modes remain accepted by the reference contract", {
  pipe <- list(
    y_point = log(c(2, 3, 4)),
    F_loading = NULL,
    sim_year = c(2030L, 2030L, 2031L),
    weight = c(1, 2, 1),
    id_vec = c("hh01", "hh02", "hh03"),
    id_col = "hhid",
    train_aug = data.frame(
      hhid = c("hh01", "hh02", "hh03"), .resid = c(-0.2, 0.1, 0.3)
    )
  )

  for (mode in c("none", "original", "resample")) {
    out <- aggregate_pipeline_per_year(
      pipe, method = "mean", weighted = TRUE, residuals = mode, seed = 123L
    )
    expect_length(out, 2L)
    expect_true(
      all(vapply(out, function(x) is.finite(x$value), logical(1))),
      info = paste("value", mode)
    )
    expect_true(
      all(vapply(out, function(x) {
        is.finite(x$value_lo) && is.finite(x$value_p50) && is.finite(x$value_hi)
      }, logical(1))),
      info = paste("bands", mode)
    )
  }
})
