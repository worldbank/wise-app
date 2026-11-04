# Fixture: tests/testthat/fixtures/enso/metadata/{enso,enso_forecast}.csv. RONI by month, Jan 1950 to
# Mar 1954, designed so each case below can be worked by hand from the values listed there:
#   1950: -0.8 -0.8 -0.6 -0.2  0.0  0.1  0.2  0.3  0.4  0.6  0.8  1.0
#   1951:  1.2  1.4  1.2  1.0  0.8  0.6  0.4  0.2  0.0 -0.2 -0.4 -0.6
#   1952: -0.8 -0.7 -0.5 -0.3 -0.1  0.0  0.1  0.2  0.3  0.4  0.5  0.6
# Phase is el_nino at 0.5 or more, la_nina at -0.5 or less, else neutral.

enso_fixture_root <- function() normalizePath(testthat::test_path("fixtures", "enso"), mustWork = TRUE)

enso_fixture_params <- function(root = enso_fixture_root()) list(type = "local", path = root)

# A data tree holding only the files given (fixture names), copied from the fixture.
enso_fixture_tree <- function(dir, files = c("enso.csv", "enso_forecast.csv")) {
  dir.create(file.path(dir, "metadata"), recursive = TRUE, showWarnings = FALSE)
  file.copy(file.path(enso_fixture_root(), "metadata", files), file.path(dir, "metadata"))
  dir
}

enso_fixture <- function() enso_load(enso_fixture_params())

# Loading (D6) ----

test_that("enso_load reads both tables and validates them", {
  e <- enso_fixture()
  expect_named(e, c("observed", "forecast"))
  expect_equal(nrow(e$observed), 51L)
  expect_equal(e$observed$month[c(1, 51)], as.Date(c("1950-01-01", "1954-03-01")))
  expect_equal(e$observed$phase[e$observed$month == as.Date("1951-02-01")], "el_nino")
  expect_equal(nrow(e$forecast), 12L)
  expect_true(all(c("source", "init_date", "month", "roni", "prob_el_nino", "phase") %in% names(e$forecast)))
})

test_that("enso_load returns NULL quietly when the observed table is unusable", {
  withr::local_tempdir() -> missing_dir
  expect_no_condition(r <- enso_load(enso_fixture_params(missing_dir)))
  expect_null(r)

  write_obs <- function(lines) {
    d <- withr::local_tempdir(.local_envir = parent.frame())
    dir.create(file.path(d, "metadata"))
    writeLines(lines, file.path(d, "metadata", "enso.csv"))
    d
  }
  hdr <- "timestamp,source,roni,phase,phase_agree"
  cases <- list(
    empty = hdr,
    missing_column = c("timestamp,roni", "1950-01-01,0.1"),
    bad_phase = c(hdr, "1950-01-01,cpc,0.1,warm,true"),
    bad_date = c(hdr, "not-a-date,cpc,0.1,neutral,true"),
    gap = c(hdr, "1950-01-01,cpc,0.1,neutral,true", "1950-03-01,cpc,0.1,neutral,true"),
    duplicate = c(hdr, "1950-01-01,cpc,0.1,neutral,true", "1950-01-01,cpc,0.1,neutral,true"),
    missing_roni = c(hdr, "1950-01-01,cpc,,neutral,true")
  )
  for (nm in names(cases)) {
    expect_no_condition(r <- enso_load(enso_fixture_params(write_obs(cases[[nm]]))))
    expect_null(r, label = nm)
  }
})

test_that("a missing or malformed forecast table only drops the forecast", {
  d <- enso_fixture_tree(withr::local_tempdir(), files = "enso.csv")
  e <- enso_load(enso_fixture_params(d))
  expect_equal(nrow(e$observed), 51L)
  expect_null(e$forecast)

  writeLines(c("source,init_date,timestamp", "multimodel,1953-10-01,1953-10-01"),
    file.path(d, "metadata", "enso_forecast.csv"))
  expect_no_condition(e <- enso_load(enso_fixture_params(d)))
  expect_equal(nrow(e$observed), 51L)
  expect_null(e$forecast)

  fc <- readLines(file.path(enso_fixture_root(), "metadata", "enso_forecast.csv"))
  writeLines(sub("el_nino", "warm", fc[2]) |> (\(x) c(fc[1], x))(), file.path(d, "metadata", "enso_forecast.csv"))
  expect_null(enso_load(enso_fixture_params(d))$forecast)
})

test_that("enso_load works on a Databricks source and returns NULL when it fails", {
  restore <- local({
    backup <- as.list(.duck)
    function() {
      new_con <- .duck$con
      rm(list = ls(.duck, all.names = TRUE), envir = .duck)
      list2env(backup, envir = .duck)
      if (!is.null(new_con) && !identical(new_con, backup$con) && inherits(new_con, "duckdb_connection")) {
        try(DBI::dbDisconnect(new_con, shutdown = TRUE), silent = TRUE)
      }
    }
  })
  withr::defer(restore())
  csv <- list(
    enso = paste(readLines(file.path(enso_fixture_root(), "metadata", "enso.csv")), collapse = "\n"),
    enso_forecast = paste(readLines(file.path(enso_fixture_root(), "metadata", "enso_forecast.csv")),
      collapse = "\n")
  )
  serve <- function(req) {
    if (grepl("/oidc/v1/token$", req$url)) {
      return(httr2::response_json(body = list(access_token = "t", expires_in = 3600), url = req$url))
    }
    hit <- names(csv)[vapply(names(csv), function(x) grepl(paste0("/", x, "\\.csv$"), req$url), logical(1))]
    if (length(hit) != 1L) return(httr2::response(status_code = 404L, url = req$url))
    httr2::response(body = charToRaw(csv[[hit]]), url = req$url)
  }
  params <- list(
    type = "databricks", workspace = "https://workspace.cloud.databricks.com",
    client_id = "client", client_secret = "secret", volume_path = "/Volumes/catalog/schema/data"
  )
  withr::local_options(httr2_mock = serve)
  e <- enso_load(params)
  expect_equal(nrow(e$observed), 51L)
  expect_equal(nrow(e$forecast), 12L)
  expect_equal(e$observed$phase[1], "la_nina")

  csv$enso_forecast <- NULL # the forecast file answers 404
  e <- enso_load(params)
  expect_equal(nrow(e$observed), 51L)
  expect_null(e$forecast)

  csv$enso <- NULL
  expect_no_condition(r <- enso_load(params))
  expect_null(r)
})

test_that("ENSO files do not affect the Overview metadata bundle", {
  d <- withr::local_tempdir()
  batch_fixture_tree(d)
  expect_null(enso_load(enso_fixture_params(d))) # no ENSO files in the tree: optional
  enso_fixture_tree(d)
  withr::local_envvar(WISEAPP_METADATA_CACHE_DISABLE = "1")
  without <- load_overview_metadata(enso_fixture_params(d))
  expect_false("enso" %in% names(without))
  expect_equal(nrow(enso_load(enso_fixture_params(d))$observed), 51L)
})

# Window and weights ----

test_that("enso_window is the union range of the fitted windows", {
  expect_equal(enso_window(data.frame(ref_start = 1, ref_end = 3)), 1:3)
  expect_equal(enso_window(data.frame(ref_start = c(1L, 5L), ref_end = c(2L, 6L))), 1:6)
  expect_equal(enso_window(data.frame(ref_start = c(1L, 2L), ref_end = c(3L, 6L))), 1:6)
  expect_equal(enso_window(data.frame(ref_start = 0, ref_end = 0)), 0L)
  expect_equal(enso_window(data.frame(x = 1)), integer(0))
  expect_equal(enso_window(data.frame(ref_start = 3, ref_end = 1)), integer(0))
})

test_that("enso_month_weights normalises by calendar month", {
  w <- enso_month_weights(c(2, 2, 2, 6))
  expect_equal(w[c(2, 6)], c(0.75, 0.25))
  expect_equal(sum(w), 1)
  expect_equal(enso_month_weights(c(2, 6), c(3, 1)), w)
  expect_equal(enso_month_weights(as.Date(c("1951-02-10", "1951-06-01")), c(3, 1)), w)
  expect_true(all(is.na(enso_month_weights(integer(0)))))
})

# Year labels (D2) ----

test_that("a window crossing December reads the previous year's months", {
  e <- enso_fixture()
  w <- enso_month_weights(2) # interviewed in February
  out <- enso_year_labels(e$observed, c(1951, 1952), w, lags = 1:3)
  # 1951: Nov 1950 0.8, Dec 1950 1.0, Jan 1951 1.2, all El Nino
  expect_equal(out$el_nino[1], 1)
  expect_equal(out$roni_exp[1], 1.0)
  expect_equal(out$label[1], "el_nino")
  # 1952: Nov 1951 -0.4 neutral, Dec -0.6 and Jan 1952 -0.8 La Nina
  expect_equal(out$la_nina[2], 2 / 3)
  expect_equal(out$neutral[2], 1 / 3)
  expect_equal(out$roni_exp[2], -0.6)
  expect_equal(out$label[2], "la_nina")
})

test_that("two variables use the union window, so the label can differ from one window", {
  e <- enso_fixture()
  w <- enso_month_weights(2)
  lags <- enso_window(data.frame(ref_start = c(1L, 5L), ref_end = c(2L, 6L)))
  out <- enso_year_labels(e$observed, 1951, w, lags = lags)
  # Aug 1950 to Jan 1951: 0.3 0.4 0.6 0.8 1.0 1.2
  expect_equal(out$el_nino, 4 / 6)
  expect_equal(out$neutral, 2 / 6)
  expect_equal(out$roni_exp, 4.3 / 6)
  expect_equal(out$label, "el_nino")
  # 1952: lags 1:3 give La Nina (2/3), but lags 1:6 (Aug 1951 to Jan 1952) give Neutral (4/6)
  out2 <- enso_year_labels(e$observed, 1952, w, lags = 1:6)
  expect_equal(c(out2$el_nino, out2$neutral, out2$la_nina), c(0, 4 / 6, 2 / 6))
  expect_equal(out2$label, "neutral")
})

test_that("a pooled multi-wave baseline weights the interview months", {
  e <- enso_fixture()
  # Waves interviewed in February (weight 3) and June (weight 1); lags 1:2
  w <- enso_month_weights(c(2, 6), c(3, 1))
  out <- enso_year_labels(e$observed, 1952, w, lags = 1:2)
  # Feb: Jan 1952, Dec 1951 La Nina; Jun: May, Apr 1952 neutral
  expect_equal(c(out$el_nino, out$neutral, out$la_nina), c(0, 0.25, 0.75))
  expect_equal(out$roni_exp, 0.75 * mean(c(-0.8, -0.6)) + 0.25 * mean(c(-0.1, -0.3)))
  expect_equal(out$label, "la_nina")
  # Weights are shares: scaling them changes nothing
  expect_equal(enso_year_labels(e$observed, 1952, w * 40, lags = 1:2), out)
})

test_that("a lag reaching before the table gives NA, not a guess", {
  e <- enso_fixture()
  w <- enso_month_weights(2)
  out <- enso_year_labels(e$observed, c(1949, 1950, 1951), w, lags = 1:3)
  expect_true(all(is.na(unlist(out[1, -1]))))
  expect_true(all(is.na(unlist(out[2, -1])))) # Nov 1949 is missing
  expect_false(is.na(out$label[3]))
  # One month back stays inside the table for 1950: January 1950 is La Nina
  expect_equal(enso_year_labels(e$observed, 1950, w, lags = 1)$label, "la_nina")
  # Only interview months with weight count: June needs no month before 1950
  expect_equal(enso_year_labels(e$observed, 1950, enso_month_weights(6), lags = 1:3)$label, "neutral")
  # The end of the table behaves the same way
  expect_true(is.na(enso_year_labels(e$observed, 1960, w, lags = 1)$label))
})

test_that("a share of exactly 0.5 reaches the threshold, and a two-way tie is mixed", {
  e <- enso_fixture()
  # Jan and Feb (La Nina), Jun (neutral), Dec (El Nino); lag 1, year 1952: shares 0.5 / 0.25 / 0.25
  w <- enso_month_weights(c(1, 2, 6, 12))
  out <- enso_year_labels(e$observed, 1952, w, lags = 1)
  expect_equal(c(out$el_nino, out$neutral, out$la_nina), c(0.25, 0.25, 0.5))
  expect_equal(out$label, "la_nina")
  # Feb (La Nina) and Jun (neutral) at equal weight: both at 0.5, no single majority
  out2 <- enso_year_labels(e$observed, 1952, enso_month_weights(c(2, 6)), lags = 1)
  expect_equal(c(out2$neutral, out2$la_nina), c(0.5, 0.5))
  expect_equal(out2$label, "mixed")
  # Shares that miss 0.5 by floating-point error still reach it; below it is mixed
  out3 <- enso_year_labels(e$observed, 1952, enso_month_weights(c(1, 2, 6, 12), c(0.1, 0.4, 0.3, 0.2)), 1)
  expect_equal(out3$la_nina, 0.5)
  expect_equal(out3$label, "la_nina")
  out4 <- enso_year_labels(e$observed, 1952, enso_month_weights(c(1, 2, 6, 12), c(0.1, 0.3, 0.4, 0.2)), 1)
  expect_equal(out4$label, "mixed")
  expect_equal(out4$neutral, 0.4)
})

test_that("shares are not rounded", {
  e <- enso_fixture()
  out <- enso_year_labels(e$observed, 1952, enso_month_weights(2), lags = 1:3)
  expect_identical(out$la_nina, 2 / 3)
  expect_identical(out$neutral, 1 / 3)
})

test_that("a forecast window labels the reference year by the year it starts", {
  e <- enso_fixture()
  w <- enso_month_weights(c(11, 12, 1))
  out <- enso_year_labels(e$observed, c(1950, 1951), w, lags = 0L, start_month = 11)
  # Nov 1950, Dec 1950, Jan 1951: all El Nino; Nov 1951, Dec 1951, Jan 1952: -0.4 -0.6 -0.8
  expect_equal(out$el_nino[1], 1)
  expect_equal(out$roni_exp, c(mean(c(0.8, 1.0, 1.2)), mean(c(-0.4, -0.6, -0.8))))
  expect_equal(out$label, c("el_nino", "la_nina"))
  # Without the rule the window is split: January of the same calendar year
  plain <- enso_year_labels(e$observed, 1951, w, lags = 0L)
  expect_equal(plain$roni_exp, mean(c(-0.4, -0.6, 1.2)))
})

test_that("unusable inputs give an NA table of the right shape", {
  e <- enso_fixture()
  expect_equal(nrow(enso_year_labels(NULL, 1990:1992, enso_month_weights(2), 1:3)), 3L)
  expect_true(all(is.na(enso_year_labels(e$observed, 1951, rep(NA_real_, 12), 1:3)$label)))
  expect_true(is.na(enso_year_labels(e$observed, 1951, enso_month_weights(2), integer(0))$label))
})

# Sample coverage ----

test_that("enso_sample_coverage places each interview in its own month", {
  e <- enso_fixture()
  dates <- as.Date(c("1950-01-15", "1950-06-10", "1951-02-01", "1951-02-20", "1949-05-01"))
  grp <- c("A", "A", "B", "B", "B")
  out <- enso_sample_coverage(e$observed, dates, group = grp)
  a <- out[out$group == "A", ]
  b <- out[out$group == "B", ]
  expect_equal(c(a$n, a$n_missing), c(2L, 0L))
  expect_equal(c(a$el_nino, a$neutral, a$la_nina), c(0, 0.5, 0.5))
  expect_equal(a$max_roni, 0.1)
  expect_equal(c(b$n, b$n_missing), c(2L, 1L)) # the 1949 interview is outside the table
  expect_equal(c(b$el_nino, b$la_nina), c(1, 0))
  expect_equal(b$max_roni, 1.4)

  w <- enso_sample_coverage(e$observed, dates[1:2], weights = c(3, 1))
  expect_equal(w$group, "all")
  expect_equal(c(w$neutral, w$la_nina), c(0.25, 0.75))
})

# Phase summary (D5) ----

test_that("enso_phase_summary gives counts, means and differences from Neutral", {
  labels <- tibble::tibble(
    sim_year = 1:10,
    label = c(rep("el_nino", 3), rep("neutral", 4), rep("la_nina", 2), "mixed")
  )
  values <- data.frame(sim_year = 1:10, value = c(1, 2, 3, 4, 4, 6, 6, 7, 9, 100))
  s <- enso_phase_summary(labels, values)
  expect_equal(s$label, ENSO_LABEL_LEVELS)
  expect_equal(s$n, c(3L, 4L, 2L, 1L))
  expect_equal(s$mean, c(2, 5, 8, 100))
  # El Nino has three years: compared. La Nina has two: hidden. Neutral and Mixed: never.
  expect_equal(s$diff_neutral, c(-3, NA, NA, NA))
  # With a lower threshold La Nina is shown
  expect_equal(enso_phase_summary(labels, values, min_n = 2L)$diff_neutral[3], 3)
  # Neutral below the threshold hides every comparison
  expect_true(all(is.na(enso_phase_summary(labels, values, min_n = 4L)$diff_neutral)))
})

test_that("enso_phase_summary handles series and unlabelled years", {
  labels <- tibble::tibble(sim_year = 1:6, label = c(rep("el_nino", 3), rep("neutral", 3)))
  values <- data.frame(
    series = rep(c("Baseline", "Policy"), each = 7), sim_year = rep(c(1:6, 7), 2),
    value = c(1, 1, 1, 2, 2, 2, 50, 2, 2, 2, 3, 3, 3, 50)
  )
  s <- enso_phase_summary(labels, values)
  expect_equal(unique(s$series), c("Baseline", "Policy"))
  expect_equal(s$diff_neutral[s$label == "el_nino"], c(-1, -1)) # year 7 has no label: dropped
  expect_equal(sum(s$n[s$series == "Policy"]), 6L)

  na_label <- tibble::tibble(sim_year = 1:6, label = c(NA, rep("el_nino", 2), rep("neutral", 3)))
  expect_equal(enso_phase_summary(na_label, values[1:6, ])$n[1:2], c(2L, 3L))
})

# Outlook (D4) ----

test_that("the outlook prefers the run's own system and fills the edge leads from enso.csv", {
  e <- enso_fixture()
  months <- as.Date(c("1953-10-01", "1953-11-01", "1953-12-01"))
  out <- enso_forecast_outlook(e, months, as.Date("1953-10-01"), system = "ecmwf_51")
  expect_equal(out$basis, rep("forecast", 3))
  expect_equal(out$source, rep("ecmwf_51", 3))
  expect_equal(out$roni, c(0.9, 1.1, 1.4)) # October: empty at the first lead, filled from enso.csv
  expect_equal(out$prob_el_nino, c(NA, 1, 1))
  expect_equal(out$phase, rep("el_nino", 3))
})

test_that("the outlook falls back on the multi-model mean", {
  e <- enso_fixture()
  months <- as.Date(c("1953-11-01", "1953-12-01"))
  out <- enso_forecast_outlook(e, months, as.Date("1953-10-01"), system = "no_such_system")
  expect_equal(out$source, rep("multimodel", 2))
  expect_equal(out$roni, c(1.0, 1.3))
  out2 <- enso_forecast_outlook(e, months, as.Date("1953-10-01"))
  expect_equal(out2$source, rep("multimodel", 2))
})

test_that("the last lead has RONI only", {
  e <- enso_fixture()
  out <- enso_forecast_outlook(e, as.Date("1954-03-01"), as.Date("1953-10-01"), "ecmwf_51")
  expect_equal(out$roni, 2.0) # forecast roni is empty; enso.csv holds the chained value
  expect_true(is.na(out$prob_el_nino))
  expect_equal(out$basis, "forecast")
})

test_that("a later initialisation shows observed months and says so", {
  e <- enso_fixture()
  months <- as.Date(c("1953-10-01", "1953-11-01"))
  out <- enso_forecast_outlook(e, months, as.Date("1953-09-01"), "ecmwf_51")
  expect_equal(out$basis, rep("observed", 2))
  expect_true(all(is.na(out$source)) && all(is.na(out$prob_el_nino)))
  expect_equal(out$roni, c(0.9, 1.2))
  expect_equal(out$phase, rep("el_nino", 2))
  # No forecast table at all behaves the same way
  e$forecast <- NULL
  expect_equal(enso_forecast_outlook(e, months, as.Date("1953-10-01"))$basis, rep("observed", 2))
})

test_that("months outside both tables give no rows", {
  e <- enso_fixture()
  expect_equal(nrow(enso_forecast_outlook(e, as.Date("1960-01-01"), as.Date("1953-10-01"))), 0L)
  expect_equal(nrow(enso_forecast_outlook(NULL, as.Date("1953-10-01"), as.Date("1953-10-01"))), 0L)
  mixed <- enso_forecast_outlook(e, as.Date(c("1953-11-01", "1960-01-01")), as.Date("1953-10-01"))
  expect_equal(nrow(mixed), 1L)
})
