# Development-only benchmark: seasonal forecast weather and Step 2 forecast run (BFA, draft-2 fixture).
#
# Reuses the input builders of dev/bench/bench_step2.R (function definitions only) and the synthetic
# draft-2 data root from dev/make_fixture_forecast_draft2.R, so no forecast data is needed upstream.
#
#   WISEAPP_DATA_PATH=/path/to/data Rscript dev/make_fixture_forecast_draft2.R   # once
#   WISEAPP_DATA_PATH=/path/to/data /usr/bin/time -l Rscript dev/bench/bench_forecast_weather.R
#
# Env: WX (weather variables, comma-separated; default t), WF (Binned|Continuous), FE=1 (interview-month fixed effects), FSTARTS ("2026-11:3,2027-03:1"),
# WISEAPP_FORECAST_FIXTURE (data root; default dev/fixtures/data_root). The peak memory is the
# `maximum resident set size` of /usr/bin/time -l.

options(golem.app.prod = FALSE)
pkgload::load_all(".", quiet = TRUE)
defs <- parse("dev/bench/bench_step2.R")
for (e in defs) {
  if (is.call(e) && identical(e[[1]], as.name("<-")) && is.call(e[[3]]) &&
      identical(e[[3]][[1]], as.name("function"))) eval(e, globalenv())
}
Sys.setenv(WISEAPP_STEP2_SURVEY_YEARS = "")
if (identical(Sys.getenv("FE"), "1")) {
  .bench_model_spec <- function(config, model_label, sw, svy_wx, so) build_selected_model(
    model_type = "Linear regression", interactions = character(0),
    fixedeffects = c("year", "loc_id_panel", "int_month"), covariate_selection = "User-defined",
    ind_covariates = character(0), hh_covariates = character(0), firm_covariates = character(0),
    area_covariates = character(0), cluster = "loc_id_panel")
}
root <- normalizePath(Sys.getenv("WISEAPP_FORECAST_FIXTURE", "dev/fixtures/data_root"), mustWork = TRUE)
cp <- build_connection_params("local", path = root)
cfg <- list(unit = "hh", outcome = "welfare", weather = strsplit(Sys.getenv("WX", "t"), ",")[[1L]], weather_form = Sys.getenv("WF", "Binned"),
  ref_end = 1L, hist_years = c(1991L, 2020L), models = "ols")
inp <- suppressMessages(.bench_build_local_inputs("BFA", cfg, cp, load_overview_metadata(cp)))
run <- .forecast_catalogue_runs(cp, "BFA")[[1L]]
common <- list(sw = inp$sw, so = inp$so, svy = inp$svy, ss = inp$ss, mf = inp$models[[1L]], cp = cp,
  fp_list = list(), ssps = character(0), residuals = "original", skip_coef_draws = TRUE,
  sim_dates = inp$sim_dates, perturbation_method = "none", stored_breaks = inp$stored_breaks)
tm <- function(label, expr) {
  t <- proc.time()[[3L]]
  v <- force(expr)
  cat(sprintf("%-46s %7.2f s\n", label, proc.time()[[3L]] - t))
  invisible(v)
}
tm("catalogue (verify checksums)", .forecast_catalogue_runs(cp, "BFA"))
tm("fct_run_simulation historical only", do.call(fct_run_simulation, common))
for (st in strsplit(Sys.getenv("FSTARTS", "2026-11:3"), ",")[[1L]]) {
  part <- strsplit(st, ":")[[1L]]
  fc <- list(run = run, start = part[[1L]], len = as.integer(part[[2L]]))
  tm(paste("forecast weather builder", st), .get_forecast_weather(
    inp$svy, inp$ss, inp$sw, cp, run, fc$start, fc$len, stored_breaks = inp$stored_breaks, keep_continuous = TRUE))
  r <- tm(paste("fct_run_simulation + forecast", st), do.call(fct_run_simulation, c(common, list(forecast = fc))))
  na <- max(vapply(r$new_scenarios[[1L]]$pipelines, function(x) mean(is.na(x$y_point)), numeric(1L)))
  cat(sprintf("  failures %d, members %d, max NA share of y_point %.3f\n",
    length(r$failures), r$n_forecast_members, na))
}
