# Phase 4 compact shared-context payload characterization.

library(testthat)

phase4_weather <- function() {
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

phase4_pipeline <- function(weather_raw, ...) {
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
    train_aug = phase4_train_aug()
  )
}

phase4_train_aug <- function() {
  data.frame(
    hhid = paste0("hh", seq_len(50L)),
    .resid = seq_len(50L) - 1.5,
    stringsAsFactors = FALSE
  )
}

phase4_input <- function() {
  train <- data.frame(
    hhid = paste0("hh", seq_len(50L)),
    welfare = seq_len(50L), temp = rep(c(1, 2), length.out = 50L),
    stringsAsFactors = FALSE
  )
  list(
    sw = data.frame(name = "temp", stringsAsFactors = FALSE),
    so = data.frame(name = "welfare", type = "numeric", transform = "log",
                    stringsAsFactors = FALSE),
    svy = transform(
      train, code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01"
    ),
    ss = NULL,
    mf = list(
      fit3 = stats::lm(welfare ~ temp, data = train), engine = "lm",
      train_data = train, weather_terms = "temp"
    ),
    cp = list(type = "local", path = tempdir()),
    fp_list = list(c("2030-01-01", "2040-12-31")),
    ssps = "ssp2_4_5",
    residuals = "original",
    skip_coef_draws = TRUE,
    sim_dates = c("2020-01-01", "2020-12-31"),
    perturbation_method = NULL,
    stored_breaks = NULL
  )
}

phase4_run <- function(payload_mode) {
  input <- phase4_input()
  do.call(fct_run_simulation, c(input, list(
      payload_mode = payload_mode,
      notify_fn = function(...) invisible(NULL),
      progress_fn = function(...) invisible(NULL),
      weather_fn = function(...) phase4_weather(),
      pipeline_fn = phase4_pipeline
    )))
}

test_that("compact mode preserves science and member-specific weather", {
  legacy <- suppressWarnings(phase4_run("legacy"))
  compact <- suppressWarnings(phase4_run("compact"))

  expect_identical(compact$payload_mode, "compact")
  expect_null(legacy$payload_mode)
  expect_identical(
    compact$hist_sim_result$pipeline$y_point,
    legacy$hist_sim_result$pipeline$y_point
  )
  expect_identical(compact$n_keys, legacy$n_keys)
  expect_identical(compact$n_keys_ok, legacy$n_keys_ok)
  expect_identical(compact$failures, legacy$failures)
  expect_identical(
    compact$new_scenarios[[1L]]$pipelines$ensemble_mean$weather_raw$temp,
    2
  )
  expect_identical(
    compact$new_scenarios[[1L]]$pipelines$ensemble_hi$weather_raw$temp,
    3
  )
})

test_that("compact pipelines resolve shared residual metadata", {
  compact <- suppressWarnings(phase4_run("compact"))
  hist <- compact$hist_sim_result
  pipe <- hist$pipeline

  expect_null(pipe$train_aug)
  expect_null(pipe$id_col)
  expect_identical(hist$shared_context$schema, 1L)
  expect_true(is.data.frame(hist$shared_context$train_aug))
  expect_identical(hist$shared_context$id_col, "hhid")

  legacy <- suppressWarnings(phase4_run("legacy"))
  legacy$hist_sim_result$pipeline$train_aug <-
    compact$hist_sim_result$shared_context$train_aug
  legacy_agg <- aggregate_pipeline_per_year(
    legacy$hist_sim_result$pipeline,
    method = "mean", residuals = "original", is_log = FALSE, seed = 123L
  )
  compact_agg <- aggregate_pipeline_per_year(
    pipe,
    method = "mean", residuals = "original", is_log = FALSE, seed = 123L,
    shared_context = hist$shared_context
  )
  expect_identical(legacy_agg, compact_agg)
})

test_that("compact residual context retains only mode-required columns", {
  train_aug <- data.frame(
    hhid = c("b", "a", "a", "missing"),
    covariate = factor(c("x", "y", "y", "z")), .fitted = 1:4,
    .resid = c(-0.2, 0.1, 0.1, NA_real_), stringsAsFactors = FALSE
  )
  original <- .compact_residual_context(train_aug, "hhid", "original")
  expect_identical(names(original), c("hhid", ".resid"))
  expect_identical(original$hhid, train_aug$hhid)
  expect_identical(original$.resid, train_aug$.resid)
  for (mode in c("normal", "resample")) {
    compact <- .compact_residual_context(train_aug, "hhid", mode)
    expect_identical(names(compact), ".resid", info = mode)
    expect_identical(compact$.resid, train_aug$.resid, info = mode)
  }
  expect_null(.compact_residual_context(train_aug, "hhid", "none"))
  expect_null(.compact_residual_context(NULL, "hhid", "original"))
  expect_identical(.compact_residual_context(
    train_aug, "hhid", "original", compact = FALSE), train_aug)
})

test_that("compact residual context preserves ID alignment and deterministic RNG", {
  train_aug <- data.frame(
    hhid = c("b", "a", "a", "c"), extra = I(list(1, 2, 3, 4)),
    .resid = c(-2, 1, 9, 3), stringsAsFactors = FALSE
  )
  compact <- .compact_residual_context(train_aug, "hhid", "original")
  ids <- c("a", "missing", "a", "c")
  for (mode in c("original", "normal", "resample")) {
    set.seed(915L)
    before <- .Random.seed
    full <- draw_residuals_vec(mode, train_aug, length(ids), ids, "hhid", seed = 51L)
    expect_identical(.Random.seed, before)
    slim <- if (identical(mode, "original")) compact else
      .compact_residual_context(train_aug, "hhid", mode)
    reduced <- draw_residuals_vec(mode, slim, length(ids), ids, "hhid", seed = 51L)
    expect_identical(reduced, full, info = mode)
  }
})

test_that("compact payload is smaller while retaining required uncertainty slots", {
  legacy <- suppressWarnings(phase4_run("legacy"))
  compact <- suppressWarnings(phase4_run("compact"))
  legacy_pipelines <- c(
    list(legacy$hist_sim_result$pipeline),
    unlist(lapply(legacy$new_scenarios, `[[`, "pipelines"), recursive = FALSE)
  )
  compact_pipelines <- c(
    list(compact$hist_sim_result$pipeline),
    unlist(lapply(compact$new_scenarios, `[[`, "pipelines"), recursive = FALSE)
  )
  expect_true(
    sum(vapply(legacy_pipelines, object.size, numeric(1))) >
      sum(vapply(compact_pipelines, object.size, numeric(1)))
  )
  expect_true("F_loading" %in% names(compact$hist_sim_result$pipeline))
  expect_true("weather_raw" %in% names(compact$hist_sim_result$pipeline))
  expect_true("svy_row_id" %in% names(compact$hist_sim_result$pipeline))
  expect_null(compact$hist_sim_result$train_data)
  expect_null(compact$hist_sim_result$cluster_counts)
})

test_that("compact payload retains non-null coefficient uncertainty", {
  legacy <- suppressWarnings(phase4_run("legacy"))
  beta <- c(`(Intercept)` = 1, temp = 0.5)
  legacy$hist_sim_result$chol_obj <- list(L = diag(2), beta = beta)
  legacy$hist_sim_result$pipeline$F_loading <- matrix(
    c(1, 0.5, 1, 1), nrow = 2, byrow = TRUE
  )
  compact <- compact_step2_result(
    legacy, phase4_train_aug(), "hhid", "original",
    legacy$hist_sim_result$chol_obj, legacy$hist_sim_result$so,
    phase4_input()$mf$train_data
  )
  expect_true(is.list(compact$hist_sim_result$chol_obj))
  expect_true(is.matrix(compact$hist_sim_result$pipeline$F_loading))
  expect_null(compact$hist_sim_result$train_data)
  expect_null(compact$hist_sim_result$cluster_counts)
})

test_that("weather references round-trip and reject stale signatures", {
  root <- withr::local_tempdir()
  weather <- phase4_weather()$ssp2_4_5_2030_2040_ensemble_mean
  store <- step2_weather_store_create("test-run", "sig-a", root = root)
  ref <- step2_weather_store_put(store, "member-a", weather)

  expect_identical(step2_weather_store_get(ref, "sig-a"), weather)
  expect_error(
    step2_weather_store_get(ref, "sig-b"),
    "stale"
  )
  expect_true(file.exists(ref$file))
  step2_weather_store_cleanup(store)
  expect_false(dir.exists(store$dir))
})

test_that("plain weather data frames pass through without schema warnings", {
  weather <- phase4_weather()$historical

  expect_warning(
    resolved <- step2_weather_reference(weather),
    NA
  )
  expect_identical(resolved, weather)
})

test_that("reference weather storage preserves member-specific payloads", {
  root <- withr::local_tempdir()
  input <- phase4_input()
  result <- suppressWarnings(do.call(fct_run_simulation, c(input, list(
    weather_storage = "reference",
    weather_store_root = root,
    notify_fn = function(...) invisible(NULL),
    progress_fn = function(...) invisible(NULL),
    weather_fn = function(...) phase4_weather(),
    pipeline_fn = phase4_pipeline
  ))))
  on.exit(step2_weather_store_cleanup(result$weather_store), add = TRUE)

  expect_identical(result$weather_storage, "reference")
  scenario <- result$new_scenarios[[1L]]
  expect_true(is.list(scenario$weather_raw) && is.character(scenario$weather_raw$file))
  mean_weather <- step2_resolve_weather(
    scenario$pipelines$ensemble_mean$weather_raw, scenario
  )
  hi_weather <- step2_resolve_weather(
    scenario$pipelines$ensemble_hi$weather_raw, scenario
  )
  expect_identical(mean_weather$temp, 2)
  expect_identical(hi_weather$temp, 3)
})

test_that("experimental join cache preserves simulation outputs", {
  input <- phase4_input()
  input$svy$int_month <- 6L
  input$svy$year <- 2020L
  run <- function(use_cache) suppressWarnings(do.call(
    fct_run_simulation,
    c(input, list(
      join_cache = use_cache,
      notify_fn = function(...) invisible(NULL),
      progress_fn = function(...) invisible(NULL),
      weather_fn = function(...) phase4_weather(),
      pipeline_fn = phase4_pipeline
    ))
  ))
  baseline <- run(FALSE)
  cached <- run(TRUE)
  expect_identical(cached$n_keys, baseline$n_keys)
  expect_identical(cached$failures, baseline$failures)
  expect_identical(
    cached$hist_sim_result$pipeline$y_point,
    baseline$hist_sim_result$pipeline$y_point
  )
  expect_identical(
    cached$new_scenarios[[1L]]$pipelines$ensemble_mean$y_point,
    baseline$new_scenarios[[1L]]$pipelines$ensemble_mean$y_point
  )
})
