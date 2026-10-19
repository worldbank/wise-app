# Fixtures for the batch pipeline tests: in-memory metadata and survey frames,
# and a small on-disk data tree (metadata, microdata, H3 and weather parquet)
# that the batch runner can read like the real data folder.

batch_fixture_variable_list <- function() {
  tibble::tibble(
    name = c("welfare", "hhsize", "urban", "electricity", "ttime_health", "tx", "pr"),
    label = c(
      "Welfare", "Household size", "Urban", "Electricity access", "Travel time to health",
      "Max temperature", "Precipitation"
    ),
    type = c("numeric", "numeric", "binary", "binary", "numeric", "numeric", "numeric"),
    units = c("USD", "n", "", "", "min", "degC", "mm"),
    id = NA_character_,
    outcome = c(1, 0, 0, 0, 0, 0, 0),
    hazard = c(0, 0, 0, 0, 0, 1, 1),
    ind = 0,
    hh = c(0, 1, 1, 1, 0, 0, 0),
    firm = 0,
    area = c(0, 0, 0, 0, 1, 0, 0),
    interact = 0, fe = 0
  ) |>
    dplyr::bind_rows(tibble::tibble(
      name = "year", label = "Year", type = "numeric", units = "", id = NA_character_,
      outcome = 0, hazard = 0, ind = 0, hh = 0, firm = 0, area = 0, interact = 0, fe = 1
    ))
}

batch_fixture_survey_list <- function(codes = "TST", years = c(2018, 2019)) {
  tibble::tibble(
    economy = "Testland", code = rep(codes, each = length(years)),
    year = rep(years, times = length(codes)), survname = "SRV", level = "hh",
    obs = 100, source = "lsms"
  )
}

batch_fixture_cpi_ppp <- function() {
  data.frame(
    code = "TST", year = c(2018, 2019), data_level = "national", cpi = 1, ppp2021 = 1,
    stringsAsFactors = FALSE
  )
}

# A raw survey frame (as read from the parquet files), two waves, with some
# missing values, missing locations and an invalid weight so every sample
# split has rows. Interviews fall in March to May of each year.
batch_fixture_survey <- function(n_per_wave = 60L, years = c(2018, 2019), seed = 11L) {
  withr::with_seed(seed, {
    do.call(rbind, lapply(years, function(y) {
      n <- n_per_wave
      loc <- rep(paste0("loc_", 1:4), length.out = n)
      data.frame(
        code = "TST", economy = "Testland", survname = "SRV", year = as.character(y),
        loc_id = loc,
        timestamp = as.Date(sprintf("%d-%02d-01", y, rep(3:5, length.out = n))),
        weight = round(stats::runif(n, 0.5, 3), 3),
        welfare = round(stats::rlnorm(n, 1.3, 0.8), 3),
        hhsize = sample(1:9, n, replace = TRUE),
        urban = sample(0:1, n, replace = TRUE),
        electricity = sample(0:1, n, replace = TRUE),
        ttime_health = round(stats::runif(n, 0, 90)),
        area_h3_7 = paste0("cell_", rep(1:4, length.out = n)),
        stringsAsFactors = FALSE
      )
    }))
  })
}

# Add the holes to a fixture: missing values, missing locations, bad weights.
batch_fixture_survey_holes <- function(df) {
  at <- function(i) i[i <= nrow(df)]
  df$hhsize[at(c(2, 9, 70))] <- NA
  df$ttime_health[at(c(4, 5, 80))] <- NA
  df$loc_id[at(c(7, 8, 90))] <- NA
  df$area_h3_7[at(c(11, 100))] <- NA
  df$weight[at(c(13, 95))] <- 0
  df$weight[at(17)] <- NA
  df
}

# Prepared survey frame, as the Survey stats tab builds it.
batch_fixture_prepared <- function(holes = TRUE) {
  raw <- batch_fixture_survey()
  if (holes) raw <- batch_fixture_survey_holes(raw)
  prepare_survey_data(raw, batch_fixture_variable_list(), batch_fixture_cpi_ppp())
}

# What get_weather() returns for the fixture: one row per wave x location x
# month, covering the calendar years `cal_years` (survey months and the
# historical comparison). Values depend on location and date only.
batch_fixture_weather <- function(wave_years = c(2018, 2019), cal_years = 2016:2019, seed = 5L) {
  withr::with_seed(seed, {
    base <- expand.grid(
      loc_id = paste0("loc_", 1:4), cal_year = cal_years, month = 3:5,
      stringsAsFactors = FALSE
    )
    base$timestamp <- as.Date(sprintf("%d-%02d-01", base$cal_year, base$month))
    base$tx <- round(stats::rnorm(nrow(base), 30, 3), 2)
    base$pr <- round(stats::runif(nrow(base), 0, 200), 1)
  })
  do.call(rbind, lapply(wave_years, function(y) {
    data.frame(
      code = "TST", year = as.character(y), survname = "SRV", loc_id = base$loc_id,
      timestamp = base$timestamp, tx = base$tx, pr = base$pr, stringsAsFactors = FALSE
    )
  }))
}

# Write the fixture data folder. Needs arrow and the DuckDB h3 extension
# (the weather query joins on H3 cells); the caller skips when unavailable.
batch_fixture_tree <- function(dir, years = c(2018, 2019)) {
  testthat::skip_if_not_installed("arrow")
  testthat::skip_if_not_installed("bit64")
  dir.create(file.path(dir, "metadata"), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(batch_fixture_survey_list(years = years), file.path(dir, "metadata", "survey_list.csv"), row.names = FALSE)
  utils::write.csv(batch_fixture_variable_list(), file.path(dir, "metadata", "variable_list.csv"), row.names = FALSE)
  utils::write.csv(batch_fixture_cpi_ppp(), file.path(dir, "metadata", "cpi_ppp.csv"), row.names = FALSE)

  con <- DBI::dbConnect(duckdb::duckdb(), bigint = "integer64")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  loaded <- tryCatch(
    {
      tryCatch(DBI::dbExecute(con, "LOAD h3"), error = function(e) {
        DBI::dbExecute(con, "INSTALL h3 FROM community; LOAD h3;")
      })
      TRUE
    },
    error = function(e) FALSE
  )
  if (!loaded) testthat::skip("DuckDB h3 extension unavailable")
  parent <- DBI::dbGetQuery(
    con, "SELECT h3_h3_to_string(h3_cell_to_parent(h3_string_to_h3('85283473fffffff'), 4)) AS h3"
  )$h3[[1L]]
  cells <- head(DBI::dbGetQuery(con, sprintf(
    "SELECT h3_h3_to_string(unnest(h3_cell_to_children(h3_string_to_h3('%s'), 5))) AS h3", parent
  ))$h3, 4L)
  ints <- DBI::dbGetQuery(con, sprintf(
    "SELECT h3_string_to_h3(h3) AS h3 FROM (VALUES %s) t(h3)",
    paste0("('", cells, "')", collapse = ", ")
  ))$h3

  loc_ids <- paste0("loc_", 1:4)
  for (y in years) {
    h3_dir <- file.path(dir, "microdata", "h3", "TST")
    dir.create(h3_dir, recursive = TRUE, showWarnings = FALSE)
    arrow::write_parquet(
      data.frame(
        h3 = cells, code = "TST", year = y, survname = "SRV", loc_id = loc_ids,
        pop_2020 = c(100L, 200L, 150L, 50L), stringsAsFactors = FALSE
      ),
      file.path(h3_dir, sprintf("TST_%d_SRV_lsms_h3.parquet", y))
    )
  }
  hh_dir <- file.path(dir, "microdata", "hh", "TST")
  dir.create(hh_dir, recursive = TRUE, showWarnings = FALSE)
  survey <- batch_fixture_survey_holes(batch_fixture_survey(years = years))
  survey$year <- as.numeric(survey$year)
  for (y in years) {
    arrow::write_parquet(
      survey[survey$year == y, ],
      file.path(hh_dir, sprintf("TST_%d_SRV_lsms_hh.parquet", y))
    )
  }
  months <- seq(as.Date(sprintf("%d-01-01", min(years) - 1)), as.Date(sprintf("%d-12-01", max(years) + 1)), by = "month")
  g <- expand.grid(loc = seq_along(cells), timestamp = months)
  withr::with_seed(5L, {
    weather <- data.frame(
      h3 = ints[g$loc], timestamp = g$timestamp,
      tx = round(stats::rnorm(nrow(g), 30, 3), 2),
      pr = round(stats::runif(nrow(g), 0, 200), 1)
    )
  })
  w_dir <- file.path(dir, "hazard", "weather", "historical", "TST")
  dir.create(w_dir, recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(weather, file.path(w_dir, "TST_era5land.parquet"))
  invisible(list(connection_params = build_connection_params("local", path = dir), cells = cells))
}
