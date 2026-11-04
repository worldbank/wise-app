# Parity of an annotation-only feature (roadmap/enso.md, D1): Steps 1 to 3 run twice in one process,
# with the ENSO tables absent (`enso` NULL) and then loaded. Every registered export table must be
# identical under identical() and all.equal(tolerance = 0), and so must hist_sim. To reuse it for
# another label-only feature, change what `run_once()` passes in.
#
# Usage (repo root): Rscript dev/parity_enso.R [--fixture]
#   --fixture  the small data folder of the tests (country TST, about 2 minutes); without it BFA on
#              WISEAPP_DATA_PATH (about 8 minutes). Iterate on the fixture, run BFA once at the end.
# Exit status 1 when any table differs. Not part of the test suite.
args <- commandArgs(trailingOnly = TRUE)
use_fixture <- "--fixture" %in% args
suppressMessages({
  pkgload::load_all(".", quiet = TRUE)
  library(shiny)
})
Sys.setenv(WISEAPP_ASYNC_STEP2 = "0", WISEAPP_ASYNC_STEP3 = "0")

cfg <- if (use_fixture) {
  suppressMessages(library(testthat))
  source("tests/testthat/helper-batch-fixture.R", local = TRUE)
  data_dir <- file.path(tempdir(), "parity-data")
  dir.create(data_dir, showWarnings = FALSE)
  batch_fixture_tree(data_dir, projections = TRUE)
  Sys.setenv(WISEAPP_DATA_PATH = data_dir)
  list(
    economy = "TST", years = c(2018, 2019), covs = c("hhsize", "urban", "electricity"),
    fe = "year", sim_hist = c(2018, 2019), future = c(2025, 2030),
    weather_inputs = list(
      `step1-weather-weather_variable_selector` = "tx",
      `step1-weather-tx_relativePeriod` = c(1, 3), `step1-weather-tx_contOrBinned` = "Continuous",
      `step1-weather-hist_years` = c(2017, 2019)
    )
  )
} else {
  list(
    economy = "BFA", years = c(2018, 2021), covs = c("hhsize", "electricity", "cellphone"),
    fe = c("year", "gaul1_code"), sim_hist = c(1991, 2020), future = c(2025, 2035),
    weather_inputs = list(
      `step1-weather-weather_variable_selector` = c("t", "r"),
      `step1-weather-t_relativePeriod` = c(1, 3), `step1-weather-t_contOrBinned` = "Binned",
      `step1-weather-t_numBins` = 5, `step1-weather-t_binningMethod` = "Equal frequency",
      `step1-weather-r_relativePeriod` = c(1, 12), `step1-weather-r_contOrBinned` = "Continuous",
      `step1-weather-hist_years` = c(1991, 2020)
    )
  )
}
cp <- build_connection_params("local", path = Sys.getenv("WISEAPP_DATA_PATH"))
md <- load_overview_metadata(cp)
enso_tables <- if (use_fixture) {
  enso_load(list(type = "local", path = normalizePath("tests/testthat/fixtures/enso")))
} else {
  md$enso
}
stopifnot(!is.null(enso_tables))
cash <- list(transfer_amount_usd = 60, targeting = "exante_poor", targeting_threshold_pct = 30, admin_cost_pct = 5)

run_once <- function(enso_value) {
  out <- NULL
  all_steps <- function(input, output, session) {
    s1 <- mod_1_modelling_server(
      "step1",
      connection_params = shiny::reactive(cp), survey_list = shiny::reactive(md$survey_list),
      variable_list = shiny::reactive(md$variable_list), cpi_ppp = shiny::reactive(md$cpi_ppp),
      enso = shiny::reactive(enso_value)
    )
    s2 <- mod_2_simulation_server(
      "step2",
      connection_params = shiny::reactive(cp), selected_outcome = s1$selected_outcome,
      selected_weather = s1$selected_weather, selected_surveys = s1$selected_surveys,
      survey_weather = s1$survey_weather, model_fit = s1$model_fit, stored_breaks = s1$stored_breaks,
      survey_version = s1$survey_version, enso = shiny::reactive(enso_value)
    )
    s3 <- mod_3_scenario_server(
      "step3",
      selected_outcome = s1$selected_outcome, selected_weather = s1$selected_weather,
      selected_model = s1$selected_model, selected_policies = s1$selected_policies,
      survey_weather = s1$survey_weather, survey_data = s1$survey_data, model_fit = s1$model_fit,
      hist_sim = s2$hist_sim, saved_scenarios = s2$saved_scenarios, selected_hist = s2$selected_hist,
      variable_list = shiny::reactive(md$variable_list), analysis_unit = s1$analysis_unit,
      skip_coef_draws = s2$skip_coef_draws, residuals = s2$residuals,
      survey_version = s1$survey_version, sim_stale = s2$stale, enso_labels = s2$enso_labels
    )
    list(s1 = s1, s2 = s2, s3 = s3)
  }
  shiny::testServer(all_steps, {
    do.call(session$setInputs, c(
      list(
        `step1-sample-unit` = "hh", `step1-sample-economy` = cfg$economy,
        `step1-outcome-outcome` = "welfare", `step1-outcome-currency` = "PPP"
      ),
      stats::setNames(list(cfg$years), paste0("step1-sample-year_", cfg$economy)),
      cfg$weather_inputs
    ))
    session$setInputs(`step1-surveystats-survey_stats` = 0L)
    session$setInputs(`step1-surveystats-survey_stats` = 1L)
    session$flushReact()
    session$setInputs(`step1-weatherstats-weather_stats` = 0L)
    session$setInputs(`step1-weatherstats-weather_stats` = 1L)
    session$flushReact()
    session$setInputs(
      `step1-model-model_type` = "Linear regression", `step1-model-interactions` = character(0),
      `step1-model-fixedeffects` = cfg$fe, `step1-model-covariates` = "User-defined",
      `step1-model-hhcov` = cfg$covs
    )
    session$flushReact()
    session$setInputs(`step1-model-run_model` = 0L)
    session$setInputs(`step1-model-run_model` = 1L)
    session$flushReact()
    session$elapse(1000)
    session$flushReact()
    session$setInputs(
      `step2-weathersim-hist_years` = cfg$sim_hist, `step2-weathersim-climate` = "ssp3_7_0",
      `step2-weathersim-fut_period_1` = cfg$future, `step2-weathersim-fut_period_2` = c(2015, 2015),
      `step2-weathersim-fut_period_3` = c(2015, 2015), `step2-weathersim-residuals` = "original",
      `step2-weathersim-include_coef_uncertainty` = TRUE,
      `step2-weathersim-propagate_all_covariate_uncertainty` = FALSE
    )
    session$flushReact()
    session$setInputs(`step2-weathersim-run_sim` = 1L)
    session$flushReact()
    session$elapse(1000)
    session$flushReact()
    stopifnot(identical(s2$run_status(), "success"))
    tables <- list()
    collect <- function(prefix) {
      items <- wise_export_items(session)
      for (it in Filter(function(x) identical(x$kind, "table"), items)) {
        v <- tryCatch(it$fun(), error = function(e) NULL)
        if (is.data.frame(v)) tables[[paste(prefix, it$key)]] <<- v
      }
    }
    for (method in c("mean", "headcount_ratio")) {
      session$setInputs(
        `step2-results-cmp_agg_method` = method, `step2-results-cmp_deviation` = "none",
        `step2-results-ensemble_band` = "p10_p90", `step2-results-uncertainty_band` = "p10_p90",
        `step2-results-pov_line` = 3
      )
      session$elapse(500)
      session$flushReact()
      collect(paste("step2", method))
    }
    do.call(session$setInputs, stats::setNames(
      utils::modifyList(wise_default_policy()$sp, cash),
      paste0("step3-sp-", names(utils::modifyList(wise_default_policy()$sp, cash)))
    ))
    session$flushReact()
    session$setInputs(`step3-run_policy_sim` = 0L)
    session$setInputs(`step3-run_policy_sim` = 1L)
    session$flushReact()
    session$elapse(1000)
    session$flushReact()
    stopifnot(identical(s3$run_status(), "success"))
    for (method in c("mean", "headcount_ratio")) {
      session$setInputs(
        `step3-results3-cmp_agg_method` = method, `step3-results3-cmp_deviation` = "none",
        `step3-results3-ensemble_band` = "p10_p90", `step3-results3-uncertainty_band` = "p10_p90",
        `step3-results3-cmp_pov_line` = 3
      )
      session$elapse(500)
      session$flushReact()
      collect(paste("step3", method))
    }
    # What the ENSO labels would be, to show they exist on the run being compared.
    labs <- s2$hist_sim()$baseline_months
    out <<- list(
      tables = tables, hist = s2$hist_sim()[setdiff(names(s2$hist_sim()), c(".artifact"))],
      baseline_months = labs
    )
  })
  out
}

cat("Run without ENSO tables ...\n")
a <- run_once(NULL)
cat("Run with ENSO tables ...\n")
b <- run_once(enso_tables)

cat(sprintf("\nregistered tables: %d (without) / %d (with)\n", length(a$tables), length(b$tables)))
# The ENSO tables themselves exist only with the ENSO tables loaded: any other table must be in both runs.
extra <- setdiff(union(names(a$tables), names(b$tables)), intersect(names(a$tables), names(b$tables)))
cat("tables in one run only:", if (length(extra)) paste(extra, collapse = ", ") else "none", "\n")
stopifnot(all(grepl("enso", extra)), length(a$tables) > 10L)
common <- intersect(names(a$tables), names(b$tables))
ok <- vapply(common, function(k) {
  isTRUE(all.equal(a$tables[[k]], b$tables[[k]], tolerance = 0)) && identical(a$tables[[k]], b$tables[[k]])
}, NA)
cat(sprintf("tables identical, all.equal(tolerance = 0): %d of %d\n", sum(ok), length(ok)))
if (!all(ok)) print(names(ok)[!ok])
cat("baseline_months identical:", identical(a$baseline_months, b$baseline_months), "\n")
cat("baseline_months (non-zero):", paste(sprintf("%d=%.3f", which(a$baseline_months > 0), a$baseline_months[a$baseline_months > 0]), collapse = " "), "\n")
cat("hist_sim identical apart from the artifact:", isTRUE(all.equal(a$hist, b$hist, tolerance = 0)), "\n")
quit(status = if (all(ok)) 0L else 1L)
