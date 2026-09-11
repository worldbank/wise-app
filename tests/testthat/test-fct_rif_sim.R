# Tests for predict_rif() and interpolate_delta()

test_that("interpolate_delta works correctly", {
  taus <- seq(0.1, 0.9, by = 0.1)
  K <- length(taus)
  n <- 5
  delta_mat <- matrix(2.0, nrow = n, ncol = K)
  tau_i <- c(0.1, 0.25, 0.5, 0.75, 0.9)
  result <- interpolate_delta(delta_mat, taus, tau_i)
  expect_equal(result, rep(2.0, n))
  delta_mat2 <- matrix(rep(taus, each = n), nrow = n, ncol = K)
  tau_i2 <- c(0.1, 0.15, 0.5, 0.85, 0.9)
  result2 <- interpolate_delta(delta_mat2, taus, tau_i2)
  expect_equal(result2, tau_i2, tolerance = 1e-10)
})

legacy_compute_rif_multi <- function(y, taus, bw = NULL, dens = NULL) {
  lapply(taus, function(tau) compute_rif(y, tau = tau, bw = bw, dens = dens))
}

test_that("multi-tau RIF preparation exactly preserves single-tau results", {
  set.seed(20260911)
  cases <- list(
    tied = c(rep(1, 20), rep(2, 10), rep(5, 5)),
    constant = rep(3, 20),
    skewed = stats::rlnorm(500, meanlog = 2, sdlog = 1.2),
    very_small = c(1, 2),
    nonfinite = c(stats::rnorm(100), NA_real_, NaN, Inf, -Inf)
  )
  taus <- c(0.9, 0.1, 0.5, 0.25)

  for (y in cases) {
    y_obs <- y[is.finite(y)]
    bw <- tryCatch(stats::bw.SJ(y_obs),
                   error = function(e) stats::bw.nrd0(y_obs))
    dens <- stats::density(y_obs, bw = bw, n = 1024)
    expect_identical(
      compute_rif_multi(y, taus, dens = dens),
      legacy_compute_rif_multi(y, taus, dens = dens)
    )
  }
})

test_that("multi-tau preparation preserves density floors and warnings", {
  y <- c(1, 2, NA_real_, Inf)
  taus <- c(0.25, 0.75)
  zero_density <- list(x = c(1, 2), y = c(0, 0))
  capture_warnings <- function(expr) {
    warnings <- character(0)
    value <- withCallingHandlers(
      expr,
      warning = function(w) {
        warnings <<- c(warnings, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    list(value = value, warnings = warnings)
  }
  actual <- capture_warnings(compute_rif_multi(y, taus, dens = zero_density))
  expected <- capture_warnings(legacy_compute_rif_multi(y, taus, dens = zero_density))
  expect_identical(actual, expected)
})

test_that("RIF engine preparation preserves tau order, schema, and factors", {
  set.seed(42)
  df <- data.frame(
    y = c(stats::rnorm(100), NA_real_, NaN, Inf, -Inf),
    group = factor(rep(c("b", "a"), 52), levels = c("b", "a", "unused"))
  )
  taus <- seq(0.1, 0.9, by = 0.1)
  rif_cols <- paste0("rif_", formatC(taus * 100, format = "d"))
  y_obs <- df$y[is.finite(df$y)]
  bw <- tryCatch(stats::bw.SJ(y_obs),
                 error = function(e) stats::bw.nrd0(y_obs))
  dens <- stats::density(y_obs, bw = bw, n = 1024)
  expected <- legacy_compute_rif_multi(df$y, taus, dens = dens)
  actual <- ENGINE_REGISTRY$rif$prepare_outcome(df, "y", FALSE)

  expect_identical(attr(actual, "rif_taus"), taus)
  expect_identical(attr(actual, "rif_cols"), rif_cols)
  expect_identical(names(actual), c("y", "group", rif_cols))
  expect_identical(actual$group, df$group)
  for (i in seq_along(rif_cols)) {
    expect_identical(actual[[rif_cols[i]]], expected[[i]])
  }
})

test_that("predict_rif returns correct structure", {
  skip_if_not_installed("fixest")
  set.seed(42)
  n <- 200
  df <- data.frame(y = rnorm(n, 10, 2), temp = rnorm(n), rain = rnorm(n), loc = factor(sample(letters[1:4], n, replace = TRUE)), year = factor(sample(2010:2015, n, replace = TRUE)))
  taus <- seq(0.1, 0.9, by = 0.1)
  rif_cols <- paste0("rif_", formatC(taus * 100, format = "d"))
  for (i in seq_along(taus)) df[[rif_cols[i]]] <- compute_rif(df$y, taus[i])
  lhs <- paste0("c(", paste(rif_cols, collapse = ", "), ")")
  fml <- stats::as.formula(paste(lhs, "~ temp + rain | loc + year"))
  fit_multi <- fixest::feols(fml, data = df, warn = FALSE)
  svy <- df[1:50, ]
  svy$.svy_row_id <- seq_len(nrow(svy))
  newdata <- svy
  newdata$temp <- svy$temp + 1
  result <- predict_rif(fit_multi = fit_multi, newdata = newdata, svy = svy, train_data = df, taus = taus, outcome = "y", weather_cols = c("temp", "rain"))
  expect_true(is.data.frame(result))
  expect_true(".fitted" %in% names(result))
  expect_true(".residual" %in% names(result))
  expect_true("y" %in% names(result))
  expect_equal(nrow(result), 50)
  expect_true(all(is.na(result$.residual)))
  deltas <- result$.fitted - svy$y[1:50]
  expect_true(any(abs(deltas) > 0.01))
})

test_that("direct RIF prediction matches fixest prediction with fixed effects", {
  skip_if_not_installed("fixest")
  set.seed(142)
  n <- 160
  df <- data.frame(
    y = rnorm(n), temp = rnorm(n), rain = rnorm(n),
    loc = factor(sample(letters[1:4], n, replace = TRUE)),
    year = factor(sample(2010:2015, n, replace = TRUE))
  )
  taus <- seq(0.1, 0.9, by = 0.2)
  rif_cols <- paste0("rif_", formatC(taus * 100, format = "d"))
  for (i in seq_along(taus)) df[[rif_cols[i]]] <- compute_rif(df$y, taus[i])
  fit_multi <- fixest::feols(
    stats::as.formula(paste0("c(", paste(rif_cols, collapse = ","), ") ~ temp + rain | loc + year")),
    data = df, warn = FALSE
  )
  base <- df[1:60, ]
  scen <- base
  scen$temp <- scen$temp + 0.75
  direct <- .direct_rif_prediction_pair(fit_multi, base, scen)
  metadata <- build_direct_rif_metadata(fit_multi)
  direct_cached <- .direct_rif_prediction_pair(fit_multi, base, scen, metadata)
  expect_length(direct, length(taus))
  expect_length(metadata, length(taus))
  for (i in seq_along(taus)) {
    expect_equal(direct[[i]]$base,
                 as.numeric(predict(fit_multi[[i]], newdata = base)),
                 tolerance = 1e-12)
    expect_equal(direct[[i]]$scenario,
                 as.numeric(predict(fit_multi[[i]], newdata = scen)),
                 tolerance = 1e-12)
    expect_equal(direct_cached[[i]]$base, direct[[i]]$base, tolerance = 1e-12)
    expect_equal(direct_cached[[i]]$scenario, direct[[i]]$scenario, tolerance = 1e-12)
  }
})

test_that("predict_rif direct mode matches fallback within numeric tolerance", {
  skip_if_not_installed("fixest")
  set.seed(143)
  n <- 140
  df <- data.frame(
    y = rnorm(n), temp = rnorm(n), rain = rnorm(n),
    loc = factor(sample(letters[1:3], n, replace = TRUE)),
    year = factor(sample(2010:2014, n, replace = TRUE))
  )
  taus <- seq(0.1, 0.9, by = 0.2)
  rif_cols <- paste0("rif_", formatC(taus * 100, format = "d"))
  for (i in seq_along(taus)) df[[rif_cols[i]]] <- compute_rif(df$y, taus[i])
  fit_multi <- fixest::feols(
    stats::as.formula(paste0("c(", paste(rif_cols, collapse = ","), ") ~ temp + rain | loc + year")),
    data = df, warn = FALSE
  )
  svy <- df[1:50, ]
  svy$.svy_row_id <- seq_len(nrow(svy))
  scen <- svy
  scen$temp <- scen$temp + 0.4
  fallback <- predict_rif(
    fit_multi, scen, svy, df, taus, "y", c("temp", "rain"),
    batch_predictions = FALSE, direct_predictions = FALSE
  )
  direct <- predict_rif(
    fit_multi, scen, svy, df, taus, "y", c("temp", "rain"),
    batch_predictions = FALSE, direct_predictions = TRUE
  )
  expect_identical(names(direct), names(fallback))
  expect_equal(direct$.fitted, fallback$.fitted, tolerance = 1e-10)
  expect_equal(direct$y, fallback$y, tolerance = 1e-10)
})

test_that("direct RIF metadata rejects unsupported model structures", {
  skip_if_not_installed("fixest")
  set.seed(144)
  d <- data.frame(y = rnorm(80), x = rnorm(80), fe = factor(sample(letters[1:3], 80, TRUE)))
  fit <- fixest::feols(y ~ x | fe, data = d, warn = FALSE)
  fit_iv <- fit
  fit_iv$iv <- TRUE
  expect_length(build_direct_rif_metadata(list(fit)), 1L)
  expect_null(build_direct_rif_metadata(list(fit_iv)))
})

test_that("predict_rif F_loading contrast is ~0 when scenario == baseline weather", {
  # Regression test for the X_diff -> X_scenario switch in predict_rif().
  # The level-mode F_loading is now built from X_scenario directly, so the
  # deviation/contrast (F_agg_scenario - F_agg_historical) must reduce to
  # zero when scenario weather equals historical weather. If it doesn't, the
  # change has silently broken the deviation-mode uncertainty bands.
  skip_if_not_installed("fixest")
  set.seed(7)
  n <- 120
  df <- data.frame(
    y    = rnorm(n, 10, 2),
    temp = rnorm(n),
    rain = rnorm(n),
    loc  = factor(sample(letters[1:3], n, replace = TRUE)),
    year = factor(sample(2010:2012, n, replace = TRUE))
  )
  taus <- seq(0.1, 0.9, by = 0.2)
  rif_cols <- paste0("rif_", formatC(taus * 100, format = "d"))
  for (i in seq_along(taus)) df[[rif_cols[i]]] <- compute_rif(df$y, taus[i])
  lhs <- paste0("c(", paste(rif_cols, collapse = ", "), ")")
  fml <- stats::as.formula(paste(lhs, "~ temp + rain | loc + year"))
  fit_multi <- fixest::feols(fml, data = df, warn = FALSE)

  chol_list <- lapply(seq_along(taus), function(k) {
    co <- compute_chol_vcov(fit_multi[[k]])
    co$L
  })

  svy <- df[1:40, ]
  svy$.svy_row_id <- seq_len(nrow(svy))

  # Run twice with the same scenario==baseline weather. F_loading should be
  # identical across runs (same X, same L), so any "scenario - historical"
  # contrast collapses to exactly zero.
  res_hist <- predict_rif(
    fit_multi = fit_multi, newdata = svy, svy = svy,
    train_data = df, taus = taus, outcome = "y",
    weather_cols = c("temp", "rain"), chol_list = chol_list
  )
  res_scen <- predict_rif(
    fit_multi = fit_multi, newdata = svy, svy = svy,
    train_data = df, taus = taus, outcome = "y",
    weather_cols = c("temp", "rain"), chol_list = chol_list
  )

  F_hist <- attr(res_hist, "F_loading")
  F_scen <- attr(res_scen, "F_loading")
  expect_false(is.null(F_hist))
  expect_false(is.null(F_scen))
  expect_equal(dim(F_hist), dim(F_scen))
  expect_lt(max(abs(F_scen - F_hist)), 1e-10)
})

test_that("predict_rif delta is ~0 when scenario == baseline weather", {
  skip_if_not_installed("fixest")
  set.seed(123)
  n <- 100
  df <- data.frame(y = rnorm(n, 10, 2), temp = rnorm(n), rain = rnorm(n), loc = factor(sample(letters[1:3], n, replace = TRUE)), year = factor(sample(2010:2012, n, replace = TRUE)))
  taus <- seq(0.1, 0.9, by = 0.1)
  rif_cols <- paste0("rif_", formatC(taus * 100, format = "d"))
  for (i in seq_along(taus)) df[[rif_cols[i]]] <- compute_rif(df$y, taus[i])
  lhs <- paste0("c(", paste(rif_cols, collapse = ", "), ")")
  fml <- stats::as.formula(paste(lhs, "~ temp + rain | loc + year"))
  fit_multi <- fixest::feols(fml, data = df, warn = FALSE)
  svy <- df[1:30, ]
  svy$.svy_row_id <- seq_len(nrow(svy))
  newdata <- svy
  result <- predict_rif(fit_multi = fit_multi, newdata = newdata, svy = svy, train_data = df, taus = taus, outcome = "y", weather_cols = c("temp", "rain"))
  deltas <- result$.fitted - svy$y[1:30]
  expect_true(all(abs(deltas) < 1e-8))
})
