library(testthat)

# PERF-W1: the lag-join roll must reproduce the legacy window query bit for bit.

roll_selected <- function(agg = "Mean", s = 1L, e = 3L, vars = c("t", "p")) {
  data.frame(
    name = vars, ref_start = s, ref_end = e, temporalAgg = agg,
    stringsAsFactors = FALSE
  )
}

# Two locations x 30 contiguous months, deterministic values with a few NULLs.
roll_loc_monthly <- function(null_base = FALSE, gaps = FALSE, dup = FALSE) {
  grid <- expand.grid(loc_id = c("a", "b"), i = 0:29, stringsAsFactors = FALSE)
  grid$code <- "XXX"
  grid$year <- 2019L
  grid$survname <- "S"
  grid$timestamp <- seq(as.Date("2018-01-01"), by = "month", length.out = 30)[grid$i + 1L]
  set.seed(7)
  grid$t <- round(20 + 5 * sin(grid$i) + rnorm(nrow(grid)), 3)
  grid$p <- round(abs(rnorm(nrow(grid), 100, 30)), 3)
  if (null_base) {
    grid$t[c(4, 11, 25)] <- NA
    grid$p[c(6, 30)] <- NA
  }
  if (gaps) grid <- grid[-c(9, 10, 33), ]
  if (dup) grid <- rbind(grid, grid[5, ])
  grid$i <- NULL
  grid
}

roll_deltas <- function() {
  d <- expand.grid(
    model = c("m1", "m2", "m3"), loc_id = c("a", "b"), month = 1:12,
    stringsAsFactors = FALSE
  )
  d$code <- "XXX"
  d$year <- 2019L
  d$survname <- "S"
  d$delta_t <- round(0.1 * d$month + 0.01 * match(d$model, c("m1", "m2", "m3")), 4)
  d$delta_p <- round(1 + 0.05 * d$month + 0.02 * match(d$loc_id, c("a", "b")), 4)
  d
}

# Legacy window query, as built by get_weather() (perturb, then roll).
roll_legacy_sql <- function(sw, pert, dates) {
  agg_fn <- c(Mean = "AVG", Sum = "SUM", Min = "MIN", Max = "MAX", Median = "MEDIAN")
  vars <- sw$name
  perturbed <- vapply(vars, function(v) {
    sprintf("l.%s %s d.delta_%s AS %s", v, if (pert[[v]] == "multiplicative") "*" else "+", v, v)
  }, "")
  rolled <- vapply(seq_along(vars), function(i) {
    sprintf(
      "%s(%s) FILTER (WHERE %s IS NOT NULL) OVER (PARTITION BY model, code, year, survname, loc_id ORDER BY (YEAR(timestamp) * 12 + MONTH(timestamp)) RANGE BETWEEN %d PRECEDING AND %d PRECEDING) AS %s",
      agg_fn[[sw$temporalAgg[i]]], vars[i], vars[i], sw$ref_end[i], sw$ref_start[i], vars[i]
    )
  }, "")
  sprintf(
    "SELECT model, code, year, survname, loc_id, timestamp, %s FROM (SELECT model, code, year, survname, loc_id, timestamp, %s FROM (SELECT d.model, l.code, l.year, l.survname, l.loc_id, l.timestamp, %s FROM (SELECT *, MONTH(timestamp) AS month FROM lm) l INNER JOIN dl_src d ON l.code = d.code AND l.year = d.year AND l.survname = d.survname AND l.loc_id = d.loc_id AND l.month = d.month)) WHERE timestamp IN (%s) ORDER BY model, code, year, survname, loc_id, timestamp",
    paste(vars, collapse = ", "), paste(rolled, collapse = ", "),
    paste(perturbed, collapse = ", "),
    paste0("'", format(dates), "'::date", collapse = ", ")
  )
}

# Runs the fast path; NULL when the guards refuse it.
roll_fast_run <- function(con, sw, pert, dates) {
  DBI::dbExecute(con, "CREATE OR REPLACE TEMP TABLE dl_src AS SELECT * FROM deltas")
  for (tn in c("t_pid", "t_bl", "t_src", "t_dl")) {
    DBI::dbExecute(con, paste("DROP TABLE IF EXISTS", tn))
  }
  if (!.wx_roll_fast_spec_ok(sw)) return(NULL)
  if (!.wx_roll_base_contiguous(con, "SELECT * FROM lm")) return(NULL)
  .wx_roll_build_base(con, "SELECT * FROM lm", sw, "t_pid", "t_bl")
  ok <- .wx_roll_build_delta(con, "SELECT * FROM deltas", sw, "t_pid", "t_src", "t_dl")
  if (!ok) return(NULL)
  sql <- .wx_roll_main_sql(con, sw, pert, dates, "t_bl", "t_dl")
  DBI::dbGetQuery(con, paste(
    "SELECT * FROM (", sql, ") ORDER BY model, code, year, survname, loc_id, timestamp"
  ))
}

roll_setup <- function(lm = roll_loc_monthly(), deltas = roll_deltas()) {
  con <- DBI::dbConnect(duckdb::duckdb())
  DBI::dbWriteTable(con, "lm", lm, overwrite = TRUE)
  DBI::dbWriteTable(con, "deltas", deltas, overwrite = TRUE)
  DBI::dbExecute(con, "SET threads = 1")
  con
}

roll_dates <- seq(as.Date("2019-01-01"), by = "month", length.out = 12)

expect_roll_equal <- function(con, sw, pert, dates = roll_dates) {
  fast <- roll_fast_run(con, sw, pert, dates)
  expect_false(is.null(fast))
  legacy <- DBI::dbGetQuery(con, roll_legacy_sql(sw, pert, dates))
  expect_gt(nrow(legacy), 0L)
  expect_identical(fast, legacy)
}

additive <- list(t = "additive", p = "additive")
mixed <- list(t = "multiplicative", p = "additive")

test_that("fast roll equals the window query for each aggregation (additive)", {
  con <- roll_setup()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  for (agg in c("Mean", "Sum", "Min", "Max")) {
    expect_roll_equal(con, roll_selected(agg), additive)
  }
})

test_that("fast roll equals the window query across lag ranges", {
  con <- roll_setup()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  for (rng in list(c(1L, 1L), c(1L, 3L), c(0L, 3L), c(1L, 12L), c(0L, 12L))) {
    for (agg in c("Mean", "Sum")) {
      expect_roll_equal(con, roll_selected(agg, rng[1], rng[2]), additive)
    }
  }
})

test_that("fast roll handles multiplicative perturbation and mixed aggregations", {
  con <- roll_setup()
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_roll_equal(con, roll_selected("Mean"), mixed)
  expect_roll_equal(con, roll_selected("Sum", 0L, 6L), list(t = "multiplicative", p = "multiplicative"))
  sw <- roll_selected("Mean", 1L, 4L)
  sw$temporalAgg <- c("Min", "Max")
  expect_roll_equal(con, sw, mixed)
  sw$ref_start <- c(0L, 2L)
  sw$ref_end <- c(2L, 5L)
  sw$temporalAgg <- c("Mean", "Sum")
  expect_roll_equal(con, sw, mixed)
})

test_that("fast roll matches the window query with NULL base values", {
  con <- roll_setup(roll_loc_monthly(null_base = TRUE))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  for (agg in c("Mean", "Sum", "Min", "Max")) {
    expect_roll_equal(con, roll_selected(agg, 1L, 3L), mixed)
    expect_roll_equal(con, roll_selected(agg, 0L, 12L), additive)
  }
})

test_that("gaps and duplicate months in the base series refuse the fast path", {
  con <- roll_setup(roll_loc_monthly(gaps = TRUE))
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_false(.wx_roll_base_contiguous(con, "SELECT * FROM lm"))
  expect_null(roll_fast_run(con, roll_selected(), additive, roll_dates))

  con2 <- roll_setup(roll_loc_monthly(dup = TRUE))
  withr::defer(DBI::dbDisconnect(con2, shutdown = TRUE))
  expect_false(.wx_roll_base_contiguous(con2, "SELECT * FROM lm"))
  expect_null(roll_fast_run(con2, roll_selected(), additive, roll_dates))

  con3 <- roll_setup()
  withr::defer(DBI::dbDisconnect(con3, shutdown = TRUE))
  expect_true(.wx_roll_base_contiguous(con3, "SELECT * FROM lm"))
})

test_that("an incomplete delta calendar refuses the fast path", {
  d <- roll_deltas()
  d <- d[!(d$model == "m2" & d$loc_id == "a" & d$month == 5L), ]
  con <- roll_setup(deltas = d)
  withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))
  expect_null(roll_fast_run(con, roll_selected(), additive, roll_dates))
  tables <- DBI::dbListTables(con)
  expect_false("t_dl" %in% tables)
  expect_false("t_src" %in% tables)
})

test_that("Median, odd windows and the env switch keep the legacy window", {
  expect_true(.wx_roll_fast_spec_ok(roll_selected("Mean")))
  expect_false(.wx_roll_fast_spec_ok(roll_selected("Median")))
  expect_false(.wx_roll_fast_spec_ok(roll_selected("Mean", 1L, 13L)))
  expect_false(.wx_roll_fast_spec_ok(roll_selected("Mean", 3L, 1L)))
  expect_false(.wx_roll_fast_spec_ok(roll_selected("Mean", NA, 3L)))
  mixed_agg <- roll_selected("Mean")
  mixed_agg$temporalAgg <- c("Mean", "Median")
  expect_false(.wx_roll_fast_spec_ok(mixed_agg))
  withr::with_envvar(c(WISEAPP_WEATHER_ROLL = "window"), {
    expect_false(.wx_roll_fast_spec_ok(roll_selected("Mean")))
  })
  withr::with_envvar(c(WISEAPP_WEATHER_ROLL = "fast"), {
    expect_true(.wx_roll_fast_spec_ok(roll_selected("Mean")))
  })
})
