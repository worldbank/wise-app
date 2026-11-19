# PERF-W2: .sim_timestamp_parts() reuses the last conversion for an identical
# timestamp vector. The reuse must never return parts for a different vector.

reference_parts <- function(timestamp) {
  lt <- as.POSIXlt(timestamp)
  list(int_month = as.integer(lt$mon + 1L), sim_year = as.integer(lt$year + 1900L))
}

test_that(".sim_timestamp_parts matches a direct conversion", {
  ts <- seq(as.Date("1991-01-01"), as.Date("2000-12-01"), by = "month")
  expect_identical(.sim_timestamp_parts(ts), reference_parts(ts))
  # Repeat call (served from the memo) is still identical
  expect_identical(.sim_timestamp_parts(ts), reference_parts(ts))
})

test_that(".sim_timestamp_parts does not return stale parts for another vector", {
  a <- seq(as.Date("1991-01-01"), by = "month", length.out = 24)
  b <- seq(as.Date("2041-03-01"), by = "month", length.out = 24)
  expect_identical(.sim_timestamp_parts(a), reference_parts(a))
  expect_identical(.sim_timestamp_parts(b), reference_parts(b))
  expect_identical(.sim_timestamp_parts(a), reference_parts(a))
  # Same length, one value different
  c2 <- a
  c2[24] <- as.Date("2030-07-01")
  expect_identical(.sim_timestamp_parts(c2), reference_parts(c2))
  expect_false(identical(.sim_timestamp_parts(c2), .sim_timestamp_parts(a)))
})

test_that(".sim_timestamp_parts keys on class and time zone, not just values", {
  d <- as.Date(c("2020-01-31", "2020-02-29"))
  p1 <- as.POSIXct(c("2020-01-31 23:30:00", "2020-02-29 23:30:00"), tz = "UTC")
  p2 <- as.POSIXct(c("2020-01-31 23:30:00", "2020-02-29 23:30:00"), tz = "Asia/Tokyo")
  for (x in list(d, p1, p2, p1)) {
    expect_identical(.sim_timestamp_parts(x), reference_parts(x))
  }
})

test_that(".add_sim_timestamp_fields output is unchanged by the memo", {
  df <- data.frame(
    year = c("2020", "2020", "2021"),
    timestamp = as.Date(c("2030-01-01", "2030-02-01", "2031-03-01"))
  )
  first <- .add_sim_timestamp_fields(df)
  second <- .add_sim_timestamp_fields(df)
  expect_identical(first, second)
  expect_identical(first$int_month, c(1L, 2L, 3L))
  expect_identical(first$sim_year, c(2030L, 2030L, 2031L))
})


# UNC-01: anchored level loading ----

test_that("original residuals anchor the loading on the household's own design", {
  train <- data.frame(
    hhid = c("hh01", "hh02", "hh03", "hh04"),
    welfare = c(1, 2, 3, 5), temp = c(0, 1, 2, 3),
    stringsAsFactors = FALSE
  )
  model <- fixest::feols(welfare ~ temp, data = train)
  svy <- data.frame(
    hhid = c("hh01", "hh02"), code = "TST", year = 2020L,
    survname = "SRV", loc_id = "loc01", int_month = c(1L, 2L),
    welfare = c(1, 2), temp = c(0, 1), weight = c(1, 2),
    stringsAsFactors = FALSE
  )
  weather_at <- function(temp) {
    data.frame(
      code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01",
      timestamp = as.POSIXct(c("2030-01-01", "2030-02-01"), tz = "UTC"),
      temp = temp, stringsAsFactors = FALSE
    )
  }
  beta <- stats::coef(model)
  chol_obj <- list(L = diag(length(beta)), beta = beta)
  run <- function(temp, residuals) {
    run_sim_pipeline(
      weather_raw = weather_at(temp), svy = svy,
      sw = data.frame(name = "temp", stringsAsFactors = FALSE),
      so = list(name = "welfare", type = "numeric", transform = "none"),
      model = model, residuals = residuals, train_data = train,
      engine = "fixest", chol_obj = chol_obj
    )
  }

  # Weather equal to the survey weather: the observed outcome pins the level
  same <- run(c(0, 1), "original")
  expect_equal(unname(same$F_loading), matrix(0, 2, 2))

  # Weather moved by 0.5: the loading is the change, the intercept drops out
  moved <- run(c(0.5, 1.5), "original")
  expect_equal(unname(moved$F_loading), cbind(0, c(0.5, 0.5)))

  # Other residual rules keep the absolute design
  abs_rule <- run(c(0.5, 1.5), "none")
  expect_equal(unname(abs_rule$F_loading), cbind(1, c(0.5, 1.5)))
})


# F0: residual and anchor matching on a key that includes round and economy ----

resid_key_frames <- function() {
  # The same hhid in two rounds of AAA and in a second economy.
  train <- data.frame(
    code = c("AAA", "AAA", "AAA", "BBB"), survname = "S",
    year = c(2018L, 2021L, 2021L, 2021L), hhid = c("h1", "h1", "h2", "h1"),
    welfare = c(1, 2, 3, 5), temp = c(0, 1, 2, 3), .resid = c(0.1, 0.2, 0.3, 0.4),
    stringsAsFactors = FALSE
  )
  svy <- data.frame(
    code = c("AAA", "AAA", "BBB"), survname = "S", year = 2021L,
    hhid = c("h1", "h2", "h1"), stringsAsFactors = FALSE
  )
  list(train = train, svy = svy)
}

test_that("the residual key tells apart repeated household ids", {
  f <- resid_key_frames()
  keyed <- step2_add_residual_key(f$train, f$svy)
  expect_identical(resolve_id_col(keyed$train_data, keyed$svy), RESID_KEY_COL)
  expect_identical(keyed$match$key, c("code", "survname", "year", "hhid"))
  expect_identical(c(keyed$match$n_matched, keyed$match$n_unmatched), c(3L, 0L))
  # Each baseline household gets its own residual, not the first row with its id.
  r <- draw_residuals_vec(
    "original", keyed$train_data, 3L, keyed$svy[[RESID_KEY_COL]], RESID_KEY_COL
  )
  expect_equal(r, c(0.2, 0.3, 0.4))
  # Without the key the first row with the id answers for all three.
  by_id <- draw_residuals_vec("original", f$train, 3L, f$svy$hhid, "hhid")
  expect_equal(by_id, c(0.1, 0.3, 0.1))
})

test_that("a baseline household without an estimation row is counted", {
  f <- resid_key_frames()
  f$svy$year[3] <- 2019L
  keyed <- step2_add_residual_key(f$train, f$svy)
  expect_identical(c(keyed$match$n_matched, keyed$match$n_unmatched, keyed$match$n_total), c(2L, 1L, 3L))
  expect_match(step2_residual_match_note(keyed$match), "^1 of 3 baseline households have no estimation row")
  expect_null(step2_residual_match_note(step2_add_residual_key(f$train, f$svy[1:2, ])$match))
})

test_that("a key that repeats in the estimation sample falls back to the id with a warning", {
  f <- resid_key_frames()
  f$train$year[1] <- 2021L
  expect_warning(keyed <- step2_add_residual_key(f$train, f$svy), "residuals are matched on 'hhid' alone")
  expect_false(RESID_KEY_COL %in% names(keyed$train_data))
  expect_identical(resolve_id_col(keyed$train_data, keyed$svy), "hhid")
  expect_identical(keyed$match$key, "hhid")
})

test_that("the anchor design row is the household's own, not another round's", {
  f <- resid_key_frames()
  keyed <- step2_add_residual_key(f$train, f$svy)
  model <- fixest::feols(welfare ~ temp, data = keyed$train_data)
  beta <- stats::coef(model)
  chol_obj <- list(L = diag(length(beta)), beta = beta)
  X <- cbind(`(Intercept)` = 1, temp = c(1, 2, 3))
  shifted <- .anchor_design_shift(
    X, chol_obj, model, keyed$train_data, keyed$svy[[RESID_KEY_COL]], RESID_KEY_COL
  )
  # Anchors: temp 1 (AAA 2021 h1), 2 (AAA 2021 h2), 3 (BBB 2021 h1).
  expect_equal(unname(shifted), cbind(0, c(0, 0, 0)))
  by_id <- .anchor_design_shift(X, chol_obj, model, keyed$train_data, f$svy$hhid, "hhid")
  expect_false(isTRUE(all.equal(unname(by_id[, 2]), c(0, 0, 0))))
})


# F8: logistic loading on the probability scale ----

test_that("a logistic fit's coefficient SD of a rate matches a link-scale Monte Carlo", {
  set.seed(11)
  n <- 400
  train <- data.frame(hhid = seq_len(n), temp = rnorm(n))
  train$ag <- rbinom(n, 1, plogis(-0.2 + 0.9 * train$temp))
  model <- fixest::feglm(ag ~ temp, data = train, family = "logit")
  beta <- stats::coef(model)
  L <- t(chol(stats::vcov(model)))
  chol_obj <- list(L = L, beta = beta)
  m <- 40
  svy <- data.frame(
    hhid = seq_len(m), code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01",
    int_month = 1L, ag = 0L, temp = 0, weight = 1, stringsAsFactors = FALSE
  )
  weather <- data.frame(
    code = "TST", year = 2020L, survname = "SRV", loc_id = "loc01",
    timestamp = as.POSIXct("2030-01-01", tz = "UTC"), temp = 1.2, stringsAsFactors = FALSE
  )
  pipe <- run_sim_pipeline(
    weather_raw = weather, svy = svy, sw = data.frame(name = "temp", stringsAsFactors = FALSE),
    so = list(name = "ag", type = "logical", transform = "none"), model = model,
    residuals = "none", train_data = train, engine = "fixest", chol_obj = chol_obj
  )
  expect_true(pipe$logit_link)
  p <- pipe$y_point
  expect_gt(min(p), 0)
  res <- aggregate_pipeline_per_year(pipe, "mean", residuals = "none", is_log = FALSE)[[1]]
  # Monte Carlo on the link scale: F rows were scaled by p (1 - p), undo that.
  F_link <- pipe$F_loading / (p * (1 - p))
  Z <- matrix(stats::rnorm(ncol(F_link) * 4000), ncol(F_link))
  draws <- colMeans(plogis(stats::qlogis(p) + F_link %*% Z))
  expect_equal(sqrt(res$var_coef), stats::sd(draws), tolerance = 0.1)
  # Without the factor the SD would be several times too large (rate near 0.5)
  unscaled <- sqrt(sum(crossprod(F_link, rep(1 / m, m))^2))
  expect_gt(unscaled, 2 * sqrt(res$var_coef))
  # The band of a rate stays inside [0, 1]
  band <- function(rate_band) {
    aggregate_with_uncertainty_delta(
      y_point = 0.02, F_loading = matrix(0.02, 1, 1), method = "mean", weights = 1,
      residuals = "none", is_log = FALSE, rate_band = rate_band
    )
  }
  expect_lt(band(FALSE)$value_lo, 0)
  expect_true(band(TRUE)$value_lo > 0 && band(TRUE)$value_hi < 1)
})
