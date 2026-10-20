# Step 1 data tables for the batch pipeline: values the app shows equal the
# app builders (and the modules that call them), batch-only statistics equal
# brute-force definitions from the legacy scripts.

# Helpers ----

vstats <- function(df = batch_fixture_prepared(), ...) {
  variable_stats_table(
    df, batch_fixture_variable_list(), outcome = "welfare",
    indicators = wise_default_indicators(), ...
  )
}

row_of <- function(tab, ...) {
  keep <- rep(TRUE, nrow(tab))
  for (nm in names(list(...))) keep <- keep & tab[[nm]] == list(...)[[nm]]
  tab[keep, , drop = FALSE]
}

# Weighted mean and SD with collapse's denominator (sum(w) - 1), written out.
brute_moments <- function(x, w) {
  ok <- is.finite(x) & is.finite(w) & w > 0
  x <- x[ok]
  w <- w[ok]
  m <- sum(w * x) / sum(w)
  c(n = length(x), mean = m, sd = sqrt(sum(w * (x - m)^2) / (sum(w) - 1)), min = min(x), max = max(x))
}

# Module drivers ----

# Run the Survey stats module on the fixture and return its state.
drive_surveystats <- function(raw, expr) {
  testthat::local_mocked_bindings(load_data = function(fnames, ...) {
    if (any(grepl("/h3/", fnames))) stop("no h3 in tests")
    raw
  }, .env = parent.frame())
  vl <- batch_fixture_variable_list()
  ss <- data.frame(
    code = "TST", year = "2018", survname = "SRV", source = "lsms",
    fname = "microdata/hh/TST/TST_2018_SRV_lsms_hh.parquet", stringsAsFactors = FALSE
  )
  shiny::testServer(
    mod_1_02_surveystats_server,
    args = list(
      id = "ss", connection_params = shiny::reactiveVal(list()),
      variable_list = shiny::reactiveVal(vl), selected_surveys = shiny::reactiveVal(ss),
      cpi_ppp = shiny::reactiveVal(batch_fixture_cpi_ppp()), tabset_id = "tabs"
    ),
    {
      session$setInputs(survey_stats = 0L)
      session$setInputs(survey_stats = 1L)
      session$flushReact()
      expr(list(
        survey_data = survey_data(), stats_base = stats_base(),
        interview_summary = interview_summary(),
        build = function(flag) build_stats_table(survey_data, vl, flag, base = stats_base)
      ))
    }
  )
}

# Tests ----

test_that("variable_stats 'all' rows are the app's weighted summary and missingness", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  vars <- c("hhsize", "urban", "electricity", "welfare", "ttime_health")
  ws <- weighted_summary_long(df, vars)
  ms <- survey_missingness_long(df, vars)
  mine <- tab[tab$sample == "all" & tab$var_group %in% c("hh", "outcome", "area") &
    !tab$wave %in% "All", ]
  mine <- mine[!duplicated(mine[c("variable", "wave")]), ]
  app <- merge(ws, ms, by = c("countryyear", "variable"))
  app$wave <- sub(".*, ", "", app$countryyear)
  m <- merge(mine, app, by = c("variable", "wave"))
  expect_identical(nrow(m), nrow(app))
  for (pair in list(
    c("n", "N"), c("mean", "Mean"), c("sd", "Std. Dev."), c("min", "Min"), c("max", "Max"),
    c("unweighted_mean", "unweighted_mean"), c("pct_missing", "% Missing")
  )) {
    expect_identical(as.numeric(m[[paste0(pair[1], ".x")]] %||% m[[pair[1]]]),
      as.numeric(m[[paste0(pair[2], ".y")]] %||% m[[pair[2]]]),
      info = pair[1]
    )
  }
})

test_that("the Survey stats module and variable_stats give identical values", {
  raw <- batch_fixture_survey_holes(batch_fixture_survey(years = 2018))
  drive_surveystats(raw, function(s) {
    tab <- variable_stats_table(
      s$survey_data, batch_fixture_variable_list(), outcome = "welfare",
      indicators = list(), location_samples = FALSE
    )
    for (flag in c("hh", "outcome", "area")) {
      app <- s$build(flag)
      lab <- batch_fixture_variable_list()
      mine <- tab[tab$var_group == flag & tab$sample == "all" & tab$wave == "2018", ]
      mine$Variable <- lab$label[match(mine$variable, lab$name)]
      m <- merge(app, mine, by = "Variable")
      expect_identical(nrow(m), nrow(app), info = flag)
      expect_identical(as.integer(m$N), as.integer(m$n), info = flag)
      for (pair in list(c("Mean", "mean"), c("Std. Dev.", "sd"), c("Min", "min"), c("Max", "max"),
                        c("% Missing", "pct_missing"))) {
        expect_identical(as.numeric(m[[pair[1]]]), as.numeric(m[[pair[2]]]), info = paste(flag, pair[1]))
      }
    }
  })
})

test_that("outcome rows carry the outcome summary's deciles, per wave and pooled", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  osw <- outcome_summary_wide(df, "welfare", "numeric")
  deciles <- paste0("p", seq(10, 90, 10))
  for (wave in c("2018", "2019")) {
    key <- paste("TST", wave, "SRV", sep = "|")
    r <- row_of(tab, variable = "welfare", sample = "all", wave = wave, var_group = "outcome")
    expect_identical(unlist(r[deciles], use.names = FALSE), unname(osw$mat[deciles, key]), info = wave)
    expect_identical(r$mean, unname(osw$mat["mean", key]))
    expect_identical(r$sd, unname(osw$mat["sd", key]))
    expect_identical(r$n_missing, as.integer(osw$mat["n_miss", key]))
  }
  r <- row_of(tab, variable = "welfare", sample = "all", wave = "All", var_group = "outcome")
  expect_identical(unlist(r[deciles], use.names = FALSE), unname(osw$mat[deciles, "all"]))
  expect_identical(r$mean, unname(osw$mat["mean", "all"]))
})

test_that("the outcome's gini equals the pairwise definition and the app's aggregate", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  # Weighted Gini from mean absolute differences, written out.
  brute_gini <- function(x, w) {
    ok <- is.finite(x) & is.finite(w) & w > 0
    x <- x[ok]
    w <- w[ok]
    sum(outer(w, w) * abs(outer(x, x, "-"))) / (2 * sum(w)^2 * (sum(w * x) / sum(w)))
  }
  for (wave in c("2018", "2019")) {
    d <- df[df$year == wave, ]
    r <- row_of(tab, variable = "welfare", sample = "all", wave = wave, var_group = "outcome")
    expect_equal(r$gini, brute_gini(d$welfare, d$weight), info = wave)
    ok <- is.finite(d$welfare) & is.finite(d$weight) & d$weight > 0
    expect_equal(r$gini, resolve_agg_fn("gini")(d$welfare[ok], d$weight[ok], NULL), info = wave)
  }
  r <- row_of(tab, variable = "welfare", sample = "all", wave = "All", var_group = "outcome")
  expect_equal(r$gini, brute_gini(df$welfare, df$weight))
  # Only the outcome carries it.
  expect_true(all(is.na(tab$gini[tab$var_group != "outcome"])))
  expect_false(anyNA(tab$gini[tab$var_group == "outcome" & tab$sample == "all" & tab$variable == "welfare"]))
})

test_that("the Outcome module summary and variable_stats agree", {
  raw <- batch_fixture_survey_holes(batch_fixture_survey(years = 2018))
  vl <- batch_fixture_variable_list()
  df <- prepare_survey_data(raw, vl, batch_fixture_cpi_ppp())
  shiny::testServer(
    mod_1_03_outcome_server,
    args = list(variable_list = shiny::reactiveVal(vl), survey_data = shiny::reactiveVal(df)),
    {
      session$setInputs(outcome = "welfare", outcome_stats_btn = 0L)
      session$setInputs(outcome_stats_btn = 1L)
      session$flushReact()
      s <- outcome_summary()
      tab <- variable_stats_table(df, vl, "welfare", list(), FALSE)
      r <- row_of(tab, variable = "welfare", sample = "all", wave = "2018", var_group = "outcome")
      deciles <- paste0("p", seq(10, 90, 10))
      expect_identical(unlist(r[deciles], use.names = FALSE), unname(s$mat[deciles, "TST|2018|SRV"]))
      expect_identical(r$mean, unname(s$mat["mean", "TST|2018|SRV"]))
    }
  )
})

test_that("location samples split the rows as the legacy definition does", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  has_loc <- !is.na(df$loc_id) & !is.na(df$area_h3_7)
  expect_gt(sum(!has_loc), 0)
  for (wave in c("2018", "2019")) {
    in_wave <- df$year == wave
    for (smp in c("with_loc", "without_loc")) {
      rows <- in_wave & (if (smp == "with_loc") has_loc else !has_loc)
      b <- brute_moments(df$welfare[rows], df$weight[rows])
      r <- row_of(tab, variable = "welfare", sample = smp, wave = wave, var_group = "outcome")
      expect_equal(r$n, unname(b[["n"]]), info = paste(smp, wave))
      expect_equal(r$mean, unname(b[["mean"]]), tolerance = 1e-10)
      expect_equal(r$sd, unname(b[["sd"]]), tolerance = 1e-10)
      expect_equal(r$min, unname(b[["min"]]))
      expect_equal(r$n_rows, sum(rows))
    }
  }
  # The two location samples partition the 'all' sample.
  a <- row_of(tab, variable = "hhsize", sample = "all", wave = "All", var_group = "hh")
  w <- row_of(tab, variable = "hhsize", sample = "with_loc", wave = "All", var_group = "hh")
  o <- row_of(tab, variable = "hhsize", sample = "without_loc", wave = "All", var_group = "hh")
  expect_identical(a$n_rows, w$n_rows + o$n_rows)
  expect_identical(a$n_missing, w$n_missing + o$n_missing)
})

test_that("within-location values are deviations from the location mean over all waves", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  has_loc <- !is.na(df$loc_id) & !is.na(df$area_h3_7)
  d <- df[has_loc, ]
  ok <- is.finite(d$ttime_health) & d$weight > 0 & is.finite(d$weight)
  dm <- rep(NA_real_, nrow(d))
  for (loc in unique(d$loc_id)) {
    i <- which(d$loc_id == loc & ok)
    dm[i] <- d$ttime_health[i] - sum(d$weight[i] * d$ttime_health[i]) / sum(d$weight[i])
  }
  for (wave in c("2018", "2019", "All")) {
    rows <- if (wave == "All") rep(TRUE, nrow(d)) else d$year == wave
    b <- brute_moments(dm[rows], d$weight[rows])
    r <- row_of(tab, variable = "ttime_health", sample = "within_loc", wave = wave, var_group = "area")
    expect_equal(r$mean, unname(b[["mean"]]), tolerance = 1e-9, info = wave)
    expect_equal(r$sd, unname(b[["sd"]]), tolerance = 1e-9, info = wave)
    expect_equal(r$n, unname(b[["n"]]), info = wave)
  }
  # Within-location rows hold the mean and SD only.
  w <- tab[tab$sample == "within_loc", ]
  expect_true(all(is.na(w$p50)) && all(is.na(w$n_unique)) && all(is.na(w$pct_missing)))
})

test_that("indicator variables are weighted shares with the legacy thresholds", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  ind <- tab[tab$var_group == "indicator", ]
  expect_setequal(unique(ind$variable), names(wise_default_indicators()))
  for (wave in c("2018", "2019")) {
    d <- df[df$year == wave, ]
    for (thr in c(15, 30, 45, 60)) {
      ok <- !is.na(d$ttime_health) & d$weight > 0 & is.finite(d$weight)
      share <- sum(d$weight[ok & d$ttime_health > thr]) / sum(d$weight[ok])
      r <- row_of(tab, variable = paste0("ttime_health_gt", thr), sample = "all", wave = wave)
      expect_equal(r$mean, share, tolerance = 1e-12, info = paste(thr, wave))
      expect_equal(r$share_one, share, tolerance = 1e-12)
    }
    ok <- d$weight > 0 & is.finite(d$weight)
    r <- row_of(tab, variable = "poor420", sample = "all", wave = wave)
    expect_equal(r$mean, sum(d$weight[ok & d$welfare < 4.2]) / sum(d$weight[ok]), tolerance = 1e-12)
  }
  # No indicators requested: no indicator rows.
  expect_false("indicator" %in% variable_stats_table(
    df, batch_fixture_variable_list(), "welfare", list(), TRUE
  )$var_group)
  # A missing source variable skips its indicator.
  few <- variable_stats_table(
    df[setdiff(names(df), "ttime_health")], batch_fixture_variable_list(), "welfare",
    wise_default_indicators(), TRUE
  )
  expect_false(any(grepl("ttime_health_gt", few$variable)))
})

test_that("distinct values, binary share and location sample switch", {
  df <- batch_fixture_prepared()
  tab <- vstats(df)
  r <- row_of(tab, variable = "urban", sample = "all", wave = "2018", var_group = "hh")
  expect_identical(r$n_unique, 2L)
  expect_equal(r$share_one, r$mean)
  expect_true(is.na(row_of(tab, variable = "hhsize", sample = "all", wave = "2018", var_group = "hh")$share_one))
  none <- vstats(df, location_samples = FALSE)
  expect_identical(unique(none$sample), "all")
  # Every group of variables is present, and a variable can sit in two groups.
  expect_true(all(c("outcome", "hh", "area", "indicator", "policy") %in% tab$var_group))
  e <- tab[tab$variable == "electricity" & tab$sample == "all" & tab$wave == "2018", "var_group"]
  expect_setequal(e, c("hh", "policy"))
})

test_that("two countries add a pooled scope with the combined code", {
  a <- batch_fixture_prepared(holes = FALSE)
  b <- a
  b$code <- "OTH"
  b$economy <- "Otherland"
  b$countryyear <- paste0(b$economy, ", ", b$year)
  tab <- variable_stats_table(rbind(a, b), batch_fixture_variable_list(), "welfare", list(), FALSE)
  expect_setequal(unique(tab$code), c("TST", "OTH", "OTH+TST"))
  pooled <- row_of(tab, variable = "welfare", wave = "All", code = "OTH+TST", sample = "all")
  expect_identical(pooled$n, 2L * row_of(tab, variable = "welfare", wave = "All", code = "TST", sample = "all")$n)
  expect_identical(
    unlist(row_of(tab, variable = "welfare", wave = "All", code = "OTH+TST", sample = "all")[paste0("p", c(10, 50, 90))]),
    unlist(outcome_summary_wide(rbind(a, b), "welfare", "numeric")$mat[c("p10", "p50", "p90"), "all"]),
    ignore_attr = TRUE
  )
})

test_that("interview dates match the module's monthly counts and the date summary", {
  raw <- batch_fixture_survey_holes(batch_fixture_survey(years = 2018))
  drive_surveystats(raw, function(s) {
    tab <- interview_dates_table(s$survey_data)
    months <- tab[!is.na(tab$month), ]
    app <- s$interview_summary
    expect_identical(as.integer(months$month), as.integer(app$month_num))
    expect_identical(as.integer(months$n), as.integer(app$hh))
  })
  df <- batch_fixture_prepared()
  tab <- interview_dates_table(df)
  tot <- tab[is.na(tab$month), ]
  expect_identical(nrow(tot), 2L)
  for (wave in c("2018", "2019")) {
    d <- df[df$year == wave & !is.na(df$timestamp), ]
    r <- tot[tot$wave == wave, ]
    expect_identical(r$n, nrow(d))
    expect_identical(r$n_dates, length(unique(d$timestamp)))
    expect_identical(r$first_date, min(d$timestamp))
    expect_identical(r$last_date, max(d$timestamp))
    has <- !is.na(d$loc_id) & !is.na(d$area_h3_7)
    per_loc <- vapply(unique(d$loc_id[has]), function(l) length(unique(d$timestamp[has & d$loc_id == l])), 1L)
    expect_equal(r$avg_dates_per_loc, mean(per_loc))
    # Locations of the wave: distinct loc_id of the records that have one,
    # dated or not.
    w <- df[df$year == wave & !is.na(df$loc_id) & !is.na(df$area_h3_7), ]
    expect_identical(r$n_locations, length(unique(w$loc_id)))
  }
  expect_true(all(is.na(tab$n_locations[!is.na(tab$month)])))
  expect_identical(sum(tab$n[!is.na(tab$month)]), sum(tot$n))
})

# Weather ----

wx_selected <- function(var = "tx", form = "Continuous") {
  swr <- wise_selected_weather(
    list(tx = list(form = form), hist_years = c(2017L, 2019L))[c(var, "hist_years")],
    batch_fixture_variable_list()
  )
  swr
}

mock_get_weather <- function(.env = parent.frame()) {
  testthat::local_mocked_bindings(
    get_weather = function(survey_data, selected_surveys, selected_weather, dates, ...) {
      list(historical = batch_fixture_weather())
    },
    .env = .env
  )
}

test_that("the weather glue merges onto the survey and keeps the historical cells", {
  mock_get_weather()
  df <- batch_fixture_prepared()
  hy <- c(from = 2017L, to = 2019L)
  w <- wise_load_weather(df, data.frame(), wx_selected(), hy, list(), 1L)
  expect_identical(
    w$survey_weather,
    merge_survey_weather(df, batch_fixture_weather())
  )
  expect_s3_class(w$survey_weather$year, "factor")
  expect_identical(
    w$hist_cells,
    join_hist_sample_cells(batch_fixture_weather(), w$survey_weather)
  )
  expect_null(w$survey_weather_cont)
})

test_that("the Weather module and the core loader build the same frames", {
  mock_get_weather()
  df <- batch_fixture_prepared()
  sw <- wx_selected()
  core <- wise_load_weather(df, data.frame(), sw, c(from = 2017L, to = 2019L), list(type = "local"), 7L)
  shiny::testServer(
    mod_1_05_weatherstats_server,
    args = list(
      connection_params = shiny::reactive(list(type = "local", path = ".")),
      variable_list = shiny::reactive(NULL),
      selected_surveys = shiny::reactive(data.frame()),
      selected_outcome = shiny::reactive(NULL),
      selected_weather = shiny::reactive(sw),
      hist_years = shiny::reactive(c(from = 2017L, to = 2019L)),
      survey_data = shiny::reactiveVal(df),
      cell_data = shiny::reactive(NULL),
      survey_version = shiny::reactiveVal(1L),
      tabset_id = "tabs"
    ),
    {
      session$setInputs(weather_stats = 0L)
      session$setInputs(weather_stats = 1L)
      session$flushReact()
      expect_identical(survey_weather(), core$survey_weather)
      expect_identical(hist_cells(), core$hist_cells)
      app <- build_weather_stats_table(survey_weather, wx_spec_sw, survey_data)
      tab <- weather_stats_table(core$survey_weather, sw[1, ], df, core$hist_cells, c(from = 2017L, to = 2019L))
      mine <- tab[tab$source == "survey" & tab$sample == "all" & tab$wave != "All", ]
      m <- merge(app, mine, by.x = "Country, Year", by.y = "wave", all = FALSE)
      app$wave <- sub(".*, ", "", app$`Country, Year`)
      m <- merge(app, mine, by = "wave")
      expect_identical(nrow(m), 2L)
      for (pair in list(c("Mean", "mean"), c("Std. Dev.", "sd"), c("Min", "min"), c("Max", "max"),
                        c("% Missing", "pct_missing"))) {
        expect_identical(as.numeric(m[[pair[1]]]), as.numeric(m[[pair[2]]]), info = pair[1])
      }
      expect_identical(as.integer(m$N), as.integer(m$n))
    }
  )
})

test_that("weather statistics: batch-only rows follow their brute-force definitions", {
  mock_get_weather()
  df <- batch_fixture_prepared()
  sw <- wx_selected()
  hy <- c(from = 2017L, to = 2019L)
  core <- wise_load_weather(df, data.frame(), sw, hy, list(), 1L)
  tab <- weather_stats_table(core$survey_weather, sw[1, ], df, core$hist_cells, hy)
  expect_setequal(unique(tab$source), c("survey", "historical"))
  expect_setequal(unique(tab$sample), c("all", "within_loc"))

  swd <- core$survey_weather
  # Survey deciles use the outcome summary's rule.
  osw <- outcome_summary_wide(transform(swd, v = tx), "v", "numeric")
  r <- row_of(tab, source = "survey", sample = "all", wave = "2018")
  deciles <- paste0("p", seq(10, 90, 10))
  expect_identical(unlist(r[deciles], use.names = FALSE), unname(osw$mat[deciles, "TST|2018|SRV"]))

  # Distinct values per location, over the rows with a location.
  has <- !is.na(swd$loc_id) & !is.na(swd$area_h3_7)
  d <- swd[swd$year == "2018" & has, ]
  per_loc <- vapply(unique(d$loc_id), function(l) length(unique(d$tx[d$loc_id == l])), 1L)
  expect_equal(r$n_unique_per_loc, mean(per_loc))
  expect_identical(r$n_unique, length(unique(swd$tx[swd$year == "2018"])))

  # Within-location: deviation from the location mean over both waves, among
  # the rows with a location.
  dm <- rep(NA_real_, nrow(swd))
  for (l in unique(swd$loc_id[has])) {
    i <- which(swd$loc_id == l & has & swd$weight > 0 & is.finite(swd$weight))
    dm[i] <- swd$tx[i] - sum(swd$weight[i] * swd$tx[i]) / sum(swd$weight[i])
  }
  b <- brute_moments(dm[swd$year == "2018"], swd$weight[swd$year == "2018"])
  rw <- row_of(tab, source = "survey", sample = "within_loc", wave = "2018")
  expect_equal(rw$mean, unname(b[["mean"]]), tolerance = 1e-9)
  expect_equal(rw$sd, unname(b[["sd"]]), tolerance = 1e-9)

  # Historical rows: cells in the comparison years, weighted by households.
  h <- core$hist_cells
  h <- h[h$cal_year >= 2017 & h$cal_year <= 2019 & h$year == "2018", ]
  bh <- brute_moments(h$tx, h$n_hh)
  rh <- row_of(tab, source = "historical", sample = "all", wave = "2018")
  expect_equal(rh$mean, unname(bh[["mean"]]), tolerance = 1e-10)
  expect_equal(rh$sd, unname(bh[["sd"]]), tolerance = 1e-10)
  expect_identical(rh$n, as.integer(bh[["n"]]))
  expect_true(is.na(rh$pct_missing))
  expect_true(all(c("All") %in% tab$wave))

  # Rows outside the comparison years are excluded.
  narrow <- weather_stats_table(core$survey_weather, sw[1, ], df, core$hist_cells, c(from = 2019L, to = 2019L))
  expect_lt(row_of(narrow, source = "historical", sample = "all", wave = "2018")$n, rh$n)
  # No location samples: no within-location rows.
  nl <- weather_stats_table(core$survey_weather, sw[1, ], df, core$hist_cells, hy, location_samples = FALSE)
  expect_identical(unique(nl$sample), "all")
})
