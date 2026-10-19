# Batch run spec: defaults, validation, hashing, resolution, YAML grid and
# app configuration import (review/batch_pipeline_plan.md, layer L1).

fixture_metadata <- function() {
  list(
    survey_list = tibble::tibble(
      economy = c("Burkina Faso", "Burkina Faso", "Malawi", "Malawi", "Malawi"),
      code = c("BFA", "BFA", "MWI", "MWI", "MWI"),
      year = c(2018, 2021, 2016, 2019, 2022),
      survname = "EHCVM", level = "hh", obs = 100, source = "GMD"
    ),
    variable_list = tibble::tibble(
      name = c("tx", "pr", "welfare", "hhsize"),
      label = c("Temperature", "Rainfall", "Welfare", "Household size"),
      type = c("numeric", "numeric", "numeric", "numeric"),
      units = c("degC", "mm", "USD", "n"),
      outcome = c(0, 0, 1, 0), hazard = c(1, 1, 0, 0),
      ind = 0, hh = c(0, 0, 0, 1), firm = 0, area = 0
    )
  )
}
remote_cp <- function() list(type = "hf")

test_that("an omitted setting and the stated app default are the same spec", {
  a <- wise_spec(weather = list(tx = list()))
  b <- wise_spec(
    sample = list(unit = "hh"),
    outcome = list(currency = "PPP"),
    weather = list(tx = list(
      ref_period = c(1, 1), form = "binned", n_bins = 5,
      binning_method = "equal frequency"
    ), hist_years = c(1991, 2020)),
    seed = 123
  )
  expect_identical(a, b)
  expect_identical(wise_spec_ids(a)$run_id, wise_spec_ids(b)$run_id)
  d <- wise_spec_defaults()
  expect_identical(a$seed, WISEAPP_DEFAULT_SEED)
  expect_identical(a$sample$unit, d$sample$unit)
  expect_identical(a$weather$hist_years, d$weather$hist_years)
})

test_that("the weather module reads its initial values from the spec defaults", {
  d <- wise_weather_var_defaults("degC")
  expect_identical(d$ref_period, c(1L, 1L))
  expect_identical(d$form, "Binned")
  expect_identical(d$n_bins, 5L)
  expect_identical(d$binning_method, "Equal frequency")
  expect_identical(d$temporal_agg, temporal_agg_default("degC"))
  shiny::testServer(
    mod_1_04_weather_server,
    args = list(id = "w", variable_list = shiny::reactiveVal(fixture_metadata()$variable_list)),
    {
      expect_identical(hist_years(), c(from = 1991L, to = 2020L))
    }
  )
  expect_identical(
    wise_spec_defaults()$weather$hist_years, c(1991L, 2020L)
  )
})

test_that("Continuous and Binned entries drop the fields that do not apply", {
  cont <- wise_spec(weather = list(tx = list(form = "Continuous", n_bins = 8, polynomial = "2")))
  expect_null(cont$weather$tx$n_bins)
  expect_identical(cont$weather$tx$polynomial, "2")
  binned <- wise_spec(weather = list(tx = list(n_bins = 8, polynomial = "2")))
  expect_null(binned$weather$tx$polynomial)
  expect_null(binned$weather$tx$custom_breaks)
  custom <- wise_spec(weather = list(tx = list(binning_method = "Custom", custom_breaks = "20, 25, 30")))
  expect_identical(custom$weather$tx$custom_breaks, c(20, 25, 30))
})

test_that("validation lists every problem and follows the app's limits", {
  err <- tryCatch(
    wise_spec(
      sample = list(unit = "village", countries = c("A", "B", "C")),
      outcome = list(currency = "EUR"),
      weather = list(
        tx = list(ref_period = c(5, 2), n_bins = 20),
        pr = list(), x3 = list(), hist_years = c(2020, 1991)
      )
    ),
    error = identity
  )
  expect_s3_class(err, "wise_spec_error")
  msg <- conditionMessage(err)
  expect_match(msg, "sample.unit")
  expect_match(msg, "at most two|one or two")
  expect_match(msg, "outcome.currency")
  expect_match(msg, "weather.tx.ref_period")
  expect_match(msg, "weather.tx.n_bins")
  expect_match(msg, "at most two variables")
  expect_match(msg, "hist_years")
  expect_error(wise_spec(model = list(engine = "fixest")), "Unknown spec section")
  expect_error(wise_spec(weather = list(tx = list(form = "Binned", binning_method = "Custom"))), "custom_breaks")
  expect_error(
    wise_spec(stats = list(indicators = list(bad = list(variable = "x", operator = "=", threshold = 1)))),
    "operator"
  )
})

test_that("stage ids are stable and depend only on their sections", {
  s <- wise_spec(
    sample = list(countries = c("MWI", "BFA"), years = list(BFA = c(2021, 2018))),
    weather = list(tx = list(ref_period = c(1, 3)), pr = list(form = "Continuous"))
  )
  ids <- wise_spec_ids(s)
  # Pinned: a change here means every stored table id changes.
  expect_identical(ids$data_id, wise_spec_ids(s)$data_id)
  expect_named(ids$wxvar_ids, c("pr", "tx"))
  expect_match(ids$data_id, "^[0-9a-f]{12}$")

  # Order of countries, years and list names does not matter.
  s2 <- wise_spec(
    sample = list(countries = c("BFA", "MWI"), years = list(BFA = c(2018, 2021))),
    weather = list(pr = list(form = "Continuous"), tx = list(ref_period = c(1L, 3L)))
  )
  expect_identical(wise_spec_ids(s2), ids)

  # Seed and weather changes leave the data id alone; weather changes only the
  # variable that changed; the seed changes the run id only.
  seeded <- wise_spec_ids(wise_spec(
    sample = list(countries = c("BFA", "MWI"), years = list(BFA = c(2018, 2021))),
    weather = list(pr = list(form = "Continuous"), tx = list(ref_period = c(1, 3))), seed = 7
  ))
  expect_identical(seeded$data_id, ids$data_id)
  expect_identical(seeded$wxvar_ids, ids$wxvar_ids)
  expect_false(identical(seeded$run_id, ids$run_id))
  s3 <- s
  s3$weather$tx$ref_period <- c(1L, 6L)
  i3 <- wise_spec_ids(s3)
  expect_identical(i3$data_id, ids$data_id)
  expect_identical(i3$wxvar_ids[["pr"]], ids$wxvar_ids[["pr"]])
  expect_false(identical(i3$wxvar_ids[["tx"]], ids$wxvar_ids[["tx"]]))
  s4 <- s
  s4$weather$hist_years <- c(1981L, 2010L)
  expect_false(any(wise_spec_ids(s4)$wxvar_ids %in% ids$wxvar_ids))
  s5 <- s
  s5$outcome$currency <- "LCU"
  expect_false(identical(wise_spec_ids(s5)$data_id, ids$data_id))

  # Binning does not change the pre-binning values, so profiles that bin a
  # variable differently share its weather statistics.
  cont <- wise_spec(weather = list(tx = list(form = "Continuous")))
  bins <- wise_spec(weather = list(tx = list(form = "Binned", n_bins = 8, binning_method = "K-means")))
  expect_identical(wise_spec_ids(cont)$wxvar_ids, wise_spec_ids(bins)$wxvar_ids)
  expect_false(identical(wise_spec_ids(cont)$run_id, wise_spec_ids(bins)$run_id))
  agg <- wise_spec(weather = list(tx = list(temporal_agg = "Max")))
  expect_false(identical(wise_spec_ids(agg)$wxvar_ids, wise_spec_ids(bins)$wxvar_ids))
})

test_that("a pinned spec keeps its hash across releases", {
  s <- wise_spec(
    sample = list(countries = "BFA", years = list(BFA = c(2018, 2021))),
    outcome = list(name = "welfare"),
    weather = list(tx = list(temporal_agg = "Mean", transformation = "None"))
  )
  expect_identical(wise_spec_ids(s)$data_id, "557e7a24c5cc")
})

test_that("resolution fills data-dependent defaults and checks them", {
  md <- fixture_metadata()
  r <- wise_spec_resolve(wise_spec(), md, remote_cp())
  expect_identical(r$sample$countries, "BFA")
  expect_identical(r$sample$years, list(BFA = c(2018L, 2021L)))
  expect_identical(names(r$weather), c("tx", "hist_years"))
  expect_identical(r$weather$tx$temporal_agg, "Mean")
  expect_identical(r$weather$tx$transformation, "None")

  pr <- wise_spec_resolve(wise_spec(weather = list(pr = list())), md, remote_cp())
  expect_identical(pr$weather$pr$temporal_agg, "Sum")

  mw <- wise_spec_resolve(wise_spec(sample = list(countries = "MWI", years = list(MWI = 2019))), md, remote_cp())
  expect_identical(mw$sample$years, list(MWI = 2019L))
  # Resolving twice changes nothing.
  expect_identical(wise_spec_resolve(r, md, remote_cp()), r)

  expect_error(wise_spec_resolve(wise_spec(sample = list(countries = "XXX")), md, remote_cp()), "XXX")
  expect_error(
    wise_spec_resolve(wise_spec(sample = list(countries = "BFA", years = list(BFA = 1999))), md, remote_cp()),
    "1999"
  )
  expect_error(wise_spec_resolve(wise_spec(weather = list(nope = list())), md, remote_cp()), "nope")
  expect_error(
    wise_spec_resolve(wise_spec(weather = list(tx = list(temporal_agg = "Sum"))), md, remote_cp()),
    "temporal_agg"
  )
})

test_that("spec JSON round-trips to the same spec", {
  s <- wise_spec(
    sample = list(countries = "BFA", years = list(BFA = c(2018, 2021))),
    weather = list(tx = list(form = "Continuous", polynomial = c("2", "3")))
  )
  f <- withr::local_tempfile(fileext = ".json")
  wise_spec_write(s, f)
  expect_identical(wise_spec_read(f), s)
})

test_that("a YAML grid expands by crossing, zipping and excluding", {
  skip_if_not_installed("yaml")
  grid <- list(
    seed = 5,
    outcome = list(name = "welfare"),
    profiles = list(weather = list(
      t3 = list(tx = list(ref_period = c(1, 3), form = "Continuous")),
      t12 = list(tx = list(ref_period = c(1, 12), form = "Continuous")),
      both = list(tx = list(form = "Continuous"), pr = list(form = "Continuous"))
    )),
    axes = list(
      country = c("BFA", "MWI"),
      weather = c("t3", "t12", "both"),
      seed = c(1, 2)
    ),
    exclude = list(list(country = "MWI", weather = "both"))
  )
  g <- wise_spec_expand(grid)
  expect_s3_class(g, "tbl_df")
  # 2 x 3 x 2 = 12, minus the 2 excluded
  expect_identical(nrow(g), 10L)
  expect_false(any(g$country == "MWI" & g$weather == "both"))
  expect_identical(anyDuplicated(g$run_id), 0L)
  expect_false(any(g$resolved))
  # Six weather x country data sets share three data ids per country: two ids.
  expect_identical(length(unique(g$data_id)), 2L)
  # t3 and t12 give different wxvar ids; the seed axis leaves them alone.
  tx <- vapply(g$wxvar_ids, function(x) x[["tx"]], "")
  expect_identical(length(unique(tx[g$country == "BFA" & g$weather %in% c("t3", "t12")])), 2L)
  expect_identical(g$spec[[1]]$outcome$name, "welfare")

  zipped <- wise_spec_expand(list(
    axes = list(country = c("BFA", "MWI"), seed = c(1, 2), unit = c("hh", "ind")),
    zip = list(c("country", "seed"))
  ))
  expect_identical(nrow(zipped), 4L)
  expect_identical(zipped$seed[zipped$country == "MWI" & zipped$unit == "hh"], "2")

  # A two-economy sample is one axis value.
  pooled <- wise_spec_expand(list(axes = list(country = list(c("BFA", "MWI"), "BFA"))))
  expect_identical(pooled$country, c("BFA+MWI", "BFA"))
  expect_identical(pooled$spec[[1]]$sample$countries, c("BFA", "MWI"))

  expect_error(wise_spec_expand(list(axes = list(model = c("a", "b")))), "later phase")
  expect_error(wise_spec_expand(list(model = list())), "later phase")
  expect_error(wise_spec_expand(list(axes = list(country = "BFA", bogus = 1))), "Unknown axis")
  expect_error(
    wise_spec_expand(list(axes = list(country = "BFA"), exclude = list(list(nope = 1)))),
    "unknown axes"
  )
  expect_warning(
    d <- wise_spec_expand(list(axes = list(country = c("BFA", "BFA")))),
    "dropped"
  )
  expect_identical(nrow(d), 1L)
})

test_that("grid expansion resolves against the data when metadata is given", {
  g <- wise_spec_expand(
    list(axes = list(country = c("BFA", "MWI"))),
    connection_params = remote_cp(), metadata = fixture_metadata()
  )
  expect_true(all(g$resolved))
  expect_identical(g$spec[[2]]$sample$years, list(MWI = c(2016L, 2019L, 2022L)))
  # Ids of a resolved grid equal the ids of the explicit spec.
  explicit <- wise_spec(sample = list(countries = "BFA", years = list(BFA = c(2018, 2021))))
  explicit <- wise_spec_resolve(explicit, fixture_metadata(), remote_cp())
  expect_identical(g$run_id[1], wise_spec_ids(explicit)$run_id)
})

test_that("a YAML file is read, with a config JSON as base", {
  skip_if_not_installed("yaml")
  dir <- withr::local_tempdir()
  cfg <- list(
    wiseapp_config_version = 1L, random_seed = 9L,
    inputs = list(
      `step1-sample-unit` = "hh", `step1-sample-economy` = "BFA",
      `step1-sample-year_BFA` = c(2018, 2021),
      `step1-weather-weather_variable_selector` = "tx",
      `step1-weather-tx_relativePeriod` = c(1, 6), `step1-weather-tx_contOrBinned` = "Continuous"
    )
  )
  jsonlite::write_json(cfg, file.path(dir, "base.json"), auto_unbox = TRUE)
  writeLines(c(
    "base: base.json",
    "axes:",
    "  country: [BFA, MWI]"
  ), file.path(dir, "grid.yaml"))
  g <- wise_spec_expand(file.path(dir, "grid.yaml"))
  expect_identical(nrow(g), 2L)
  expect_identical(g$spec[[1]]$seed, 9L)
  expect_identical(g$spec[[1]]$weather$tx$ref_period, c(1L, 6L))
  expect_identical(g$spec[[1]]$weather$tx$form, "Continuous")
})

test_that("an app configuration export becomes a spec", {
  cfg <- list(
    wiseapp_config_version = 1L, random_seed = 42L, app_version = "0.3.0",
    inputs = list(
      `step1-sample-unit` = "ind",
      `step1-sample-economy` = c("BFA", "MWI"),
      `step1-sample-year_BFA` = c(2018, 2021), `step1-sample-year_MWI` = 2019,
      `step1-outcome-outcome` = "poor", `step1-outcome-currency` = "PPP",
      `step1-outcome-poverty_line` = 4.2,
      `step1-weather-weather_variable_selector` = c("tx", "pr"),
      `step1-weather-tx_relativePeriod` = c(1, 3), `step1-weather-tx_temporalAgg` = "Max",
      `step1-weather-tx_varConstruction` = "Deviation from mean",
      `step1-weather-tx_contOrBinned` = "Binned", `step1-weather-tx_numBins` = 8,
      `step1-weather-tx_binningMethod` = "K-means",
      `step1-weather-pr_contOrBinned` = "Continuous", `step1-weather-pr_polynomial` = "2",
      `step1-weather-hist_years` = c(1981, 2010),
      `step1-model-model_type` = "Linear regression"
    )
  )
  s <- wise_spec_from_config(cfg)
  expect_identical(s$seed, 42L)
  expect_identical(s$sample$unit, "ind")
  expect_identical(s$sample$countries, c("BFA", "MWI"))
  expect_identical(s$sample$years, list(BFA = c(2018L, 2021L), MWI = 2019L))
  expect_identical(s$outcome$name, "poor")
  expect_identical(s$outcome$poverty_line, 4.2)
  expect_identical(s$weather$tx$n_bins, 8L)
  expect_identical(s$weather$tx$binning_method, "K-means")
  expect_identical(s$weather$tx$transformation, "Deviation from mean")
  expect_identical(s$weather$pr$polynomial, "2")
  expect_identical(s$weather$hist_years, c(1981L, 2010L))

  bad <- cfg
  bad$wiseapp_config_version <- 2L
  expect_error(wise_spec_from_config(bad), "configuration version")
  expect_error(wise_spec_from_config(list(inputs = list(a = 1))), "wiseapp_config_version")

  f <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(cfg, f, auto_unbox = TRUE)
  expect_identical(wise_spec_from_config(f), s)
})

test_that("the configuration input ids still exist in the module controls", {
  # Renaming a control in a module must break this test, not drop a setting.
  src <- function(f) paste(readLines(testthat::test_path("..", "..", "R", f)), collapse = "\n")
  skip_if(!file.exists(testthat::test_path("..", "..", "R", "mod_1_01_sample.R")))
  s1 <- src("mod_1_01_sample.R")
  for (id in c("unit", "economy")) expect_match(s1, paste0('ns("', id, '")'), fixed = TRUE)
  expect_match(s1, 'paste0("year_", code)', fixed = TRUE)
  s3 <- src("mod_1_03_outcome.R")
  for (id in c("outcome", "currency", "poverty_line")) expect_match(s3, paste0('ns("', id, '")'), fixed = TRUE)
  s4 <- src("mod_1_04_weather.R")
  expect_match(s4, 'ns("weather_variable_selector")', fixed = TRUE)
  expect_match(s4, 'ns("hist_years")', fixed = TRUE)
  for (key in unname(.WX_INPUT_KEYS)) {
    expect_match(s4, paste0('"', key, '"'), fixed = TRUE)
  }
  prefixes <- c("step1-sample-", "step1-outcome-", "step1-weather-")
  expect_identical(unname(.CONFIG_PREFIX), prefixes)
  app <- src("app_server.R")
  expect_match(app, 'mod_1_modelling_server\\(\\s+id = "step1"')
  mod <- src("mod_1_modelling.R")
  for (m in c("sample", "outcome", "weather")) expect_match(mod, paste0('"', m, '",'), fixed = TRUE)
})
