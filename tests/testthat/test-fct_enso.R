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

test_that("ENSO files ride along in the Overview metadata bundle without changing it", {
  d <- withr::local_tempdir()
  batch_fixture_tree(d)
  expect_null(enso_load(enso_fixture_params(d))) # no ENSO files in the tree: optional
  withr::local_envvar(WISEAPP_METADATA_CACHE_DISABLE = "1")
  without <- load_overview_metadata(enso_fixture_params(d))
  expect_true("enso" %in% names(without))
  expect_null(without$enso)
  enso_fixture_tree(d)
  with <- load_overview_metadata(enso_fixture_params(d))
  expect_equal(nrow(with$enso$observed), 51L)
  expect_equal(with[setdiff(names(with), "enso")], without[setdiff(names(without), "enso")])
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

# Results helpers ----

enso_labels_fixture <- function() {
  tibble::tibble(
    sim_year = 2001:2010,
    el_nino = c(1, 1, 1, 0, 0, 0, 0, 0, 0.2, 0.2),
    neutral = c(0, 0, 0, 1, 1, 1, 0, 0, 0.5, 0.5),
    la_nina = c(0, 0, 0, 0, 0, 0, 1, 1, 0.3, 0.3),
    roni_exp = c(1.2, 1.4, 1.1, 0, 0.1, 0, -1, -1.1, 0.2, 0.3),
    label = c(rep("el_nino", 3), rep("neutral", 3), rep("la_nina", 2), rep("mixed", 2))
  )
}

test_that("interview months carry the phase and RONI of their own month, by wave", {
  obs <- tibble::tibble(
    month = as.Date(c("2018-05-01", "2018-06-01", "2021-05-01")),
    phase = c("el_nino", "neutral", "la_nina"), roni = c(0.82, 0.1, -0.86)
  )
  dates <- as.Date(c("2018-05-10", "2018-05-20", "2018-06-02", "2021-05-03", "1900-01-01", NA))
  grp <- c("A, 2018", "A, 2018", "A, 2018", "A, 2021", "A, 2021", "A, 2021")
  out <- enso_interview_months(obs, dates, grp)
  expect_equal(nrow(out), 3L) # one row per wave and month; dates outside the record or missing are left out
  expect_identical(out$phase[out$group == "A, 2021"], "la_nina")
  expect_equal(out$roni[out$group == "A, 2018" & out$month_num == 5L], 0.82)
})

test_that("the month chip names one month's phase and RONI, or counts the months of a wave", {
  m <- data.frame(month_num = c(5L, 6L, 11L), phase = c("el_nino", "neutral", "el_nino"), roni = c(0.82, 0.1, 0.9))
  one <- as.character(enso_month_chip_ui(m, "5"))
  expect_match(one, "El Ni\u00f1o, RONI 0.82")
  expect_match(one, "\u25B2")
  expect_match(as.character(enso_month_chip_ui(m, "6")), "Neutral, RONI 0.10")
  expect_null(enso_month_chip_ui(m, "7"))
  all <- as.character(enso_month_chip_ui(m, "all"))
  expect_match(all, "2 El Ni\u00f1o  .*1 Neutral")
  expect_null(enso_month_chip_ui(m[0, ], "all"))
})

test_that("labels attach by simulation year and skip the forecast-window series", {
  tbl <- data.frame(
    scenario = c("Historical", "Historical", "SSP3-7.0 / 2025-2035", "Historical (Nov-Jan)"),
    sim_year = c(2001L, 2007L, 2001L, 2001L), value = 1:4
  )
  out <- enso_attach_labels(tbl, enso_labels_fixture())
  expect_equal(out$enso_label[1:3], c("el_nino", "la_nina", "el_nino")) # SSP rows keep the template label
  expect_equal(out$enso_roni[1], 1.2)
  expect_true(is.na(out$enso_label[4]))
  expect_equal(nrow(out), nrow(tbl))
  # A year outside the labels, and a label table with no row, give NA rather than an error
  tbl$sim_year[1] <- 1900L
  expect_true(is.na(enso_attach_labels(tbl, enso_labels_fixture())$enso_label[1]))
})

test_that("the series table averages models per year and compares phases with Neutral", {
  lab <- enso_labels_fixture()
  d <- expand.grid(model_id = c("a", "b"), sim_year = 2001:2010, scenario = c("Historical", "SSP3-7.0 / 2025-2035"),
    stringsAsFactors = FALSE)
  d$value <- ifelse(d$scenario == "Historical", 10, 20) + ifelse(d$sim_year <= 2003, -1, 0) +
    ifelse(d$model_id == "a", 1, -1) # the model offsets cancel in the year mean
  out <- enso_series_table(d, lab)
  expect_equal(out$series, c("Historical", "SSP3-7.0 / 2025-2035"))
  h <- out[out$series == "Historical", ]
  expect_equal(c(h$n_el_nino, h$n_neutral, h$n_la_nina, h$n_mixed), c(3L, 3L, 2L, 2L))
  expect_equal(c(h$mean_el_nino, h$mean_neutral), c(9, 10))
  expect_equal(h$diff_el_nino, -1)
  expect_true(is.na(h$diff_la_nina)) # two La Nina years: below the minimum of three
  # Forecast-window series are never compared
  d2 <- rbind(d, transform(d, scenario = "Historical (Nov-Jan)"))
  expect_equal(nrow(enso_series_table(d2, lab)), 2L)
  expect_null(enso_series_table(d[0, ], lab))
})

test_that("the series table adds the same-months Historical row of a window, and works on it alone", {
  lab <- enso_labels_fixture()
  d <- data.frame(model_id = "a", sim_year = 2001:2010, scenario = "Historical", value = 10)
  window <- list(
    values = data.frame(
      series = "Historical (Nov - Jan)", sim_year = 2001:2010, value = c(1, 1, 1, 4, 4, 4, 7, 7, 0, 0)
    ),
    labels = lab
  )
  out <- enso_series_table(d, lab, window = window)
  expect_equal(out$series, c("Historical", "Historical (Nov - Jan)"))
  expect_equal(out$mean_el_nino[2], 1)
  expect_equal(out$diff_el_nino[2], -3)
  alone <- enso_series_table(NULL, NULL, window = window)
  expect_equal(alone$series, "Historical (Nov - Jan)")
  expect_null(enso_series_table(NULL, NULL))
})

test_that("the phase sentence names the differences from Neutral, and is absent without a comparison", {
  lab <- enso_labels_fixture()
  tbl <- enso_series_table(data.frame(scenario = "Historical", sim_year = 2001:2010, value = c(1, 1, 1, 4, 4, 4, 7, 7, 0, 0)), lab)
  expect_match(
    enso_phase_sentence(tbl, "Historical"),
    "^In Historical, the mean outcome is 3.000 lower in El Ni\u00f1o years \\(3\\) than in Neutral years \\(3\\)\\.$"
  )
  expect_null(enso_phase_sentence(tbl, "Other"))
  tbl$diff_el_nino <- NA_real_
  expect_null(enso_phase_sentence(tbl, "Historical"))
})

test_that("the adverse sentence counts El Nino among the worst years", {
  lab <- enso_labels_fixture()
  # Worst 3 of 10 are the three El Nino years when low is adverse
  v <- data.frame(sim_year = 2001:2010, value = c(1, 2, 3, 10, 11, 12, 13, 14, 15, 16))
  expect_equal(
    enso_adverse_sentence(lab, v, "low"),
    "3 of the 3 most adverse years have El Niño exposure; 3 of 10 years do."
  )
  expect_match(enso_adverse_sentence(lab, v, "high"), "^0 of the 3 ")
  expect_null(enso_adverse_sentence(lab[1:4, ], v[1:4, ])) # fewer than five labelled years
  none <- transform(lab, label = "neutral")
  expect_null(enso_adverse_sentence(none, v))
})

test_that("baseline months come from int_month or timestamp and the weight column", {
  svy <- data.frame(int_month = c(2L, 2L, 6L), weight = c(1, 1, 2))
  w <- enso_baseline_months(svy)
  expect_equal(w[c(2, 6)], c(0.5, 0.5))
  expect_equal(sum(w), 1)
  svy2 <- data.frame(timestamp = as.Date(c("2020-03-10", "2020-03-20")))
  expect_equal(enso_baseline_months(svy2)[3], 1)
  expect_true(all(is.na(enso_baseline_months(data.frame(x = 1)))))
  expect_true(all(is.na(enso_baseline_months(NULL))))
})

# Chart marks (D1: draws, counts and series ids do not change) ----

enso_chart_tbl <- function() {
  d <- data.frame(
    scenario = rep(c("Historical", "SSP3-7.0 / 2025-2035"), each = 10), sim_year = rep(2001:2010, 2),
    value = c(seq(5, 6, length.out = 10), seq(4, 5, length.out = 10))
  )
  enso_attach_labels(d, enso_labels_fixture())
}

enso_dot_series <- function(chart) {
  s <- chart$x$opts$series
  s[vapply(s, function(x) startsWith(as.character(x$id %||% ""), "draws|"), logical(1L))]
}

test_that("marking ENSO years keeps the draws, their order and the series ids", {
  tbl <- enso_chart_tbl()
  plain <- echart_step3_annual_distribution(tbl)
  marked <- echart_step3_annual_distribution(tbl, enso_marks = TRUE)
  p <- enso_dot_series(plain)
  m <- enso_dot_series(marked)
  expect_equal(vapply(m, `[[`, "", "id"), vapply(p, `[[`, "", "id"))
  expect_true(all(grepl("^draws\\|[^|]+\\|All$", vapply(m, `[[`, "", "id"))))
  expect_equal(vapply(m, function(x) length(x$data), 1L), vapply(p, function(x) nrow(x$data), 1L))
  # The coordinates are the same
  xy <- function(s) t(vapply(s$data, function(d) as.numeric(if (is.list(d)) d$value else d), numeric(2)))
  expect_equal(xy(m[[1]]), unname(p[[1]]$data))
  # Only the El Nino and La Nina draws carry a style; the tooltip text names the year and exposure
  hist <- m[[which(vapply(m, `[[`, "", "name") == "Historical")]]$data
  styled <- vapply(hist, function(d) is.list(d) && !is.null(d$itemStyle), logical(1L))
  expect_equal(which(styled), c(1:3, 7:8))
  expect_match(
    hist[[1]]$enso_text,
    "^Weather year 2001: El Niño exposure \\(El Niño 100%, Neutral 0%, La Niña 0%; RONI 1.20\\)$"
  )
  expect_equal(hist[[1]]$symbol, "triangle")
  expect_equal(hist[[7]]$symbol, "diamond")
  expect_true(is.null(hist[[4]]$symbol)) # Neutral keeps the default look
  expect_false(is.null(hist[[9]]$enso_text)) # Mixed carries the tooltip text only
  expect_true(is.null(hist[[9]]$itemStyle))
  # Without the label columns the toggle changes nothing
  bare <- echart_step3_annual_distribution(tbl[c("scenario", "sim_year", "value")], enso_marks = TRUE)
  expect_equal(enso_dot_series(bare), enso_dot_series(plain))
})

test_that("forecast-window rows stay unlabelled when marked", {
  tbl <- rbind(enso_chart_tbl(), enso_attach_labels(
    data.frame(scenario = "Historical (Nov-Jan)", sim_year = 2001:2003, value = 5), enso_labels_fixture()
  )[names(enso_chart_tbl())])
  m <- enso_dot_series(echart_step3_annual_distribution(tbl, enso_marks = TRUE))
  win <- m[[which(grepl("Nov-Jan", vapply(m, `[[`, "", "name"), fixed = TRUE))]]
  expect_true(all(vapply(win$data, function(d) !is.list(d), logical(1L))))
})

# Forecast window (item 7) ----

enso_window_fixture <- function(years = 1950:1952) {
  list(forecast_months = as.Date(c("1953-11-01", "1953-12-01", "1954-01-01")), reference_years = years)
}

test_that("a forecast table with the text NA for empty values loads, as upstream writes it", {
  d <- withr::local_tempdir()
  enso_fixture_tree(d)
  path <- file.path(d, "metadata", "enso_forecast.csv")
  lines <- readLines(path)
  lines[-1L] <- gsub(",(?=,|$)", ",NA", lines[-1L], perl = TRUE)
  writeLines(lines, path)
  e <- enso_load(enso_fixture_params(d))
  expect_equal(nrow(e$forecast), 12L)
  expect_true(is.numeric(e$forecast$roni) && is.numeric(e$forecast$prob_el_nino))
  mm <- e$forecast[e$forecast$source == "multimodel", ]
  mm <- mm[order(mm$month), ]
  expect_true(is.na(mm$roni[[1L]]))
  expect_true(is.na(mm$prob_el_nino[[1L]]))
  expect_equal(mm$roni[[2L]], 1)
})

test_that("window labels weight the target months equally and date a year by the window's start", {
  lab <- enso_window_labels(enso_fixture()$observed, enso_window_fixture(), 1L)
  # 1950: Oct, Nov, Dec 1950 feed Nov 1950 to Jan 1951 (0.6, 0.8, 1.0)
  expect_equal(lab$el_nino[lab$sim_year == 1950L], 1)
  expect_equal(lab$roni_exp[lab$sim_year == 1950L], 0.8)
  expect_equal(lab$label[lab$sim_year == 1950L], "el_nino")
  # 1951: Oct, Nov, Dec 1951 (-0.2, -0.4, -0.6): the January lag sits in the year the window starts
  expect_equal(lab$neutral[lab$sim_year == 1951L], 2 / 3)
  expect_equal(lab$la_nina[lab$sim_year == 1951L], 1 / 3)
  expect_equal(lab$label[lab$sim_year == 1951L], "neutral")
  expect_equal(lab$period[[1L]], "Nov 1950 - Jan 1951")
  # The fitted lags count: with months 1 to 3, 1951 reads Aug 1951 to Dec 1951
  wide <- enso_window_labels(enso_fixture()$observed, enso_window_fixture(), 1:3)
  expect_equal(wide$roni_exp[wide$sim_year == 1951L], mean(c(0.2, 0, -0.2, 0, -0.2, -0.4, -0.2, -0.4, -0.6)))
  # A window inside one calendar year
  one <- list(forecast_months = as.Date(c("1953-02-01", "1953-03-01")), reference_years = 1951L)
  lab_one <- enso_window_labels(enso_fixture()$observed, one, 1L)
  expect_equal(lab_one$roni_exp, mean(c(1.2, 1.4)))
  expect_equal(lab_one$period, "Feb 1951 - Mar 1951")
  # One month, and a year whose months leave the table
  single <- list(forecast_months = as.Date("1953-02-01"), reference_years = c(1951L, 1960L))
  lab_single <- enso_window_labels(enso_fixture()$observed, single, 1L)
  expect_equal(lab_single$period, c("Feb 1951", "Feb 1960"))
  expect_true(is.na(lab_single$label[[2L]]))
})

test_that("window labels go on the target-month Historical rows only, never on members", {
  lab <- enso_window_labels(enso_fixture()$observed, enso_window_fixture(1:3 + 1949L), 1L)
  member_lab <- lab
  member_lab$sim_year <- 1:3 # a member index that equals a labelled year must not match
  tbl <- rbind(
    data.frame(scenario = "Historical", sim_year = 1950:1952, value = 1),
    data.frame(scenario = "Historical (Nov - Jan)", sim_year = 1950:1952, value = 2),
    data.frame(scenario = "Forecast (Nov - Jan)", sim_year = 1:3, value = 3)
  )
  annual <- enso_attach_labels(tbl, enso_labels_fixture())
  out <- enso_attach_window_labels(annual, lab, "Historical (Nov - Jan)")
  hist <- out$scenario == "Historical (Nov - Jan)"
  expect_equal(out$enso_label[hist], lab$label)
  expect_equal(out$enso_period[hist], lab$period)
  expect_true(all(is.na(out$enso_label[startsWith(out$scenario, "Forecast")])))
  expect_identical(out$enso_label[out$scenario == "Historical"], annual$enso_label[annual$scenario == "Historical"])
  expect_true(all(is.na(out$enso_period[!hist])))
  expect_true(all(is.na(
    enso_attach_window_labels(annual, member_lab, "Historical (Nov - Jan)")$enso_label[startsWith(out$scenario, "Forecast")]
  )))
  # Without annual columns, and without labels or a window
  bare <- enso_attach_window_labels(tbl, lab, "Historical (Nov - Jan)")
  expect_equal(bare$enso_label[bare$scenario == "Historical (Nov - Jan)"], lab$label)
  expect_identical(enso_attach_window_labels(tbl, NULL, "x"), tbl)
  expect_identical(enso_attach_window_labels(tbl, lab, NULL), tbl)
})

test_that("the tooltip of a target-month draw names its months", {
  rows <- data.frame(
    sim_year = c(1997L, 1998L), enso_label = "el_nino", enso_el_nino = 1, enso_neutral = 0, enso_la_nina = 0,
    enso_roni = 2, enso_period = c("Nov 1997 - Jan 1998", NA)
  )
  pts <- .enso_dot_data(cbind(c(1, 2), c(1, 1)), rows, "Historical (Nov - Jan)", "All")
  expect_match(pts[[1L]]$enso_text, "Weather year Nov 1997 - Jan 1998: El Ni", fixed = TRUE)
  expect_match(pts[[2L]]$enso_text, "Weather year 1998: El Ni", fixed = TRUE)
})

test_that("the outlook phase needs at least half of the months", {
  ph <- function(...) enso_outlook_phase(list(phase = c(...)))
  expect_equal(ph("el_nino", "el_nino", "neutral"), "el_nino")
  expect_equal(ph("el_nino", "neutral", "la_nina"), "mixed")
  expect_equal(ph("el_nino", "neutral"), "mixed")
  expect_equal(ph(NA, "la_nina"), "la_nina")
  expect_true(is.na(ph(NA_character_)))
})

enso_placement_fixture <- function(tail = "low") {
  list(
    reference = data.frame(year = 1950:1955, value = c(1, 2, 3, 4, 5, 6)),
    summary = list(member_median = 3), adverse_tail = tail
  )
}
enso_reference_labels <- function(labels) tibble::tibble(sim_year = 1950:1955, label = labels)

test_that("the reference comparison counts as the placement does, and hides below three years", {
  lab <- enso_reference_labels(c("el_nino", "el_nino", "neutral", "el_nino", "la_nina", "mixed"))
  low <- enso_reference_comparison(enso_placement_fixture(), lab, "el_nino")
  expect_equal(unlist(low), c(n = 3, n_adverse = 2, n_all = 6, n_adverse_all = 3)) # ties count as adverse
  high <- enso_reference_comparison(enso_placement_fixture("high"), lab, "el_nino")
  expect_equal(high$n_adverse, 1L)
  expect_equal(high$n_adverse_all, 4L)
  expect_null(enso_reference_comparison(enso_placement_fixture(), lab, "la_nina"))
  expect_null(enso_reference_comparison(enso_placement_fixture(), NULL, "el_nino"))
  p <- enso_placement_fixture()
  p$summary$member_median <- NA_real_
  expect_null(enso_reference_comparison(p, lab, "el_nino"))
})

test_that("the placement text reads the run's system, falls back, and says when it is a later outlook", {
  e <- enso_fixture()
  months <- list(forecast_months = as.Date(c("1953-11-01", "1953-12-01", "1954-01-01")))
  lab <- enso_reference_labels(rep(c("el_nino", "neutral"), 3L))
  run <- list(init = as.Date("1953-10-01"), model_id = "ecmwf_seas51")
  txt <- function(run, labels = lab, enso = e, f = months) {
    enso_placement_text(enso, f, run, enso_placement_fixture(), labels, "Nov - Jan")
  }
  own <- txt(run)
  expect_match(own$line, "^ENSO outlook, Nov - Jan: ")
  expect_match(own$line, "At least as adverse as the median member: 2 of 3 El Ni\u00f1o exposure years, 3 of 6 in all years.",
    fixed = TRUE)
  expect_match(own$info, "Few events fall in a window: 3 of 6 years here.", fixed = TRUE)
  # An unknown model falls back on the multi-model mean
  expect_match(txt(list(init = run$init, model_id = "other"))$line, "(multi-model)", fixed = TRUE)
  # Another initialisation: months from enso.csv, without member shares
  later <- txt(list(init = as.Date("1953-09-01"), model_id = "ecmwf_seas51"))
  expect_match(later$line, "(later outlook, not from this run)", fixed = TRUE)
  expect_no_match(later$line, "members")
  expect_match(txt(NULL)$line, "later outlook", fixed = TRUE)
  # Below three years of the phase: the outlook stays, the comparison goes
  few <- txt(run, enso_reference_labels(rep("neutral", 6L)))
  expect_no_match(few$line, "At least as adverse")
  expect_match(few$info, "^Past events")
  # Nothing covers the target months
  expect_null(txt(run, f = list(forecast_months = as.Date("1990-01-01"))))
})

test_that("the outlook drops member shares at an empty lead and names a value above the record", {
  e <- enso_fixture()
  run <- list(init = e$forecast$init_date[[1L]], model_id = "ecmwf_seas51")
  f <- function(months) list(forecast_months = as.Date(months))
  lab <- enso_reference_labels(rep("el_nino", 6L))
  e$forecast$phase <- "el_nino"
  e$forecast$roni[is.na(e$forecast$roni)] <- 1
  e$observed$roni[[1L]] <- 5 # the record
  full <- e$forecast$month[!is.na(e$forecast$prob_el_nino) & e$forecast$source == "ecmwf_51"]
  shares <- enso_placement_text(e, f(full), run, enso_placement_fixture(), lab, "x")
  expect_match(shares$line, "all members", fixed = TRUE)
  e_some <- e
  e_some$forecast$prob_el_nino[e_some$forecast$prob_el_nino == 1] <- 0.925
  expect_match(
    enso_placement_text(e_some, f(full), run, enso_placement_fixture(), lab, "x")$line, "at least 92% of members",
    fixed = TRUE
  )
  first <- min(e$forecast$month)
  edge <- enso_placement_text(e, f(c(first, full)), run, enso_placement_fixture(), lab, "x")
  expect_no_match(edge$line, "members")
  expect_no_match(shares$line, "stronger than any event")
  e$forecast$roni <- 9
  strong <- enso_placement_text(e, f(full), run, enso_placement_fixture(), lab, "x")
  expect_match(strong$line, "stronger than any event in the record, on this forecast", fixed = TRUE)
  # A forecast month of the observed table is not part of the record
  e$observed$source[nrow(e$observed)] <- "forecast"
  e$observed$roni[nrow(e$observed)] <- 20
  expect_match(enso_placement_text(e, f(full), run, enso_placement_fixture(), lab, "x")$line, "stronger than")
})

test_that("the ENSO phase reaches the card, the full line its popover, and neither the exported note", {
  reference <- 1:20
  placement <- c(.forecast_placement_stats(c(4, 5, 6, 7, 8), reference, "low"),
    list(reference = data.frame(year = 2001:2020, value = reference), method = "mean", adverse_tail = "low"))
  bands <- data.frame(
    scenario = c("Historical", "Forecast (Nov - Jan)"), value = c(10, 6), is_historical = c(TRUE, FALSE),
    lo = c(9, 5), hi = c(11, 7)
  )
  plain <- step2_headline_cards(bands, forecast_placement = placement)
  placement$enso <- list(line = "ENSO outlook line.", short = "ENSO outlook: El Ni\u00f1o", info = "ENSO info.")
  cards <- step2_headline_cards(bands, forecast_placement = placement)
  card <- Filter(function(x) identical(x$label, "Placement in climatology"), cards)[[1L]]
  card0 <- Filter(function(x) identical(x$label, "Placement in climatology"), plain)[[1L]]
  expect_match(as.character(card$note_html), "ENSO outlook: El Ni\u00f1o")
  expect_match(card$info, "ENSO outlook line. ENSO info.", fixed = TRUE)
  expect_identical(card$note, card0$note)
  expect_no_match(as.character(card0$note_html), "ENSO")
  expect_identical(step2_headline_df(cards), step2_headline_df(plain))
})

test_that("trajectory bands shade runs of El Nino and La Nina years only", {
  ts <- data.frame(
    scenario = "Historical", model_id = "m1", sim_year = 2001:2010, is_historical = TRUE,
    value = seq(1, 2, length.out = 10)
  )
  ch <- echart_timeseries_spaghetti(ts, x_label = "Welfare", enso_labels = enso_labels_fixture())
  lines <- Filter(function(s) identical(s$type, "line") && !is.null(s$markArea), ch$x$opts$series)
  expect_length(lines, 1L)
  areas <- lines[[1]]$markArea$data
  expect_length(areas, 2L)
  expect_equal(c(areas[[1]][[1]]$xAxis, areas[[1]][[2]]$xAxis), c(2000.5, 2003.5))
  expect_equal(c(areas[[2]][[1]]$xAxis, areas[[2]][[2]]$xAxis), c(2006.5, 2008.5))
  expect_match(as.character(ch$x$opts$tooltip$formatter), "ENSO exposure", fixed = TRUE)
  # No labels, no bands, same series
  plain <- echart_timeseries_spaghetti(ts, x_label = "Welfare")
  expect_length(Filter(function(s) !is.null(s$markArea), plain$x$opts$series), 0L)
})

# Policy comparison by label (item 4) ----

enso_paired_fixture <- function() {
  d <- expand.grid(model_id = c("a", "b"), sim_year = 2001:2010, scenario = c("Historical / 2001-2010", "SSP3-7.0 / 2025-2035"),
    stringsAsFactors = FALSE)
  d$baseline <- 10 + ifelse(d$model_id == "a", 1, -1) # offsets cancel in the year mean
  d$effect <- ifelse(d$sim_year <= 2003, 3, 1) # a larger effect in El Nino years
  d$policy <- d$baseline + d$effect
  d
}

test_that("the policy table gives baseline, policy and effect by label, one year counted once", {
  out <- enso_policy_table(enso_paired_fixture(), enso_labels_fixture())
  expect_equal(unique(out$series), c("Historical / 2001-2010", "SSP3-7.0 / 2025-2035")) # order of the input
  h <- out[out$series == "Historical / 2001-2010", ]
  expect_equal(h$label, c("el_nino", "neutral", "la_nina", "mixed"))
  expect_equal(h$n, c(3L, 3L, 2L, 2L))
  expect_equal(h$baseline, rep(10, 4))
  expect_equal(h$effect, c(3, 1, 1, 1))
  expect_equal(h$policy, h$baseline + h$effect)
  expect_equal(h$effect_vs_neutral, c(2, NA, NA, NA)) # La Nina has two years: not compared
})

test_that("the policy table leaves out forecast series, unlabelled years and empty phases", {
  d <- enso_paired_fixture()
  d2 <- rbind(d, transform(d, scenario = "Historical (Nov-Jan)"))
  expect_equal(unique(enso_policy_table(d2, enso_labels_fixture())$series), unique(d$scenario))
  # Only El Nino years in the labels: the other phases have no row
  lab <- enso_labels_fixture()
  lab$label[lab$label != "el_nino"] <- NA
  out <- enso_policy_table(d, lab)
  expect_equal(unique(out$label), "el_nino")
  expect_true(all(is.na(out$effect_vs_neutral)))
  expect_null(enso_policy_table(d[0, ], enso_labels_fixture()))
  lab$label <- NA_character_
  expect_null(enso_policy_table(d, lab))
})

test_that("the policy table adds the same-months Historical row of a window, and works on it alone", {
  lab <- enso_labels_fixture()
  w <- data.frame(
    scenario = "Historical (Nov - Jan)", sim_year = 2001:2010, baseline = 5,
    effect = ifelse(2001:2010 <= 2003, 2, 1)
  )
  w$policy <- w$baseline + w$effect
  both <- enso_policy_table(enso_paired_fixture(), lab, window = list(paired = w, labels = lab))
  expect_equal(unique(both$series), c("Historical / 2001-2010", "SSP3-7.0 / 2025-2035", "Historical (Nov - Jan)"))
  alone <- enso_policy_table(NULL, NULL, window = list(paired = w, labels = lab))
  expect_equal(unique(alone$series), "Historical (Nov - Jan)")
  expect_equal(alone$effect_vs_neutral[alone$label == "el_nino"], 1)
  expect_null(enso_policy_table(NULL, NULL))
})

test_that("the policy sentence names the effect in each phase with three years, and needs Neutral", {
  tbl <- enso_policy_table(enso_paired_fixture(), enso_labels_fixture())
  expect_equal(
    enso_policy_sentence(tbl, "Historical / 2001-2010"),
    "In Historical / 2001-2010, the policy changes the outcome by +3.000 in El Ni\u00f1o years (3) and +1.000 in Neutral years (3)."
  )
  expect_match(enso_policy_sentence(tbl, "Historical / 2001-2010", scale = 100, digits = 1), "\\+300.0 in El")
  expect_null(enso_policy_sentence(tbl[tbl$label != "neutral", ], "Historical / 2001-2010"))
})

# Weather support by label (item 6) ----

test_that("support by label counts the values outside the fitted interval in each phase", {
  ref <- data.frame(t = 0:100) # 1% to 99% interval: 1 to 99
  # 2 values per year: one inside, plus one outside (above 99) only in El Nino years 2001 and 2002
  d <- data.frame(
    sim_year = rep(2001:2010, each = 2),
    t = unlist(lapply(2001:2010, function(y) c(50, if (y <= 2002) 150 else 60)))
  )
  out <- weather_support_by_phase(ref, list(Historical = d), "t", enso_labels_fixture())
  en <- out[out$phase == "el_nino", ]
  expect_equal(c(en$n_years, en$n_values, en$outside_share), c(3, 6, 2 / 6))
  expect_false("la_nina" %in% out$phase) # two years: below the minimum of three
  all <- out[out$phase == "all", ]
  expect_equal(c(all$n_years, all$n_values, all$outside_share), c(10, 20, 2 / 20))
  # Lower minimum reports La Nina, with no value outside
  out2 <- weather_support_by_phase(ref, list(Historical = d), "t", enso_labels_fixture(), min_years = 2L)
  expect_equal(out2$outside_share[out2$phase == "la_nina"], 0)
})

test_that("a binned variable is checked on its bins, as the support table does", {
  lv <- c("[0, 10]", "(10, 20]")
  ref <- data.frame(t = factor(c("[0, 10]", "(10, 20]"), levels = lv))
  d <- data.frame(sim_year = 2001:2010, t = factor(rep("[0, 10]", 10), levels = lv))
  d$t <- as.character(d$t)
  d$t[1:3] <- "(20, 30]" # a bin the fitted sample does not contain, in the three El Nino years
  spec <- data.frame(name = "t", cont_binned = "Binned")
  out <- weather_support_by_phase(ref, list(H = d), "t", enso_labels_fixture(), weather_specs = spec)
  expect_equal(out$outside_share[out$phase == "el_nino"], 1)
  expect_true(all(out$is_binned))
  expect_match(enso_support_sentences(out, "Temperature"), "in bins the fitted sample lacks")
})

test_that("support by label tolerates unusable input", {
  lab <- enso_labels_fixture()
  expect_equal(nrow(weather_support_by_phase(NULL, list(H = data.frame()), "t", lab)), 0L)
  expect_equal(nrow(weather_support_by_phase(data.frame(t = 1:10), list(H = data.frame(x = 1)), "t", lab)), 0L)
  expect_equal(nrow(weather_support_by_phase(data.frame(t = 1:10), NULL, "t", lab)), 0L)
})

test_that("support sentences name the series, phases, counts and the all-years share", {
  tbl <- tibble::tibble(
    scenario = c("Historical", "Historical", "Historical"), phase = c("el_nino", "la_nina", "all"),
    n_years = c(4L, 7L, 30L), n_values = c(8L, 14L, 60L), outside_share = c(0.0125, 0.02, 0.0167)
  )
  expect_equal(
    enso_support_sentences(tbl, "Temperature"),
    paste0(
      "Historical, temperature outside the fitted range: 1.2% in El Niño exposure years (4), ",
      "2.0% in La Niña exposure years (7); 1.7% in all years."
    )
  )
  only_all <- tbl[tbl$phase == "all", ]
  expect_identical(enso_support_sentences(only_all, "Temperature"), character(0))
})

test_that("table cells show a sign only on non-zero differences", {
  expect_equal(.enso_fmt(NA_real_), "-")
  expect_equal(.enso_fmt(0.0004, digits = 3, sign = TRUE), "0.000")
  expect_equal(.enso_fmt(-0.0004, digits = 3, sign = TRUE), "0.000")
  expect_equal(.enso_fmt(0.0123, digits = 3, sign = TRUE), "+0.012")
  expect_equal(.enso_fmt(-0.0123, digits = 3, sign = TRUE), "-0.012")
  expect_equal(.enso_fmt(1234.5, digits = 1), "1,234.5")
  expect_equal(.enso_fmt(0.5, scale = 100, digits = 1, sign = TRUE), "+50.0")
})


# Exports and batch (item 8) ----

test_that("provenance names the table version and moves when a table does", {
  e <- enso_fixture()
  p <- enso_provenance(e)
  expect_named(p, c("enso_observed_sha256", "enso_forecast_sha256", "enso_last_cpc_month", "enso_forecast_init_date"))
  expect_match(p$enso_observed_sha256, "^[0-9a-f]{64}$")
  expect_equal(p$enso_forecast_init_date, "1953-10-01")
  changed <- e
  changed$observed$roni[[1L]] <- 9
  expect_false(identical(enso_provenance(changed)$enso_observed_sha256, p$enso_observed_sha256))
  expect_identical(enso_provenance(changed)$enso_forecast_sha256, p$enso_forecast_sha256)
  e$forecast <- NULL
  expect_true(is.na(enso_provenance(e)$enso_forecast_sha256))
  expect_true(is.na(enso_provenance(e)$enso_forecast_init_date))
  e$observed$source <- "era5"
  expect_true(is.na(enso_provenance(e)$enso_last_cpc_month))
  expect_null(enso_provenance(NULL))
})

test_that("the year table stacks the annual and target-month labels", {
  e <- enso_fixture()
  annual <- enso_year_labels(e$observed, 1951:1952, enso_month_weights(1:12), 1L)
  window <- enso_window_labels(e$observed, enso_window_fixture(1951:1952), 1L)
  both <- enso_year_table(annual, window)
  expect_equal(both$sample, rep(c("annual", "target_months"), each = 2L))
  expect_true(all(is.na(both$period[both$sample == "annual"])))
  expect_equal(both$period[both$sample == "target_months"], window$period)
  expect_equal(unique(enso_year_table(annual)$sample), "annual")
})

enso_text_fixture <- function(labels = enso_reference_labels(rep(c("el_nino", "neutral"), 3L))) {
  enso_placement_text(
    enso_fixture(), list(forecast_months = as.Date(c("1953-11-01", "1953-12-01", "1954-01-01"))),
    list(init = as.Date("1953-10-01"), model_id = "ecmwf_seas51"), enso_placement_fixture(), labels, "Nov - Jan"
  )
}

test_that("the outlook table carries the months, the comparison and the card line", {
  text <- enso_text_fixture()
  out <- enso_outlook_table(text)
  expect_equal(nrow(out), 3L)
  expect_equal(unique(out$n_phase_years), 3L)
  expect_equal(unique(out$n_phase_adverse), 2L)
  expect_equal(unique(out$card_line), text$line)
  hidden <- enso_outlook_table(enso_text_fixture(enso_reference_labels(rep("neutral", 6L))))
  expect_true(all(is.na(hidden$n_phase_years)))
  expect_null(enso_outlook_table(NULL))
})

test_that("summary rows give means, differences and the forecast comparison in long form", {
  tbl <- enso_series_table(
    data.frame(scenario = "Historical", sim_year = 2001:2010, value = 1:10), enso_labels_fixture()
  )
  rows <- enso_annual_summary(tbl, "mean")
  expect_true(all(rows$section == "enso"))
  expect_equal(rows$estimate[rows$measure == "mean" & rows$group == "el_nino"], 2)
  expect_equal(rows$n[rows$measure == "mean" & rows$group == "neutral"], 3)
  expect_equal(rows$estimate[rows$measure == "diff_neutral" & rows$group == "el_nino"], -3)
  expect_setequal(rows$group[rows$measure == "diff_neutral"], c("el_nino", "la_nina"))

  text <- enso_text_fixture()
  fc <- enso_forecast_summary(text, "Forecast", "mean", outlook = TRUE)
  expect_equal(fc$text[fc$measure == "card_line"], text$line)
  adverse <- fc[fc$measure == "reference_adverse", ]
  expect_equal(c(adverse$group, adverse$estimate, adverse$n), c("el_nino", "2", "3"))
  expect_equal(fc$estimate[fc$measure == "reference_adverse_all"], 3)
  expect_equal(sum(fc$measure == "outlook_roni"), 3L)
  expect_true(all(is.na(fc$metric[startsWith(fc$measure, "outlook_")])))
  expect_false(any(startsWith(enso_forecast_summary(text, "Forecast", "gini")$measure, "outlook_")))
})

test_that("a batch branch labels the annual and target-month years and skips member rows", {
  e <- enso_fixture()
  years <- 1951:1952
  annual <- rbind(
    data.frame(sim_id = "s", code = "TST", scenario = "Historical", metric = "mean", member = "Historical",
      sim_year = years, value = c(1, 2)),
    data.frame(sim_id = "s", code = "TST", scenario = "Seasonal forecast / x (y run)", metric = "mean",
      member = "m", sim_year = 1953L, value = 3)
  )
  forecast <- data.frame(
    sim_id = "s", code = "TST", scenario = "Seasonal forecast / x (y run)", metric = "mean",
    kind = c("member", "member", "reference", "reference"), id = c("a", "b", "refyear_1951", "refyear_1952"),
    year = c(NA, NA, years), value = c(1, 3, 1, 3)
  )
  branch <- list(ok = TRUE, tables = list(annual = annual, forecast = forecast), enso_inputs = list(
    baseline_months = enso_month_weights(1:12), lags = 1L,
    forecast = list(
      entry = enso_window_fixture(years), run = list(init = as.Date("1953-10-01"), model_id = "ecmwf_seas51"),
      months_label = "Nov - Jan", adverse_tail = c(mean = "low")
    )
  ))
  src <- c(e, list(provenance = enso_provenance(e)))
  out <- wise_batch_enso(src, list(branch, list(ok = FALSE)))
  expect_identical(out$provenance, src$provenance)
  expect_equal(nrow(out$enso_years), 4L)
  expect_equal(unique(out$enso_years$sim_id), "s")
  expect_setequal(out$enso_years$sim_year, years) # 1953 is the forecast anchor, not a label
  expect_true(all(out$summary$section == "enso"))
  expect_true("Historical" %in% out$summary$scenario)
  expect_equal(sum(out$summary$measure == "card_line"), 1L)

  # No tables, and a branch from before this stage
  expect_null(wise_batch_enso(NULL, list(branch)))
  branch$enso_inputs <- NULL
  expect_equal(nrow(wise_batch_enso(src, list(branch))$enso_years), 0L)
})

test_that("a batch branch that fails is left out without failing the run", {
  e <- enso_fixture()
  bad <- list(ok = TRUE, tables = list(annual = "not a table"), enso_inputs = list(lags = 1L))
  expect_no_error(out <- suppressMessages(wise_batch_enso(c(e, list(provenance = list())), list(bad))))
  expect_equal(nrow(out$enso_years), 0L)
})

test_that("review edge cases: factor months, no finite values, negative zero", {
  expect_equal(which(enso_month_weights(factor(c(1, 3, 10))) > 0), c(1L, 3L, 10L))
  labels <- tibble::tibble(sim_year = 2000:2005, label = rep(c("el_nino", "neutral"), 3))
  curves <- data.frame(scenario = "Historical", sim_year = 2000:2005, value = NaN)
  expect_null(enso_series_table(curves, labels))
  expect_null(enso_series_table(NULL, labels))
  expect_identical(.enso_fmt(-0.0001, 1, 0L), "0")
  expect_identical(.enso_fmt(-0.0001, 1, 3L), "0.000")
})

# Forecast marks ----

test_that("forecast members take the outlook phase of the target months as a mark", {
  e <- enso_fixture()
  fc <- list(forecast_months = as.Date(c("1953-11-01", "1953-12-01")))
  marks <- enso_forecast_marks(e, fc, list(init = as.Date("1953-10-01"), model_id = "ecmwf_seas51"), "Nov - Dec")
  expect_identical(marks$phase, "el_nino")
  expect_match(marks$text, "ENSO outlook, Nov - Dec: El Niño (RONI 1.10 to 1.40)", fixed = TRUE)
  expect_null(enso_forecast_marks(e, list(forecast_months = as.Date("1900-01-01")), NULL, "Jan"))

  tbl <- data.frame(
    scenario = c("Historical (Nov - Dec)", "Forecast (Nov - Dec 1953)", "Forecast (Nov - Dec 1953)"),
    sim_year = c(1990L, 1L, 2L), enso_label = c("neutral", NA, NA)
  )
  out <- enso_attach_forecast_labels(tbl, marks, "Forecast (Nov - Dec 1953)")
  expect_identical(out$enso_label, c("neutral", "el_nino", "el_nino"))
  expect_true(is.na(out$enso_text[[1L]]))
  expect_identical(enso_attach_forecast_labels(tbl, NULL, "x"), tbl)

  pts <- .enso_dot_data(cbind(c(1, 2), c(1, 1)), out[2:3, ], "Forecast (Nov - Dec 1953)", "All")
  expect_identical(pts[[1L]]$enso_text, marks$text)
  expect_identical(pts[[1L]]$symbol, "triangle")
})

test_that("the legend names the phases only and the toggle label sits in line", {
  legend <- as.character(enso_legend_ui())
  expect_false(grepl("Marked draws|exposure", legend))
  expect_match(legend, "El Niño")
  toggle <- as.character(enso_mark_toggle_ui(shiny::NS("x")))
  expect_match(toggle, "ENSO phase", fixed = TRUE)
  expect_match(toggle, "display: flex", fixed = TRUE)
})

# Relevance of ENSO to the weather ----

test_that("weather relevance is the median rank correlation over locations", {
  years <- 1991:2010
  lab <- tibble::tibble(sim_year = years, roni_exp = seq(-1, 1, length.out = 20))
  grid <- expand.grid(loc_id = c("a", "b", "c"), cal_year = years, int_month = 1:2, stringsAsFactors = FALSE)
  rank_of <- match(grid$cal_year, years)
  grid$follows <- ifelse(grid$loc_id == "c", -rank_of, rank_of) + grid$int_month # a, b rise; c falls
  grid$flat <- 1
  set.seed(1)
  grid$noise <- stats::rnorm(nrow(grid))
  out <- enso_weather_relevance(grid, lab, c("follows", "flat", "noise", "absent"))
  expect_identical(out$variable, c("follows", "noise"))
  expect_equal(out$rho[[1L]], 1) # median of 1, 1, -1
  expect_equal(out$abs_rho[[1L]], 1)
  expect_identical(out$n_years[[1L]], 20L)
  expect_identical(out$n_locations[[1L]], 3L)
  expect_lt(out$abs_rho[[2L]], 0.5)

  expect_identical(nrow(enso_weather_relevance(grid, lab, "follows", min_years = 25L)), 0L)
  expect_identical(nrow(enso_weather_relevance(grid, NULL, "follows")), 0L)
  expect_identical(nrow(enso_weather_relevance(grid[c("loc_id", "follows")], lab, "follows")), 0L)

  # A binned variable is read from its continuous companion.
  grid$binned <- factor(grid$follows > stats::median(grid$follows))
  grid$binned_cont <- grid$follows
  binned <- enso_weather_relevance(grid, lab, "binned")
  expect_identical(binned$variable, "binned")
  expect_equal(binned$rho, 1)
  expect_identical(nrow(enso_weather_relevance(grid[names(grid) != "binned_cont"], lab, "binned")), 0L)
})

test_that("the relevance sentence grades the correlation and caveats a flat one", {
  tbl <- tibble::tibble(
    variable = c("t", "r"), n_years = 30L, n_locations = c(40L, 38L), rho = c(0.55, -0.1), abs_rho = c(0.55, 0.12)
  )
  s <- enso_relevance_sentences(tbl, c(t = "Temperature", r = "Rainfall"))
  expect_match(s, "Temperature moderately follows ENSO (r = 0.55)", fixed = TRUE)
  expect_match(s, "Rainfall barely follows ENSO (r = -0.10)", fixed = TRUE)
  expect_match(s, "across 30 years, the median over 40 locations", fixed = TRUE)
  expect_false(grepl("whatever the welfare response", s))

  flat <- enso_relevance_sentences(tbl[2L, ], c(r = "Rainfall"))
  expect_match(flat, "small differences between phases are expected whatever the welfare response", fixed = TRUE)
  expect_identical(enso_relevance_sentences(tbl[0L, ]), character(0))
  expect_identical(enso_relevance_sentences(NULL), character(0))
})

# Flyout strip marks ----

test_that("the strip marks come from the record for past months and the outlook for forecast months", {
  e <- enso_fixture()
  run <- list(init = as.Date("1953-10-01"), model_id = "ecmwf_seas51", n_leads = 3L, observed_through = as.Date("1953-09-01"))
  m <- .step2_forecast_months(run)
  marks <- enso_strip_marks(e, m, run)
  expect_true(all(c("value", "phase", "text") %in% names(marks)))
  expect_identical(marks$phase[marks$value == "1953-09"], "neutral")
  expect_match(marks$text[marks$value == "1953-09"], "Neutral, RONI 0.40 (observed, ERA5)", fixed = TRUE)
  expect_identical(marks$phase[marks$value == "1953-11"], "el_nino")
  expect_match(marks$text[marks$value == "1953-11"], "(forecast)", fixed = TRUE)
  expect_null(enso_strip_marks(NULL, m, run))
})

test_that("the strip draws a symbol and tooltip for El Nino and La Nina months, blank for the rest", {
  run <- list(
    id = "r", init = as.Date("2026-10-01"), n_leads = 6L, observed_through = as.Date("2026-09-01"),
    product = "seasonal"
  )
  m <- .step2_forecast_months(run)
  marks <- data.frame(
    value = c("2026-09", "2026-11", "2026-12"), phase = c("neutral", "el_nino", "la_nina"),
    text = c("Neutral, RONI 0.10 (observed, CPC)", "El Niño, RONI 1.20 (forecast)", "La Niña, RONI -0.80 (forecast)"),
    stringsAsFactors = FALSE
  )
  html <- as.character(forecast_strip_input("fc_start", "fc_len", m, "2026-11", enso_marks = marks))
  expect_equal(lengths(regmatches(html, gregexpr('class="fc-enso"', html))), nrow(m))
  expect_match(html, "▲", fixed = TRUE)
  expect_match(html, "◆", fixed = TRUE)
  expect_match(html, "ENSO: El Niño, RONI 1.20 (forecast)", fixed = TRUE)
  expect_match(html, 'title="El Niño, RONI 1.20 (forecast)"', fixed = TRUE)
  expect_no_match(as.character(forecast_strip_input("fc_start", "fc_len", m, "2026-11")), "fc-enso")
  expect_match(as.character(forecast_strip_legend(enso = TRUE)), "La Niña", fixed = TRUE)
  expect_no_match(as.character(forecast_strip_legend()), "Niñ")
})
