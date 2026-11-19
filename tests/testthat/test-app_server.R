# Tests for app_server() wiring (R/app_server.R). The four step modules and the
# export menu are replaced by stubs that record their arguments, so these tests
# check how reactives are passed between steps, not what the steps compute.
# The real Step 0 to 3 flow needs a browser (see the review's M8).

new_app_stubs <- function(model_fit = NULL, fit_stale = FALSE, hist_sim = NULL) {
  rec <- new.env()
  rec$overview_api <- list(
    connection_params = shiny::reactiveVal(list(type = "local")),
    survey_list = shiny::reactiveVal(data.frame(survey_id = c("s1", "s2"))),
    variable_list = shiny::reactiveVal(data.frame(name = "x")),
    cpi_ppp = shiny::reactiveVal(data.frame(year = 2020L))
  )
  rec$step1_api <- list(
    selected_outcome = shiny::reactiveVal("o"),
    selected_weather = shiny::reactiveVal("w"),
    selected_surveys = shiny::reactiveVal("s"),
    selected_model = shiny::reactiveVal("m"),
    selected_policies = shiny::reactiveVal("p"),
    survey_weather = shiny::reactiveVal("sw"),
    survey_data = shiny::reactiveVal("sd"),
    model_fit = shiny::reactiveVal(model_fit),
    stored_breaks = shiny::reactiveVal("b"),
    survey_version = shiny::reactiveVal(1L),
    analysis_unit = shiny::reactiveVal("hh"),
    fit_stale = shiny::reactiveVal(fit_stale),
    survey_load_done = shiny::reactiveVal(0L),
    survey_load_status = shiny::reactiveVal("idle"),
    weather_load_done = shiny::reactiveVal(0L),
    weather_load_status = shiny::reactiveVal("idle"),
    fit_generation = shiny::reactiveVal(0L),
    fit_status = shiny::reactiveVal("idle")
  )
  rec$step2_api <- list(
    hist_sim = shiny::reactiveVal(hist_sim),
    saved_scenarios = shiny::reactiveVal("ss"),
    selected_hist = shiny::reactiveVal("sh"),
    skip_coef_draws = shiny::reactiveVal(FALSE),
    residuals = shiny::reactiveVal("none"),
    propagate_all_covariate_uncertainty = shiny::reactiveVal(FALSE),
    stale = shiny::reactiveVal(FALSE),
    run_generation = shiny::reactiveVal(0L),
    run_status = shiny::reactiveVal("idle")
  )
  rec$step3_api <- list(
    policy_hist_sim = shiny::reactiveVal(NULL),
    stale = shiny::reactiveVal(FALSE),
    run_generation = shiny::reactiveVal(0L),
    run_status = shiny::reactiveVal("idle")
  )
  rec
}

local_app_stubs <- function(rec, env = parent.frame()) {
  testthat::local_mocked_bindings(
    .duck_register_session = function(session) invisible(FALSE),
    mod_0_overview_server = function(id) rec$overview_api,
    mod_1_modelling_server = function(id, ...) {
      rec$step1_args <- list(...)
      rec$step1_api
    },
    mod_2_simulation_server = function(id, ...) {
      rec$step2_args <- list(...)
      rec$step2_api
    },
    mod_3_scenario_server = function(id, ...) {
      rec$step3_args <- list(...)
      rec$step3_api
    },
    export_menu_server = function(input, output, session, ...) {
      rec$export_args <- list(...)
      invisible(NULL)
    },
    .env = env
  )
}

test_that("Step 0 outputs feed Step 1, and Step 1 outputs feed Steps 2 and 3", {
  rec <- new_app_stubs()
  local_app_stubs(rec)
  shiny::testServer(app_server, {
    a1 <- rec$step1_args
    expect_identical(a1$survey_list, rec$overview_api$survey_list)
    expect_identical(a1$variable_list, rec$overview_api$variable_list)
    expect_identical(a1$connection_params, rec$overview_api$connection_params)
    expect_identical(a1$cpi_ppp, rec$overview_api$cpi_ppp)
    expect_equal(a1$survey_list()$survey_id, c("s1", "s2"))

    a2 <- rec$step2_args
    expect_identical(a2$model_fit, rec$step1_api$model_fit)
    expect_identical(a2$survey_weather, rec$step1_api$survey_weather)
    expect_identical(a2$selected_outcome, rec$step1_api$selected_outcome)
    expect_identical(a2$stored_breaks, rec$step1_api$stored_breaks)
    expect_identical(a2$connection_params, rec$overview_api$connection_params)

    a3 <- rec$step3_args
    expect_identical(a3$model_fit, rec$step1_api$model_fit)
    expect_identical(a3$selected_model, rec$step1_api$selected_model)
    expect_identical(a3$hist_sim, rec$step2_api$hist_sim)
    expect_identical(a3$saved_scenarios, rec$step2_api$saved_scenarios)
    expect_identical(a3$variable_list, rec$overview_api$variable_list)
    expect_identical(a3$sim_stale, rec$step2_api$stale)
    expect_identical(a3$analysis_unit, rec$step1_api$analysis_unit)
  })
})

test_that("Steps 2 and 3 share one aggregation cache; one trigger per stage", {
  rec <- new_app_stubs()
  local_app_stubs(rec)
  shiny::testServer(app_server, {
    expect_identical(
      rec$step2_args$shared_aggregation_cache,
      rec$step3_args$shared_aggregation_cache
    )
    trig <- rec$export_args$run_triggers
    expect_named(trig, c("load_survey", "load_weather", "step1", "step2", "step3"))
    expect_identical(trig$step1, rec$step1_args$run_trigger)
    expect_identical(trig$load_survey, rec$step1_args$load_survey_trigger)
    expect_identical(trig$load_weather, rec$step1_args$load_weather_trigger)
    expect_identical(trig$step2, rec$step2_args$run_trigger)
    expect_identical(trig$step3, rec$step3_args$run_trigger)

    res <- rec$export_args$step_results
    expect_identical(res$step1$generation, rec$step1_api$fit_generation)
    expect_identical(res$step2$status, rec$step2_api$run_status)
    expect_identical(res$step3$generation, rec$step3_api$run_generation)
    expect_identical(res$load_weather$status, rec$step1_api$weather_load_status)
  })
})

test_that("stale flags are shared with export registrations through userData", {
  rec <- new_app_stubs()
  local_app_stubs(rec)
  shiny::testServer(app_server, {
    expect_identical(session$userData$wise_step1_stale, rec$step1_api$fit_stale)
    expect_identical(session$userData$wise_step2_stale, rec$step2_api$stale)
    expect_identical(session$userData$wise_step3_stale, rec$step3_api$stale)
  })
})

test_that("export menu gets the default seed and an import hook that stores the imported seed", {
  rec <- new_app_stubs()
  local_app_stubs(rec)
  shiny::testServer(app_server, {
    expect_identical(rec$export_args$seed, WISEAPP_DEFAULT_SEED)
    on_import <- rec$export_args$on_import
    on_import(NULL)
    expect_null(session$userData$wise_analysis_seed)
    on_import(Inf)
    expect_null(session$userData$wise_analysis_seed)
    on_import(2468)
    expect_identical(session$userData$wise_analysis_seed, 2468L)
  })
})

test_that("provenance is empty until a step has a result", {
  rec <- new_app_stubs()
  local_app_stubs(rec)
  shiny::testServer(app_server, {
    expect_length(rec$export_args$provenance(), 0L)
  })
})

test_that("navbar badges: none before a run, different once a result exists and when stale", {
  badge_html <- function(rec) {
    local_app_stubs(rec, env = parent.frame())
    out <- NULL
    shiny::testServer(app_server, {
      out <<- as.character(output$step1_badge$html)
    })
    out
  }
  none <- badge_html(new_app_stubs())
  fresh <- badge_html(new_app_stubs(model_fit = list(engine = "fixest")))
  stale <- badge_html(new_app_stubs(model_fit = list(engine = "fixest"), fit_stale = TRUE))
  expect_false(isTRUE(nzchar(none)))
  expect_true(nzchar(fresh))
  expect_true(nzchar(stale))
  expect_false(identical(fresh, stale))
})
