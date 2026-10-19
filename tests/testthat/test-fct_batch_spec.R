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
  expect_error(wise_spec(policy = list(engine = "fixest")), "Unknown spec section")
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

  expect_error(wise_spec_expand(list(axes = list(policy = c("a", "b")))), "later phase")
  expect_error(wise_spec_expand(list(policy = list())), "later phase")
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
    connection_params = remote_cp(), metadata = fixture_metadata(),
    survey_columns = c("welfare", "hhsize", "tx", "pr")
  )
  expect_true(all(g$resolved))
  expect_identical(g$spec[[2]]$sample$years, list(MWI = c(2016L, 2019L, 2022L)))
  expect_identical(g$spec[[1]]$outcome$name, "welfare")
  # Ids of a resolved grid equal the ids of the explicit spec.
  explicit <- wise_spec(sample = list(countries = "BFA", years = list(BFA = c(2018, 2021))))
  explicit <- wise_spec_resolve(explicit, fixture_metadata(), remote_cp(),
    survey_columns = c("welfare", "hhsize", "tx", "pr")
  )
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
  s6 <- src("mod_1_06_model.R")
  for (id in c(
    "model_type", "fixedeffects", "covariates", "hhcov", "indcov", "firmcov", "areacov",
    "lasso_alpha", "lasso_interactions", "lasso_nfolds", "lasso_standardize", "use_mice", "mi_m",
    "mi_maxit", "stability_threshold", "interactions", "selected_policies"
  )) {
    expect_match(s6, paste0('ns("', id, '")'), fixed = TRUE)
  }
  expect_match(s6, 'paste0("force_in_", role)', fixed = TRUE)
  expect_match(s6, 'paste0("force_out_", role)', fixed = TRUE)
  s21 <- src("mod_2_01_weathersim.R")
  for (id in c(
    "hist_years", "climate", "baseline_survey", "residuals", "include_coef_uncertainty",
    "propagate_all_covariate_uncertainty"
  )) {
    expect_match(s21, paste0('ns("', id, '")'), fixed = TRUE)
  }
  expect_match(s21, 'ns("fut_period_1")', fixed = TRUE)
  expect_match(s21, 'ns("fut_period_2")', fixed = TRUE)
  expect_match(s21, 'ns("fut_period_3")', fixed = TRUE)
  prefixes <- c(
    "step1-sample-", "step1-outcome-", "step1-weather-", "step1-model-", "step2-weathersim-"
  )
  expect_identical(unname(.CONFIG_PREFIX), prefixes)
  app <- src("app_server.R")
  expect_match(app, 'mod_1_modelling_server\\(\\s+id = "step1"')
  expect_match(app, 'mod_2_simulation_server\\(\\s+id\\s+= "step2"')
  mod <- src("mod_1_modelling.R")
  for (m in c("sample", "outcome", "weather", "model")) expect_match(mod, paste0('"', m, '",'), fixed = TRUE)
  expect_match(src("mod_2_simulation.R"), 'mod_2_01_weathersim_server\\(\\s+"weathersim"')
})

# Model section ----

test_that("the model section: absent means no fit, empty means the app defaults", {
  expect_null(wise_spec()$model)
  expect_true(is.na(wise_spec_ids(wise_spec())$fit_id))
  m <- wise_spec(model = list())$model
  expect_identical(m, wise_spec(model = list(covariates = list(method = "User-defined")))$model)
  expect_identical(m$covariates$method, "user")
  expect_identical(m$covariates$vars, character(0))
  expect_null(m$covariates$lasso)
  expect_null(m$type)
  expect_null(m$fixed_effects)
  # An explicitly empty fixed-effects set is not the rule.
  none <- wise_spec(model = list(fixed_effects = list()))$model
  expect_identical(none$fixed_effects, character(0))
  expect_false(identical(wise_spec_ids(wise_spec(model = list()))$fit_id,
    wise_spec_ids(wise_spec(model = list(fixed_effects = list())))$fit_id))
  # The Lasso block carries the Model tab defaults.
  l <- wise_spec(model = list(covariates = list(method = "Lasso")))$model$covariates
  expect_null(l$vars)
  expect_identical(l$lasso[names(wise_default_lasso())], wise_default_lasso())
  expect_identical(l$lasso$force_in, character(0))
})

test_that("model types and covariates are normalised so equal specs hash equal", {
  a <- wise_spec(model = list(
    type = "linear", fixed_effects = c("year", "gaul1_code"),
    covariates = list(vars = c("urban", "hhsize", "urban"))
  ))
  b <- wise_spec(model = list(
    type = "Linear regression", fixed_effects = c("gaul1_code", "year"),
    covariates = list(method = "user", vars = c("hhsize", "urban"))
  ))
  expect_identical(a, b)
  expect_identical(a$model$type, "Linear regression")
  expect_identical(wise_spec(model = list(type = "RIF"))$model$type, "Unconditional quantile regression (RIF)")
  # User covariates do not enter a Lasso spec; Lasso settings do not enter a user spec.
  u <- wise_spec(model = list(covariates = list(method = "user", lasso = list(alpha = 0.3))))
  expect_identical(u, wise_spec(model = list()))
  s <- wise_spec(model = list(covariates = list(method = "lasso", vars = "hhsize")))
  expect_identical(s, wise_spec(model = list(covariates = list(method = "lasso"))))
})

test_that("fit_id follows data, weather, model and seed", {
  base <- wise_spec(weather = list(tx = list()), model = list())
  ids <- wise_spec_ids(base)
  expect_match(ids$fit_id, "^[0-9a-f]{12}$")
  vary <- function(...) wise_spec_ids(wise_spec(weather = list(tx = list()), model = list(), ...))
  # Binning is part of the weather, so it moves the fit id but not the wxvar id.
  bins <- wise_spec_ids(wise_spec(weather = list(tx = list(n_bins = 4)), model = list()))
  expect_false(identical(bins$fit_id, ids$fit_id))
  expect_identical(bins$wxvar_ids, ids$wxvar_ids)
  expect_false(identical(bins$weather_id, ids$weather_id))
  expect_false(identical(vary(seed = 7)$fit_id, ids$fit_id))
  expect_false(identical(vary(outcome = list(currency = "LCU"))$fit_id, ids$fit_id))
  m2 <- wise_spec_ids(wise_spec(weather = list(tx = list()), model = list(fixed_effects = "year")))
  expect_false(identical(m2$fit_id, ids$fit_id))
  # The weather frame is shared across models; the seed matters for K-means bins only.
  expect_identical(m2$weather_id, ids$weather_id)
  expect_identical(vary(seed = 7)$weather_id, ids$weather_id)
  km <- function(seed) {
    wise_spec_ids(wise_spec(
      weather = list(tx = list(binning_method = "K-means")), model = list(), seed = seed
    ))$weather_id
  }
  expect_false(identical(km(1), km(2)))
  # A change in the statistics options changes data_id and so the fit id (tables.md section 2).
  st <- wise_spec_ids(wise_spec(
    weather = list(tx = list()), model = list(), stats = list(location_samples = FALSE)
  ))
  expect_false(identical(st$fit_id, ids$fit_id))
})

test_that("model validation lists the problems", {
  err <- function(...) conditionMessage(tryCatch(wise_spec(model = list(...)), error = identity))
  expect_match(err(type = "Random forest"), "model.type must be one of")
  expect_match(err(interactions = "urban"), "model.interactions")
  expect_match(err(policy_vars = "x"), "policy variables arrive")
  expect_match(err(covariates = list(method = "stepwise")), "method must be")
  lasso <- function(...) err(covariates = list(method = "lasso", lasso = list(...)))
  expect_match(lasso(alpha = 2), "alpha must be between 0 and 1")
  expect_match(lasso(lambda = "lambda.max"), "lambda must be")
  expect_match(lasso(nfolds = 3), "nfolds must be between 5 and 20")
  expect_match(lasso(stability_threshold = 0.05), "stability_threshold")
  expect_match(lasso(force_in = "a", force_out = "a"), "share: a")
  expect_match(err(fixed_effects = c("year", "")), "variable names")
  # Model type against the outcome type, once the outcome is known.
  md <- fixture_metadata()
  md$variable_list$name[3] <- "welfare"
  cols <- c("welfare", "hhsize", "tx")
  logit <- wise_spec(model = list(type = "logistic"))
  expect_error(wise_spec_resolve(logit, md, remote_cp(), cols), "needs a binary outcome")
  rif_poor <- wise_spec(outcome = list(name = "poor"), model = list(type = "rif"))
  expect_error(wise_spec_resolve(rif_poor, md, remote_cp(), cols), "needs a continuous outcome")
  ok <- wise_spec_resolve(wise_spec(outcome = list(name = "poor"), model = list(type = "logistic")), md, remote_cp(), cols)
  expect_identical(ok$model$type, "Logistic regression")
})

test_that("resolution fills the default outcome and model type", {
  md <- fixture_metadata()
  r <- wise_spec_resolve(wise_spec(model = list()), md, remote_cp(), c("welfare", "hhsize", "tx"))
  expect_identical(r$outcome$name, "welfare")
  expect_identical(r$model$type, "Linear regression")
  p <- wise_spec_resolve(wise_spec(outcome = list(name = "poor"), model = list()), md, remote_cp(), "welfare")
  expect_identical(p$model$type, "Logistic regression")
  # An outcome the surveys lack is left for the data stage to report.
  expect_identical(
    wise_spec_resolve(wise_spec(outcome = list(name = "nope")), md, remote_cp(), "welfare")$outcome$name,
    "nope"
  )
  # Without survey columns the outcome stays as given.
  expect_null(wise_spec_resolve(wise_spec(), md, remote_cp())$outcome$name)
  # The resolved outcome is part of the stage ids.
  expect_false(identical(
    wise_spec_ids(r)$data_id, wise_spec_ids(wise_spec_resolve(wise_spec(model = list()), md, remote_cp()))$data_id
  ))
})

test_that("a grid crosses model, fixed-effects and covariate profiles", {
  skip_if_not_installed("yaml")
  grid <- list(
    profiles = list(
      model = list(linear = list(type = "linear"), rif = list(type = "rif")),
      fixed_effects = list(year_region = c("year", "gaul1_code"), none = list()),
      covariates = list(
        basic = list(method = "user", vars = c("hhsize", "urban")), lasso = list(method = "lasso")
      )
    ),
    axes = list(
      country = "BFA", model = c("linear", "rif"), fixed_effects = c("year_region", "none"),
      covariates = c("basic", "lasso")
    ),
    exclude = list(list(model = "rif", covariates = "lasso"))
  )
  g <- wise_spec_expand(grid)
  expect_identical(nrow(g), 6L)
  expect_identical(length(unique(g$fit_id)), 6L)
  # Weather and data are shared by all of them.
  expect_identical(length(unique(g$weather_id)), 1L)
  expect_identical(length(unique(g$data_id)), 1L)
  one <- g$spec[[which(g$model == "rif" & g$fixed_effects == "none" & g$covariates == "basic")]]
  expect_identical(one$model$type, "Unconditional quantile regression (RIF)")
  expect_identical(one$model$fixed_effects, character(0))
  expect_identical(one$model$covariates$vars, c("hhsize", "urban"))
  l <- g$spec[[which(g$model == "linear" & g$covariates == "lasso")[1]]]
  expect_identical(l$model$covariates$method, "lasso")
  expect_null(l$model$covariates$vars)
  # Dotted paths work too.
  d <- wise_spec_expand(list(model = list(covariates = list(method = "lasso")), axes = list(`model.covariates.lasso.alpha` = c(0.5, 1))))
  expect_identical(nrow(d), 2L)
})

test_that("a configuration export carries the model settings", {
  cfg <- list(
    wiseapp_config_version = 1L, random_seed = 5L,
    inputs = list(
      `step1-model-model_type` = "Linear regression",
      `step1-model-fixedeffects` = c("year", "gaul1_code"),
      `step1-model-covariates` = "User-defined",
      `step1-model-hhcov` = c("hhsize", "urban"), `step1-model-areacov` = "ttime_health",
      `step1-model-interactions` = character(0)
    )
  )
  s <- wise_spec_from_config(cfg)
  expect_identical(s$model$type, "Linear regression")
  expect_identical(s$model$fixed_effects, c("gaul1_code", "year"))
  expect_identical(s$model$covariates$vars, c("hhsize", "ttime_health", "urban"))
  lasso <- cfg
  lasso$inputs <- c(cfg$inputs, list(
    `step1-model-covariates` = "Lasso", `step1-model-lasso_alpha` = 0.5,
    `step1-model-lasso_standardize` = "Do not standardize", `step1-model-force_in_hh` = "hhsize"
  ))
  lasso$inputs <- lasso$inputs[!duplicated(names(lasso$inputs), fromLast = TRUE)]
  l <- wise_spec_from_config(lasso)$model$covariates
  expect_identical(l$method, "lasso")
  expect_identical(l$lasso$alpha, 0.5)
  expect_false(l$lasso$standardize)
  expect_identical(l$lasso$force_in, "hhsize")
  # A section the batch model does not support is reported, not dropped silently.
  cfg$inputs[["step1-model-interactions"]] <- "urban"
  expect_warning(wise_spec_from_config(cfg), "interactions")
  # No model inputs, no model section.
  expect_null(wise_spec_from_config(list(wiseapp_config_version = 1L, inputs = list(other = 1)))$model)
})

test_that("a model spec survives the JSON round trip", {
  s <- wise_spec(model = list(
    type = "rif", fixed_effects = list(),
    covariates = list(method = "lasso", lasso = list(alpha = 0.5, force_in = "hhsize"))
  ))
  f <- withr::local_tempfile(fileext = ".json")
  wise_spec_write(s, f)
  expect_identical(wise_spec_read(f), s)
})

# Simulation section ----

sim_spec <- function(sim = list(), ..., model = list()) wise_spec(model = model, sim = sim, ...)

test_that("the sim section: absent means no simulation, empty means the app defaults", {
  expect_null(wise_spec()$sim)
  expect_true(is.na(wise_spec_ids(wise_spec(model = list()))$sim_id))
  s <- sim_spec()$sim
  d <- wise_default_sim()
  for (f in names(d)) expect_identical(s[[f]], d[[f]], info = f)
  # The baseline waits for the sample (the latest wave of each economy).
  expect_null(s$baseline_survey)
  expect_identical(names(s), sort(names(s)))
  expect_error(wise_spec(sim = list()), "needs a model section")
  # The defaults are the initial state of the Step 2 sidebar.
  expect_identical(d$hist_years, c(1991L, 2020L))
  expect_identical(d$future_periods, list(c(2025L, 2035L)))
  expect_identical(d$ssps, "ssp3_7_0")
  expect_identical(d$residuals, "original")
  expect_true(d$coef_uncertainty)
  expect_false(d$propagate_all_covariate_uncertainty)
  # The sidebar starts from the same state (mod_2_01 reads wise_default_sim()).
  html <- as.character(mod_2_01_weathersim_ui("sim"))
  expect_match(html, 'id="sim-hist_years"[^>]*data-from="1991"[^>]*data-to="2020"')
  expect_match(html, 'id="sim-fut_period_1"[^>]*data-from="2025"[^>]*data-to="2035"')
})

test_that("sim settings are normalised so equal specs hash equal", {
  a <- sim_spec(list(
    ssps = c("SSP5_8_5", "ssp2_4_5", "ssp5_8_5"), future_periods = list(c(2025, 2035)),
    baseline_survey = c("MWI|2019", "BFA|2021"), residuals = "Original"
  ))$sim
  expect_identical(a$ssps, c("ssp2_4_5", "ssp5_8_5"))
  expect_identical(a$baseline_survey, c("BFA|2021", "MWI|2019"))
  expect_identical(a$residuals, "original")
  # One flat pair is one period; periods keep the order given (it sets the
  # random stream of the residual draws).
  expect_identical(sim_spec(list(future_periods = c(2025, 2035)))$sim$future_periods, list(c(2025L, 2035L)))
  p <- sim_spec(list(future_periods = list(c(2040, 2050), c(2025, 2035))))$sim$future_periods
  expect_identical(p, list(c(2040L, 2050L), c(2025L, 2035L)))
  # An empty list is a setting: no projection periods, no scenarios.
  none <- sim_spec(list(future_periods = list()))$sim
  expect_identical(none$future_periods, list())
  expect_identical(sim_spec(list(ssps = list(), future_periods = list()))$sim$ssps, character(0))
  ids <- function(...) wise_spec_ids(sim_spec(list(...)))$sim_id
  expect_identical(
    ids(future_periods = list(), ssps = "ssp2_4_5"), ids(future_periods = list(), ssps = list())
  )
  expect_false(identical(ids(future_periods = list(c(2025, 2035))), ids(future_periods = list())))
})

test_that("sim validation lists the problems", {
  err <- function(...) conditionMessage(tryCatch(sim_spec(list(...)), error = identity))
  expect_match(err(hist_years = c(2020, 1991)), "sim.hist_years must be two years")
  expect_match(err(hist_years = c(1940, 2000)), "between 1950 and 2024")
  expect_match(err(hist_years = 2000), "sim.hist_years")
  expect_match(err(future_periods = list(c(2010, 2030))), "starts|between 2015")
  expect_match(err(future_periods = list(c(2030, 2030))), "the end after the start")
  expect_match(err(future_periods = list(c(2030, 2120))), "2100")
  expect_match(err(future_periods = list(c(2020, 2030), c(2020, 2030))), "listed twice")
  four <- list(c(2020, 2025), c(2026, 2030), c(2031, 2035), c(2036, 2040))
  expect_match(err(future_periods = four), "at most three")
  expect_match(err(ssps = "ssp1_1_9"), "sim.ssps must be among")
  expect_match(err(ssps = list()), "choose at least one scenario")
  expect_match(err(residuals = "normal"), "sim.residuals must be one of")
  expect_match(err(coef_uncertainty = NA), "coef_uncertainty must be true or false")
  expect_match(err(baseline_survey = "BFA2021"), "CODE|YEAR")
  expect_match(err(nope = 1), "sim.nope")
  # Every problem is listed at once.
  expect_match(err(residuals = "x", ssps = "y"), "residuals.*\n.*ssps|ssps.*\n.*residuals")
})

test_that("the baseline survey resolves to the latest wave of each economy", {
  md <- fixture_metadata()
  r <- wise_spec_resolve(sim_spec(), md, remote_cp(), c("welfare", "hhsize", "tx"))
  expect_identical(r$sim$baseline_survey, "BFA|2021")
  both <- wise_spec_resolve(
    wise_spec(sample = list(countries = c("BFA", "MWI")), model = list(), sim = list()),
    md, remote_cp(), c("welfare", "hhsize", "tx")
  )
  expect_identical(both$sim$baseline_survey, c("BFA|2021", "MWI|2022"))
  given <- wise_spec_resolve(
    sim_spec(list(baseline_survey = "BFA|2018")), md, remote_cp(), c("welfare", "hhsize", "tx")
  )
  expect_identical(given$sim$baseline_survey, "BFA|2018")
  expect_error(
    wise_spec_resolve(sim_spec(list(baseline_survey = "MWI|2019")), md, remote_cp()),
    "outside the sample: MWI\\|2019"
  )
  # Resolving twice changes nothing; the resolved baseline is part of the id.
  expect_identical(wise_spec_resolve(r, md, remote_cp(), c("welfare", "hhsize", "tx")), r)
  expect_false(identical(wise_spec_ids(r)$sim_id, wise_spec_ids(given)$sim_id))
})

test_that("sim_id follows the fit and the simulation settings that change results", {
  ids <- function(model = list(), ...) wise_spec_ids(wise_spec(model = model, sim = list(...)))
  base <- ids()
  expect_match(base$sim_id, "^[0-9a-f]{12}$")
  # The earlier ids do not know about the simulation (they are pinned).
  expect_identical(base$fit_id, wise_spec_ids(wise_spec(model = list()))$fit_id)
  expect_identical(base$weather_id, wise_spec_ids(wise_spec(model = list()))$weather_id)
  expect_identical(base$data_id, wise_spec_ids(wise_spec())$data_id)
  # Each setting moves the id.
  for (change in list(
    list(hist_years = c(1981, 2010)), list(future_periods = list(c(2030, 2040))),
    list(ssps = "ssp5_8_5"), list(residuals = "resample"), list(coef_uncertainty = FALSE),
    list(propagate_all_covariate_uncertainty = TRUE), list(baseline_survey = "BFA|2018")
  )) {
    expect_false(identical(do.call(ids, change)$sim_id, base$sim_id), info = names(change))
    expect_identical(do.call(ids, change)$fit_id, base$fit_id, info = names(change))
  }
  # The fit and the seed reach it.
  expect_false(identical(ids(model = list(fixed_effects = "year"))$sim_id, base$sim_id))
  expect_false(identical(wise_spec_ids(wise_spec(model = list(), sim = list(), seed = 5))$sim_id, base$sim_id))
  # Residuals are not drawn for RIF: the setting does not change the run.
  rif <- function(residuals) ids(model = list(type = "rif"), residuals = residuals)$sim_id
  expect_identical(rif("original"), rif("resample"))
  expect_false(identical(ids(residuals = "original")$sim_id, ids(residuals = "resample")$sim_id))
  # Scenarios are irrelevant without projection periods.
  hist <- function(ssps) ids(future_periods = list(), ssps = ssps)$sim_id
  expect_identical(hist("ssp2_4_5"), hist("ssp5_8_5"))
})

test_that("a grid crosses sim profiles and shares the fit across them", {
  skip_if_not_installed("yaml")
  grid <- list(
    model = list(),
    profiles = list(sim = list(
      ssp3 = list(ssps = "ssp3_7_0", future_periods = list(c(2025, 2035))),
      ssp2_5 = list(ssps = c("ssp2_4_5", "ssp5_8_5"), future_periods = list(c(2025, 2035), c(2040, 2050))),
      historical = list(future_periods = list())
    )),
    axes = list(country = "BFA", sim = c("ssp3", "ssp2_5", "historical"))
  )
  g <- wise_spec_expand(grid)
  expect_identical(nrow(g), 3L)
  expect_identical(length(unique(g$fit_id)), 1L)
  expect_identical(length(unique(g$sim_id)), 3L)
  expect_identical(g$spec[[2]]$sim$ssps, c("ssp2_4_5", "ssp5_8_5"))
  expect_identical(g$spec[[2]]$sim$future_periods, list(c(2025L, 2035L), c(2040L, 2050L)))
  # An empty list in a profile switches the projections off.
  expect_identical(g$spec[[3]]$sim$future_periods, list())
  # A top-level section merges with the profile; dotted paths work too.
  top <- wise_spec_expand(list(
    model = list(), sim = list(residuals = "resample", future_periods = list()),
    axes = list(`sim.coef_uncertainty` = c(TRUE, FALSE))
  ))
  expect_identical(nrow(top), 2L)
  expect_identical(top$spec[[1]]$sim$residuals, "resample")
  expect_identical(top$spec[[1]]$sim$future_periods, list())
  expect_identical(top$spec[[2]]$sim$coef_uncertainty, FALSE)
  # Resolved against the data, the baseline is part of the specs.
  r <- wise_spec_expand(
    list(model = list(), sim = list(), axes = list(country = c("BFA", "MWI"))),
    connection_params = remote_cp(), metadata = fixture_metadata(),
    survey_columns = c("welfare", "hhsize", "tx")
  )
  expect_identical(r$spec[[1]]$sim$baseline_survey, "BFA|2021")
  expect_identical(r$spec[[2]]$sim$baseline_survey, "MWI|2022")
  expect_false(anyNA(r$sim_id))
  # A simulation needs a model.
  expect_error(wise_spec_expand(list(sim = list())), "needs a model section")
})

test_that("a configuration export carries the simulation settings", {
  cfg <- list(
    wiseapp_config_version = 1L, random_seed = 5L,
    inputs = list(
      `step1-model-model_type` = "Linear regression",
      `step2-weathersim-hist_years` = c(1981, 2010), `step2-weathersim-climate` = c("ssp2_4_5", "ssp5_8_5"),
      `step2-weathersim-fut_period_1` = c(2030, 2040), `step2-weathersim-fut_period_2` = c(2015, 2015),
      `step2-weathersim-fut_period_3` = c(2050, 2060), `step2-weathersim-baseline_survey` = "BFA|2018",
      `step2-weathersim-residuals` = "resample", `step2-weathersim-include_coef_uncertainty` = FALSE,
      `step2-weathersim-propagate_all_covariate_uncertainty` = TRUE
    )
  )
  s <- wise_spec_from_config(cfg)$sim
  expect_identical(s$hist_years, c(1981L, 2010L))
  expect_identical(s$ssps, c("ssp2_4_5", "ssp5_8_5"))
  # The empty period is left out, as the app leaves it out.
  expect_identical(s$future_periods, list(c(2030L, 2040L), c(2050L, 2060L)))
  expect_identical(s$baseline_survey, "BFA|2018")
  expect_identical(s$residuals, "resample")
  expect_false(s$coef_uncertainty)
  expect_true(s$propagate_all_covariate_uncertainty)
  # No usable period: no projections.
  none <- cfg
  none$inputs[c("step2-weathersim-fut_period_1", "step2-weathersim-fut_period_3")] <- list(c(2015, 2015), c(2015, 2015))
  expect_identical(wise_spec_from_config(none)$sim$future_periods, list())
  # Without Step 2 inputs there is no simulation; without a model the
  # simulation is dropped, with a warning.
  expect_null(wise_spec_from_config(list(
    wiseapp_config_version = 1L, inputs = list(`step1-model-model_type` = "Linear regression")
  ))$sim)
  nomodel <- cfg
  nomodel$inputs[["step1-model-model_type"]] <- NULL
  expect_warning(spec <- wise_spec_from_config(nomodel), "needs a Step 1 model")
  expect_null(spec$sim)
  # The app default state is the empty section.
  defaults <- list(
    wiseapp_config_version = 1L, inputs = list(
      `step1-model-model_type` = "Linear regression", `step2-weathersim-hist_years` = c(1991, 2020),
      `step2-weathersim-climate` = "ssp3_7_0", `step2-weathersim-fut_period_1` = c(2025, 2035),
      `step2-weathersim-fut_period_2` = c(2015, 2015), `step2-weathersim-fut_period_3` = c(2015, 2015),
      `step2-weathersim-residuals` = "original", `step2-weathersim-include_coef_uncertainty` = TRUE,
      `step2-weathersim-propagate_all_covariate_uncertainty` = FALSE
    )
  )
  expect_identical(wise_spec_from_config(defaults)$sim, sim_spec()$sim)
})

test_that("a sim spec survives the JSON round trip", {
  f <- withr::local_tempfile(fileext = ".json")
  for (s in list(
    sim_spec(list(future_periods = list(c(2025, 2035), c(2040, 2050)), ssps = c("ssp2_4_5", "ssp5_8_5"))),
    sim_spec(list(future_periods = list(), baseline_survey = c("BFA|2018", "MWI|2019"))),
    sim_spec(list(future_periods = list(c(2025, 2035))))
  )) {
    wise_spec_write(s, f)
    expect_identical(wise_spec_read(f), s)
  }
})
