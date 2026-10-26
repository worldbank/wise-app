# Step 2 input glue: the baseline survey, the periods and the snapshot that
# mod_2_01 and the batch runner both hand to step2_compute()
# (R/fct_step2_input.R; batch/docs/spec_inventory.md section 4).

library(shiny)

step2_input_survey <- function() {
  data.frame(
    hhid = 1:6, code = rep(c("AAA", "BBB"), each = 3), year = rep(c(2019L, 2020L, 2020L), 2),
    survname = "SRV", loc_id = "L1", int_month = c(1L, 2L, 3L, 1L, 2L, 3L),
    welfare = 1:6, temp = 3:8, weight = 1
  )
}
step2_input_surveys <- function() {
  data.frame(
    code = c("AAA", "AAA", "BBB"), year = c(2019L, 2020L, 2020L), survname = "SRV",
    source = "src", economy = c("A", "A", "B"), stringsAsFactors = FALSE
  )
}
step2_input_weather <- function() {
  data.frame(name = c("temp", "pr"), units = c("degC", "mm"), stringsAsFactors = FALSE)
}
step2_input_outcome <- function() {
  data.frame(name = "welfare", type = "numeric", transform = "log", units = "USD", povline = 3)
}
step2_input_fit <- function(engine = "fixest") {
  fit <- list(
    engine = engine, .sig = list(fit = 1L), fit3 = NULL, train_data = data.frame(x = 1:2),
    weather_terms = c("temp", "pr"), y_var = "welfare", fit1 = "drop", fit2 = "drop",
    .snap = list(model = list(a = 1), survey_weather = "big")
  )
  if (identical(engine, "rif")) {
    fit$fit3 <- list(q10 = "f10", q50 = "f50")
    fit$taus <- c(0.1, 0.5)
  }
  fit
}

test_that("the default baseline is the latest wave of each economy", {
  expect_identical(
    wise_default_baseline(c("AAA|2019", "AAA|2020", "BBB|2020", "BBB|2018")),
    c("AAA|2020", "BBB|2020")
  )
  expect_identical(wise_default_baseline(character(0)), character(0))
  ch <- step2_baseline_choices(step2_input_survey(), step2_input_surveys())
  expect_identical(unname(ch), c("AAA|2019", "AAA|2020", "BBB|2019", "BBB|2020"))
  expect_identical(names(ch), c("A 2019", "A 2020", "B 2019", "B 2020"))
  # Without the survey metadata the economy code labels the choice.
  expect_identical(names(step2_baseline_choices(step2_input_survey(), NULL))[1], "AAA 2019")
  expect_identical(step2_baseline_choices(data.frame(code = "A"), NULL), character(0))
  expect_identical(step2_baseline_label(ch, c("AAA|2020", "BBB|2020")), "A 2020, B 2020")
  expect_identical(step2_baseline_label(ch, "ZZZ|1999"), "Selected baseline survey")
  expect_identical(nrow(step2_baseline_svy(step2_input_survey(), "AAA|2020")), 2L)
  expect_identical(step2_baseline_svy(step2_input_survey(), character(0)), step2_input_survey())
  expect_identical(step2_hist_label(c(1991, 2020)), "Historical / 1991-2020")
})

test_that("the snapshot carries the periods, scenarios and the residual rule", {
  svy <- step2_input_survey()
  make <- function(fit = step2_input_fit(), ...) {
    args <- list(
      sw = step2_input_weather(), so = step2_input_outcome(), svy = svy, ss = step2_input_surveys(),
      mf = fit, cp = list(type = "local", path = "/data"), hist_years = c(2000, 2002),
      periods = list(c(2030, 2040), c(2050, 2060)), ssps = c("ssp2_4_5", "ssp5_8_5")
    )
    extra <- list(...)
    args[names(extra)] <- extra
    do.call(wise_step2_input, args)
  }
  x <- make()
  expect_setequal(names(x), c(
    .step2_compute_required, "propagate_all_covariate_uncertainty", "fit_multi", "taus", "weather_cols"
  ))
  expect_identical(x$fp_list, list(c("2030-01-01", "2040-12-31"), c("2050-01-01", "2060-12-31")))
  expect_identical(x$ssps, c("ssp2_4_5", "ssp5_8_5"))
  expect_identical(x$perturbation_method, c(temp = "additive", pr = "multiplicative"))
  expect_identical(x$sim_dates, build_hist_sim_dates(svy, c(2000, 2002)))
  expect_identical(x$residuals, "original")
  expect_false(x$skip_coef_draws)
  expect_false(x$propagate_all_covariate_uncertainty)
  expect_null(x$fit_multi)

  # Coefficient uncertainty off, propagation and the residual rule.
  y <- make(coef_uncertainty = FALSE, propagate_all = TRUE, residuals = "resample")
  expect_true(y$skip_coef_draws)
  expect_true(y$propagate_all_covariate_uncertainty)
  expect_identical(y$residuals, "resample")

  # RIF: no residual draw, the quantile fits travel with the input.
  r <- make(step2_input_fit("rif"), residuals = "resample")
  expect_identical(r$residuals, "none")
  expect_identical(r$fit_multi, list(q10 = "f10", q50 = "f50"))
  expect_identical(r$taus, c(0.1, 0.5))
  expect_identical(r$weather_cols, c("temp", "pr"))

  # No usable period: no future run, whatever the scenarios.
  h <- make(periods = list(c(2010, 2030), c(2015, 2015)))
  expect_identical(h$fp_list, list())
  expect_identical(h$ssps, character(0))
  expect_null(h$perturbation_method)
  expect_identical(make(ssps = character(0))$fp_list, list())
  # A period that starts before the projections is left out, the others stay.
  p <- make(periods = list(c(2010, 2030), c(2040, 2050)))
  expect_identical(p$fp_list, list(c("2040-01-01", "2050-12-31")))
})

test_that("the worker snapshot is a slim copy and leaves the live fit alone", {
  fit <- step2_input_fit()
  slim <- wise_step2_input(
    step2_input_weather(), step2_input_outcome(), step2_input_survey(), step2_input_surveys(),
    fit, list(type = "local", path = "/data"), c(2000, 2002), list(), character(0), slim = TRUE
  )
  expect_identical(slim$mf, step2_slim_model_fit(fit))
  expect_null(slim$mf$fit1)
  expect_identical(fit$fit1, "drop")
  full <- wise_step2_input(
    step2_input_weather(), step2_input_outcome(), step2_input_survey(), step2_input_surveys(),
    fit, list(type = "local", path = "/data"), c(2000, 2002), list(), character(0), slim = FALSE
  )
  expect_identical(full$mf, fit)
})

test_that("a finished run is described by its historical label and summary", {
  res <- wise_step2_annotate(list(hist_sim_result = list(a = 1), total_runs = 9L),
    step2_input_weather(), c(1991, 2020), "A 2020")
  expect_identical(res$hist_sim_result$hist_label, "Historical / 1991-2020")
  expect_identical(res$hist_sim_result$sim_summary$historical_years, c(1991, 2020))
  expect_identical(res$hist_sim_result$sim_summary$baseline_survey, "A 2020")
  expect_identical(res$hist_sim_result$sim_summary$total_runs, 9L)
  expect_identical(res$hist_sim_result$a, 1)
})

test_that("the original rule keys baseline and estimation rows by round and economy (F0)", {
  fit <- step2_input_fit()
  fit$train_data <- data.frame(
    hhid = c(1, 2, 3, 1), code = c("AAA", "AAA", "AAA", "BBB"), year = c(2019L, 2019L, 2020L, 2020L),
    survname = "SRV"
  )
  make <- function(residuals) {
    wise_step2_input(
      step2_input_weather(), step2_input_outcome(), step2_input_survey(), step2_input_surveys(),
      fit, list(type = "local", path = "/data"), c(2000, 2002), list(), character(0),
      residuals = residuals
    )
  }
  x <- make("original")
  expect_true(RESID_KEY_COL %in% names(x$svy))
  expect_true(RESID_KEY_COL %in% names(x$mf$train_data))
  expect_false(RESID_KEY_COL %in% names(fit$train_data))
  rm_ <- attr(x, "residual_match")
  expect_identical(c(rm_$n_matched, rm_$n_unmatched, rm_$n_total), c(2L, 4L, 6L))
  expect_match(step2_residual_match_note(rm_), "^4 of 6 baseline households have no estimation row")
  # Other rules draw no matched residual: no key, no counts.
  y <- make("resample")
  expect_false(RESID_KEY_COL %in% names(y$svy))
  expect_null(attr(y, "residual_match"))
  res <- wise_step2_annotate(list(hist_sim_result = list(), total_runs = 1L),
    step2_input_weather(), c(1991, 2020), "A 2020", residual_match = rm_)
  expect_identical(res$hist_sim_result$sim_summary$residual_match, rm_)
})

# Baseline without weather ----

step2_gap_survey <- function() {
  svy <- data.frame(
    hhid = 1:8, code = "AAA", year = 2020L, survname = "SRV", loc_id = rep(c("L1", "L2"), 4),
    int_month = 1L, urban = c(1, 0, 1, 0, 1, NA, 1, 0), temp = c(20, NA, 21, 22, 23, 24, NA, 25),
    weight = c(1, 2, 1, 1, 1, 1, 4, 1), stringsAsFactors = FALSE
  )
  svy$temp_cont <- svy$temp
  svy
}
step2_gap_fit <- function() {
  fit <- step2_input_fit()
  fit$weather_terms <- "temp"
  fit$formulas <- list(formula3 = welfare ~ temp + I(temp^2) + urban | loc_id)
  fit
}

test_that("households without weather or model data are left out of the baseline", {
  svy <- step2_gap_survey()
  sw <- step2_input_weather()
  base <- step2_baseline_complete(svy, sw, step2_gap_fit(), step2_input_outcome())
  # Rows 2 and 7 have no weather; row 6 has no value of the control `urban`.
  expect_identical(base$svy$hhid, c(1L, 3L, 4L, 5L, 8L))
  d <- base$dropped
  expect_identical(c(d$n_total, d$n_dropped, d$n_dropped_weather), c(8L, 3L, 2L))
  # Weights are kept as they are; the dropped share is reported.
  expect_identical(base$svy$weight, svy$weight[c(1, 3, 4, 5, 8)])
  expect_equal(d$weight_share_dropped, 7 / 12)
  expect_true(all(c("temp", "temp_cont", "urban", "loc_id") %in% d$variables))
  expect_identical(svy, step2_gap_survey())
  # Without a model only the selected weather is checked; nothing dropped, same object.
  expect_identical(step2_baseline_complete(step2_input_survey(), sw)$svy, step2_input_survey())
  expect_identical(
    step2_baseline_complete(svy, sw)$dropped$n_dropped, 2L
  )
  # The shared call: baseline waves first, then complete cases.
  run <- step2_baseline_run(svy, "AAA|2020", sw, step2_gap_fit(), step2_input_outcome())
  expect_identical(run$svy, base$svy)
  expect_match(step2_dropped_note(d), "3 of 8 baseline households left out.*58.3% of the survey weight")
  expect_null(step2_dropped_note(step2_baseline_complete(step2_input_survey(), sw)$dropped))
  expect_null(step2_dropped_note(NULL))
})

test_that("a baseline with no complete household is an error", {
  svy <- step2_gap_survey()
  svy$temp <- NA_real_
  expect_error(
    step2_baseline_complete(svy, step2_input_weather(), step2_gap_fit()),
    "No household of the baseline survey has complete weather"
  )
})

test_that("the filtered baseline reaches the step 2 input and the run summary", {
  fit <- step2_gap_fit()
  base <- step2_baseline_run(step2_gap_survey(), character(0), step2_input_weather(), fit)
  input <- wise_step2_input(
    step2_input_weather(), step2_input_outcome(), base$svy, step2_input_surveys(),
    fit, list(type = "local", path = "/data"), c(2000, 2002), list(), character(0)
  )
  expect_identical(input$svy$hhid, c(1L, 3L, 4L, 5L, 8L))
  res <- wise_step2_annotate(
    list(hist_sim_result = list(), total_runs = 9L), step2_input_weather(), c(1991, 2020), "A 2020",
    base$dropped
  )
  expect_identical(res$hist_sim_result$sim_summary$baseline_dropped, base$dropped)
})

test_that("the Step 2 input version is part of sim_id", {
  spec <- wise_spec(
    outcome = list(name = "welfare"), weather = list(tx = list()), model = list(), sim = list()
  )
  ids <- wise_spec_ids(spec)
  expect_false(is.na(ids$sim_id))
  without_version <- .spec_digest(list(fit_id = ids$fit_id, sim = .sim_effective(spec)))
  expect_false(identical(ids$sim_id, without_version))
  expect_identical(
    ids$sim_id,
    .spec_digest(list(fit_id = ids$fit_id, sim = .sim_effective(spec), step2_input = .STEP2_INPUT_VERSION))
  )
})

# Module parity ----

# Drive the simulation module and return what it hands to the worker (async
# path) or to fct_run_simulation() (the debugging path).
drive_sim_module <- function(fit, inputs, sync = FALSE) {
  captured <- new.env()
  testthat::local_mocked_bindings(
    .wise_step2_async_enabled = function(...) !sync,
    .wise_step2_async_submit = function(snapshot, ...) {
      captured$snapshot <- snapshot
      list2env(list(
        id = "mock-job", generation = list(...)$generation,
        dependency_signature = list(...)$dependency_signature, settled = FALSE
      ), parent = emptyenv())
    },
    .wise_step2_async_cancel = function(...) invisible(TRUE),
    fct_run_simulation = function(...) {
      captured$sync_args <- list(...)
      list(
        hist_sim_result = list(pipeline = list(y_point = 1)), new_scenarios = list(),
        total_runs = 7L, failures = list(), n_keys = 1L, n_keys_ok = 1L, t_elapsed = 1,
        data_quality = NULL
      )
    }
  )
  testServer(mod_2_01_weathersim_server, args = list(
    id = "sim", connection_params = reactiveVal(list(type = "local", path = "/fixed/path")),
    selected_outcome = reactiveVal(step2_input_outcome()),
    selected_weather = reactiveVal(step2_input_weather()),
    selected_surveys = reactiveVal(step2_input_surveys()),
    survey_weather = reactiveVal(step2_input_survey()), model_fit = reactiveVal(fit),
    stored_breaks = reactive(list(temp = c(1, 2)))
  ), {
    do.call(session$setInputs, inputs)
    session$flushReact()
    if (sync) {
      session$setInputs(run_sim = 1L)
      session$flushReact()
      captured$hist_sim <- hist_sim()
    } else {
      submit_step2_async()
    }
  })
  captured
}

sim_module_inputs <- list(
  hist_years = c(1991, 2020), climate = c("ssp2_4_5", "ssp5_8_5"), baseline_survey = "AAA|2020",
  residuals = "original", include_coef_uncertainty = TRUE,
  fut_period_1 = c(2030, 2040),
  fut_period_2 = c(2050, 2060), fut_period_3 = c(2015, 2015)
)

test_that("the module hands the worker exactly the core's input", {
  by_name <- function(x) x[order(names(x))]
  survey <- step2_input_survey()
  for (engine in c("fixest", "rif")) {
    fit <- step2_input_fit(engine)
    got <- drive_sim_module(fit, sim_module_inputs)$snapshot$input
    core <- wise_step2_input(
      step2_input_weather(), step2_input_outcome(),
      svy = step2_baseline_svy(survey, "AAA|2020"),
      ss = .step2_filter_baseline_surveys(step2_input_surveys(), "AAA|2020"),
      mf = fit, cp = .wise_step2_async_connection_params(list(type = "local", path = "/fixed/path")),
      hist_years = c(1991, 2020), periods = list(c(2030, 2040), c(2050, 2060)),
      ssps = c("ssp2_4_5", "ssp5_8_5"), stored_breaks = list(temp = c(1, 2))
    )
    extras <- c("weather_storage", "weather_collect", "weather_threads", "display")
    expect_setequal(names(got), c(names(core), extras))
    expect_identical(by_name(got[names(core)]), by_name(core), info = engine)
    expect_identical(got$weather_storage, "memory")
  }
  # Historical only, resampled residuals, no coefficient uncertainty.
  alt <- utils::modifyList(sim_module_inputs, list(
    fut_period_1 = c(2015, 2015), fut_period_2 = c(2015, 2015), residuals = "resample",
    include_coef_uncertainty = FALSE,
    baseline_survey = c("AAA|2020", "BBB|2020")
  ))
  got <- drive_sim_module(step2_input_fit(), alt)$snapshot$input
  expect_identical(got$fp_list, list())
  expect_identical(got$residuals, "resample")
  expect_true(got$skip_coef_draws)
  expect_false(got$propagate_all_covariate_uncertainty)
  expect_identical(unique(got$svy$code), c("AAA", "BBB"))
})

test_that("the debugging path of the module runs the same input and annotates the result", {
  cap <- drive_sim_module(step2_input_fit(), sim_module_inputs, sync = TRUE)
  core <- wise_step2_input(
    step2_input_weather(), step2_input_outcome(),
    svy = step2_baseline_svy(step2_input_survey(), "AAA|2020"),
    ss = .step2_filter_baseline_surveys(step2_input_surveys(), "AAA|2020"),
    mf = step2_input_fit(), cp = list(type = "local", path = "/fixed/path"),
    hist_years = c(1991, 2020), periods = list(c(2030, 2040), c(2050, 2060)),
    ssps = c("ssp2_4_5", "ssp5_8_5"), stored_breaks = list(temp = c(1, 2)), slim = FALSE
  )
  expect_identical(cap$sync_args[names(core)], core)
  expect_identical(cap$hist_sim$hist_label, "Historical / 1991-2020")
  expect_identical(cap$hist_sim$sim_summary$baseline_survey, "A 2020")
  expect_identical(cap$hist_sim$sim_summary$total_runs, 7L)
})

test_that("the module controls start at the spec defaults", {
  d <- wise_default_sim()
  expect_identical(d$hist_years, c(1991L, 2020L))
  expect_identical(d$ssps, "ssp3_7_0")
  expect_identical(d$future_periods, list(c(2025L, 2035L)))
  html <- as.character(mod_2_01_weathersim_ui("sim"))
  expect_match(html, 'id="sim-hist_years"[^>]*data-from="1991"[^>]*data-to="2020"')
  expect_match(html, 'id="sim-fut_period_1"[^>]*data-from="2025"[^>]*data-to="2035"')
  expect_match(html, 'value="ssp3_7_0" checked')
  expect_match(html, 'name="sim-residuals"|id="sim-residuals"')
  expect_match(html, 'id="sim-include_coef_uncertainty"[^>]*checked')
})
