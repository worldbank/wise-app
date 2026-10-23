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
